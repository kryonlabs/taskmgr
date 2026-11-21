# Changelog

## [Unreleased]

### Added

- Run the shared Task Manager interface on TaijiOS ZX with real guest tasks,
  allocator memory, selected-task control and bounded platform sampling.
- Clicking an application expands it to the processes it owns, each with its
  state, CPU, memory and GPU use.
- AMD, Intel and other GPUs with standard DRM fdinfo counters now report
  per-application GPU use, not only NVIDIA.

### Changed

- Bound process grouping and stable sorting work at full task capacity, reuse
  unchanged guest table text and reduce fixed text storage without changing
  refresh rates, task limits or the shared interface.

- CPU and GPU shares show one decimal below 10% (`0.4`) instead of rounding
  light use to `00`.
- The Applications GPU column appears only when a per-process GPU source has
  data, instead of a column of `n/a`.
- The GPU helper process is named `taskmgr-gpu` instead of `exe`.

## [0.1.3] - 2026-11-13

### Added

- Debian package (`taskmgr-linux-amd64.deb`) and AppImage
  (`taskmgr-linux-x86_64.AppImage`) downloads replace the Linux tarball, which
  could not start on other machines because it lacked a Kryon library. Task
  Manager also has its own icon.
- The Applications tab shows CPU, memory and GPU use for each window, counting
  the window's whole process tree (a browser's helper processes count toward
  the browser). GPU use comes from NVIDIA's driver through a small helper that
  runs only while the Applications or Performance tab is open; other GPUs
  show `n/a`.

### Fixed

- The Performance tab shows GPU usage and VRAM for NVIDIA cards instead of
  `n/a`.

## [0.1.2] - 2026-11-13

### Changed

- Task Manager now uses far less memory: the desktop app stays below 30 MiB
  instead of roughly 148 MB, even after many process refreshes.
- System-theme colors now cover the whole window, including tabs, the process
  list and the status bar, instead of leaving mixed white surfaces.
- Performance graphs use classic Windows-style colors and show each detected
  GPU with its own card label, separate usage and VRAM history, and `n/a`
  when the driver does not report a reading.
- Ctrl+1, Ctrl+2 and Ctrl+3 switch to the Applications, Processes and
  Performance tabs in the order they appear.

### Fixed

- VRAM no longer appears 100% used when nothing is allocated; zero usage now
  shows as 0%.

## [0.1.1] - 2026-11-12

### Changed

- Process groups now expand and collapse from their aggregate row, exposing
  every member as a normal selectable process row.
- Added `End Group`, which sends SIGTERM to every current member and reports
  partial failures instead of hiding them.
- Memory readings now use explicit adaptive units such as MB and GB.
- The desktop window now accepts Harmony's host palette when available and
  falls back to the current Linux desktop palette for standalone launches.

## [0.1.0] - 2026-11-12

### Added

- Initial taskmgr: a Kryon process monitor with a sortable process table,
  CPU and memory summary, per-second refresh, and an End Task action that
  sends SIGTERM.
- Added the classic Windows 2000-style menu, Applications / Processes /
  Performance tabs and three-pane status bar, using the current Linux desktop
  theme for the window and controls.
- Added EWMH application listing with Switch To and close requests, CPU and
  memory history plots, detailed system totals, Run and refresh controls.
- Added clean green-on-black CPU, memory, GPU and VRAM history graphs without
  endpoint markers.
- Added process grouping, enabled by default, including a single `codex` group
  for Codex-family processes; selected processes highlight the complete row.
