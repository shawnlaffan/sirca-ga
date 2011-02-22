# vim: set ts=4 sw=4 et :
"""
Startup script for the GUI
"""
import sys
import main
import profile
import logging
import logging.config

#logging.config.fileConfig('sirca_gui.log.conf')
logging.debug('a')
logging.basicConfig(level='DEBUG')
logging.debug('a')

# load config file passed in as an argument
start_filename = None
if len(sys.argv) > 1:
    start_filename = sys.argv[1]

app = main.MainApp(start_filename)
main.app = app

#profile.run('app.MainLoop()', 'sircaprof')


app.MainLoop()
