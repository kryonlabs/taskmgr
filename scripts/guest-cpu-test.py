#!/usr/bin/env python3
"""Run the real CPU model probe beside an owned sleeper in a disposable guest."""
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
with TemporaryDirectory(dir=root / 'build/zx-smoke', prefix='taskmgr-cpu-') as directory:
    image = Path(directory) / 'probe.zx'
    shutil.copyfile(Path(__file__).resolve().parents[1] / 'build/taiji-cpu-live.zx', image)
    command = f"bind '#p' /prog; sleep 10 &; sleep 1; zxrun /{image.relative_to(root)}"
    result = subprocess.run([emu, '-p', 'main=32M', '-r', root, '/zx/sh.dis', '-c', command],
                            env=env, start_new_session=True, capture_output=True, timeout=30)
    assert len(result.stdout) <= 128 * 1024, 'guest probe output exceeded bound'
    assert result.returncode in (0, -9), (result.returncode, result.stderr[:4096])
    assert not result.stderr, result.stderr[:4096]
    assert b'TASK_CPU_LIVE_OK ' in result.stdout and result.stdout.endswith(b'\n0\n'), result.stdout
    print(result.stdout.decode(), end='')
