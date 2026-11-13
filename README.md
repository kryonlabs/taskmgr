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
  that it close, or open a new command.
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
  reading; unsupported counters display `n/a`. Memory values use explicit
  adaptive B, KB, MB, GB or TB units.
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
```

`make x11-test` never touches the current desktop. It needs `Xvfb`, `xfwm4`
(or `X11_TEST_WM`), `xterm` and `xprop`; when one is absent it reports a skip.
`make memory-test` likewise uses only a scrubbed private Xvfb display, waits for
several process and retained-text refreshes, then enforces a 30 MiB RSS cap.

The desktop profile opens an SDL2 window through Kryon's `desktop` backend.
The `tui`, `web`, `portable`, and headless `shot` profiles use the same
application `Frame` declared in `ziran.toml`.
