#!/bin/sh
# Uses the canonical package toolchain and the guest owner's typed host module.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
: "${TAIJIOS_TASK_MODULES:?Set TAIJIOS_TASK_MODULES to TaijiOS appl/cmd}"
mkdir -p build
exec ./scripts/ziran.sh bundle --project --define TASKMGR_TAIJI \
    --module-path "$TAIJIOS_TASK_MODULES" --bind-host taijios_tasks \
    --bind-host kryon/pixmap \
    --entry taiji_host:main -o build/taskmgr.zx src/taiji_host.zi
