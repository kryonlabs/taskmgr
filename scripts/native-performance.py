#!/usr/bin/env python3
"""Measure one native Task Manager on a scrubbed private Xvfb display."""
import argparse
import json
import os
from pathlib import Path
import select
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('binary', type=Path)
parser.add_argument('--seconds', type=int, default=12)
args = parser.parse_args()
if args.seconds < 1:
    parser.error('--seconds must be positive')
binary = args.binary.resolve()

def ticks(pid):
    fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    return int(fields[11]) + int(fields[12])

def until(check, timeout=8):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        value = check()
        if value:
            return value
        time.sleep(.01)
    raise AssertionError('native window/redraw timed out')

with tempfile.TemporaryDirectory(dir='build', prefix='native-perf-') as scratch:
    env = {'PATH': os.environ['PATH'], 'HOME': str(Path(scratch).resolve()),
           'TMPDIR': str(Path(scratch).resolve()), 'HARMONY_DESKTOP_RECOVERY': '0'}
    read_fd, write_fd = os.pipe()
    display = subprocess.Popen(['Xvfb', '-displayfd', str(write_fd), '-screen', '0',
                                '800x600x24', '-nolisten', 'tcp'], env=env,
                               pass_fds=(write_fd,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(write_fd)
    app = None
    try:
        assert select.select([read_fd], [], [], 8)[0], 'private Xvfb did not start'
        env['DISPLAY'] = ':' + os.read(read_fd, 32).decode().strip()
        def command(*cmd):
            return subprocess.run(cmd, env=env, capture_output=True, check=True, timeout=8).stdout
        app = subprocess.Popen([str(binary)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        def find():
            assert app.poll() is None, 'native app exited'
            return subprocess.run(['xdotool', 'search', '--onlyvisible', '--pid', str(app.pid)], env=env, capture_output=True).stdout.strip()
        window = until(find).decode().splitlines()[0]
        command('xdotool', 'windowfocus', window)
        time.sleep(2)
        start = time.monotonic(); before = ticks(app.pid)
        time.sleep(args.seconds)
        idle = {'wall_s': time.monotonic() - start, 'cpu_s': (ticks(app.pid) - before) / os.sysconf('SC_CLK_TCK')}
        latencies = []
        start = time.monotonic(); before = ticks(app.pid)
        # Tab highlight gives an observable pixel change for each delivered input.
        def tab_pixels():
            return command('import', '-window', window, '-crop', '300x28+0+20', 'rgb:-')
        for index in range(10):
            pixels = tab_pixels()
            event_start = time.monotonic()
            command('xdotool', 'key', '--window', window, '--clearmodifiers', 'ctrl+' + ('1' if index % 2 == 0 else '2'))
            until(lambda: tab_pixels() != pixels)
            latencies.append((time.monotonic() - event_start) * 1000)
        active = {'wall_s': time.monotonic() - start, 'cpu_s': (ticks(app.pid) - before) / os.sysconf('SC_CLK_TCK'),
                  'events': 10, 'observed_redraw_ms': latencies}
        status = {}
        for line in Path(f'/proc/{app.pid}/status').read_text().splitlines():
            if line.split(':')[0] in ('VmRSS', 'RssAnon', 'RssFile', 'RssShmem', 'THP_enabled'):
                key, value = line.split(':', 1); status[key] = value.strip()
        huge = [line for line in Path(f'/proc/{app.pid}/smaps_rollup').read_text().splitlines() if line.startswith('AnonHugePages:')]
        print(json.dumps({'idle': idle, 'input': active, 'memory': status, 'huge': huge}, sort_keys=True))
    finally:
        os.close(read_fd)
        for process in (app, display):
            if process is not None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait()
