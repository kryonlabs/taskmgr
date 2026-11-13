#!/bin/sh
# Applications tab test on a private X display: starts Xvfb, an EWMH window
# manager and one xterm titled taskmgr-probe, then runs build/windows-test.
# The environment is scrubbed so nothing reaches the developer's own display,
# X authority or session bus, and only processes started here are stopped.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_binary=$root/build/windows-test
app_binary=$root/build/taskmgr-desktop
window_manager=${X11_TEST_WM:-xfwm4}

for tool in Xvfb "$window_manager" xterm xprop; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'x11-test: SKIPPED, %s is not installed\n' "$tool"
        exit 0
    fi
done

# The first free display number from 90 up.
number=90
while [ -e "/tmp/.X11-unix/X$number" ] || [ -e "/tmp/.X$number-lock" ]; do
    number=$((number + 1))
done

mkdir -p "$root/build"
scratch=$(mktemp -d "$root/build/x11-test.XXXXXX")
pids=
cleanup() {
    status=$?
    trap - EXIT INT TERM
    for pid in $pids; do kill "$pid" 2>/dev/null || true; done
    for pid in $pids; do wait "$pid" 2>/dev/null || true; done
    if [ "$status" -eq 0 ]; then
        rm -rf "$scratch"
    else
        printf 'x11-test: failed logs retained in %s\n' "$scratch" >&2
    fi
    exit "$status"
}
trap cleanup EXIT INT TERM

run() {
    env -i PATH="$PATH" HOME="$scratch" DISPLAY=":$number" \
        HARMONY_DESKTOP_RECOVERY=0 "$@"
}

env -i PATH="$PATH" HOME="$scratch" HARMONY_DESKTOP_RECOVERY=0 \
    Xvfb ":$number" -screen 0 1024x720x24 -nolisten tcp -noreset \
    >"$scratch/xvfb.log" 2>&1 &
pids="$!"
waited=0
until [ -e "/tmp/.X11-unix/X$number" ]; do
    waited=$((waited + 1))
    if [ "$waited" -gt 50 ]; then
        echo 'x11-test: private Xvfb did not start' >&2
        exit 1
    fi
    sleep 0.1
done

run "$window_manager" >"$scratch/wm.log" 2>&1 &
wm_pid=$!
pids="$pids $wm_pid"
waited=0
until run xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -qv 'not found'; do
    waited=$((waited + 1))
    if ! kill -0 "$wm_pid" 2>/dev/null || [ "$waited" -gt 100 ]; then
        echo 'x11-test: private window manager did not publish _NET_CLIENT_LIST' >&2
        sed -n '1,120p' "$scratch/wm.log" >&2
        exit 1
    fi
    sleep 0.1
done
run "$app_binary" >"$scratch/taskmgr.log" 2>&1 &
app_pid=$!
pids="$pids $app_pid"
sleep 2
if ! kill -0 "$app_pid" 2>/dev/null; then
    echo 'x11-test: native taskmgr exited before opening its private-display window' >&2
    sed -n '1,120p' "$scratch/taskmgr.log" >&2
    exit 1
fi
run xterm -T taskmgr-probe -e sleep 120 >"$scratch/xterm.log" 2>&1 &
pids="$pids $!"

run "$test_binary"
if ! kill -0 "$app_pid" 2>/dev/null; then
    echo 'x11-test: native taskmgr exited during the window-manager test' >&2
    sed -n '1,120p' "$scratch/taskmgr.log" >&2
    exit 1
fi
echo 'taskmgr native X11 smoke passed'
