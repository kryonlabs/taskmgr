# Changelog

## [Unreleased]

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
