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

- Ziran toolchain: `5462fe2ebf2c3c42663249e47ef99d61f45ff39f`
- Kryon: `b764139c3c03b3ee183e2e712f9f045b4575fc92`
- data_views: `e8abb23a4bbae6d92b62d477f816d0fa5ded5e1a`

Commit as Waozi <waozi@proton.me>; ordinary changes stay in CHANGELOG's
`Unreleased` section. Window tests scrub inherited display/session variables
and never touch the live desktop.
