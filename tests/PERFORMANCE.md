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

## Guest CPU follow-up

The CPU-capable Taiji emulator and this checkout were tested locally with the
same ignored canonical dependency overrides and explicit full-raster surface
path (the then-current `retain_paint=false` API, now normal `Run`). This does not validate a published-dependencies-only
build. Task CPU uses cumulative guest execution nanoseconds, task incarnation,
captured monotonic time and the measured capture timestamp error. New/reset or
invalid readings remain unavailable; no host process statistics supply app data.

The real 32 MiB model probe measured its busy ZX task at 99.979236% and its owned
Sleep task at 0%, and verified CPU sorting. Pure arithmetic tests cover the first
sample, idle/busy deltas, resets/reuse, nonpositive elapsed time, exact/excessive
capture-skew bounds and signed-limit arithmetic. Typed model tests cover CPU
availability, aggregation, sorting, capture failure and bounded refresh storage.

The shared GUI profile then completed 60 frames over a 30-second idle window and
ten input events with real CPU readings. Main pool settled at 25,579,200 bytes;
high water was 26,252,928 bytes, within 33,554,432 bytes. The last six readings
were stable; total settled growth was 32 bytes. Private-display OCR showed numeric
per-task CPU and a `Task CPU` total. CPU time remains explicitly unavailable.
This run is a CPU correctness/memory gate, not a matched performance comparison.

```sh
make check test x11-test
TAIJIOS_TASK_MODULES=/mnt/storage/Projects/taijiosnet/taijios/appl/cmd make taiji-test taiji taiji-performance taiji-cpu-live
python3 scripts/guest-cpu-test.py /mnt/storage/Projects/taijiosnet/taijios --emu /mnt/storage/Projects/taijiosnet/taijios/emu/Linux/o.emu
python3 scripts/guest-performance.py /mnt/storage/Projects/taijiosnet/taijios build/guest-profile.zx --seconds 30 --emu /mnt/storage/Projects/taijiosnet/taijios/emu/Linux/o.emu --require-cpu
```

A separate 39-frame private GUI run exercised CPU header sorting through its
sort cycle and OCR-verified the real busy task first (`99`), with the high water
unchanged. The first focus/header attempt did not change sort; two later clicks
selected ascending then descending order. The test allows this bounded cycle.

The production GUI lifecycle subsequently reproduced a 32 MiB failure after the
owned sleeper was confirmed killed, before View/Refresh/Exit. Both observed
allocator PCs map to `compiler_exec_ExecResizeAddresses` in the guest interpreter;
requests were about 2.6 MiB with about 29.6 MiB already allocated. Two runs failed
at different address-producing instructions (PixmapBlendMask and QueuePaint).
The runtime owner has this evidence; this app does not change its interpreter.
The core address-slot fix resolved this failure on the same previous artifact;
the current normal/retained comparison below uses that fixed runtime.

```sh
python3 scripts/guest-lifecycle-test.py /mnt/storage/Projects/taijiosnet/taijios --emu /mnt/storage/Projects/taijiosnet/taijios/emu/Linux/o.emu
```

The guest owner subsequently installed normal production bundle
`1750e67b7246c9b3d5db8a0694a903c755b252a11b7c29ebbfbeb78ab9d3f069`
with the fixed matching emulator. Its private-Xvfb 32 MiB test passed owned-sleeper
termination, live refresh, PID sorting, resize, bottom-control reflow twice,
close and reopen (installation receipt `7621fa0cfbd827f29d6d3895638a5447b777`).
The earlier installation report above applies to the preceding performance
milestone. Native RSS limitations remain unchanged.

## Fixed-runtime paired table/dialog run

The normal comparison used `Surface.Run(window, Draw, 250)`. The explicit
profile test builds the same `App.Frame` and observations twice, selecting
`Run` or experimental `RunRetained` with `TASKMGR_RETAINED`. Neither changes task
capacity, the one-second process sampler or the 250 ms callback interval.
After the full lifecycle gate below passed, the production entry was promoted
to `Surface.RunRetained(window, Draw, 250)`.

Both runs used the same fixed Linux/386 emulator (Build ID
`22e6b24cff005f119b9261619e38b4ab94598f60`), main pool 32 MiB, private Xvfb and
scrubbed display/session environment. The workload is 90 seconds idle, ten
pointer events, actual CPU-header sorting verified from private pixels, then six
PID sort/select/End Process confirmation/No cycles while sampling continues.
No task is killed by this profiling workload; the separate canonical guest
lifecycle suite tests killing its owned disposable sleeper, refresh and close.

| Local measurement | Normal | Retained |
| --- | --- | --- |
| Idle emulator CPU / elapsed (s) | 54.10 / 90.029 | 14.53 / 90.037 |
| Six table/dialog cycles CPU / elapsed (s) | 75.94 / 82.050 | 24.71 / 38.551 |
| App callbacks | 341 | 523 |
| Final main pool (bytes) | 24,145,888 | 23,302,080 |
| Main pool high water (bytes) | 24,480,576 | 24,119,616 |
| Last six pool samples' range (bytes) | 0 | 0 |

Both completed all cycles and numeric CPU assertions. Static table-header pixels
matched exactly, as did the confirmation-dialog crop. Full-image hashes differ
because live CPU/memory values differ; they are not a pixel-equality verdict.
The retained run used about 73% less idle CPU and 67% less workload CPU in this
single pair. These observations are not a statistical guarantee or a pure render
microbenchmark; other managed tasks shared the machine. OCR and waits are part
of the elapsed workload. The larger retained callback count reflects its faster
loop, rather than a changed sampling or callback interval.

Only the real main allocator pool/high water is exposed to the profile. Direct
interpreter address-slot high water and presentation counts are unavailable in
the typed app API, so these results do not invent either measurement. The guest
runtime owner separately instruments address lifetime and installed lifecycle.

```sh
TAIJIOS_TASK_MODULES=/mnt/storage/Projects/taijiosnet/taijios/appl/cmd make taiji taiji-performance
python3 scripts/guest-performance.py /mnt/storage/Projects/taijiosnet/taijios build/guest-profile.zx --seconds 90 --cycles 6 --emu /mnt/storage/Projects/taijiosnet/taijios/emu/Linux/o.emu --require-cpu --output build/guest-normal-long.json
python3 scripts/guest-performance.py /mnt/storage/Projects/taijiosnet/taijios build/guest-profile-retained.zx --seconds 90 --cycles 6 --emu /mnt/storage/Projects/taijiosnet/taijios/emu/Linux/o.emu --require-cpu --output build/guest-retained-long.json
```

Bundle SHA-256 identities: normal production `1750e67b7246c9b3d5db8a0694a903c755b252a11b7c29ebbfbeb78ab9d3f069`,
normal profile `77d4a7ed07cb5eed83260ab845d49e3903f94d349ff8c4620dd77179f0bc3e6e`,
retained profile `4c67f924659b8e882bb8cc2773a39912ad5bb12ec570580074ee6a151cfec2e4`.
Static header digest: `d372ed887957bd0dfd72ec3ac8454d9485db4caa74392fa9f0391b5144091084`;
modal digest: `15775f17018dbbe29622d038bae779356ec04a1c68c836efd10cea05d922e5ed`.

The uninstrumented retained lifecycle candidate used the same production host
with compile-time `TASKMGR_RETAINED`; no UI or profile logger was copied. It was built
with `TAIJIOS_TASK_MODULES=/mnt/storage/Projects/taijiosnet/taijios/appl/cmd make taiji-retained-test`.
Its explicit test artifact is `build/taskmgr-retained-test.zx`, SHA-256
`9f82ce6c01013022ff41739baa45949badf89151e4d40f189c0a7a06658cb03b`.
The guest owner passed the identical 32 MiB owned-sleeper termination, View
refresh, grow/shrink with bottom-control reflow, close/reopen/repeat and
panel/chrome suite on these bytes (receipt `7a766798fc947f3150f4c75327ae7a426cd4`).
It atomically installed the tested artifact at `dis/wm/taskmgr.zx`, verified byte
equality and passed the installed production-path recheck with
`--cpu --gui --require-window-resize` (receipt `1ea00a52cae5c616dcb9bdfd850cd90d464a`).
Existing desktop instances were preserved.

The guest owner also measured successful interpreter address-table allocation
capacity under hardware GDB breakpoints during the full lifecycle: normal
1,448,408 bytes, retained 697,756 bytes (receipt
`76fe2d465a5a84afd72775cdf219e4accd12`). Both instrumented lifecycle runs passed.
These are address-table capacity peaks, not total guest memory or live slot
counts. They complement the actual allocator high-water readings above.
The earlier first-four-frame measurement was 731,044 / 417,392 bytes; it is
superseded for lifecycle coverage by this complete run.

## Final production source and package pin

The production host now calls `RunRetained` directly. Rebuilding it through
`TAIJIOS_TASK_MODULES=/mnt/storage/Projects/taijiosnet/taijios/appl/cmd make taiji`
writes stable `build/taskmgr.zx`, SHA-256
`109c2314690c0ecd19624119aa9a3229a91245b3ec91e883e6f4997b2a6be200`.
Removing the test-only define/branch changed the bundle identity, so the app
lane repeated `python3 scripts/guest-lifecycle-test.py /mnt/storage/Projects/taijiosnet/taijios --emu /mnt/storage/Projects/taijiosnet/taijios/Linux/386/bin/emu`.
It passed the namespace/CPU and real private-Xvfb selected-task kill, live refresh
and close tests at 32 MiB (receipt `4d35328ed6eba7016ad97942038b22089e86`).
This artifact was handed to the same sole guest installer for its final
production-path copy and resize recheck.

The manifest pins canonical Gitea Kryon revision
`b764139c3c03b3ee183e2e712f9f045b4575fc92`, independently verified against
remote master and its exported `RunRetained` source. The normal lock was generated
with the documented `ZIRAN_LOCK_GIT_OBJECTS` / `ziran lock` command, using only
existing canonical repositories. After that pin, `make check test` and
`TAIJIOS_TASK_MODULES=/mnt/storage/Projects/taijiosnet/taijios/appl/cmd make taiji-test taiji`
passed again and produced the same production digest (receipt
`03f1f459b05a15a4c6e5b9d0fe001fd05656`). These remain current-tree local tests with
ignored dependency overrides; no locked-only build is claimed. Kryon's working
manifest still declares dependency metadata beyond that pinned commit, which
the package tool resolves in memory for local builds.
