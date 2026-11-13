# Changelog

## [Unreleased]

### Changed

- Reduced the native desktop working set from roughly 148 MB to below 30 MiB
  by updating Kryon to its software pixel-presenter path, bounding process and
  cell storage, and using a compact resizable native surface.
- Added a private-Xvfb RSS regression that measures the steady application
  after multiple process refreshes and enforces the 30 MiB limit.
- System-theme colors now cover the whole page, tabs, process panel and status
  panes instead of leaving mixed hard-coded white surfaces.

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
