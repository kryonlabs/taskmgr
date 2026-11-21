# taskmgr

A task manager for Linux written in Ziran with Kryon widgets. It reads
`/proc` directly: process names, states, CPU percentages, and resident
memory, plus total CPU and memory usage.

## Interface

The window keeps the compact structure of the Windows 2000 Task Manager while
installing the host application's palette when one is supplied, or the current
Linux desktop palette for a standalone window. That palette covers the menu
bar, Applications / Processes / Performance tabs, bordered content and the
three-pane status bar.

- **Applications** lists top-level EWMH windows and can switch to one, request
  that it close, or open a new command. CPU, Memory and GPU columns total each
  window's process tree: its `_NET_WM_PID` plus every descendant that no
  nearer listed window owns. Clicking a window expands it to those processes.
  Windows without a PID show `-`. Only top-level desktop windows appear, so
  background services do not, and under Wayland only XWayland windows do.
  Per-process GPU shares come from DRM fdinfo counters (AMD, Intel and other
  drivers that publish them) and, on NVIDIA's driver, from NVML sampled by
  `taskmgr --gpu-helper` (`taskmgr-gpu`), a display-free child of the same
  binary that runs only while this tab or Performance is open, so NVML's
  memory never enters the window process. The GPU column appears only once a
  source has data. Shares below 10% show one decimal.
- **Processes** is a sortable DataViews table with image name, PID, CPU, CPU
  time and resident memory. Rows are grouped by image name by default, with all
  Codex-family processes combined under `codex`; Options → Group Processes
  toggles the grouping. Clicking an aggregate row expands or collapses its real
  process rows. Selecting any cell highlights the complete row. `End Process`
  sends SIGTERM to one member; `End Group` sends it to every current member and
  reports any partial failure.
- **Performance** shows 60-sample CPU, memory, GPU and VRAM histories as clean
  Windows-style colored lines on black, plus process, thread, handle,
  physical-memory, commit and kernel-memory totals. Every detected DRM card
  has a stable `cardN` label, distinct graph color and independent GPU/VRAM
  reading; unsupported counters display `n/a`. NVIDIA's driver has no sysfs
  GPU counters, so its cards use the same `--gpu-helper` NVML samples as the
  Applications tab, matched to `cardN` by PCI address, while this tab or
  Applications is open. Memory values use explicit adaptive B, KB, MB, GB or
  TB units.
- File, Options, View and Help menus provide Run, refresh speed, manual refresh,
  kernel-time display, process grouping, end-process confirmation and About
  actions.
- Ctrl+1, Ctrl+2 and Ctrl+3 switch to Applications, Processes and Performance,
  matching the visible tab order.

The model refreshes once a second by default and reads `/proc` directly.
`TASKMGR_TAB=applications|processes|performance` selects the initial tab, which
is useful for headless rendering and tests.

The native window starts at a compact, resizable 400 × 480 size. Kryon's
software pixel presenter is the default because taskmgr already rasterizes its
widgets on the CPU; this avoids loading Mesa's LLVM/Gallium stack just to copy
that finished frame. Set `KRYON_PIXMAP_GPU=1` before launch to opt into GPU
presentation when that tradeoff is useful.

## Build and run

```sh
make            # ziran tool kryon build
make run        # open the desktop window
make test       # native model tests (no display needed)
make x11-test   # native app and Applications actions on a private Xvfb display
make memory-test # steady native RSS on private Xvfb; must stay below 30 MiB
make shot       # render one frame to build/taskmgr.ppm
make check      # compile every module
make package    # dist/taskmgr-linux-amd64.deb and dist/taskmgr-linux-x86_64.AppImage
```

`make package` stages the app with `ziran install`, moves libraries the build
produced (such as `libkryonavif.so`) to `/usr/lib/taskmgr` and points the
program's RUNPATH there. It needs `patchelf`, `dpkg-deb`, `dpkg-shlibdeps` and,
for the AppImage, `LINUXDEPLOY` set to a linuxdeploy AppImage. The release
workflow publishes both files under these version-free names, so
`https://github.com/kryonlabs/taskmgr/releases/latest/download/taskmgr-linux-amd64.deb`
and `.../taskmgr-linux-x86_64.AppImage` always fetch the newest release.

`make x11-test` never touches the current desktop. It needs `Xvfb`, `xfwm4`
(or `X11_TEST_WM`), `xterm` and `xprop`; when one is absent it reports a skip.
`make memory-test` likewise uses only a scrubbed private Xvfb display, waits for
several process and retained-text refreshes, then enforces a 30 MiB RSS cap.

The desktop profile opens an SDL2 window through Kryon's `desktop` backend.
The `tui`, `web`, `portable`, and headless `shot` profiles use the same
application `Frame` declared in `ziran.toml`.

## TaijiOS ZX

The same `app:Frame`, process model, sorting and selection run on TaijiOS.
The small `taiji_host` entry uses canonical `kryon/host/surface`; it contains
no UI. `platform_taiji` reads only the typed `taijios_tasks` host service.
Linux keeps its existing `/proc`, EWMH, GPU helper and native host behavior.

```sh
TAIJIOS_TASK_MODULES=/path/to/taijios/appl/cmd make taiji-test taiji
```

This writes `build/taskmgr.zx`. The Taiji launcher owner installs that artifact
with its existing `TASKMGR_ZX` integration; this repository does not modify the
emulator, menu or launcher. The guest requires `/prog` plus `taijios_tasks`,
Kryon's software surface/pixmap and monotonic clock host capabilities.

Guest PID values identify Dis tasks. `Est. Memory` is the guest's Dis
stack/module estimate in KiB, converted to bytes for display; it is not RSS.
The status and Performance memory reading is the real main allocator pool in
bytes against its configured limit, not total system RAM. `CPU %` uses real
cumulative task CPU nanoseconds divided
by elapsed captured monotonic nanoseconds; 100% means one core. The first sample,
new/reused task identity, counter reset, unavailable counter or nonpositive elapsed
time displays `n/a` until a comparable next sample. Idle tasks then show real zero.
`Task CPU` is the sum of comparable live task deltas, not whole-machine CPU:
new/exited/unmeasured tasks and kernel/idle work are excluded. It can exceed 100%
when guest execution threads run concurrently. Performance shows the comparable
task count. CPU time, Linux windows, GPU and other unsupported counters remain
explicitly unavailable. The guest requires the additive `SampleNanos` capability
and seven-field `TaskAt` CPU/incarnation/timestamp-error extension from the matching
emulator. Timestamp uncertainty must be smaller than the interval. A task delta
above 100% is accepted as saturation only when its excess fits within the measured
capture uncertainty; larger inconsistencies display `n/a`.
The guest has no shell launch or group termination. End Process targets only
the selected captured guest PID through the native `/prog/PID/ctl` operation.
Refresh storage and task count are bounded; failed captures clear visible rows.

`make taiji-test` runs 1,000 service-fixture refreshes, unit conversion,
unavailable/stale handling and selected-PID control through a ZX bundle.
For the real guest CPU model test, build `make taiji-cpu-live` with the same
`TAIJIOS_TASK_MODULES`, then run `python3 scripts/guest-cpu-test.py /path/to/taijios`.
It starts a disposable 32 MiB guest, measures its busy ZX task beside an owned
sleeper, and checks real CPU sorting. No guest task is fabricated or controlled.
`python3 scripts/guest-lifecycle-test.py /path/to/taijios` mounts only the built
artifact in a disposable private-Xvfb guest and runs the canonical Taiji CPU and
GUI lifecycle suite. `--emu /path/to/emu` can select the runtime owner's verified
candidate. This does not install the app. Actual installation/menu integration
remains with the Taiji launcher owner. See the CPU follow-up in
[tests/PERFORMANCE.md](tests/PERFORMANCE.md) for local lifecycle and paired renderer
results at the default 32 MiB pool.

## Performance measurements

Grouping uses a bounded hash index; raw and group order use stable merge sort.
The native 2,048-task and guest 1,024-task limits are unchanged. Guest sampling
still runs at the selected refresh rate, but unchanged process rows reuse their
formatted order. Pool readings update independently. Text storage keeps both
retained generations and sizes native window titles separately from process names.

```sh
make performance-test
python3 scripts/native-performance.py build/taskmgr-desktop
TAIJIOS_TASK_MODULES=/path/to/taijios/appl/cmd make taiji-performance
python3 scripts/guest-performance.py /path/to/taijios build/guest-profile.zx --seconds 30
```

The model workload groups and sorts a deterministic full-capacity fixture three
times; fixture values never appear in the app. `TASKMGR_PERF_SMALL` builds the
same workload with 128 rows for comparison with the earlier quadratic algorithm.
Run `build/performance-test.zx` through the actual guest's `zxrun` with
`-p main=32M`. The guest profile is an explicit test entry calling the normal
`App.Frame` at the same surface size and idle interval. It reports declaration
time, real allocator bytes/high water, emulator CPU, and input-to-next-callback
time. That callback measurement does not include final pixel presentation.
The native profile measures process CPU and input-to-observed-tab-redraw time.
Both GUI scripts create a scrubbed private Xvfb and stop only their own processes.

`make taiji-performance` also builds `build/guest-profile-retained.zx`, selecting
Kryon's `RunRetained` with the same shared app and observations. Production Taiji
uses that retained surface; the normal profile remains a comparison test.
`make taiji-retained-test` builds an uninstrumented lifecycle test artifact at
`build/taskmgr-retained-test.zx`. These explicit test targets do not install
anything. Use `--cycles 6 --seconds 90 --require-cpu`
with the guest profiler for the paired table/dialog workload.

See [the measured baseline and limitations](tests/PERFORMANCE.md). Model work is
substantially faster. Retained guest rendering reduced idle CPU by 73% and the
table/dialog workload CPU by 67% in one paired local run; those measurements are
not a universal performance guarantee. The native 30 MiB RSS test remains an enforced regression
threshold; repeated measurements can exceed it as anonymous huge-page residency
and file-backed library pages vary. A raised measurement limit is not a cap pass.
