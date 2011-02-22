# vim: set ts=4 sw=4 et :
import threading
import socket
import logging
import os
import yaml

Thread = threading.Thread



# base class for a SIRCA job
# a job will send a command to the SIRCA process and receive the results
class SIRCACommand(Thread):
    log = logging.getLogger('interface.SIRCACommand')

    # ################################
    # these need to be overriden
    # ################################
    
    def GetName(self):
        raise "GetName must be overriden!"

    # called when an object is received from SIRCA
    # if have final result, should call SetCompleted()
    def handle_result(self, obj):
        raise "handle_result must be overriden"

    # returns command that is send to the GUI (usually a dictionary)
    def get_command(self):
        raise "get_command must be overriden"

    def __init__(self):
        Thread.__init__(self)

        # initially cleared
        self.completed_event = threading.Event()
        self.started = False
        self.sirca = None
        self.error = None # any exceptions
        self.has_error = False

    # ################################
    # to be called by derived classes
    #   (and also on error)
    # ################################
    def SetCompleted(self):
        self.sirca.CommandComplete(self) # tell the instance that we're finished
        if self.error is not None:
            self.sirca.ShowError(self.error)

        self.completed_event.set()

    def RaiseErrors(self):
        if self.error is not None:
            self.log.error(self.error)
            raise self.error

    # ################################
    # can be overriden
    # ################################

    def GetSocket(self):
        return self.sirca.GetCommandSocket()

    # ################################
    # called from outside
    # ################################
    def WaitTillCompleted(self, timeout=None):
        if not self.started:
            raise "job not even started yet!"
        self.completed_event.wait(timeout)
        self.RaiseErrors()

    def HasError(self):
        return self.has_error

    # ################################
    # called by SIRCAInstance
    # ################################

    def Start(self, instance):
        self.sirca = instance
        self.started = True
        self.start()

    def IsConcurrent(self):
        # by default, commands must be run one at a time
        # the logging collector though is concurrent - it uses a different socket
        return False 

    # ################################
    # internal code
    # ################################


    # thread-procedure
    def run(self):
        self.setName(self.GetName())
        sock = self.GetSocket()

        try:

            # send command
            self.log.debug('job running')
            command = self.get_command()
            command = self.__to_yaml(command)
            sock.sendall(command)
            #self.log.debug('command sent')
            #print command
            
            # now receive stuff until the job is done
            partial_frag = ""
            while not self.completed_event.isSet():

                data = partial_frag + sock.recv(4096)
                if (len(data) == 0):
                    # this means the socket is closed
                    self.log.error('socket closed unexpectdely')
                    raise ConnectionException('socket closed unexpectedly')
                
                self.log.debug('received %d bytes', len(data))

                # process any YAML documents received
                # a YAML document is delimited by '---\n' and '\n...\n'
                # NOTE that there could be multiple docs received in the buffer.
                # We may also receive partial documents
                
                fragments = data.split('\n...\n')
                for frag in fragments[:-1]: # iterate over all except for last
                    self.log.debug('partial fragment: "%s"', partial_frag)
                    
                    # frag must be a complete yaml document!
                    self.log.debug('loaded YAML fragment: %s', frag)
                    result = self.__from_yaml(frag)

                    if self.completed_event.isSet():
                        self.log.warn('job completed but still have buffered results!')
                    
                    # handle errors ourselves
                    # derived classes must call RaiseErrors()
                    if result['type'] == 'error':
                        self.error = CommandException(result['message'], self.error) # nested..
                        self.has_error = True
                        self.SetCompleted()
                    else:
                        # give to subclass
                        self.handle_result(result)

                # if the delimiter occurs at the end, Python's split adds an empty string
                # to the fragments list
                #
                # if something else is at the end, it must be a partial YAML document
                last_frag = fragments[-1]
                partial_frag = last_frag
        except Exception, e:
            self.log.error(e)
            self.error = CommandException(str(e), self.error) # nested..
            self.has_error = True
            self.SetCompleted()
            
    def __to_yaml(self, obj):
        yaml_str = yaml.dump(
            obj,
            explicit_start=True,
            explicit_end=True,
            line_break=False,
            width=10000000, # HACK
            Dumper=yaml.CDumper)
        return yaml_str

    def __from_yaml(self, yaml_doc):
        return yaml.load(yaml_doc, Loader=yaml.CLoader)


class Log4PerlCollectorJob(SIRCACommand):
    """this dummy "command" receives log messages from
    SircaUI::sirca_appender_socket.pm"""
    log = logging.getLogger('interface.perl.log')

    def __init__(self):
        SIRCACommand.__init__(self)
    
    def GetName(self):
        return "Log4PerlCollectorJob"

    # overriding..
    def GetSocket(self):
        return self.sirca.GetLoggingSocket()

    # for overriding..
    def handle_message(self, msg):
        self.log.info(msg)

    # overriden
    def IsConcurrent(self):
        return True 

    # called when an object is received from SIRCA
    # if have final result, should call SetCompleted()
    def handle_result(self, obj):
        if obj['type'] == 'log_msg':
            self.handle_message(obj['msg'])
        else:
            raise CommandException("unexpected message: %s" % repr(job))

    # overriding SetCompleted() - we never complete - regardless of any errors!
    #   We Are the Loggers
    def SetCompleted(self):
        #### self.completed_event.set()
        #### self.sirca.CommandComplete(self) # tell the instance that we're finished
        if self.error is not None:
            self.log.error('LOGGING ERROR: %s' % (self.error))
               
    # returns command that is send to the GUI (usually a dictionary)
    def get_command(self):
        return { 'type' : 'dummy', 'why' : 'this doesnt really need a command, but framework wants one...' }


class CommandException(Exception):
    def __init__(self, param=None, nexterror=None):
        self.param = param
        self.nexterror = nexterror
    def __str__(self):
        next = ''
        if self.nexterror is not None:
            next = ', ' + repr(self.nexterror)
        return repr(self.param) + next

class ConnectionException(Exception):
    def __init__(self, param=None):
        self.param = param
    def __str__(self):
        return repr(self.param)
        
class CommandAlreadyRunningException(Exception):
    def __init__(self, *args):
        self.args = args
    def __str__(self):
        return "a job is already running: %s" % (",".join(self.args))

class SIRCAInstanceException(Exception):
    def __init__(self, *args):
        self.args = args
    def __str__(self):
        return "%s" % (",".join(self.args))


class SIRCAInstance():
    log = logging.getLogger('interface.SIRCAInstance')
    command_port = 6181
    logging_port = 6182

    def __init__(self):
            
        # create socket server for perl app to connect to
        
        # start the perl application, telling it where to connect
        self.closed = False
        commandline = 'perl sirca_client.pl localhost %d %d' % (self.command_port, self.logging_port)

        # must create in self so these stdin/stdout objects don't get close()d when __init__ finishes,
        # causing an infinite loop as close() tries to wait for sirca_client.pl to exit
        (self.child_stdin, self.child_stdout_and_stderr) = os.popen4(commandline)
        
        self.command_conn = self.accept_connection(self.command_port, timeout=30)
        self.logging_conn = self.accept_connection(self.logging_port, timeout=30)
        self.runningCommand = None

        log_collector = self.get_log_collector_job()
        log_collector.Start(self) # launches thread


    def accept_connection(self, port, timeout):
        HOST = ''   # means localhost
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.bind((HOST, port))
        sock.listen(1)
        self.log.debug('listening on port %d', port)

        sock.settimeout(30)
        try:
            conn, addr = sock.accept()
            self.log.debug('got connection from %s', addr)
            conn.setblocking(1)
        except socket.error, e:
            err = ConnectionException('failed to receive connection from sirca_client.pl - possible error - see log. (%s)' % e)
            self.log.error(err)
            raise err
        finally:
            sock.close()

        return conn


    def get_log_collector_job(self):
        return Log4PerlCollectorJob()

    def __del__(self):
        self.Close()

    def Close(self):
        # close connection socket - perl app should terminate
        self.command_conn.close()
        self.closed = True

    def IsClosed(self):
        return self.closed

    def GetCommandSocket(self):
        return self.command_conn

    def GetLoggingSocket(self):
        return self.logging_conn

    def StartCommand(self, job):
        if not job.IsConcurrent():
            if self.runningCommand is not None:
                raise CommandAlreadyRunningException(self.runningCommand.GetName())
            self.runningCommand = job

        job.Start(self) # launches thread

    def DoCommand(self, job):
        self.StartCommand(job)
        job.WaitTillCompleted()

    def CommandComplete(self, job):
        if not job.IsConcurrent() and self.runningCommand is not None and job != self.runningCommand:
            err = 'CommandComplete: running job different from completed job! (%s vs %s)' % (job.GetName(), self.runningCommand.GetName())
            self.log.error(err)
            raise SIRCAInstanceException(err)
        else:
            self.log.info('Command complete: %s', job.GetName())
            self.runningCommand = None

    # to be overriden
    def ShowError(self, exception):
        self.log.error(exception)
        

