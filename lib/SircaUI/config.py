# vim: set et sw=4 ts=4:
"""
GUI class for configuring parameters

The parameter file is in perl syntax and is
imported/exported via the sirca interface

This module's ControlFile class then produces
the UI:
 - configuration tree to display in GUI panel
 - panels to display in GUI's tabs
 - specialised fields for editing configuration fields

Additional information for setting up the specialised fields
"""

import os
import subprocess
import logging
import yaml
import copy

import wx
import wx.grid
import wx.lib.scrolledpanel

import main
import listedit
import workspace
import event_grid
import perl_commands

ScrolledPanel = wx.lib.scrolledpanel.ScrolledPanel

g_openConfigPanels = {}

def get_sorted_fields(metadata_root, config_fields):
    """takes in a dictionary mapping config key -> config value
    returns a list of (key, value) ordered according to the XML file"""


    def __get_field_orders():
        """returns hash: field name -> order as field appears in the xml file"""
        hash = {}
        i = 0
        for field in metadata_root.getiterator('field'):
            hash[field.attrib['name']] = i
            i = i + 1
        
        return hash


    dict_tuples = [ (key, value) for key, value in config_fields.iteritems() ]
    dict_sort = __get_field_orders()

    def sort_cmp(a,b):
        try:
            ia = dict_sort[a[0]]
        except:
            return 1

        try:
            ib = dict_sort[b[0]]
        except:
            return -1

        return cmp(ia, ib)


    dict_tuples.sort(cmp=sort_cmp)
    return dict_tuples


class GUITreeNode:
    """
    wxPython UI implementation for nodes in the configuration tree
    """
    log = logging.getLogger('config.GUITreeNode')

    def __init__(self, tree, node):
        self.tree = tree
        self.node = node
        self.tree.SetPyData(self.node, self)

        self.activate_callback = None
        self.rightclick_callback = None
        self.log.debug('new instance')

    def SetLabel(self, label):
        self.tree.SetItemText(self.node, label)
        self.log.debug('set label to ' + label)

    def PopupMenu(self, menu):
        self.tree.PopupMenu(menu)

    def CreateChild(self):
        child_item = self.tree.AppendItem(self.node, 'unnamed child')
        self.log.debug('child created')
        return GUITreeNode(self.tree, child_item)

    def Delete(self):
        self.tree.Delete( self.node )

    def HandleActivate(self, callback):
        self.activate_callback = callback

    def HandleRightClick(self, callback):
        self.rightclick_callback = callback

    def HandleMenuItem(self, id, callback):
        self.tree.Bind(wx.EVT_MENU, callback, id=id)

    def OnActivate(self, activated):
        if self.activate_callback is not None:
            self.log.debug('activated (calling handler)')
            self.__call(self.activate_callback)
        else:
            self.log.debug('activated (no handler)')

    def OnRightClick(self, node):
        if self.rightclick_callback is not None:
            self.log.debug('right-clicked (calling handler)')
            self.__call(self.rightclick_callback)
        else:
            self.log.debug('right-clicked (no handler)')

    def __call(self, callback):
        try:
            callback()
        except Exception, value:
            self.log.error(str(value))
            raise
        except:
            self.log.error('unknown exception whilst calling callback: ' + str(callback))



class ConfigPanel(wx.Panel):
    """
    represents the Configuration panel on the main window
    gets completely filled by a tree control
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
        self.Bind(wx.EVT_TREE_ITEM_MENU, self.OnRightClick, self.tree)
       
        # expand tree to fill self
        sizer = wx.BoxSizer()
        sizer.Add(self.tree, 1, wx.EXPAND)
        self.SetSizer(sizer)        

    def ClearTree(self):
        self.tree.DeleteAllItems()

    def CreateRootNode(self):
        root_item = self.tree.AddRoot('unnamed root')
        return GUITreeNode(self.tree, root_item)

    def GetTree(self):
        return self.tree
        
    def OnSize(self, event):
        w,h = self.GetClientSizeTuple()
        self.tree.SetDimensions(0, 0, w, h)

    def OnRightClick(self, event):
        # Pass down the double-click event to the python object representing the clicked on node
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

class EventsTableField:
    """Implements an event editor using a grid"""
    log = logging.getLogger('config.EventsTable')
    def __init__(self, *args, **kwargs):
        self.key = kwargs['key']
        self.metadata = kwargs['metadata']
        self.sirca_dict = None
        self.control = None

    def CreateControl(self, fields_panel):
        self.control = event_grid.EventsTableGrid(fields_panel)
        self.__set_value()
        return self.control

    def SetConfigValue(self, sirca_dict):
        self.sirca_dict = sirca_dict
        self.__set_value()

    def __set_value(self):
        sirca_dict = self.sirca_dict
        if self.control is not None and sirca_dict is not None:
            # raw data from sirca is like
             # {'40' => [{'type' => 'CULL','fraction' => '0.5','state' => '2'},
             #           {'type' => 'CULL','fraction' => '0.5','state' => '3'}
             #          ],
             #  '0' => [{'count' => '5','type' => 'RAND_STATE_CHANGE','state' => '2'}
             #          ]
             #}

            # convert to internal event format used by event_grid.py
            events = []
            for t,e_list in sirca_dict.iteritems():
                for event in e_list:
                    typename = event['type']
                    #del event['type']

                    # the rest of event is turned into the params
                    events.append( { 'time':int(t), 'type':typename, 'params':event} )


            # load types as given by the metadata
            types = {}
            for type_node in self.metadata.GetNode():
                typename = type_node.get('name')

                params = {}
                for field_node in type_node:
                    params[field_node.get('name')] = field_node.get('default')

                # store this type
                types[typename] = params                
                        
            # load the EventsDataTable
            self.control.GetTable().InitData(events, types)

    def GetConfigKey(self):
        return self.key

    def GetConfigValue(self):
        if self.control is None:
            # not loaded yet - return raw data
            if self.sirca_dict is None:
                log.error('GetConfigValue called before SetConfigValue')
            return self.sirca_dict
        else:
            
            events = self.control.GetTable().GetEvents()
            # got a copy - can destroy if so wish..

            # convert to sirca format
            sirca_dict = {}
            for event in events:
                t = event['time']
                if t not in sirca_dict:
                    sirca_dict[t] = []

                params = event['params']
                sirca_event = {}
                for (k,v) in params:
                    sirca_event[k] = v
                
                sirca_event['type'] = event['type']
                sirca_dict[t].append(sirca_event)
            
            return sirca_dict
        


class GridField:
    """Implements a grid-editor field"""
    log = logging.getLogger('config.GridField')
    def __init__(self, *args, **kwargs):
        self.key = kwargs['key']
        self.metadata = kwargs['metadata']
        self.grid_ref = None
        self.control = None

    def CreateControl(self, fields_panel):
        self.control = wx.grid.Grid(fields_panel, -1)

        self.control.SetColLabelAlignment(wx.ALIGN_LEFT, wx.ALIGN_BOTTOM)
      
        # events
        self.control.Bind(wx.grid.EVT_GRID_CELL_CHANGE, self.__on_cell_changed)

        self.__set_value()

        return self.control


    def SetConfigValue(self, grid_ref):
        self.grid_ref = grid_ref
        self.__set_value()

    def __set_value(self):
        grid_ref = self.grid_ref
        if self.control is not None and grid_ref is not None:
            rows = len(grid_ref)
            cols = len(grid_ref[-1])

            self.control.CreateGrid(rows, cols)
            
            # fill grid
            for i in range(rows):
                for j in range(cols):
                    try:
                        value = grid_ref[i][j]
                        self.control.SetCellValue(i, j, str(value))
                        #self.SetCellEditor(i, j, wx.grid.GridCellFloatEditor(0,1000))
                    except IndexError:
                        # empty rows readonly for now
                        self.control.SetReadOnly(i, j, True)

            #self.SetColLabelValue(0, "Custom")
            #self.SetColLabelValue(1, "column")
            #self.SetColLabelValue(2, "labels")


    def GetConfigKey(self):
        return self.key

    def GetConfigValue(self):
        return self.grid_ref
        
    def __on_cell_changed(self, evt):
        row, col = evt.GetRow(), evt.GetCol()
        value = self.control.GetCellValue(row, col)
        self.log.debug( "field (%d,%d) changed to %s" % (row, col, str(value)))
        self.grid_ref[row][col] = value


class TextField:
    """Implements a text-editor field"""
    log = logging.getLogger('config.TextField')
    def __init__(self, *args, **kwargs):
        self.key = kwargs['key']
        self.metadata = kwargs['metadata']
        self.value = self.metadata.get('default')
        self.control = None
        self.change_callbacks = []

    def CreateControl(self, fields_panel):
        self.control = wx.TextCtrl(fields_panel, -1, 'uninitialised!')
        self.control.Bind(wx.EVT_TEXT, self.OnTextChanged)
        self.__set_value()
        return self.control

    def OnTextChanged(self, event):
        self.value = event.GetString()
        self.value = str(self.value) # no !!python/unicode pls
        self.__call_change_callbacks()
        self.log.debug("field %s changed to %s" % (self.key, self.value))

    def GetConfigKey(self):
        return self.key

    def GetConfigValue(self):
        return self.value

    def SetConfigValue(self, value):
        self.value = value
        self.__set_value()

    def RegisterChangeCallback(self, callback):
        self.change_callbacks.append(callback)

    def __call_change_callbacks(self):
        for cb in self.change_callbacks:
            cb()

    def __set_value(self):
        if self.control is not None:
            if self.value is None:
                self.value = '[None!]'
            else:
                self.value = str(self.value)
            self.control.SetValue(self.value)
            self.__call_change_callbacks()


class IntField(TextField):
    """Implements a text-editor field for integers"""
    log = logging.getLogger('config.IntField')
    def __init__(self, *args, **kwargs):
        TextField.__init__(self, *args, **kwargs)


class ListField:
    """Implements a list-editor field"""
    log = logging.getLogger('config.ListField')
    def __init__(self, *args, **kwargs):
        self.key = kwargs['key']
        self.metadata = kwargs['metadata']
        self.value = []
        self.control = None
        self.textbox = None

    def CreateControl(self, fields_panel):
        # create a horizontal sizer for a readonly textbox and an edit button
        hsizer = wx.BoxSizer(wx.HORIZONTAL)
        
        self.textbox = wx.TextCtrl(fields_panel, -1, 'uninitialized!', style=wx.TE_READONLY)
        self.button = wx.Button(fields_panel, -1, "Edit...")
        self.button.Bind(wx.EVT_BUTTON, self.OnEditList)

        hsizer.Add(self.textbox, 1, wx.EXPAND)
        hsizer.Add(self.button, 0, wx.EXPAND)

        self.__set_value()

        return hsizer

    def SetConfigValue(self, value):
        # only numeric lists are supported
        try:
            self.value = map(int, value) # try converting to ints
            self.__set_value()
            
        except TypeError:
            self.log.error( "item: %s: only numeric lists are currently supported" % (self.key))

    def __set_value(self):
        if self.textbox is not None:
            self.textbox.SetValue(str(self.value))



    def OnEditList(self, event):
        btn = event.GetEventObject()
        
        # show a list editor edilog
        dlg = listedit.ListEditDlg(None, "Editing " + self.key, self.value)
        if dlg.ShowModal() == wx.ID_OK:
            result = dlg.GetResultantData()
            self.log.debug( "field %s changed to %s" % (self.key, str(result)))
            self.value = result
            self.textbox.SetValue(str(result))
        dlg.Destroy()
        

    def GetConfigKey(self):
        return self.key

    def GetConfigValue(self):
        return self.value


class FieldsPanel(ScrolledPanel, workspace.WorkspacePanel):
    """A row of widgets for simple config"""
    
    def __init__(self, parent, config_obj, caption):
        ScrolledPanel.__init__(self, parent)
        self.sizer = None
        self.SetupScrolling()
        self.caption = caption
        self.config_obj = config_obj

    # WorkspacePanel methods
    def GetCaption(self):
        return self.caption
    def GetKey(self):
        return self.config_obj

    def LoadFields(self, config_node):
        # create controls for each supported config items
        control_grid = []
        for field in config_node.IterateFields():
            
            control = field.CreateControl(self)
            label_ctl = wx.StaticText(self, -1, self.MakeFriendlyLabel(field.GetConfigKey()) )

            control_grid.append(label_ctl)
            control_grid.append( (control, 1, wx.EXPAND) )
        
        # delete old controls
        if self.sizer is not None:
            self.grid.DeleteWindows()
            self.sizer.DeleteWindows()
            self.sizer.Destroy()
            self.sizer = None
        
        # layout
        self.grid = wx.FlexGridSizer(cols=2, hgap=4, vgap=4)
        self.grid.AddGrowableCol(1, proportion=1)
        self.grid.AddMany(control_grid)
        
        self.sizer = wx.BoxSizer(wx.VERTICAL)
        self.sizer.Add(self.grid, 0, wx.EXPAND | wx.ALL, 20)

        self.SetSizer(self.sizer)
        self.sizer.Layout()

    def MakeFriendlyLabel(self, name):
        """Changes a name from UPPERCASE into just like This"""
        name = name.replace('_', ' ')
        return name[0].upper() + name[1:].lower()
        
    

class ArgsWithMetadata(object):
    def __init__(self, **kwargs):
        super(ArgsWithMetadata, self).__init__()
        self.kwargs = kwargs
        self.metadata = None
        try:
            self.metadata = kwargs['metadata']
        except KeyError:
            pass

    def GetNode(self):
        return self.metadata

    def Clone(self):
        # we're read-only
        return ArgsWithMetadata(**self.kwargs)

    def get(self, name):
        try:
            # first try explicit args
            return self.kwargs[name]
        except KeyError:
            if self.metadata is None:
                raise AttributeError(name)
            else:
                # try direct attribut lookup
                ret = self.metadata.get(name)
                if ret is not None: return ret

                # try to get an inner element with this name
                elem = self.metadata.find(name)
                if elem is not None:
                    # try its text
                    ret = elem.text
                    if ret is not None: return ret

                    # try a 'value' attribute
                    ret = elem.get('value')
                    if ret is not None: return ret

                raise AttributeError(name)



class ConfigNode:
    """represents a configration section that is best represented
    by a tree node - possibly with children (eg: MODELS)
    """
    def __init__(self, args):
        self.args = args
        self.key = args.get('key')
        self.control = None
        self.children = []

    def LoadControl(self, control):
        """loads this node into the presentation control"""
        self.control = control
        control.SetLabel(self.args.get('label'))
        for child in self.children:
            self.__add_child_control(control, child)

    def AddChildItem(self, child_item):
        self.children.append(child_item)
        try:
            # optional..
            child_item.SetParent(self)
        except AttributeError:
            pass

        if self.control is not None:
            self.__add_child_control(self.control, child_item)

    def DeleteChildItem(self, child_item):
        self.children.remove(child_item)

    def GetConfigValue(self):
        """returns this node's final configuration (including everything underneath it..."""
        # get list of children's configuration values
        child_vals = map(lambda child: child.GetConfigValue(), self.children)
        return { self.key : child_vals }

    def __add_child_control(self, control, child_item):
        child_control = control.CreateChild()
        child_item.LoadControl(child_control)

class ConfigFieldsNode:
    """represents a configration section that shows a fields panel when activated
    """
    log = logging.getLogger('config.ConfigFieldsNode')
    def __init__(self, config_parent, args):
        self.config_parent = config_parent
        self.args = args
        self.label_mode = self.args.get('label_mode')
        self.label_mode = self.args.get('label_mode')
        if self.label_mode == 'field':
            self.label_field_name = self.args.get('label_field_name')
        self.control = None
        self.fields = []

        # possible actions for popup menu
        self.allow_duplicate = args.get('allow_duplicate')
        self.allow_delete = args.get('allow_delete')
       
    def SetParent(self, config_parent):
        self.config_parent = config_parent

    def LoadControl(self, control):
        """loads this node into the presentation control"""
        self.control = control
        control.HandleActivate(lambda: self.OnActivated() )
        control.HandleRightClick(lambda: self.OnRightClick() )
        self.__update_label()

        # event handlers for popup menu
        self.id_duplicate = wx.NewId()
        self.id_delete = wx.NewId()

        control.HandleMenuItem(self.id_duplicate, self.OnDuplicate)
        control.HandleMenuItem(self.id_delete, self.OnDelete)

    def __get_label(self, label_field=None):
        if self.label_mode == 'field':
            label_field_name = self.args.get('label_field_name')
            if label_field is None:
                for field in self.fields:
                    if field.GetConfigKey() == label_field_name:
                        label_field = field
                        break

            if label_field is None:
                return "BUG: no label field: " + label_field_name

            return label_field.GetConfigValue()

        elif self.label_mode == 'fixed':
            return self.args.get('label')
        else:
            return "BUG: bad label mode " + self.label_mode

    def __update_label(self, label_field=None):
        label = self.__get_label(label_field)

        if self.control is not None:
            self.control.SetLabel(label)


    def AddField(self, field_control):
        self.fields.append(field_control)
        if self.label_mode == 'field':
            if self.label_field_name == field_control.GetConfigKey():
                # pass field_control to __update_label so it doesn't have
                # to search for it
                callback = lambda: self.__update_label(field_control)
                field_control.RegisterChangeCallback(callback)

                self.__update_label(field_control)

    def IterateFields(self):
        for field in self.fields:
            yield field

    def OnActivated(self):
        # try to open an existing panel
        view = self.args.get('view')
        if (view.ShowExistingPanel(self)): return
        
        caption = "Config - %s" % self.__get_label()
        fields_panel = FieldsPanel(view.GetWorkspace(), config_obj = self, caption = caption)
        fields_panel.LoadFields(self)
        view.ShowPanel(fields_panel, self)

    def OnRightClick(self):
        # Show a pop-up menu (if there's anything to show..)
        menu = wx.Menu()
        shouldShow = False

        if self.allow_duplicate:
            menu.Append(self.id_duplicate, "Duplicate")
            shouldShow = True
        if self.allow_delete:
            menu.Append(self.id_delete, "Delete")
            shouldShow = True

        if shouldShow:
            self.control.PopupMenu(menu)
            menu.Destroy()


    def OnDuplicate(self, event):
        """called in response to Duplicate in the popup menu"""
        if self.label_mode != 'field':
            self.log.error('BUG: can only duplicate nodes that are labelled by \'field\'')
            return

        # duplicate self
        dup_node = ConfigFieldsNode(self.config_parent, self.args.Clone())
        self.config_parent.AddChildItem(dup_node)

        # add each field
        metadata_root = self.args.get('metadata_root')
        view = self.args.get('view')
        label_field_name = self.args.get('label_field_name')

        for key, value in get_sorted_fields(metadata_root, self.GetConfigValue()):

            # change label to indicate duplicate
            if key == label_field_name:
                value = value + ' copy'

            field_metadata = metadata_root.xpath('//field[@name="%s"]' % (key) )
            if len(field_metadata) == 1:
                # create a presenter object to edit the field
                field_metadata = ArgsWithMetadata(metadata=field_metadata[0])
                field_type = field_metadata.get('type')
                field_presenter = view.MapFieldTypeToPresenter(field_type, key=key, metadata=field_metadata)

                if field_presenter:
                    field_presenter.SetConfigValue(value)
                    dup_node.AddField(field_presenter)
            else:
                self.error('BUG: OnDuplicate: don\'t have one metadata entry for field ' + key)


    def OnDelete(self, event):
        """called in response to Delete in the popup menu"""
        self.config_parent.DeleteChildItem(self)

        if self.control is not None:
            self.control.Delete()
            self.control = None


    def GetConfigValue(self):
        """returns this node's final configuration (including everything underneath it..."""
        # get list of children's configuration values
        child_vals = map(lambda child: (child.GetConfigKey(), child.GetConfigValue()), self.fields)
        return dict(child_vals)


class GUIConfigView:
    log = logging.getLogger('config.GUIConfigView')
    def __init__(self, main_frame):
        self.main_frame = main_frame

    def GetTreeRoot(self):
        return self.main_frame.configPanel.CreateRootNode()

    def ClearTree(self):
        return self.main_frame.configPanel.ClearTree()

    def GetTree(self):
        return self.main_frame.configPanel.GetTree()

    def ShowExistingPanel(self, OutputObject):
        """ Tries to show an existing output
        Returns whether successful"""

        return self.main_frame.ShowExistingPanel(OutputObject)

    def ShowPanel(self, panel, OutputObject):
        """
        Shows a panel on the central notebook (tab control)
        """
        return self.main_frame.ShowPanel(panel, OutputObject)

    def GetWorkspace(self):
        """
        Returns the main windows's notebook control
        Needed for giving a parent to the Output panels
        """
        return self.main_frame.GetWorkspace()

    def MapFieldTypeToPresenter(self, t, **kwargs):
        """
        Returns an object that will display/edit a field
        of the given type. None if unhandled.
        """

        class_type = None
        try:
            class_type = self.field_types[t]
        except KeyError:
            self.log.warn("couldn't find control mapping for " + t)
            return None

        if class_type is None:
            self.log.warn('control not yet implemented for ' + t)
            return None
        else:
            return class_type(**kwargs)


    field_types = {
            'text' : TextField,
            'integer' : IntField,
            'boolean' : IntField, # FIXME
            'formula' : TextField, # FIXME

            'list' : ListField,
            'table' : GridField,
            'eventstable' : EventsTableField,

            'filename' : TextField, # FIXME
            'directory' : TextField, # FIXME
           }

class ControlFile:
    """loads a control file into the GUI"""
    log = logging.getLogger('config.ControlFile')

    def __init__(self, **args):
        self.config_dict = args['loader'].GetConfigDict()
        self.metadata_root = args['metadata']


    def LoadView(self, view):
        try:
            # root
            view.ClearTree()
            root_control = view.GetTreeRoot()
            root_item = ConfigNode( ArgsWithMetadata(key='', label='root') )
            root_item.LoadControl(root_control)

            # models
            self.config_models = ConfigNode( ArgsWithMetadata(key='MODEL_CONTROLS', label='Models') )
            root_item.AddChildItem(self.config_models)

            for model_config in self.config_dict['MODEL_CONTROLS']:
                # tree node to edit model fields
                fields_node = ConfigFieldsNode(
                        self.config_models,
                        ArgsWithMetadata(
                            view=view,metadata_root=self.metadata_root,
                            label_mode='field',label_field_name='LABEL',
                            allow_duplicate=True,allow_delete=True,min_children=1) )
                self.config_models.AddChildItem(fields_node)

                # add each field
                for key, value in get_sorted_fields(self.metadata_root, model_config):

                    field_metadata = self.metadata_root.xpath('//field[@name="%s"]' % (key) )
                    if len(field_metadata) == 0:
                        self.log.warn('no metadata found for field ' + key)
                    elif len(field_metadata) > 1:
                        self.log.warn('multiple metadata items found for field ' + key)
                    else:
                        # create a presenter object to edit the field
                        field_metadata = ArgsWithMetadata(metadata=field_metadata[0])
                        field_type = field_metadata.get('type')
                        field_presenter = view.MapFieldTypeToPresenter(field_type, key=key, metadata=field_metadata)

                        if field_presenter:
                            field_presenter.SetConfigValue(value)
                            fields_node.AddField(field_presenter)

            # misc fields (in top-level dict)
            self.config_misc = ConfigFieldsNode(
                    root_item,
                    ArgsWithMetadata(view=view,label='Misc', label_mode='fixed',
                            allow_duplicate=False,allow_delete=False,min_children=1) )
            root_item.AddChildItem(self.config_misc)

            for key, value in get_sorted_fields(self.metadata_root, self.config_dict):

                if type(value) != dict:

                    field_metadata = self.metadata_root.xpath('//field[@name="%s"]' % (key) )
                    if len(field_metadata) == 0:
                        self.log.warn('no metadata found for field ' + key)
                    elif len(field_metadata) > 1:
                        self.log.warn('multiple metadata items found for field ' + key)
                    else:
                        # create a presenter object to edit the field
                        field_metadata = field_metadata[0]
                        field_metadata = ArgsWithMetadata(metadata=field_metadata)
                        field_type = field_metadata.get('type')
                        field_presenter = view.MapFieldTypeToPresenter(field_type, key=key, metadata=field_metadata)

                        if field_presenter:
                            field_presenter.SetConfigValue(value)
                            self.config_misc.AddField(field_presenter)

        except Exception, value:
            # FIXME FIXME FIXME and similar..
            self.log.error(value)
            raise
        except str, s:
            self.log.error('exception whilst calling LoadView: ' + s)
        except:
            self.log.error('unknown exception whilst calling LoadView')

    def GetConfigDict(self):
        config_dict = {}

        # add both models and misc data
        models = self.config_models.GetConfigValue()
        misc = self.config_misc.GetConfigValue()

        config_dict.update(models)
        config_dict.update(misc)
        return config_dict

    def SaveAsPerl(self, sirca_instance, filename):
        # convert our config into control file data (Perl hash format)
        config = self.GetConfigDict()
        command = perl_commands.WriteParametersAsControlFile(config)
        sirca_instance.StartCommand(command)
        control_file_data = command.GetControlFileData()

        # save into file
        f = open(filename, 'w')
        f.write(control_file_data)
        f.close()


class PerlControlFile:
    log = logging.getLogger('config.PerlControlFile')

    """Load configuration from a Sirca perl control file into a python dictionary"""
    def __init__(self, **kwargs):

        if 'filename' in kwargs:
            # load a perl config file
            filename = kwargs['filename']
            sirca_instance = kwargs['sirca_instance']
            self.config_dict = self.__load_config(sirca_instance, filename)
            self.__expand_paramsfiles(filename)
        elif 'config_dict' in kwargs:
           self.config_dict = kwargs['config_dict']
        else:
           raise "PerlControlFile: bad arguments: " + kwargs
        

    def GetConfigDict(self):
        return self.config_dict

    def __expand_paramsfiles(self, filename):
        """recursively find and expand all external parameter files"""
                
        dirname = os.path.dirname(filename)
        def helper(obj):
            if type(obj) == dict:
                if "PARAMSFILES" in obj:
                    paramsfiles = obj["PARAMSFILES"]
                    del obj["PARAMSFILES"]
                    # add directory name
                    paramsfiles = [os.path.join(dirname,x) for x in paramsfiles]
                    # load
                    loaded_dicts = [self.__load_config(x) for x in paramsfiles]
                    # merge
                    for d in loaded_dicts:
                        obj.update(d)
                else:
                    # run recursively
                    for val in obj.values():
                        helper(val)
            if type(obj) == list:
                for val in obj:
                    helper(val)

        helper(self.config_dict)
                                        

    def __load_config(self, sirca_instance, filename):
        command = perl_commands.ReadParameters(filename)
        sirca_instance.StartCommand(command)
        config_dict = command.GetConfigDict()
        return config_dict
        

if __name__ == "__main__":
    import sys, pprint
    import main
    import profile

    app = main.MainApp(0)
    main.app = app

    #profile.run('app.MainLoop()', 'sircaprof')
    app.frame.LoadConfig('C:\sirca_gui\parameters\eugene\gui\dens_test.txt')
    
    print app.frame.control_file.config_root.GetConfigValue()
    app.frame.save_filename = 'C:\sirca_gui\parameters\config2.pl'
    app.frame.SaveConfig()

    app.MainLoop()
