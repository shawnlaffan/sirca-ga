# vim: set ts=4 sw=4 et :
"""
This module handles displaying and exporting simulation outputs
 - plots (working on)
 - tables
 - images

New data is appended by the simulator dynamically by outputting YAML documents as it runs
"""

import wx

import main
import stat_outputs
import perl_commands

class OutputTreeNode:
    """
    base class for nodes in the output tree
    """

    def ShowExistingPanel(self, key):
        """ Tries to show an existing output
        Returns whether successful"""

        return main.app.frame.ShowExistingPanel(key)

    def ShowPanel(self, panel, key):
        """
        Shows a panel on the central notebook (tab control)
        """
        return main.app.frame.ShowPanel(panel, key)

    def GetWorkspace(self):
        """
        Returns the main windows's notebook control
        Needed for giving a parent to the Output panels
        """
        return main.app.frame.GetWorkspace()


class OutputRootNode(OutputTreeNode):
    """
    manages the root node of the outputs tree
    """
    def __init__(self, tree, sirca_instance):
        self.tree = tree
        self.node = tree.AddRoot("outputs")
        self.tree.SetPyData(self.node, self)

        #self.tree.SetItemImage(self.node, fldridx, wx.TreeItemIcon_Normal)
        #self.tree.SetItemImage(self.node, fldropenidx, wx.TreeItemIcon_Expanded)
        
        # add stat outputs
        stat_node = self.tree.AppendItem(self.node, "Epicurves")
        self.tree.SetPyData(stat_node, self)

        # load stat data from SIRCA
        stats_command = perl_commands.GetStats()
        sirca_instance.DoCommand(stats_command)
        stats = stats_command.GetStats()
        for stat_data in stats:
            node = StatNode(self.tree, stat_node, stat_data)

        self.tree.Expand(stat_node)

        # add density maps
        map_node = self.tree.AppendItem(self.node, "Density maps")
        self.tree.SetPyData(map_node, self)


    def OnActivate(self, activated):
        pass
    def OnRightClick(self, node):
        pass


class MapNode(OutputTreeNode):
    """
    manages a node with density plots
    in the outputs treee
    """
    def __init__(self, tree, parent, stat_data):
        self.tree = tree
        self.parent = parent

        self.node = self.tree.AppendItem(parent, stat_data.name)
        self.tree.SetPyData(self.node, self)
        #self.tree.SetItemImage(self.node, fldridx, wx.TreeItemIcon_Normal)
        #self.tree.SetItemImage(self.node, fldropenidx, wx.TreeItemIcon_Expanded)

        self.stat_data = stat_data
        self.id = id(stat_data)

    def OnActivate(self, activated):

        # check for existing panel
        if (self.ShowExistingPanel(self.stat_data)): return
        
        plotPanel = stat_outputs.OutputPlotPanel(self.GetWorkspace(), self.stat_data)
        self.ShowPanel(plotPanel, self.stat_data)
        
class StatNode(OutputTreeNode):
    """
    manages a node like "COUNT" or "DENSITY"
    in the outputs treee
    """
    def __init__(self, tree, parent, stat_data):
        self.tree = tree
        self.parent = parent

        self.node = self.tree.AppendItem(parent, stat_data.name)
        self.tree.SetPyData(self.node, self)
        #self.tree.SetItemImage(self.node, fldridx, wx.TreeItemIcon_Normal)
        #self.tree.SetItemImage(self.node, fldropenidx, wx.TreeItemIcon_Expanded)

        self.stat_data = stat_data
        self.id = id(stat_data)

    def OnActivate(self, activated):

        # check for existing panel
        if (self.ShowExistingPanel(self.stat_data)): return
        
        plotPanel = stat_outputs.OutputPlotPanel(self.GetWorkspace(), self.stat_data)
        self.ShowPanel(plotPanel, self.stat_data)
 
class OutputPanel(wx.Panel):
    """
    represents the outputs panel on the main window
    """
    def __init__(self, parent):
        wx.Panel.__init__(self, parent, -1, size=(150,300), style=wx.WANTS_CHARS)

        tID = wx.NewId()
        self.tree = wx.TreeCtrl(self, tID, wx.DefaultPosition, wx.DefaultSize,
                               wx.TR_HAS_BUTTONS
                               | wx.TR_LINES_AT_ROOT
                               #| wx.TR_MULTIPLE
                               | wx.TR_HIDE_ROOT
                                )
        self.Bind(wx.EVT_TREE_ITEM_ACTIVATED, self.OnActivate, self.tree)
        self.Bind(wx.EVT_RIGHT_UP, self.OnRightClick, self.tree)
       
        # expand tree to fill self
        sizer = wx.BoxSizer()
        sizer.Add(self.tree, 1, wx.EXPAND)
        self.SetSizer(sizer)        

    def Update(self, sirca_instance):
        self.tree.DeleteAllItems()
        self.root = OutputRootNode(self.tree, sirca_instance)
        #self.tree.Expand(self.root.node)
        
    def OnSize(self, event):
        w,h = self.GetClientSizeTuple()
        self.tree.SetDimensions(0, 0, w, h)

    def OnRightClick(self, event):
        # Pass down the right-click event to the python object representing the clicked on node
        item = event.GetItem()
        node = self.tree.GetPyData(item)
        try:
            node.OnRightClick(item)
        except AttributeError:
            pass

    def OnActivate(self, event):
        # Pass down the double-click event to the python object representing the clicked on node
        item = event.GetItem()
        node = self.tree.GetPyData(item)
        try:
            node.OnActivate(item)
            event.Veto()
        except AttributeError:
            pass



if __name__ == "__main__":
    pass
