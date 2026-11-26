#!/bin/sh
# Applications tab test on a private X display: starts Xvfb, an EWMH window
# manager and one xterm titled taskmgr-probe, then runs build/windows-test.
# The environment is scrubbed so nothing reaches the developer's own display,
# X authority or session bus, and only processes started here are stopped.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_binary=$root/build/windows-test
app_binary=${TASKMGR_BINARY:-$root/build/taskmgr-desktop}
window_manager=${X11_TEST_WM:-xfwm4}
display_attempt_limit=${X11_TEST_DISPLAY_ATTEMPTS:-100}

for tool in Xvfb xdpyinfo "$window_manager" xterm xprop xwininfo xdotool; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'x11-test: SKIPPED, %s is not installed\n' "$tool"
        exit 0
    fi
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
    env -i PATH="$PATH" HOME="$scratch" TMPDIR="$scratch" DISPLAY=":$number" \
        HARMONY_DESKTOP_RECOVERY=0 "$@"
}

run_bg() {
    log=$1
    shift
    env -i PATH="$PATH" HOME="$scratch" TMPDIR="$scratch" DISPLAY=":$number" \
        HARMONY_DESKTOP_RECOVERY=0 "$@" >"$log" 2>&1 &
    run_bg_pid=$!
}

start=$((120 + ($$ % 100)))
number=
attempt=0
while [ "$attempt" -lt "$display_attempt_limit" ]; do
    candidate=$((120 + ((start - 120 + attempt) % 100)))
    env -i PATH="$PATH" HOME="$scratch" TMPDIR="$scratch" HARMONY_DESKTOP_RECOVERY=0 \
        Xvfb ":$candidate" -screen 0 1024x720x24 -nolisten tcp -noreset \
        >"$scratch/xvfb.log" 2>&1 &
    candidate_pid=$!
    waited=0
    while kill -0 "$candidate_pid" 2>/dev/null && [ "$waited" -lt 40 ]; do
        if env -i PATH="$PATH" HOME="$scratch" TMPDIR="$scratch" \
            DISPLAY=":$candidate" xdpyinfo >/dev/null 2>&1; then
            number=$candidate
            pids=$candidate_pid
            break
        fi
        waited=$((waited + 1))
        sleep 0.1
    done
    if [ -n "$number" ]; then break; fi
    kill "$candidate_pid" 2>/dev/null || true
    wait "$candidate_pid" 2>/dev/null || true
    attempt=$((attempt + 1))
done
if [ -z "$number" ]; then
    echo 'x11-test: private Xvfb did not start on displays 120-219' >&2
    sed -n '1,120p' "$scratch/xvfb.log" >&2
    exit 1
fi

run_bg "$scratch/wm.log" "$window_manager"
wm_pid=$run_bg_pid
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
run_bg "$scratch/taskmgr.log" "$app_binary"
app_pid=$run_bg_pid
pids="$pids $app_pid"
taskmgr_window=
waited=0
while [ "$waited" -lt 100 ] && [ -z "$taskmgr_window" ]; do
    if ! kill -0 "$app_pid" 2>/dev/null; then
        echo 'x11-test: native taskmgr exited before opening its private-display window' >&2
        sed -n '1,120p' "$scratch/taskmgr.log" >&2
        exit 1
    fi
    for window_id in $(run xprop -root _NET_CLIENT_LIST 2>/dev/null | sed 's/.*# //; s/,//g'); do
        window_pid=$(run xprop -id "$window_id" _NET_WM_PID 2>/dev/null | awk '{print $3}')
        if [ "$window_pid" = "$app_pid" ]; then
            taskmgr_window=$window_id
            break
        fi
    done
    if [ -n "$taskmgr_window" ]; then break; fi
    waited=$((waited + 1))
    sleep 0.1
done
if [ -z "$taskmgr_window" ]; then
    echo 'x11-test: native taskmgr window was not published within 10 seconds' >&2
    sed -n '1,120p' "$scratch/taskmgr.log" >&2
    sed -n '1,120p' "$scratch/wm.log" >&2
    exit 1
fi
width=$(run xwininfo -id "$taskmgr_window" | awk '$1 == "Width:" {print $2}')
height=$(run xwininfo -id "$taskmgr_window" | awk '$1 == "Height:" {print $2}')
if [ "$width" != 400 ] || [ "$height" != 480 ]; then
    printf 'x11-test: taskmgr client is %sx%s, expected 400x480\n' "$width" "$height" >&2
    exit 1
fi
run xdotool windowsize "$taskmgr_window" 800 600
waited=0
while [ "$waited" -lt 40 ]; do
    if ! kill -0 "$app_pid" 2>/dev/null; then
        echo 'x11-test: native taskmgr exited while its private window was resized' >&2
        sed -n '1,120p' "$scratch/taskmgr.log" >&2
        exit 1
    fi
    width=$(run xwininfo -id "$taskmgr_window" | awk '$1 == "Width:" {print $2}')
    height=$(run xwininfo -id "$taskmgr_window" | awk '$1 == "Height:" {print $2}')
    if [ "$width" = 800 ] && [ "$height" = 600 ]; then break; fi
    waited=$((waited + 1))
    sleep 0.1
done
if [ "$width" != 800 ] || [ "$height" != 600 ]; then
    printf 'x11-test: taskmgr did not resize responsively; client stayed %sx%s\n' \
        "$width" "$height" >&2
    exit 1
fi
run_bg "$scratch/xterm.log" xterm -T taskmgr-probe -e sleep 120
pids="$pids $run_bg_pid"

run "$test_binary"
if ! kill -0 "$app_pid" 2>/dev/null; then
    echo 'x11-test: native taskmgr exited during the window-manager test' >&2
    sed -n '1,120p' "$scratch/taskmgr.log" >&2
    exit 1
fi
echo 'taskmgr native X11 smoke passed'
