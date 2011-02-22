# vim: set ts=4 sw=4 et :
"""
This code defines classes that send commands to SIRCA
and return the results
"""
import logging
import sirca_get_stats

from perl_interface import CommandException, SIRCACommand

class ReadParameters(SIRCACommand):
    log = logging.getLogger('command.ReadParameters')

    def __init__(self, filename):
        SIRCACommand.__init__(self)

        f = open(filename, 'r')
        self.perl_data = f.read()
        self.log.debug('read configuration file:\n%s' % self.perl_data)
        f.close()        
    
    def GetName(self):
        return "ReadParameters"

    def GetConfigDict(self):
        self.WaitTillCompleted()
        return self.params
    
    # called when an object is received from SIRCA
    # if have final result, should call SetCompleted()
    def handle_result(self, obj):
        if obj['type'] == 'finished':
            if obj['finished'] == 'read_parameters':
                self.params = obj['parameters']
                self.SetCompleted()
            else:
                raise CommandException("finished job isn't read_parameters but %s" % obj['finished'])
        else:
            raise CommandException("unexpected message: %s" % repr(job))
               
    # returns command that is send to the GUI (usually a dictionary)
    def get_command(self):
        return { 'type' : 'read_parameters', 'data' : self.perl_data }

class WriteParametersAsControlFile(SIRCACommand):
    log = logging.getLogger('command.WriteParametersAsControlFile')

    def __init__(self, params):
        SIRCACommand.__init__(self)
        self.params = params

    def GetName(self):
        return "WriteParametersAsControlFile"

    def GetControlFileData(self):
        self.WaitTillCompleted()
        return self.control_file_data
    
    # called when an object is received from SIRCA
    # if have final result, should call SetCompleted()
    def handle_result(self, obj):
        if obj['type'] == 'finished':
            if obj['finished'] == 'write_parameters_as_control_file':
                self.control_file_data = obj['control_file_data']
                self.SetCompleted()
            else:
                raise CommandException("finished job isn't write_parameters_as_control_file but %s" % obj['finished'])
        else:
            raise CommandException("unexpected message: %s" % repr(job))
               
    # returns command that is send to the GUI (usually a dictionary)
    def get_command(self):
        return { 'type' : 'write_parameters_as_control_file', 'params' : self.params }

class LoadFromParameters(SIRCACommand):
    log = logging.getLogger('command.LoadFromParameters')

    def __init__(self, params):
        SIRCACommand.__init__(self)
        self.params = params
    
    def GetName(self):
        return "LoadFromParameters"

    # called when an object is received from SIRCA
    # if have final result, should call SetCompleted()
    def handle_result(self, obj):
        if obj['type'] == 'finished':
            if obj['finished'] == 'load_from_parameters':
                self.SetCompleted()
            else:
                raise CommandException("finished job isn't load_from_parameters but %s" % obj['finished'])
        else:
            raise CommandException("unexpected message: %s" % repr(job))
               
    # returns command that is send to the GUI (usually a dictionary)
    def get_command(self):
        return { 'type' : 'load_from_parameters', 'params' : self.params }

class LoadFromSavedState(SIRCACommand):
    log = logging.getLogger('command.LoadFromSavedState')

    def __init__(self, filename):
        SIRCACommand.__init__(self)

        # for now will send filename rather than raw data due to its size
        self.filename = filename

        #f = open(filename, 'r')
        #self.saved_state = f.read()
        #f.close()        
    
    def GetName(self):
        return "LoadFromSavedState"

    # called when an object is received from SIRCA
    # if have final result, should call SetCompleted()
    def handle_result(self, obj):
        if obj['type'] == 'finished':
            if obj['finished'] == 'load_from_saved_state':
                self.SetCompleted()
            else:
                raise CommandException("finished job isn't load_from_saved_state but %s" % obj['finished'])
        else:
            raise CommandException("unexpected message: %s" % repr(job))
               
    # returns command that is send to the GUI (usually a dictionary)
    def get_command(self):
        return { 'type' : 'load_from_saved_state', 'filename' : self.filename }
        #return { 'type' : 'load_from_saved_state', 'saved_state' : self.saved_state }

class SaveState(SIRCACommand):
    log = logging.getLogger('command.SaveState')

    def __init__(self, filename):
        SIRCACommand.__init__(self)
        self.filename = filename
    
    def GetName(self):
        return "SaveState"

    # called when an object is received from SIRCA
    # if have final result, should call SetCompleted()
    def handle_result(self, obj):
        if obj['type'] == 'finished':
            if obj['finished'] == 'save_state':
                self.SetCompleted()
            else:
                raise CommandException("finished job isn't save_state but %s" % obj['finished'])
        else:
            raise CommandException("unexpected message: %s" % repr(job))
               
    # returns command that is send to the GUI (usually a dictionary)
    def get_command(self):
        return { 'type' : 'save_state', 'filename' : self.filename }

class Simulate(SIRCACommand):
    log = logging.getLogger('command.Simulate')

    def __init__(self, new_params=None):
        SIRCACommand.__init__(self)
        self.new_params = new_params
    
    def GetName(self):
        return "Simulate"

    # called when an object is received from SIRCA
    # if have final result, should call SetCompleted()
    def handle_result(self, obj):
        if obj['type'] == 'finished':
            if obj['finished'] == 'simulate':
                self.SetCompleted()
            else:
                raise CommandException("finished job isn't simulate but %s" % obj['finished'])
        else:
            raise CommandException("unexpected message: %s" % repr(job))
               
    # returns command that is send to the GUI (usually a dictionary)
    def get_command(self):
        if self.new_params is None:
            return { 'type' : 'simulate' }
        else:
            return { 'type' : 'simulate', 'new_params' : self.new_params }

class GetStats(SIRCACommand):
    log = logging.getLogger('command.GetStats')

    def __init__(self):
        SIRCACommand.__init__(self)
    
    def GetName(self):
        return "GetStats"

    def GetStats(self):
        """returns a list of StatPlotData objects"""
        self.WaitTillCompleted()
        extractor = sirca_get_stats.StatExtractor(stats_dict=self.stats)
        return extractor.GetStats()

    # called when an object is received from SIRCA
    # if have final result, should call SetCompleted()
    def handle_result(self, obj):
        if obj['type'] == 'finished':
            if obj['finished'] == 'get_stats':
                self.stats = obj['stats']
                self.SetCompleted()
            else:
                raise CommandException("finished job isn't get_stats but %s" % obj['finished'])
        else:
            raise CommandException("unexpected message: %s" % repr(job))
               
    # returns command that is send to the GUI (usually a dictionary)
    def get_command(self):
        return { 'type' : 'get_stats' }

class GetParameters(SIRCACommand):
    log = logging.getLogger('command.GetParameters')

    def __init__(self):
        SIRCACommand.__init__(self)
    
    def GetName(self):
        return "GetParameters"

    def GetParameters(self):
        self.WaitTillCompleted()
        return self.params

    # called when an object is received from SIRCA
    # if have final result, should call SetCompleted()
    def handle_result(self, obj):
        if obj['type'] == 'finished':
            if obj['finished'] == 'get_parameters':
                self.params = obj['params']
                self.SetCompleted()
            else:
                raise CommandException("finished job isn't get_parameters but %s" % obj['finished'])
        else:
            raise CommandException("unexpected message: %s" % repr(job))
               
    # returns command that is send to the GUI (usually a dictionary)
    def get_command(self):
        return { 'type' : 'get_parameters' }
    
