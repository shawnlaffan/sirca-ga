# vim: set ts=4 sw=4 et :
class WorkspacePanel:
    """Base class for panels being shown in central notebok of the main window"""

    def GetKey(self):
        """Returns the key object associated with this
        panel. eg: configuration item in case of a 
        configuration panel. This objects allows the
        workspace page to be recycled rather than having
        to create a new one"""
        raise "IMPLEMENT ME"

    def GetCaption(self):
        raise "IMPLEMENT ME"

    def OnActivate(self):
        """called when this notebook page is selected"""
        pass

    def OnDeactivate(self):
       """called when this notebook page loses the selection"""
       pass
