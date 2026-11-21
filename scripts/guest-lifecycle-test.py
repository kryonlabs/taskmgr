#!/usr/bin/env python3
"""Run the canonical guest's real lifecycle test against this project's artifact."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('taiji', type=Path)
parser.add_argument('--emu', type=Path)
args = parser.parse_args()
root = args.taiji.resolve()
emu = (args.emu or root / 'Linux/386/bin/emu').resolve()
env = os.environ.copy()
for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'XAUTHORITY', 'DBUS_SESSION_BUS_ADDRESS',
            'XDG_RUNTIME_DIR', 'XDG_SESSION_ID', 'SESSION_MANAGER', 'HARMONY_GUEST_DISPLAY'):
    env.pop(key, None)
env['HARMONY_DESKTOP_RECOVERY'] = '0'
env['PYTHONDONTWRITEBYTECODE'] = '1'
env['PYTHONPATH'] = str(root / 'appl/cmd/tcltk')
with TemporaryDirectory(dir=root / 'build/zx-smoke', prefix='taskmgr-lifecycle-') as directory:
    shutil.copyfile(Path(__file__).resolve().parents[1] / 'build/taskmgr.zx',
                    Path(directory) / 'taskmgr.zx')
    subprocess.run(['python3', '-u', str(root / 'appl/wm/taskmgr_zx_test.py'), str(emu),
                    '--cpu', '--gui', '--guest-overlay', directory],
                   env=env, cwd=root, check=True)
