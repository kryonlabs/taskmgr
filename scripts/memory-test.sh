#!/bin/sh
# Measure the native application's resident set on a scrubbed private Xvfb
# display. Only the display and taskmgr process started here are stopped.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_binary=${TASKMGR_BINARY:-$root/build/taskmgr-desktop}
limit_kb=${TASKMGR_RSS_LIMIT_KB:-30720}
duration_seconds=${TASKMGR_MEMORY_SECONDS:-30}
display_attempt_limit=${TASKMGR_DISPLAY_ATTEMPTS:-100}

for tool in Xvfb xdpyinfo awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'memory-test: SKIPPED, %s is not installed\n' "$tool"
        exit 0
    fi
done

mkdir -p "$root/build"
scratch=$(mktemp -d "$root/build/memory-test.XXXXXX")
pids=
cleanup() {
    status=$?
    trap - EXIT INT TERM
    for pid in $pids; do kill "$pid" 2>/dev/null || true; done
    for pid in $pids; do wait "$pid" 2>/dev/null || true; done
    if [ "$status" -eq 0 ]; then rm -rf "$scratch"; fi
    exit "$status"
}
trap cleanup EXIT INT TERM

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
    echo 'memory-test: private Xvfb did not start on displays 120-219' >&2
    sed -n '1,120p' "$scratch/xvfb.log" >&2
    exit 1
fi

env -i PATH="$PATH" HOME="$scratch" TMPDIR="$scratch" DISPLAY=":$number" \
    HARMONY_DESKTOP_RECOVERY=0 \
    "$app_binary" >"$scratch/taskmgr.log" 2>&1 &
app_pid=$!
pids="$pids $app_pid"
if [ "$duration_seconds" -lt 1 ]; then
    echo 'memory-test: TASKMGR_MEMORY_SECONDS must be at least 1' >&2
    exit 1
fi

# Sample for a sustained interval so delayed allocations and repeated process
# refreshes cannot hide behind a single favorable reading.
elapsed=0
peak_kb=0
rss_series=
while [ "$elapsed" -lt "$duration_seconds" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
    if ! kill -0 "$app_pid" 2>/dev/null; then
        echo 'memory-test: taskmgr exited before measurement completed' >&2
        sed -n '1,120p' "$scratch/taskmgr.log" >&2
        exit 1
    fi
    rss_kb=$(awk '$1 == "VmRSS:" { print $2 }' "/proc/$app_pid/status")
    if [ -z "$rss_series" ]; then rss_series=$rss_kb; else rss_series="$rss_series $rss_kb"; fi
    if [ "$rss_kb" -gt "$peak_kb" ]; then peak_kb=$rss_kb; fi
done

anon_kb=$(awk '$1 == "RssAnon:" { print $2 }' "/proc/$app_pid/status")
file_kb=$(awk '$1 == "RssFile:" { print $2 }' "/proc/$app_pid/status")
shmem_kb=$(awk '$1 == "RssShmem:" { print $2 }' "/proc/$app_pid/status")
printf 'taskmgr RSS series (1s..%ss): %s KB\n' "$duration_seconds" "$rss_series"
printf 'taskmgr peak RSS: %s KB; final %s KB (anonymous %s KB, file %s KB, shared %s KB)\n' \
    "$peak_kb" "$rss_kb" "$anon_kb" "$file_kb" "$shmem_kb"
if [ "${TASKMGR_MEMORY_DETAILS:-0}" = 1 ]; then
    awk '
        /^[0-9a-f]+-[0-9a-f]+/ {
            name = $6
            if (name == "") name = "[anonymous]"
            next
        }
        $1 == "Rss:" { rss[name] += $2 }
        END { for (name in rss) printf "%10d KB  %s\n", rss[name], name }
    ' "/proc/$app_pid/smaps" | sort -nr | head -20
fi
if [ "${TASKMGR_MEMORY_DETAILS:-0}" = 2 ]; then
    awk '
        function emit() {
            if (anonymous && rss > 0) printf "%10d KB RSS  %10d KB size  %s\n", rss, size, header
        }
        /^[0-9a-f]+-[0-9a-f]+/ {
            emit()
            header = $0
            anonymous = (NF < 6)
            size = 0
            rss = 0
            next
        }
        $1 == "Size:" { size = $2 }
        $1 == "Rss:" { rss = $2 }
        END { emit() }
    ' "/proc/$app_pid/smaps" | sort -nr | head -30
fi
if [ "$peak_kb" -ge "$limit_kb" ]; then
    printf 'memory-test: peak RSS %s KB exceeds limit %s KB\n' "$peak_kb" "$limit_kb" >&2
    exit 1
fi
echo 'taskmgr memory limit passed'
