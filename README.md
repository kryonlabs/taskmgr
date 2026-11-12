# taskmgr

A task manager for Linux written in Ziran with Kryon widgets. It reads
`/proc` directly: process names, states, CPU percentages, and resident
memory, plus total CPU and memory usage.

## Interface

- Sortable process table (Name, PID, CPU %, Memory, State) from the DataViews
  `TableView` widget; click a header to change the sort.
- Total CPU and memory bars, with a per-second automatic refresh.
- `Refresh now` resamples immediately; `End Task` sends SIGTERM to the
  selected process.

## Build and run

```sh
make            # ziran tool kryon build
make run        # open the desktop window
make test       # native model tests (no display needed)
make shot       # render one frame to build/taskmgr.ppm
make check      # compile every module
```

The desktop profile opens an SDL2 window through Kryon's `desktop` backend.
The `tui`, `web`, `portable`, and headless `shot` profiles use the same
application `Frame` declared in `ziran.toml`.
