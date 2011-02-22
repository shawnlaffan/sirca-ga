# vim: set ts=4 sw=4 et :

import time
import threading
import wx
import yaml
import base64
import os
from cStringIO import StringIO

import sirca_get_stats


class SimulationProcess(wx.Process):
    """for handling OnTerminate"""
    def __init__(self, main_win):
        wx.Process.__init__(self, main_win)
        self.main_win = main_win

    def OnTerminate(self, pid, status):
        print "pid", pid, "terminating with status", status
        wx.PostEvent(self.main_win, SimulationFinishedEvent() )

class SimulationSavedInstance:
    """Class that manages a SIRCA simulation that gets loaded from an .scs file"""
    def __init__(self, main_win, filename):

        self.main_win = main_win
        self.filename = filename



class SimulationInstance:
    """Class that manages a "run" of a SIRCA simulation"""

    def __init__(self, main_win, control_file=None):

        self.main_win = main_win
        self.control_file = control_file
        self.process = None
        self.saved_state_filename = None
        self.preserve_saved_state_file = False
        self.stats_yaml_str = None
        self.stats = None
        self.isRunning = False

    def __del__(self):
        print "SimulationInstance deleted"

        # kill process
        if self.process is not None:
            #FIXME: self.process.Kill()
            self.process.Detach()
            self.process.CloseOutput()
            self.process = None

        # remove any temporary files
        if (not self.preserve_saved_state_file) and (self.saved_state_filename is not None):
           os.unlink(self.saved_state_filename)

    # saved state
    def set_saved_state_filename(self, filename):
        print "saved state in", filename
        self.saved_state_filename = filename
        self.preserve_saved_state_file = False

    def get_saved_state_filename(self):
        return self.saved_state_filename

    def SaveStateToFile(self, filename):

        if self.preserve_saved_state_file:
            # do a copy
            newfile = file(filename, 'w')
            oldfile = file(self.saved_state_filename, 'r')
            while True:
                buffer = oldfile.read(4096)
                if buffer is None:
                    break
                else:
                    newfile.write(buffer)
            newfile.close()
            oldfile.close()
            print "[simulation] save state - copied", self.saved_state_filename, "to", filename

        else:
            # do a move
            if os.path.exists(self.saved_state_filename):
                os.rename(self.saved_state_filename, filename)
                print "[simulation] save state - moved", self.saved_state_filename, "to", filename
            else:
                print "[simulation] save state - ERROR saved state file", self.saved_state_filename, "is gone"
                

        # make new file the current saved state
        self.saved_state_filename = filename
        self.preserve_saved_state_file = True

    def StartLoadFromSavedState(self, filename):
        """Loads required data from a saved state file"""

        self.set_saved_state_filename(filename)
        
        perl_run_sirca_script = """
        # Perl script to run the simulation
        #  formerly known as run_sirca_gui.pl
        use strict;
        use warnings;
        use Carp;
        use YAML::Syck;
        use Data::Dumper;
        use MIME::Base64;
        use Storable qw /store retrieve freeze thaw dclone nstore_fd fd_retrieve /;
        use File::Temp qw/ tempfile /;
        use Sirca::Landscape;

        $| = 1;

        # load from Storable
        my $landscape = retrieve('SCS_FILE');

        # send stat data to the GUI
        my $gui_data = {};
        $$gui_data{'type'} = 'model_stats';
        $$gui_data{'yaml_str'} = YAML::Syck::Dump ({ MODEL_STATS => $$landscape{'MODEL_STATS'} });
        print YAML::Syck::Dump ($gui_data); print "...\n";

        exit 61;

        """.replace("SCS_FILE", filename)
        
        # start process
        self.process = SimulationProcess(self.main_win)
        #self.process = wx.Process(self.main_win)
        self.process.Redirect()
        pid = wx.Execute("perl", wx.EXEC_ASYNC, self.process)
        print "executed pid", pid

        # send perl the startup script
        to_perl = self.process.GetOutputStream()
        print "running", perl_run_sirca_script
        to_perl.write(perl_run_sirca_script)
        self.process.CloseOutput()

        # start worker threads for stdout & stderr
        self.stdout_thread = SimulationOutputThread(self.main_win, self,
                self.process.GetInputStream(), SimulationOutputThread.STDOUT)

        self.stderr_thread = SimulationOutputThread(self.main_win, self,
                self.process.GetErrorStream(), SimulationOutputThread.STDERR)

        self.isRunning = True    


    # stats
    def set_stats_yaml(self, yaml_str):
        print "loaded stats YAML", yaml_str
        self.stats_yaml_str = yaml_str

    def GetStats(self):
        """returns a list of StatPlotData objects"""

        # check if alread loaded
        if self.stats is not None:
            return self.stats
        else:
            extractor = sirca_get_stats.StatExtractor(yaml_str=self.stats_yaml_str)
            self.stats_yaml_str = None
            self.stats = extractor.GetStats()
            return self.stats


    # running the simulation
    def Start(self):
        """Run the SIRCA simulation"""

        yaml_str = self.control_file.SaveAsYAML()
        perl_run_sirca_script = """
        # Perl script to run the simulation
        #  formerly known as run_sirca_gui.pl
        use strict;
        use warnings;
        use Carp;
        use YAML::Syck;
        use Data::Dumper;
        use MIME::Base64;
        use Storable qw /store retrieve freeze thaw dclone nstore_fd fd_retrieve /;
        use File::Temp qw/ tempfile /;
        use File::Spec;
        use Sirca::Landscape;

        $| = 1;

        # Load configuration via YAML (provided by GUI)
        my $yaml = <<'EEEOOOFFF';
YAML_STR
EEEOOOFFF
        my $cfg = YAML::Syck::Load ($yaml);
        my $landscape = Sirca::Landscape -> new (config => $cfg);
        #my $landscape = retrieve('C:\sirca_gui\parameters\eugene\gui\main.scs');

        # run
        $landscape -> run;

        # send saved state to the GUI (storable data)
        # GUI might save it to a file if users wants to

        # stored into temp file (stdout reading to slow <-- FIXME
        my ($temp_fh, $temp_filename) = tempfile( "sirca_state_XXXX", SUFFIX => '.scs');
        $temp_filename = File::Spec->rel2abs($temp_filename);
        nstore_fd ($landscape, $temp_fh);
        close($temp_fh);

        local $Storable::Deparse = 1;  #  store code refs
        my $gui_data = {};
        $$gui_data{'type'} = 'landscape_stored';
        $$gui_data{'data_filename'} = $temp_filename;
        print YAML::Syck::Dump ($gui_data); print "...\n";


        # send stat data to the GUI
        $gui_data = {};
        $$gui_data{'type'} = 'model_stats';
        $$gui_data{'yaml_str'} = YAML::Syck::Dump ({ MODEL_STATS => $$landscape{'MODEL_STATS'} });
        print YAML::Syck::Dump ($gui_data); print "...\n";

        exit 61;

        """.replace("YAML_STR", yaml_str)
        
        # start process
        self.process = SimulationProcess(self.main_win)
        #self.process = wx.Process(self.main_win)
        self.process.Redirect()
        pid = wx.Execute("perl", wx.EXEC_ASYNC, self.process)
        print "executed pid", pid

        # send perl the startup script
        to_perl = self.process.GetOutputStream()
        print "running", perl_run_sirca_script
        to_perl.write(perl_run_sirca_script)
        self.process.CloseOutput()

        # start worker threads for stdout & stderr
        self.stdout_thread = SimulationOutputThread(self.main_win, self,
                self.process.GetInputStream(), SimulationOutputThread.STDOUT)

        self.stderr_thread = SimulationOutputThread(self.main_win, self,
                self.process.GetErrorStream(), SimulationOutputThread.STDERR)

        self.isRunning = True

    def Stop(self):
        # stop output reading threads
        self.stdout_thread.abort()
        self.stderr_thread.abort()
        self.stdout_thread.join()
        self.stderr_thread.join()
        self.stdout_thread = None
        self.stderr_thread = None
        self.isRunning = False

    def IsRunning(self):
        return self.isRunning



# Thread class that executes processing
Thread = threading.Thread
class SimulationOutputThread(Thread):
    """worker thread to read simulation's stdout OR stderr"""
    STDOUT = 1
    STDERR = 2

    def __init__(self, main_win, simulation_instance, stream, type):
        Thread.__init__(self)
        self.main_win = main_win
        self.simulation_instance = simulation_instance
        self.stream = stream
        self.want_abort = 0
        self.reading_yaml = False
        self.line_handler_override = None

        self.f = file("C:\\shawn\\svn\\simout.txt", "w")

        if type == self.STDOUT:
            self.type = "STDOUT"
        elif type == self.STDERR:
            self.type = "STDERR"
        else:
            raise "BUG: bad type: " + str(type)

        # This starts the thread running on creation, but you could
        # also make the GUI thread responsible for calling this
        self.start()

    def run(self):
        """thread procedure that reads lines from the simulation subprocess"""

        print "reading", self.type
        stream = self.stream
        incomplete = ""
        while self.want_abort == 0:
            if stream.CanRead():
                line = stream.readline()
                if line == None:
                    break

                # sometimes get incomplete lines...
                if line.endswith('\n'):
                    self.__process_line(incomplete + line)
                    incomplete = ""
                else:
                    incomplete = incomplete + line
                    

            if not stream.CanRead():
                # FIXME: not too bad..
                time.sleep(0.1)

        print self.type, "finished"
        self.f.close()

    def abort(self):
        """abort worker thread."""
        # Method for use by main thread to signal an abort
        self.want_abort = 1

    def __process_line(self, line):

        # sometimes, simulation will send us YAML commands (eg: saved state or stats)
        # we process these and call the appropriate handler

        # handler has the option to register a line_handler_override
        # this can be used for receiving base64 data (eg: saved state)

        # otherwise we send line to the gui
        # remove newline
        line = line.rstrip()
        self.f.write(line + "\n")
        self.f.flush()

        if self.line_handler_override is not None:
            self.line_handler_override(line)

        elif line == "---":
            print "beginning YAML doc"
            self.reading_yaml = True
            self.yaml_buffer = []

        elif line == "...":
            self.reading_yaml = False

            # load yaml document
            yaml_str = "\n\n".join(self.yaml_buffer)
            del self.yaml_buffer

            object = yaml.load(yaml_str, Loader=yaml.CLoader)
            print "loaded YAML object:", str(object)

            # determine handler
            handler_name = "handle_" + object["type"]
            if hasattr(self, handler_name):
                getattr(self, handler_name).__call__(object)
    
        elif self.reading_yaml:
            self.yaml_buffer.append(line)

        else:
            # append to GUI log
            wx.PostEvent(self.main_win, AppendLogEvent(line + "\n") )

    def handle_model_stats(self, object):
        """perl has provided that stats as a yaml string"""

        yaml = object["yaml_str"]
        # the YAML encoder escapes all newlines, which must be unescaped..
        yaml = eval("str('%s')" % (yaml) )

        self.simulation_instance.set_stats_yaml(yaml)

    def handle_landscape_stored(self, object):
        """perl has saved simulation state to a temporary file"""
        self.simulation_instance.set_saved_state_filename(object["data_filename"]);

    def handle_frozen_landscape(self, object):
        """perl will send lots of base64 lines returned by storable"""
        self.eof_line = object["data_eof"]
        self.data_buffer = StringIO()
        self.curline = 0
        self.line_handler_override = self.read_base64_line
        self.eof_handler = lambda data: self.read_frozen_landscape(object, data)

    def read_frozen_landscape(self, object, data):

        print "read frozen landscape with %d bytes" % (len(data))

        # remove our hooks
        self.line_handler_override = None
        self.eof_handler = None

    def read_base64_line(self, line):
        """buffers base64 data line-by-line"""

        if line == self.eof_line:
            # finished
            self.data_buffer.seek(0)
            data = self.data_buffer.read()
            del self.data_buffer
            del self.eof_line

            print "finished reading base64 data"
            self.eof_handler(data)

        else:
            if len(line) > 0:
                self.curline = self.curline + 1
                if self.curline % 1000:
                    print "@ line %d" % (self.curline)
                #decoded = base64.b64decode(line)
                #self.data_buffer.write(decoded)



