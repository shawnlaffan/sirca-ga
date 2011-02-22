# vim: set ts=4 sw=4 et :
"""
Class for creating the main window and the Application
"""
import wx
import wx.aui
import pprint
import os
import subprocess
import sys
from datetime import datetime

import logging
from lxml import etree

import config
import outputs, stat_outputs
import perl_commands_for_gui as commands

ID_ABOUT=101
ID_OPEN=102
ID_BUTTON1=110
ID_EXIT=200

# For default directory use use two levels above where this file should
# be located (SIRCADIR/lib/SircaUI), unless have explicit env. variable
try:
    SIRCADIR = os.environ["SIRCADIR"]
except:
    SIRCADIR = os.path.abspath('../..')


class MainFrame(wx.Frame):
    log = logging.getLogger('gui.MainApp')
    def __init__(self, starting_config_filename=None):

        self.have_loaded_simulation = False
        self.simulation_command = None
        self.starting_config_filename = starting_config_filename

        # intialise GUI elements..
        self.init_mainframe()

        # EVT_WINDOW_CREATE doesn't seem to work
        self.Bind(wx.EVT_SHOW, self.OnWindowCreated)

    def OnWindowCreated(self, event):
        # initialise communication with the SIRCA perl process
        # must call this after window is created since we may get
        # immediate events sent to us
        if not hasattr(self, 'sirca_instance'):
            self.sirca_instance = commands.SIRCAInstanceForGUI(self)

        if self.starting_config_filename is not None:
            self.LoadConfigFromFile(self.starting_config_filename)


    def init_mainframe(self):    
        wx.Frame.__init__(self, None, -1, 'Sirca GUI')
        self.save_filename = None
        self.control_file = None
        self._mgr = wx.aui.AuiManager()
        self._mgr.SetManagedWindow(self)
        self.SetSize((640, 480))

        # status bar
        self.sb = wx.StatusBar(self)
        self.SetStatusBar(self.sb)
        self.sb.SetStatusText("")
        
        # file menu
        filemenu = wx.Menu()
        self.filemenu = filemenu
        file_open = filemenu.Append(-1, "&Open control file\tCtrl+O","Load a perl configuration file")
        file_save = filemenu.Append(-1, "&Save control file\tCtrl+S","Save a perl configuration file")
        file_save_as = filemenu.Append(-1, "Save As control file","Save a perl configuration file")
        filemenu.AppendSeparator()

        filehistorymenu = wx.Menu()
        self.filehistorymenu = filehistorymenu
        filemenu.AppendMenu(-1, "Recent files", filehistorymenu)
        filemenu.AppendSeparator()
        
        file_exit = filemenu.Append(-1,"E&xit","Quit the program")

        self.Bind(wx.EVT_MENU, self.OnLoadConfig, file_open)
        self.Bind(wx.EVT_MENU, self.OnSaveConfig, file_save)
        self.Bind(wx.EVT_MENU, self.OnSaveConfigAs, file_save_as)
        self.Bind(wx.EVT_MENU, self.OnExit, file_exit)
        self.file_save_id = file_save.GetId()
        self.file_save_as_id = file_save_as.GetId()
        
        # file history
        self.fileHistory = wx.FileHistory()
        self.fileHistory.UseMenu(filehistorymenu)
        self.Bind(wx.EVT_MENU_RANGE, self.OnFileHistory, id=wx.ID_FILE1, id2=wx.ID_FILE9)

        #self.Bind(wx.EVT_WINDOW_DESTROY, self.Cleanup)
        wx.EVT_WINDOW_DESTROY(self, self.Cleanup)

        self.config = wx.Config('Sirca', 'UNSW')
        self.fileHistory.Load(self.config)

        # simulation menu
        sim_menu = wx.Menu()
        self.sim_run = sim_menu.Append(-1, "&Run simulation\tCtrl+R","Run SIRCA simulation using the loaded control file")
        sim_menu.AppendSeparator()
        self.sim_load_state = sim_menu.Append(-1, "&Load from saved state\tCtrl+L","Load a SIRCA saved state file (.scs file)")
        self.sim_save_state = sim_menu.Append(-1, "&Save state","Save loaded simulation to a SIRCA saved state file")

        self.Bind(wx.EVT_MENU, self.OnRun, self.sim_run)
        self.Bind(wx.EVT_MENU, self.OnLoadState, self.sim_load_state)
        self.Bind(wx.EVT_MENU, self.OnSaveState, self.sim_save_state)

        # menu bar
        menuBar = wx.MenuBar()
        menuBar.Append(filemenu,"&File")
        menuBar.Append(sim_menu,"&Simulation")
        self.SetMenuBar(menuBar)

        # toolbar
        tb1 = wx.ToolBar(self, -1, wx.DefaultPosition, wx.DefaultSize,
                         wx.TB_FLAT | wx.TB_NODIVIDER)
        tb1.SetToolBitmapSize(wx.Size(16, 16))
        
        def addButton(toolbar, bitmapID, longHelp, caption, proc):
            bmp = wx.ArtProvider.GetBitmap(bitmapID, wx.ART_TOOLBAR, (16,16))
            id = wx.NewId()
            toolbar.AddLabelTool(id, caption, bmp, shortHelp = caption, longHelp = longHelp)
            self.Bind(wx.EVT_TOOL, proc, id=id)
            return id

        addButton(tb1, wx.ART_NEW, "New", "New configuration", self.OnLoadConfig)
        addButton(tb1, wx.ART_FILE_OPEN, "Open", "Open existing configuration file", self.OnLoadConfig)
        addButton(tb1, wx.ART_FILE_SAVE, "Save", "Save configuration", self.OnSaveConfig)
        addButton(tb1, wx.ART_FILE_SAVE_AS, "Save as", "Save configuration with a new name", self.OnSaveConfigAs)
        tb1.AddSeparator()
        addButton(tb1, wx.ART_FIND, "Display config", "Open config file in an editor", self.OnShowConfig)
        # remember id of start button so we can disable it..
        self.toolbar_run_id = addButton(tb1, wx.ART_TICK_MARK, "Run!", "Run simulation", self.OnRun)
        self.toolbar = tb1

        tb1.Realize()

        # bindings
        self.Bind(wx.EVT_CLOSE, self.OnCloseWindow)

        # create toolbar pane
        self._mgr.AddPane(tb1, wx.aui.AuiPaneInfo().
                  Name("tb1").Caption("Toolbar 1").
                  ToolbarPane().Top().Row(1).
                  LeftDockable(False).RightDockable(False))

        # create config panel
        self.configPanel = config.ConfigPanel(self)
        self._mgr.AddPane(self.configPanel, wx.aui.AuiPaneInfo().
                          Name("parameters").Caption("Parameters").
                          Left().Position(1).CloseButton(True).MaximizeButton(True))

        # create outputs panel
        self.outputPanel = outputs.OutputPanel(self)
        self._mgr.AddPane(self.outputPanel, wx.aui.AuiPaneInfo().
                          Name("outputs").Caption("outputs").
                          Left().Position(1).CloseButton(True).MaximizeButton(True))

        # create plots panel
        self.plotsPlanel = stat_outputs.PlotsPanel(self)
        self._mgr.AddPane(self.plotsPlanel, wx.aui.AuiPaneInfo().
                          Name("plots").Caption("plots").
                          Left().Position(1).CloseButton(True).MaximizeButton(True))

        # create log panel
        self.output = wx.TextCtrl(self, -1, size=(-1,100), style=wx.TE_MULTILINE)
        self.output.SetEditable(False)
        self._mgr.AddPane(self.output, wx.aui.AuiPaneInfo().
                          Name("log").Caption("Output log").
                          Bottom().Position(1).CloseButton(True).MaximizeButton(True))

        # create central notebook panel
        self.workspace = wx.aui.AuiNotebook(self)
        self._mgr.AddPane(self.workspace, wx.aui.AuiPaneInfo().
                          Name("workspace").Caption("Workspace").
                          CenterPane())
        self.open_panels = {}
        self.Bind(wx.aui.EVT_AUINOTEBOOK_PAGE_CLOSE,
                self.OnWorkspacePageClose, self.workspace)
        self.Bind(wx.aui.EVT_AUINOTEBOOK_PAGE_CHANGED,
                self.OnWorkspacePageChange, self.workspace)
        
        # bind handler for SIRCA events (eg: simulation finished)
        self.Connect(-1, -1, commands.EVT_GUI_ID, self.OnSimulationEvent)

        # show panels
        self._mgr.GetPane("tb1").Show()
        self._mgr.GetPane("parameters").Show()
        self._mgr.GetPane("outputs").Show()
        self._mgr.GetPane("plots").Show()
        self._mgr.GetPane("log").Show()
        self._mgr.GetPane("workspace").Show()
        self._mgr.Update()

        # update UI
        self.UpdateFileMenu()
        self.UpdateSimulationUI()

    def GetPlotsPanel(self):
        return self.plotsPlanel

    #
    # showing stuff in the central notebook
    #
    def GetWorkspace(self):
        return self.workspace

    def ShowExistingPanel(self, key):
        """
        Tries to show an existing object
        Returns whether successful
        """
        try:
            panel = self.open_panels[id(key)]
            self._ActivateWorkPanel(panel)
            return True
        except KeyError:
            return False

    def ShowPanel(self, panel, key):
        """
        Shows a panel on the central notebook (tab control)
        """
        self.open_panels[id(key)] = panel
        self._ActivateWorkPanel(panel)

    def _ActivateWorkPanel(self, panel):
        # try to get ID (if panel is in the workspace already)
        pageID = self.workspace.GetPageIndex(panel)
        if (pageID >= 0):
            self.workspace.SetSelection(pageID)
        else:
            self.workspace.AddPage(panel, caption=panel.GetCaption(),select=True)
            
    def OnWorkspacePageClose(self, event):
        closing_page = self.workspace.GetPage(event.Selection)
        closing_key = closing_page.GetKey()
        self.open_panels.pop(id(closing_key))

    def OnWorkspacePageChange(self, event):
        old_sel = event.OldSelection
        if old_sel is not None and old_sel >= 0:
            old_page = self.workspace.GetPage(old_sel)
            old_page.OnDeactivate()

        new_page = self.workspace.GetPage(event.Selection)
        new_page.OnActivate()

    #
    # Running
    #
    
    def OnRun(self, event):
        """Run SIRCA simulation"""

        # update log
        time_str = datetime.now().ctime()
        self.output.AppendText("\n---------------------------")
        self.output.AppendText("\nStarting simulation at %s using %s\n\n" % (time_str, "perl"))

        # start simulating, creating a new landscape with our current parameters
        #  will get an event when finished
        self.simulation_command = commands.AsyncSimulate(self, new_params = self.control_file.GetConfigDict())
        self.sirca_instance.StartCommand(self.simulation_command)
        self.UpdateSimulationUI()
        
    def OnSimulationEvent(self, evt):
        """handles one of the events in simulation.py, eg: SimulationFinishedEvent"""
        evt.update_ui(self)

    def OnSimulationFinished(self):

        # update log
        time_str = datetime.now().ctime()
        if not self.simulation_command.HasError():
            self.output.AppendText("\nsimulation finished at %s\n" % (time_str))
            self.outputPanel.Update(self.sirca_instance)
        else:
            self.output.AppendText("\nsimulation failed at %s\n" % (time_str))

        self.have_loaded_simulation = True
        self.simulation_command = None
        self.UpdateSimulationUI()

    #
    # Load & Saving simulation state (.scs files)
    #
    def OnLoadState(self, event):
        dlg = wx.FileDialog(
            self, message="Find a saved state file",
            #defaultDir=os.path.join(SIRCADIR, "parameters"), 
            defaultFile="",
            wildcard="Saved state files (*.scs)|*.scs",
            style=wx.OPEN | wx.CHANGE_DIR)
        
        try:
            if dlg.ShowModal() == wx.ID_OK:
                filename = dlg.GetPaths()[0]

                # load landscape into SIRCA
                load_command = commands.LoadFromSavedState(filename)
                self.sirca_instance.DoCommand(load_command)
                self.have_loaded_simulation = True

                # update outputs
                self.outputPanel.Update(self.sirca_instance)

                # update our loaded parameters
                self.LoadConfigFromLoadedLandscape()
                
                self.UpdateSimulationUI()
            
        finally:
            dlg.Destroy()

    def OnSaveState(self, event):
        dlg = wx.FileDialog(
            self, message="Save control file",
            defaultDir=os.path.join(SIRCADIR, "parameters"), 
            defaultFile="",
            wildcard="Saved state files (*.scs)|*.scs",
            style=wx.SAVE | wx.CHANGE_DIR)
        
        if dlg.ShowModal() == wx.ID_OK:
            filename = dlg.GetPaths()[0]

            save_command = commands.SaveState(filename)
            self.sirca_instance.DoCommand(save_command)
            save_command.WaitTillCompleted()
            
        dlg.Destroy()

    # Load & Saving config (control files)
    #
    def SaveConfig(self):
        """Saving config into an existing file"""
        self.control_file.SaveAsPerl(filename=self.save_filename, sirca_instance=self.sirca_instance)
        
    def OnSaveConfigAs(self, event):
        dlg = wx.FileDialog(
            self, message="Save control file",
            defaultDir=os.path.join(SIRCADIR, "parameters"), 
            defaultFile="",
            wildcard="txt files (*.txt)|*.txt|prm files (*.prm)|*.prm",
            style=wx.SAVE | wx.CHANGE_DIR)
        
        if dlg.ShowModal() == wx.ID_OK:
            self.save_filename = dlg.GetPaths()[0]
            self.SaveConfig()
            
        dlg.Destroy()
    
    def OnShowConfig(self, bla):
        subprocess.Popen(["notepad", self.loaded_filename])

    def OnSaveConfig(self, event):
        if self.save_filename == None:
            self.OnSaveConfigAs(None)
        else:
            self.SaveConfig()
        
    def LoadConfigFromFile(self, filename):
        self.log.info('loading config file ' + filename)
        self.loaded_filename = filename
        loader = config.PerlControlFile(filename=filename, sirca_instance=self.sirca_instance)
        self.LoadConfig(loader)

    def LoadConfigFromLoadedLandscape(self):
        self.loaded_filename = None

        load_command = commands.GetParameters()
        self.sirca_instance.DoCommand(load_command)
        params = load_command.GetParameters()

        loader = config.PerlControlFile(config_dict=params)
        self.LoadConfig(loader)

        
    def LoadConfig(self, loader):
        # FIXME: close all config tabs

        # find metadata xml file
        metadata_filename =os.path.join(SIRCADIR, 'lib', 'SircaUI', 'metadata', 'metadata.xml')
        metadata_tree = etree.parse(metadata_filename)

        # load control file into our configuration-model objects
        self.control_file = config.ControlFile(loader=loader, metadata=metadata_tree)

        # load config data into the GUI view
        view = config.GUIConfigView(self)
        self.control_file.LoadView(view)

        # update UI
        self.UpdateFileMenu()
        self.UpdateSimulationUI()

    def OnLoadConfig(self, event):
        dlg = wx.FileDialog(
            self, message="Choose a control file",
            defaultDir=os.path.join(SIRCADIR, "parameters"), 
            defaultFile="",
            wildcard="txt files (*.txt)|*.txt|prm files (*.prm)|*.prm",
            style=wx.OPEN | wx.CHANGE_DIR)
        
        if dlg.ShowModal() == wx.ID_OK:
            filename = dlg.GetPaths()[0]
            self.fileHistory.AddFileToHistory(filename)
            self.LoadConfigFromFile(filename)
            
        dlg.Destroy()

    def OnFileHistory(self, evt):
        # get the file based on the menu ID
        fileNum = evt.GetId() - wx.ID_FILE1
        filename = self.fileHistory.GetHistoryFile(fileNum)
        print "selected %s from history menu" % (filename)

        # add it back to the history so it will be moved up the list
        self.fileHistory.AddFileToHistory(filename)
        self.LoadConfigFromFile(filename)
    

    #
    # MISC
    #
    def UpdateFileMenu(self):

        haveControlFile = self.control_file is not None

        for id in [self.file_save_id, self.file_save_as_id]:
            menuItem = self.filemenu.FindItemById(id)
            menuItem.Enable(haveControlFile)

    def UpdateSimulationUI(self):

        haveControlFile = self.control_file is not None
        isRunning = self.simulation_command is not None

        self.sim_save_state.Enable(self.have_loaded_simulation)

        enableRun = haveControlFile and (not isRunning)
        self.sim_run.Enable(enableRun)
        self.toolbar.EnableTool(self.toolbar_run_id, enableRun)
    
    def OnAbout(self, event):
        pass

    def OnExit(self, event):
        self.Destroy()

    def OnCloseWindow(self, event):
        self.Destroy()

    def Cleanup(self, event):

        if (event.GetWindow() == self):
            # shutdown the SIRCA process
            self.sirca_instance.Close()

            # save file history
            self.fileHistory.Save(self.config)

            # A little extra cleanup is required for the FileHistory control
            del self.fileHistory

class MainApp(wx.App):

    def __init__(self, starting_config_filename=None):
        self.starting_config_filename = starting_config_filename
        wx.App.__init__(self, redirect=False, filename=None,
                useBestVisual=True, clearSigInt=True)

    def OnInit(self):
        self.frame = MainFrame(self.starting_config_filename)
        self.SetTopWindow(self.frame)
        self.frame.Show()
        return 1
