"""
Helper dialog for editing lists found in SIRCA
parameters.

Basically displays an editable listbox with
add and remove buttons
"""

import sys
import wx
import wx.lib.mixins.listctrl  as  listmix

#---------------------------------------------------------------------------

class EditableListCtrl(wx.ListCtrl, listmix.TextEditMixin):

    def __init__(self, parent, ID, pos=wx.DefaultPosition,
                 size=wx.DefaultSize, style=0, datalist = []):
        wx.ListCtrl.__init__(self, parent, ID, pos, size, style)

        self.InsertColumn(0, "Column 1")

        self.Populate(datalist)
        listmix.TextEditMixin.__init__(self)

    def Populate(self, datalist):
        self.datalist = datalist
        i = 0
        for item in datalist:
            index = self.InsertStringItem(sys.maxint, str(item))
            self.SetItemData(index, i)
            i = i + 1

    def GetResultantData(self):
        result = []
        for i in range(self.GetItemCount()):
            s = self.GetItemText(i)
            result.append(int(s)) # converting everything to integers
        return result
            
            




class ListEditDlg(wx.Dialog):
    def __init__(self, parent, caption, datalist):
        pre = wx.PreDialog()
        pre.Create(parent, -1, caption,
            wx.DefaultPosition, wx.DefaultSize,
            style=wx.DEFAULT_DIALOG_STYLE | wx.RESIZE_BORDER)
        self.PostCreate(pre)

        # sizers
        vsizer = wx.BoxSizer(wx.VERTICAL)
        hsizer = wx.BoxSizer(wx.HORIZONTAL)

        #list
        listID = wx.NewId()
        self.list = EditableListCtrl(self, listID,
                style=wx.BORDER_NONE | wx.LC_REPORT | wx.LC_NO_HEADER | wx.LC_HRULES,
                datalist = datalist)

        #buttons
        self.new_btn = wx.Button(self, -1, "Add")
        self.del_btn = wx.Button(self, -1, "Delete")
        self.ok_btn = wx.Button(self, wx.ID_OK, "OK")
        self.cancel_btn = wx.Button(self, wx.ID_CANCEL, "Cancel")
        
        self.Bind(wx.EVT_BUTTON, self.OnNewItem, self.new_btn)
        self.Bind(wx.EVT_BUTTON, self.OnDeleteItem, self.del_btn)

        #layout
        hsizer.Add(self.new_btn, 0, wx.EXPAND)
        hsizer.Add(self.del_btn, 0, wx.EXPAND)
        hsizer.Add(self.ok_btn, 0, wx.EXPAND)
        hsizer.Add(self.cancel_btn, 0, wx.EXPAND)
        
        vsizer.Add(self.list, 1, wx.EXPAND)
        vsizer.Add(hsizer, 0, wx.EXPAND)
        
        self.SetSizer(vsizer)
        self.SetAutoLayout(True)
    
    def OnNewItem(self, event):
        numItems = self.list.GetItemCount()
        if numItems > 0:
            lastText = self.list.GetItemText(numItems - 1)
        else:
            lastText = "0"
        
        index = self.list.InsertStringItem(sys.maxint, lastText)

    def OnDeleteItem(self, event):
        if self.list.GetSelectedItemCount() > 0:
            selected = self.list.GetFirstSelected()
            self.list.DeleteItem(selected)
            
            # select next item
            if self.list.GetItemCount() > 0:
                select = min(selected, self.list.GetItemCount() - 1)
                self.list.Select(select, True)

    def GetResultantData(self):
        """Retrieve the final list of data generated by the user"""
        return self.list.GetResultantData()
        

if __name__ == '__main__':
    class SimpleApp(wx.App):
        def OnInit(self):
            data = [1,2,3]
            frame = ListEditDlg(None, "Editing DENSITY_PARAMS", data)
            frame.Show(True)
            self.SetTopWindow(frame)
            return 1

    SimpleApp(0).MainLoop()