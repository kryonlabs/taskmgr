# Changelog

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
