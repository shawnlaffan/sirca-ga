# vim: set ts=4 sw=4 et :
"""
This module defines a control for editing GLOBAL_PARAMETERS
field found in SIRCA configuration files

It is basically a chronological list of "events".
There are several types of events and additional 
parameters for each type.
"""
import wx
import wx.grid as gridlib
import logging
import copy

#---------------------------------------------------------------------------

class EventsDataTable(gridlib.PyGridTableBase):
    """Grid table for the events editor
    
    It manages multiple events ordered by time in a grid.
    If time is changed, the grid is re-ordered
    
    Each event also has a type and some type-specific parameters
    There is one parameter for each row
    """
    log = logging.getLogger('config.EventsDataTable')
    def __init__(self):
        gridlib.PyGridTableBase.__init__(self)

        self.col_labels = ['Time', 'Event', 'Parameter', 'Value']

        self.data_types = [gridlib.GRID_VALUE_NUMBER,
                          gridlib.GRID_VALUE_CHOICE + ':', # to be completed when loading events!
                          gridlib.GRID_VALUE_STRING,
                          gridlib.GRID_VALUE_STRING,
                          ]

        #                  gridlib.GRID_VALUE_CHOICE + ':only in a million years!,wish list,minor,normal,major,critical',

        self.rows = []      # rows[index] -> event
        self.events = []    # events ordered sequentially by time
        self.types = {}     # type name -> { parameter name -> default value }
        self.current_nrows = 0
        
    #--------------------------------------------------
    # data access

    def GetEvents(self):
        """return copy of the list of events, sorted by time"""
        # don't return 'new' psuedo-event
        return copy.deepcopy(self.events[:-1])

    def __get_test_events(self):
        return [
                { 'time':8, 'type':'E3', 'params' : { 'offset' : '1234', 'bias' : '53' } },
                { 'time':7, 'type':'E2', 'params' : {} },
                { 'time':9, 'type':'E4', 'params' : { 'last' : 'yes' } },
                { 'time':6, 'type':'E1', 'params' : { 'P1' : 'x', 'P2' : 'y', 'P3' : 'z' } },
               ]

    def __get_test_types(self):
        return {
                'E3' : { 'offset' : '_333', 'bias' : '_53' },
                'E2' : {},
                'E4' : { 'last' : '_yes' },
                'E1' : { 'P1' : '_x', 'P2' : '_y', 'P3' : '_z' },
               }

    def InitTestData(self):
        self.InitData(self.__get_test_events(), self.__get_test_types() )

    def InitData(self, events, types):
        """called by the model/control layer to add data to the grid"""
        # load data
        self.events = events
        self.types = types
        
        # make types choices for the event (2nd) columns
        typenames = self.types.keys()
        if 'new' in typenames:
            raise "'new' is special and not allowed as a type name"
        typenames.sort()
        self.data_types[1] += ','.join(typenames)

        # sort events
        self.events.sort( key = lambda e: e['time'] )

        # append 'new' "event"
        self.__append_new_event()
        
        for e in self.events:
            # turn 'params' into an ordered list of tuples
            dparams = e['params']
            kparams = dparams.keys()
            kparams.sort()
            lparams = []
            for key in kparams:
                lparams.append( (key, dparams[key]) )
            e['params'] = lparams

            # set number of parameters for each event ('nparams')
            e['nparams'] = len ( lparams )

        # create our data structures to allocate and keep track of rows
        self.__rebuild_event_rows()

        # add any rows
        rows_added = len(self.rows) - self.current_nrows
        self.__signal_rows_changed(0, rows_added)

        # refresh
        self.__refresh()

    def __rebuild_event_rows(self):
        """allocate and keep track of rows"""
        self.rows = []
        for e in self.events:
            # set number of rows needed for each event ('nrows')
            nrows = max(1, e['nparams'])
            e['nrows'] = nrows

            # set 'start_row'
            e['start_row'] = len(self.rows)

            # initialise event reference for each row
            for i in range(nrows):
                self.rows.append(e)        

    def __append_new_event(self):
        self.events.append( { 'time':None, 'type':'new', 'nparams':0, 'params':{} } )
    
    #--------------------------------------------------
    # required methods for the wxPyGridTableBase interface

    def GetNumberRows(self):
        nrows = len(self.rows)
        self.log.debug('--> GetNumberRows: %d', nrows)
        self.current_nrows = nrows
        return nrows

    def GetNumberCols(self):
        ncols = len(self.col_labels)
        return ncols

    def __translate_coords(self, row, col):
        """
        Validates coords and returns (event, event_row),
          where event_row is the given rows position for that event (eg: 0th row for this event)
        """
        assert(row >= 0 and row < len(self.rows) )
        assert(col >= 0 and col < 4)

        event = self.rows[row]
        event_row = row - event['start_row']
        assert(event_row >= 0)
        
        return (event, event_row)

    def IsEmptyCell(self, row, col):
        """
        returns whether a cell should be considered blank
          weird - used only for obscure stuff like CTRL-arrows.
            a rendered is still created and GetValue is called
        """
        
        # get event associated with this row,col
        (event, event_row) = self.__translate_coords(row, col)

        if col == 0 or col == 1:
            # time - enabled on an event's first row
            # type - enabled on an event's first row
            val = event_row != 0

            # but time is empty for the 'new' event
            if not val and col == 0 and event['type'] == 'new':
                val = True
        elif col == 2 or col == 3:
            # parameters
            nparams = event['nparams']
            assert(nparams >= 0)

            if nparams == 0:
                val = True
            else:
                val = False

        else:
            assert(False)

        #self.log.debug( '--> IsEmptyCell (%d,%d) -> %s', row, col, val)
        return val
    
    def GetValue(self, row, col):
        """called by grid to get contents of a grid cell"""
        # get event associated with this row,col
        (event, event_row) = self.__translate_coords(row, col)

        if col == 0:
            # time
            if event_row == 0:
                if event['type'] == 'new':
                    val = ''
                else:
                    assert( event['time'] >= 0)
                    val = event['time']
            else:
                val = ''

        elif col == 1:
            # type - enabled on an event's first row
            if event_row == 0:
                val = event['type']
            else:
                val = ''

        elif col == 2 or col == 3:
            nparams = event['nparams']
            assert(nparams >= 0)
            if nparams == 0:
                val = ''
            elif col == 2:                        
                # parameter name
                val = event['params'][event_row][0]
            elif col == 3:
                # parameter value
                val = event['params'][event_row][1]
        else:
            assert(False)

        #self.log.debug( '--> GetValue (%d,%d) -> %s', row, col, val)
        return val

    def SetValue(self, row, col, value):
        """called by grid to set contents of a cell"""

        (event, event_row) = self.__translate_coords(row, col)
        if col == 0:
            # time changed
            assert(event_row == 0) # time can only be changed on event's first row!
            new_time = int(value)
            event['time'] = new_time

            # insert event into its new position
            self.events.remove(event)
            hi = len(self.events)
            lo = 0
            while lo < hi:
                mid = (lo+hi)//2
                e_time = self.events[mid]['time']
                if e_time is None:
                    # 'new' event always comes last
                    hi = mid
                elif new_time < e_time:
                    hi = mid
                else:
                    lo = mid + 1
            self.events.insert(lo, event)
            self.log.debug('event time changed to %d for %s', new_time, event)
            self.log.debug('sorted event list: %s', self.events)

            # re-allocate rows            
            self.__rebuild_event_rows()
            self.__refresh()


        elif col == 1:
            # type changed
            cur_type = event['type']
            cur_nrows = event['nrows']
            new_type = value
            new_params = self.types[value]
            new_nrows = max(1, len(new_params.keys()))
            self.log.debug('type %s (%d rows) changed to %s (%d rows)',
                      cur_type, cur_nrows, new_type, new_nrows)

            # reset params to type's defaults,
            #   turning 'params' into an ordered list of tuples
            new_param_names = new_params.keys()
            new_param_names.sort()
            lparams = []
            for key in new_param_names:
                lparams.append( (key, new_params[key]) )

            # update event
            event['type'] = new_type
            event['params'] = lparams
            event['nparams'] = len ( new_param_names )
            event['nrows'] = new_nrows

            # if added new event:
            new_row = 0
            if cur_type == 'new':
                # set time to last time + 1
                assert(len(self.events) >= 1)
                if len(self.events) == 1:
                    event['time'] = 0 # no other events..
                else:
                    event['time'] = self.events[-2]['time'] + 1

                # add another 'new' event
                self.__append_new_event()
                new_row = 1
                
            # re-allocate rows            
            self.__rebuild_event_rows()

            # tell grid that if we added/removed any rows
            rows_added = new_nrows - cur_nrows + new_row
            self.__signal_rows_changed(event_row, rows_added)

            self.__refresh()
            
        elif col == 2:
            assert(false) # parameter names should be read-only
        elif col == 3:
            # parameter value changed
            param_name = event['params'][event_row][0]
            event['params'][event_row] = (param_name, value)
            self.log.debug('param %s changed to %s', param_name, value)
           
        else:
            assert(false) # col out-of-bounds

    def GetColLabelValue(self, col):
        """Called when the grid needs to display labels"""
        return self.col_labels[col]

    def GetTypeName(self, row, col):
        """Called to get a cell's data type"""
        if self.IsEmptyCell(row, col):
            # empty cells will be blank readonly strings
            return gridlib.GRID_VALUE_STRING
        else:
            return self.data_types[col]

    def GetAttr(self, row, col, someExtraParameter ):
        """called to get custom formatting - readonly, fonts, colours,..."""
        # empty cells will be blank readonly strings
        # so too is the Parameters column
        if col == 2 or self.IsEmptyCell(row, col):
            attr = gridlib.GridCellAttr()
            attr.SetReadOnly(1)
            return attr
        else:
            # default
            return None
        

    # Called to determine how the data can be fetched and stored by the
    # editor and renderer.  This allows you to enforce some type-safety
    # in the grid.
    def CanGetValueAs(self, row, col, typeName):
        colType = self.data_types[col].split(':')[0]
        if typeName == colType:
            return True
        else:
            return False

    def CanSetValueAs(self, row, col, typeName):
        return self.CanGetValueAs(row, col, typeName)


    def __refresh(self):
        self.log.debug('loading events: %s', self.events)
        self.log.debug('          rows: %s', self.rows)
        self.__tell_grid(gridlib.GRIDTABLE_REQUEST_VIEW_GET_VALUES)

    def __refresh(self):
        self.log.debug('loading events: %s', self.events)
        self.log.debug('          rows: %s', self.rows)
        self.__tell_grid(gridlib.GRIDTABLE_REQUEST_VIEW_GET_VALUES)

    def __signal_rows_changed(self, pos, rows_added):
        if rows_added > 0:
            self.__signal_rows_inserted(pos, rows_added)
        elif rows_added < 0:
            rows_removed = -1 * rows_added
            self.__signal_rows_deleted(pos, rows_removed)  
    
    def __signal_rows_inserted(self, pos, numrows):
        self.log.debug('inserted %d rows at %d', numrows, pos)
        self.__tell_grid(gridlib.GRIDTABLE_NOTIFY_ROWS_INSERTED, pos, numrows)

    def __signal_rows_deleted(self, pos, numrows):
        self.log.debug('deleted %d rows at %d', numrows, pos)
        self.__tell_grid(gridlib.GRIDTABLE_NOTIFY_ROWS_DELETED, pos, numrows)
        
        
    def __tell_grid(self, *args):
        msg = gridlib.GridTableMessage(self, *args)
        view = self.GetView()
        if view:
            view.ProcessTableMessage(msg)



#---------------------------------------------------------------------------
# TESTING
#---------------------------------------------------------------------------


class EventsTableGrid(gridlib.Grid):
    """After creating call GetTable() and use SetConfigVale/GetConfigValue"""
    def __init__(self, parent):
        gridlib.Grid.__init__(self, parent, -1)

        self.table = EventsDataTable()

        # The second parameter means that the grid is to take ownership of the
        # table and will destroy it when done.  Otherwise you would need to keep
        # a reference to it and call it's Destroy method later.
        self.SetTable(self.table, True)

        self.SetRowLabelSize(0)
        self.SetMargins(0,0)
        self.AutoSizeColumns(False)

        gridlib.EVT_GRID_CELL_LEFT_DCLICK(self, self.OnLeftDClick)

    def GetTable(self):
        """Returns EventsDataTable that manages the grid"""
        return self.table

    # I do this because I don't like the default behaviour of not starting the
    # cell editor on double clicks, but only a second click.
    def OnLeftDClick(self, evt):
        if self.CanEnableCellControl():
            self.EnableCellEditControl()


#---------------------------------------------------------------------------

class TestFrame(wx.Frame):
    def __init__(self, parent, log):

        wx.Frame.__init__(
            self, parent, -1, "Testbed for events editor grid", size=(640,480)
            )

        p = wx.Panel(self, -1, style=0)
        grid = EventsTableGrid(p)
        grid.GetTable().InitTestData()
        b = wx.Button(p, -1, "Another Control...")
        b.SetDefault()
        self.Bind(wx.EVT_BUTTON, self.OnButton, b)
        b.Bind(wx.EVT_SET_FOCUS, self.OnButtonFocus)
        bs = wx.BoxSizer(wx.VERTICAL)
        bs.Add(grid, 1, wx.GROW|wx.ALL, 5)
        bs.Add(b)
        p.SetSizer(bs)

    def OnButton(self, evt):
        print "button selected"

    def OnButtonFocus(self, evt):
        print "button focus"


#---------------------------------------------------------------------------

if __name__ == '__main__':
    import sys
    logging.basicConfig(level=logging.DEBUG)
    app = wx.PySimpleApp()
    frame = TestFrame(None, sys.stdout)
    frame.Show(True)
    app.MainLoop()


#---------------------------------------------------------------------------
