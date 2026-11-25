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
parser.add_argument('--emu', type=Path)
parser.add_argument('--require-cpu', action='store_true')
parser.add_argument('--cycles', type=int, default=0, help='bounded table/modal/cancel cycles')
parser.add_argument('--output', type=Path, help='save complete measurement JSON')
args = parser.parse_args()
if not 1 <= args.seconds <= 300 or not 0 <= args.cycles <= 32:
    parser.error("--seconds must be 1..300 and --cycles 0..32")
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
    guest = launch(env, (args.emu or root / 'Linux/386/bin/emu').resolve(), '-p', 'main=32M', '-r', root,
                   '-g', '800x600', 'wm/wm', '/zx/sh.dis', '-c',
                   f'zxrun -w /{image.relative_to(root)}', stdin=subprocess.DEVNULL,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output = bytearray()
    def drain():
        for stream in select.select([guest.stdout], [], [], 0)[0]:
            output.extend(os.read(stream.fileno(), 4096))
        assert len(output) < 256 * 1024, 'profile output exceeded bound'
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
        if args.require_cpu:
            # Exercise the shared table header, then read its first rendered CPU
            # cell from this private guest. Cover the three-state sort cycle;
            # the initial guest focus click may be consumed by its WM.
            command('xdotool', 'mousemove', '--window', window, '100', '12', 'mousedown', '1', 'sleep', '.25', 'mouseup', '1')
            time.sleep(.7)
            sorted_busy = False
            for attempt in range(3):
                command('xdotool', 'mousemove', '--window', window, '218', '116', 'sleep', '.04', 'mousedown', '1', 'sleep', '.25', 'mouseup', '1')
                time.sleep(1.5)
                cell = command('import', '-window', window, '-crop', '40x26+200+130', '-resize', '400%', 'png:-')
                text = subprocess.run(['tesseract', 'stdin', 'stdout', '--psm', '7'], input=cell,
                                      env=env, capture_output=True, check=True, timeout=8).stdout.decode()
                print(f'CPU_GUI_FIRST attempt={attempt} text={text.strip()!r}', flush=True)
                reading = re.fullmatch(r'\s*(\d+(?:\.\d+)?)\s*', text)
                if reading and 5 < float(reading[1]) <= 100:
                    sorted_busy = True
                    break
            Path('build/taskmgr-performance.png').write_bytes(command('import', '-window', window, 'png:-'))
            assert sorted_busy, f'CPU header did not put a busy task first: {text!r}'
            print('TASK_CPU_GUI_SORT_OK: CPU header puts a real busy task first')
        workload = {'cycles': 0}
        if args.cycles:
            def click(x, y):
                command('xdotool', 'mousemove', '--window', window, str(x), str(y),
                        'sleep', '.04', 'mousedown', '1', 'sleep', '.25', 'mouseup', '1')
            def word(label):
                picture = command('import', '-window', window, '-resize', '200%', 'png:-')
                tsv = subprocess.run(['tesseract', 'stdin', 'stdout', '--psm', '11', 'tsv'],
                                     input=picture, env=env, capture_output=True, check=True, timeout=8).stdout
                for line in tsv.decode().splitlines()[1:]:
                    cells = line.split('\t')
                    if len(cells) == 12 and cells[11].lower().strip('.,:') == label:
                        return ((int(cells[6]) + int(cells[8]) // 2) // 2,
                                (int(cells[7]) + int(cells[9]) // 2) // 2)
                return None
            # Use the actual table and confirmation modal without killing any
            # task. Owned-process termination is covered by guest-lifecycle-test.
            click(100, 12)
            before = ticks(guest.pid)
            start = time.monotonic()
            modal_pixels = None
            for cycle in range(args.cycles):
                click(173, 116)  # PID column: every cycle exercises a sort.
                time.sleep(.8)
                click(70, 146)
                click(344, 444)
                no = until(lambda: word('no'), 'confirmation modal did not open', timeout=12)
                if modal_pixels is None:
                    modal_pixels = hashlib.sha256(command('import', '-window', window,
                        '-crop', '400x130+0+205', 'rgb:-')).hexdigest()
                # Keep sampling while the confirmation modal is open.
                time.sleep(1)
                click(*no)
                until(lambda: not word('no'), 'confirmation modal did not close', timeout=12)
                drain()
                print(f'TABLE_MODAL_CYCLE_OK cycle={cycle + 1}', flush=True)
            workload = {'cycles': args.cycles, 'wall_s': time.monotonic() - start,
                        'host_cpu_s': (ticks(guest.pid) - before) / os.sysconf('SC_CLK_TCK'),
                        'modal_pixels_sha256': modal_pixels}
        # Capture only this private display. Retain a digest for matched UI runs.
        pixels = command('import', '-window', window, 'rgb:-')
        Path('build/taskmgr-performance.png').write_bytes(command('import', '-window', window, 'png:-'))
        cells = command('import', '-window', window, '-crop', '260x300+0+100', 'rgb:-')
        frames = [tuple(map(int, row)) for row in re.findall(rb'FRAME_PERF frame=(\d+) declaration_ms=(\d+) pool=(\d+) high=(\d+) valid=(-?\d+)', bytes(drain()))]
        assert len(frames) >= 12 and all(row[4] == 0 for row in frames), output.decode(errors='replace')
        assert max(row[3] for row in frames) <= 32 * 1024 * 1024, 'guest pool exceeded default 32 MiB'
        assert max(row[2] for row in frames[-6:]) - min(row[2] for row in frames[-6:]) <= 256 * 1024, 'guest pool did not settle'
        if args.require_cpu:
            cpu_rows = re.findall(rb'FRAME_CPU valid=(\d+) measured=(\d+) percent=([0-9.]+)', bytes(drain()))
            assert cpu_rows and any(int(valid) and int(count) and float(value) > 0
                                    for valid, count, value in cpu_rows), 'no live CPU reading'
            print('TASK_CPU_GUI_MODEL_OK: live CPU samples while shared app renders')
        result = {'idle': idle, 'input': input_metrics, 'workload': workload, 'frames': len(frames),
                  'declaration_ms': [row[1] for row in frames],
                  'pool_bytes': [row[2] for row in frames], 'highwater_bytes': max(row[3] for row in frames),
                  'pixels_sha256': hashlib.sha256(pixels).hexdigest(),
                  'static_header_sha256': hashlib.sha256(command('import', '-window', window, '-crop', '400x130+0+0', 'rgb:-')).hexdigest(),
                  'process_cells_sha256': hashlib.sha256(cells).hexdigest()}
        if args.output:
            args.output.write_text(json.dumps(result, sort_keys=True) + '\n')
            print(json.dumps({key: result[key] for key in ('idle', 'workload', 'frames', 'highwater_bytes', 'pixels_sha256')}, sort_keys=True))
        else:
            print(json.dumps(result, sort_keys=True))
    finally:
        stop(guest)
        diagnostic = guest.stderr.read(4096)
        guest.stdout.close()
        guest.stderr.close()
        assert not diagnostic, diagnostic.decode(errors='replace')
