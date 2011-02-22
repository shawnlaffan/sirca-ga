# vim: set ts=4 sw=4 et :
"""
Handles display of statistics (epicurve) plots
"""

import copy
import wx
import wx.lib.customtreectrl
from wx.lib.mixins import treemixin


from matplotlib.numerix import arange, sin, pi
import matplotlib
import matplotlib.colors
matplotlib.use('WXAgg')
from matplotlib.backends.backend_wxagg import FigureCanvasWxAgg as FigureCanvas
from matplotlib.backends.backend_wx import NavigationToolbar2Wx
from matplotlib.figure import Figure


import main
import outputs
import workspace

class StatPlotData:
    """Represents data that can be plotted on a single graph
    eg: data for the DENSITY or COUNT statistics

    It may include several dimensions (eg: model -> state)
    """

    def __init__(self, name, dimension_info, data_array):
        self.name = name
        self.dimension_info = dimension_info
        self.data_array = data_array

        # Build a tree heirarchy for implementing the "tree model" stuff

        def build_hierarchy(dimensions):
            if len(dimensions) == 0: return []

            my_level = dimensions[0]
            my_indices = my_level.keys()
            my_indices.sort()

            children = build_hierarchy(dimensions[1:])
            tree_items = []

            for txt in my_indices:
                tree_items.append( (txt, copy.copy(children) ) )

            return tree_items

        if dimension_info is None:
            self.items = [ ('no graph selected', []) ]
        else:
            temp = copy.copy(dimension_info)
            self.items = build_hierarchy(temp)

        self.shown_plots = {} # plot index -> line object

        # initialise colour info
        #self.colour_list = ['blue', 'black', 'forestgreen', 'red', 'cyan', 'magenta', 'yellow',]
        #self.colour_list = ['blue', 'black', 'forestgreen', 'red', 'cyan', 'magenta', 'yellow',]

    # Tree methods

    def GetItem(self, indices):
        """returns a dictionary with (text, children)"""
        text, children = 'Hidden root', self.items
        for index in indices:
            text, children = children[index]
        return text, children

    def GetText(self, indices):
        return self.GetItem(indices)[0]

    def GetChildren(self, indices):
        return self.GetItem(indices)[1]

    def GetChildrenCount(self, indices):
        return len(self.GetChildren(indices))

    def GetItemChecked(self, indices):
        if self.shown_plots.get(indices) is None:
            #print "%s: %s NOT chcked" % (self.name, str(indices))
            return False
        else:
            #print "%s: %s chcked" % (self.name, str(indices))
            return True

    def GetTextColour(self, indices):
        line = self.shown_plots.get(indices)
        if line is None:
            # return black
            return wx.Colour(0,0,0,255)
        else:
            return self.GetLineColour(line)


    def SetChecked(self, indices, isChecked, tree, item):

        if (not isChecked) and (self.shown_plots.get(indices) is not None):
            # being unchecked.. remove plot
            #print "%s: %s removed" % (self.name, str(indices))
            line = self.shown_plots[indices]
            lines = self.axes.lines
            lines.pop(lines.index(line))

            del self.shown_plots[indices]
            
            # set tree node colour to black
            tree.SetItemTextColour(item, wx.Color( 0,0,0,255 ))

        elif isChecked and (self.shown_plots.get(indices) is None):
            # being checked.. show plot

            #print "%s: %s showing" % (self.name, str(indices))
            # extract data points from our multidimensional array
            data_points = self.data_array[indices]
            time = arange(0, len(data_points) )

            # find colour
            #colour = self.GetNextColour()
            # matplotlib likes its colours in range 0-1
            #matplot_colour = tuple(map (lambda x: x/255.0, colour.Get()))
            #print "color: ", matplot_colour

            # plot line
            #line = self.axes.plot(time, data_points, color=matplot_colour)[0]
            line = self.axes.plot(time, data_points)[0]
            self.shown_plots[indices] = line

            # set tree node colour to what matplotlib selected
            tree.SetItemTextColour(item, self.GetLineColour(line))

            
        # refresh
        self.canvas.draw()

    def GetLineColour(self, line):
        colour_0to1 = matplotlib.colors.colorConverter.to_rgb( line.get_color() )
        colour_0to255 = map( lambda x: int(x * 255), colour_0to1) + [255] # 255 added for alpha
        return wx.Colour(*colour_0to255)


    def GetNextColour(self):
        # get colour from top of list and put it at the end
        colour_str = self.colour_list.pop(0)
        self.colour_list.append(colour_str)

        wx_colour = wx.ColourDatabase().Find(colour_str)
        return wx_colour


    # Plotting methods
    def SetAxes(self, axes):
        self.axes = axes

    def SetCanvas(self, canvas):
        self.canvas = canvas

    def __repr__(self):
        return "StatPlotData (name=%s)" % (self.name)

class OutputPlotPanel(wx.Panel, workspace.WorkspacePanel):
    """Plot / tree that appears in the main workspace"""

    def __init__(self, parent, stat_data):
        wx.Panel.__init__(self, parent, -1)
        self.caption = stat_data.name
        self.stat_data = stat_data

        self.SetBackgroundColour(wx.NamedColor("WHITE"))

        self.figure = Figure()
        self.axes = self.figure.add_subplot(111)
        self.canvas = FigureCanvas(self, -1, self.figure)

        stat_data.SetAxes(self.axes)
        stat_data.SetCanvas(self.canvas)

        #t = arange(0.0,3.0,0.01)
        #s = sin(2*pi*t)
        #self.axes.plot(t,s)
        #self.axes.plot(t,s+1)


        self.sizer = wx.BoxSizer(wx.VERTICAL)
        self.sizer.Add(self.canvas, 1, wx.LEFT | wx.TOP | wx.GROW)
        self.SetSizer(self.sizer)
        self.Fit()

        self.add_toolbar()  # comment this out for no toolbar


    # WorkspacePanel methods

    def GetCaption(self):
        return self.caption
    def GetKey(self):
        return self.stat_data

    def OnActivate(self):
        plotsPanel = main.app.frame.GetPlotsPanel()
        plotsPanel.SetTreeModel( self.stat_data )
        print "activated ", self.stat_data.name

    def OnDeactivate(self):
        plotsPanel = main.app.frame.GetPlotsPanel()
        plotsPanel.SetTreeModel( StatPlotData('no graph selected', None, None) )
        print "disactivated ", self.stat_data.name

    def add_toolbar(self):
        self.toolbar = NavigationToolbar2Wx(self.canvas)
        self.toolbar.Realize()
        if wx.Platform == '__WXMAC__':
            # Mac platform (OSX 10.3, MacPython) does not seem to cope with
            # having a toolbar in a sizer. This work-around gets the buttons
            # back, but at the expense of having the toolbar at the top
            self.SetToolBar(self.toolbar)
        else:
            # On Windows platform, default window size is incorrect, so set
            # toolbar width to figure width.
            tw, th = self.toolbar.GetSizeTuple()
            fw, fh = self.canvas.GetSizeTuple()
            # By adding toolbar in sizer, we are able to put it at the bottom
            # of the frame - so appearance is closer to GTK version.
            # As noted above, doesn't work for Mac.
            self.toolbar.SetSize(wx.Size(fw, th))
            self.sizer.Add(self.toolbar, 0, wx.LEFT | wx.EXPAND)
        # update the axes menu on the toolbar
        self.toolbar.update()  

        
    def OnPaint(self, event):
        self.canvas.draw()


class PlotTreeCtrl(treemixin.VirtualTree, wx.lib.customtreectrl.CustomTreeCtrl):
    def __init__(self, *args, **kwargs):
        kwargs['ctstyle'] = wx.TR_DEFAULT_STYLE | wx.TR_HAS_BUTTONS | wx.TR_FULL_ROW_HIGHLIGHT
        self.model = kwargs.get('treemodel', StatPlotData('no graph selected', None, None) )

        super(PlotTreeCtrl, self).__init__(*args, **kwargs)

        self.Bind(wx.lib.customtreectrl.EVT_TREE_ITEM_CHECKED, self.OnItemChecked)
        self.CreateImageList()

    def CreateImageList(self):
        size = (16, 16)
        self.imageList = wx.ImageList(*size)
        #self.AssignImageList(self.imageList)

    def OnGetItemImage(self, indices, which):
        return 0
        # Return the right icon depending on whether the item has children.
        if which in [wx.TreeItemIcon_Normal, wx.TreeItemIcon_Selected]:
            if self.model.GetChildrenCount(indices):
                return 1
            else:
                return 2
        else:
            return 3

    def OnGetItemText(self, indices):
        return self.model.GetText(indices)

    def OnGetChildrenCount(self, indices):
        return self.model.GetChildrenCount(indices)

    def OnGetItemTextColour(self, indices):
        return super(PlotTreeCtrl, self).OnGetItemTextColour(indices)

    def OnGetItemBackgroundColour(self, indices):
        return super(PlotTreeCtrl, self).OnGetItemBackgroundColour(indices)

    def OnGetItemType(self, indices):
        # no checkboxes for the top nodes
        if len(indices) == 1:
            return 0
        else:
            return 1

    def OnGetItemChecked(self, indices):
        return self.model.GetItemChecked(indices)

    def OnItemChecked(self, event):
        item = event.GetItem()
        indices = self.GetIndexOfItem(item)
        checked = item.IsChecked()
        self.model.SetChecked(indices, checked, self, item)

    def OnGetItemTextColour(self, indices):
        return self.model.GetTextColour(indices)


class PlotsPanel(wx.Panel):
    """ represents the plot tree in the main window (for the currently selected statistic)
    """
    def __init__(self, parent):
        wx.Panel.__init__(self, parent, -1, size=(150,300))

        self.tree = PlotTreeCtrl(self)
        self.tree.RefreshItems()

        self.Bind(wx.EVT_RIGHT_UP, self.OnRightClick, self.tree)
       
        # expand tree to fill self
        sizer = wx.BoxSizer()
        sizer.Add(self.tree, 1, wx.EXPAND)
        self.SetSizer(sizer)        

    def SetTreeModel(self, treemodel):
        self.tree.model = treemodel
        self.tree.RefreshItems()

    def OnSize(self, event):
        w,h = self.GetClientSizeTuple()
        self.tree.SetDimensions(100, 100, w, h)

    def OnRightClick(self, event):
        # Pass down the double-click event to the python object representing the clicked on node
        item = event.GetItem()
        node = self.tree.GetPyData(item)
        try:
            node.OnRightClick(item)
        except AttributeError:
            pass

