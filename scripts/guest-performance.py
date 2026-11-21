#!/usr/bin/env python3
"""Measure an explicit Task Manager test host on a private default-32M guest."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import select
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('taiji', type=Path)
parser.add_argument('image', type=Path)
parser.add_argument('--seconds', type=int, default=12)
args = parser.parse_args()
if args.seconds < 1:
    parser.error("--seconds must be positive")
root = args.taiji.resolve()
sys.path.insert(0, str(root / 'appl/cmd/tcltk'))
from test_logwindow import private_display
from test_tcltk import launch, stop, until
for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'XAUTHORITY', 'DBUS_SESSION_BUS_ADDRESS',
            'XDG_RUNTIME_DIR', 'XDG_SESSION_ID', 'SESSION_MANAGER', 'HARMONY_GUEST_DISPLAY'):
    os.environ.pop(key, None)
os.environ['HARMONY_DESKTOP_RECOVERY'] = '0'

def ticks(pid):
    # Host emulator CPU is a benchmark measurement, never guest process data.
    fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    return int(fields[11]) + int(fields[12])

with TemporaryDirectory(dir=root / 'build/zx-smoke', prefix='taskmgr-perf-') as scratch, private_display() as env:
    image = Path(scratch) / 'profile.zx'
    shutil.copyfile(args.image, image)
    guest = launch(env, root / 'Linux/386/bin/emu', '-p', 'main=32M', '-r', root,
                   '-g', '800x600', 'wm/wm', '/dis/sh.dis', '-c',
                   f'zxrun -w /{image.relative_to(root)}', stdin=subprocess.DEVNULL,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output = bytearray()
    def drain():
        for stream in select.select([guest.stdout], [], [], 0)[0]:
            output.extend(os.read(stream.fileno(), 4096))
        assert len(output) < 32768, 'profile output exceeded bound'
        assert guest.poll() is None, output.decode(errors='replace')
        return output
    def command(*cmd):
        return subprocess.run(cmd, env=env, capture_output=True, check=True, timeout=8).stdout
    try:
        window = until(lambda: subprocess.run(['xdotool', 'search', '--onlyvisible', '--name', '^inferno$'], env=env, capture_output=True).stdout.strip(), 'guest window missing').decode()
        until(lambda: b'FRAME_PERF frame=2 ' in drain(), 'test app did not render', timeout=30)
        # Allow startup buffers to settle; then measure an unchanged idle window.
        time.sleep(2)
        drain()
        before = ticks(guest.pid)
        start = time.monotonic()
        end = start + args.seconds
        while time.monotonic() < end:
            select.select([guest.stdout], [], [], .1)
            drain()
        idle = {'wall_s': time.monotonic() - start, 'host_cpu_s': (ticks(guest.pid) - before) / os.sysconf('SC_CLK_TCK')}
        # Force input delivery without changing task data or sampling frequency.
        before = ticks(guest.pid)
        start = time.monotonic()
        latencies = []
        for index in range(10):
            frame_before = bytes(drain()).count(b"FRAME_PERF ")
            event_start = time.monotonic()
            command('xdotool', 'mousemove', '--window', window, str(90 + index % 2), '65')
            until(lambda: bytes(drain()).count(b"FRAME_PERF ") > frame_before, "input frame missing", timeout=5)
            latencies.append((time.monotonic() - event_start) * 1000)
        input_metrics = {'events': 10, 'callback_latency_ms': latencies, 'wall_s': time.monotonic() - start,
                         'host_cpu_s': (ticks(guest.pid) - before) / os.sysconf('SC_CLK_TCK')}
        # Capture only this private display. Retain a digest for matched UI runs.
        pixels = command('import', '-window', window, 'rgb:-')
        Path('build/taskmgr-performance.png').write_bytes(command('import', '-window', window, 'png:-'))
        cells = command('import', '-window', window, '-crop', '260x300+0+100', 'rgb:-')
        frames = [tuple(map(int, row)) for row in re.findall(rb'FRAME_PERF frame=(\d+) declaration_ms=(\d+) pool=(\d+) high=(\d+) valid=(-?\d+)', bytes(drain()))]
        assert len(frames) >= 12 and all(row[4] == 0 for row in frames), output.decode(errors='replace')
        assert max(row[3] for row in frames) <= 32 * 1024 * 1024, 'guest pool exceeded default 32 MiB'
        assert max(row[2] for row in frames[-6:]) - min(row[2] for row in frames[-6:]) <= 256 * 1024, 'guest pool did not settle'
        result = {'idle': idle, 'input': input_metrics, 'frames': len(frames),
                  'declaration_ms': [row[1] for row in frames],
                  'pool_bytes': [row[2] for row in frames], 'highwater_bytes': max(row[3] for row in frames),
                  'pixels_sha256': hashlib.sha256(pixels).hexdigest(),
                  'process_cells_sha256': hashlib.sha256(cells).hexdigest()}
        print(json.dumps(result, sort_keys=True))
    finally:
        stop(guest)
        diagnostic = guest.stderr.read(4096)
        guest.stdout.close()
        guest.stderr.close()
        assert not diagnostic, diagnostic.decode(errors='replace')
