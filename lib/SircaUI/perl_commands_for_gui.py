# vim: set ts=4 sw=4 et :
"""
This module extends perl_commands with stuff for use in the wxPython GUI

This includes some asynchronous jobs (like AsyncSimulate) that send a
wxPython event when done, and a subclass of SIRCAStandardOuptutThread that
sends events to get messages put into the GUI's log
"""
import logging
import wx
import threading

from perl_commands import *
import perl_interface

# Define a notification event for talking to the GUI
#  eg: when simulation is finished, or when text should be
#     appended to the log
EVT_GUI_ID = wx.NewId()
def EVT_GUI(win, func):
    """function to connect the event"""
    win.Connect(-1, -1, EVT_GUI_ID, func)
class GUIEvent(wx.PyEvent):
    """Event sent to GUI thread to update UI in response to simulation"""
    def __init__(self):
        wx.PyEvent.__init__(self)
        self.SetEventType(EVT_GUI_ID)

    def update_ui(self, main_win):
        """executed in the context of GUI thread.."""
        raise "BUG: update_ui not implemented in derived class!"

class AppendLogEvent(GUIEvent):
    """Event to append text to the GUI's output panel"""
    def __init__(self, text):
        GUIEvent.__init__(self)
        self.text = text

    def update_ui(self, main_win):
        main_win.output.AppendText(self.text)

class SimulationFinishedEvent(GUIEvent):
    """Event to signal that simulation has finished"""
    def __init__(self):
        GUIEvent.__init__(self)

    def update_ui(self, main_win):
        main_win.OnSimulationFinished()


class AsyncSimulate(Simulate):
    """Just like simulate but sends a wxPython event when
    the simulation is complete"""

    def __init__(self, main_win, **kwargs):
        Simulate.__init__(self, **kwargs)
        self.main_win = main_win

    def SetCompleted(self):
        Simulate.SetCompleted(self)
        wx.PostEvent(self.main_win, SimulationFinishedEvent() )

class GUILogCollectorJob(perl_interface.Log4PerlCollectorJob):
    """this dummy "command" receives log messages from
    SircaUI::sirca_appender_socket.pm"""
    def __init__(self, main_win):
        self.main_win = main_win
        perl_interface.Log4PerlCollectorJob.__init__(self)
    
    # overriden
    def handle_message(self, msg):
        self.log.info(msg)
        wx.PostEvent(self.main_win, AppendLogEvent(msg) )

    def GetName(self):
        return "GUILogCollectorJob"

class SIRCAInstanceForGUI(perl_interface.SIRCAInstance):
    def __init__(self, main_win):
        self.main_win = main_win

        perl_interface.SIRCAInstance.__init__(self)

    # overriden
    def ShowError(self, exception):
        perl_interface.SIRCAInstance.ShowError(self, exception)
        dlg = wx.MessageDialog(self.main_win, str(exception),
                               'Error from SIRCA Perl process',
                               wx.OK | wx.ICON_ERROR)
        dlg.ShowModal()
        dlg.Destroy()

    # overriden
    def get_log_collector_job(self):
        return GUILogCollectorJob(self.main_win)


