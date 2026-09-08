#!/usr/bin/env bash
# Run one module's cocotb testbench.
#   scripts/test.sh <test_module> <toplevel> [SIM]
# e.g. scripts/test.sh test_sync_fifo sync_fifo
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$here/scripts/env.sh"

MODULE="${1:?usage: test.sh <test_module> <toplevel> [SIM]}"
TOPLEVEL="${2:?usage: test.sh <test_module> <toplevel> [SIM]}"
SIM="${3:-verilator}"

make -C "$here/tb" MODULE="$MODULE" TOPLEVEL="$TOPLEVEL" SIM="$SIM"
