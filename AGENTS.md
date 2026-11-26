# taskmgr

The Kryon task manager: a desktop application that lists processes, GPU and
memory usage, including TaijiOS guest tasks. README.md documents usage;
CHANGELOG.md records changes.

## Layout

| Path | Contents |
| --- | --- |
| `src/app.zi` | Application entrypoint and frames |
| `src/gpu_drm.zi`, `src/gpu_processes.zi` | GPU device and process readings |
| `src/guest_cpu.zi`, `src/hosted.zi` | TaijiOS guest CPU and hosted mode |
| `src/layout.zi`, `src/app_shortcuts.zi`, `src/desktop_host.zi` | UI layout and host wiring |
| `tests/` | Model, ordering, guest-CPU and window tests; PERFORMANCE.md records measurements |

## Commands

```sh
make build          # build the app
make run            # build and run
make check          # type-check
make test           # model, ordering and guest-CPU tests
make x11-test       # window test on a private Xvfb display
make memory-test    # pool and allocation checks
make taiji          # ZX build for TaijiOS
make taiji-test     # guest tests in a Taiji emulator
make performance-test  # build the performance harness
```

## Pins

- Ziran toolchain: `ecf134facb35654b4d437696984753574525b8dc`
- Kryon: `35a52f70f3ce4c15cc6eb6feb39d195c3cedf7f7`
- data_views: `020a427c56e5629b924238745c78363f83acf906`

Commit as Waozi <waozi@proton.me>; ordinary changes stay in CHANGELOG's
`Unreleased` section. Window tests scrub inherited display/session variables
and never touch the live desktop.
