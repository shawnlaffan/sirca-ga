# vim: set ts=4 sw=4 et :
from sirca_server import *
import logging
import unittest

class AddJob(SIRCAJob):
    log = logging.getLogger('command.AddJob')

    def __init__(self, a, b):
        SIRCAJob.__init__(self)
        self.a = a
        self.b = b
    
    def GetName(self):
        return "Add"

    def GetResult(self):
        self.WaitTillCompleted()
        self.RaiseErrors()
        return self.answer

    def handle_result(self, result):
        self.log.debug(result)
        if result['type'] == 'add_result':
            self.answer = result['result']
            self.SetCompleted()

    # returns command that is send to the GUI (usually a dictionary)
    def get_command(self):
        return { 'type' : 'test_add', 'a' : self.a, 'b' : self.b }

class CrashJob(SIRCAJob):
    log = logging.getLogger('command.CrashJob')

    def __init__(self):
        SIRCAJob.__init__(self)
    
    def GetName(self):
        return "Add"

    def GetResult(self):
        self.WaitTillCompleted()
        self.RaiseErrors()
        raise "didn't crash?!?"

    def handle_result(self, result):
        self.log.debug(result)
        raise "unexpected result!"

    # returns command that is send to the GUI (usually a dictionary)
    def get_command(self):
        return { 'type' : 'test_crash' }

class TestSircaServer(unittest.TestCase):
    def setUp(self):
        logging.basicConfig(level=logging.DEBUG)
        self.instance = SIRCAInstance()

    def tearDown(self):
        self.instance.Close()

    def testAdd(self):
        job = AddJob(5, 6)
        self.instance.StartJob(job)
        ans = job.GetResult()
        self.assertEquals(ans, 11)

    def testCrash(self):
        job = CrashJob()
        self.instance.StartJob(job)
        try:
            ans = job.GetResult()
            self.fail() # didn't crash!?
        except JobException, e:
            self.assertTrue ('on purpose' in str(e))
        
if __name__ == '__main__':
    unittest.main()        
