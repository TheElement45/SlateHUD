"""Run the widget tests with Lua 5.1, the same language version used by Rainmeter.

Optional test dependency: python -m pip install --target Tests/.scratch-lua-runtime lupa
"""
from pathlib import Path
import sys
import tempfile

tests = Path(__file__).resolve().parent
sys.path.insert(0, str(tests / '.scratch-lua-runtime'))
from lupa.lua51 import LuaRuntime

root = tests.parent
media_entry = (root / '@Resources' / 'MediaUnicode.lua').read_text(encoding='utf-16')
with tempfile.TemporaryDirectory(prefix='.scratch-widgets-', dir=tests) as scratch:
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.execute((tests / 'WidgetRegression.lua').read_text(encoding='utf-8'))
    runtime.globals().RunWidgetTests(root.as_posix(), Path(scratch).as_posix())
    network = LuaRuntime(unpack_returned_tuples=True)
    network.execute((tests / 'NetworkRegression.lua').read_text(encoding='utf-8'))
    network.globals().RunNetworkTests(root.as_posix())
    apps = LuaRuntime(unpack_returned_tuples=True)
    apps.execute((tests / 'AppsRegression.lua').read_text(encoding='utf-8'))
    apps.globals().RunAppsTests(root.as_posix(), Path(scratch).as_posix())
    for test in ('TestLayout', 'TestGpu', 'TestNotes', 'TestMedia', 'TestVisualizer', 'TestDisks', 'TestWatchdog', 'TestBatteryUpdates'):
        polish = LuaRuntime(unpack_returned_tuples=True)
        polish.execute((tests / 'PolishRegression.lua').read_text(encoding='utf-8'))
        args = (root.as_posix(), Path(scratch).as_posix())
        if test == 'TestMedia':
            args += (media_entry,)
        polish.globals()[test](*args)
    notes = LuaRuntime(unpack_returned_tuples=True)
    notes.execute((tests / 'NotesRegression.lua').read_text(encoding='utf-8'))
    notes.globals().TestDailyNotes(root.as_posix(), Path(scratch).as_posix())
