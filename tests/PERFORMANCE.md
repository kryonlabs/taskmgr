# Task Manager performance measurements

Measured locally on Omega, 2026-11-21, from the canonical checkout with its
existing ignored local Ziran/Kryon overrides. Baseline: the previous Task Manager
milestone, before the grouping/sorting/text changes. Native GUI baseline used the
previous installed executable. Guest comparison used the same explicit profile
host, 400 × 480 surface, 250 ms surface idle interval, one-second process sampling,
private Xvfb and default 32 MiB main pool. These are local measurements, not CI. A build using only published locked
dependencies was not repeated; the package tool notes additional dependency
metadata in the local Kryon override.

## Deterministic model workload

Each row contains three grouping passes, three reverse-memory raw sorts and
three group sorts. Capacity, stable ordering and returned checksum are checked.
Times below are single matched observations, not statistical guarantees.

| Workload | Baseline grouping/raw/group sort | After grouping/raw/group sort |
| --- | --- | --- |
| Native 2,048 rows (µs) | 24,635 / 8,190 / 29,168 | 86 / 94 / 79 |
| Guest 128 rows (ms) | 140 / 39 / 106 | 3 / 4 / 3 |
| Guest 1,024 rows (ms) | default instruction budget exceeded | 21 / 43 / 37 |

The full native workload totals 61,993 → 259 µs; the comparable guest workload
285 → 10 ms. Full guest capacity now completes within the original instruction
budget. This synthetic model workload does not measure UI rendering or fabricate
process metrics. Native ordering tests compare every column and direction with
an independent stable-sort oracle; grouping checks case folding/Codex aliases.

## Actual guest UI

Matched 12-second idle windows followed by ten pointer events, each waiting for
the next app callback. The service supplies real guest tasks and pool readings.

| Measurement | Baseline | After |
| --- | --- | --- |
| Idle emulator CPU / wall (s) | 6.96 / 12.049 | 6.81 / 12.050 |
| Input emulator CPU / wall (s) | 3.36 / 5.846 | 3.29 / 5.785 |
| Steady main pool (bytes) | 24,747,104 | 24,513,408 |
| Main pool high water (bytes) | 25,693,376 | 25,634,144 |
| App declaration after startup (ms) | usually 11–14 | usually 11–14 |
| Input-to-next-callback (ms) | 542–662 | 422–663 |

Process-cell pixel digests matched exactly; status memory values legitimately
changed. The 233,696-byte steady-pool saving is real, but these runs do not show
a material overall GUI CPU/latency improvement. Canonical Kryon's surface loop
still performs full raster/presentation on idle and pointer movement; that
upstream hot path was reported to the owning coordinator. Callback times are
polling upper bounds and exclude completed pixel presentation.

## Native GUI and RSS

Matched 12-second idle and ten alternating Applications/Processes shortcuts:
baseline CPU 0.14 s idle / 0.04 s input; after 0.12 s / 0.04 s. Observed tab redraw
was approximately 29–31 ms in both runs, including input-tool and capture cost.
These small differences are not evidence of a material native GUI speedup.

Three 30-second RSS runs of the baseline installed executable peaked at 32,792,
32,564 and 30,716 KiB. Three after runs peaked at 30,960, 32,972 and 29,328 KiB.
Those characterization runs explicitly used `TASKMGR_RSS_LIMIT_KB=100000`; that
is measurement headroom, not a pass against the normal 30,720 KiB threshold.
Default-cap testing also reproduced a failure. The cap has not been raised.

The CPU comparison exposed 2,048 KiB of anonymous huge pages in one baseline
run and 4,096 KiB in an after run, tracking much of the RSS variance. File-backed
library residency is about 22 MiB. A tested process-local huge-page opt-out did
not remove pages already resident at startup or reliably meet the cap; it was
removed. Reducing fixed backing storage preserves capacity, but does not imply
that every reserved byte was resident before this change. The final installed executable also peaked at 30,760 KiB in the default-cap
30-second test, which failed by 40 KiB. Native memory remains
a limitation requiring upstream/runtime or allocation work; do not claim a stable
30 MiB cap from these results.

## Reproduction

From Task Manager:

```sh
make check test performance-test x11-test
TAIJIOS_TASK_MODULES=/mnt/storage/Projects/taijiosnet/taijios/appl/cmd make taiji-test taiji taiji-performance
python3 scripts/native-performance.py build/taskmgr-desktop
python3 scripts/guest-performance.py /mnt/storage/Projects/taijiosnet/taijios build/guest-profile.zx --seconds 30
./scripts/memory-test.sh
```

Run guest model artifact `/build/zx-smoke/taskmgr-performance.zx` using the
canonical emulator with `-p main=32M -r "$PWD" /dis/sh.dis -c 'zxrun /build/zx-smoke/taskmgr-performance.zx'`.
Copy only the built test artifact to that disposable test path first; no source
copy or installation is needed. The shell may end by killing its emulator after
printing the successful `MODEL_PERF ... checksum=1024` and exit status `0`.
The bridge/GUI lifecycle test remains the Taiji installer's existing command:

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PWD/appl/cmd/tcltk" python3 -u appl/wm/taskmgr_zx_test.py Linux/386/bin/emu --gui
```

That command is run from TaijiOS after its owner installs the stable Task Manager
artifact. It uses a disposable guest and only its owned sleeper for termination.

## Installation verification

The optimized native executable was installed with `./scripts/ziran.sh install`
and passed `TASKMGR_BINARY=/home/wao/.local/bin/taskmgr ./scripts/x11-test.sh`.
The installed native memory run failed the unchanged 30 MiB cap as described above.

The Taiji owner installed the stable `build/taskmgr.zx` artifact with its matching
emulator, launcher and panel. The installed SHA-256 is
`17e529fc13c7199f3e7f1efd73262a17bf20f3328c765f01f0bffe2844d3b55d`.
Its existing private-Xvfb lifecycle command exited zero with `TASK_BRIDGE_OK`,
`TASK_NAMESPACE_OK` and `TASK_GUI_OK`: real tasks, PID sorting, selection,
confirmed termination of an owned sleeper, live refresh and close at 32 MiB.
Earlier attempts using a new launcher overlay with the old installed emulator
failed ABI loading before the app ran; the matching installation resolved it.
An independent rerun of the installed lifecycle command also passed. Repeating
the 30-second profile against the matching newly installed stack produced 69
frames: steady pool 24,557,024 bytes, high water 25,187,680 bytes, idle emulator
CPU 16.83 / 30.031 seconds. The settled pool changed only 64 bytes. This last
run verifies the new runtime installation; it is not a matched baseline
comparison with the older runtime. Existing owner desktop instances were preserved.

Both installed artifacts include the checkout's pre-existing memory-first startup
preference. That owner hunk remains outside the app performance commit.
