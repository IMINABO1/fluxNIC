#!/usr/bin/env bash
# Synthesize a module for Lattice ECP5 with yosys and print resource usage.
#   scripts/synth.sh <toplevel> [src.sv ...]
# With no explicit sources, synthesizes all of rtl/.
# Reports LUT4 / flip-flop / BRAM / DSP counts (real, measured area numbers).
# Fmax requires place-and-route (nextpnr or Vivado) and is not produced here.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$here/scripts/env.sh"

TOP="${1:?usage: synth.sh <toplevel> [sources...]}"
shift || true
if [ "$#" -gt 0 ]; then SRCS=("$@"); else mapfile -t SRCS < <(ls "$here"/rtl/*.sv); fi

mkdir -p "$here/synth"
report="$here/synth/${TOP}_ecp5.txt"

yosys -q -p "
    read_verilog -sv ${SRCS[*]}
    hierarchy -check -top $TOP
    synth_ecp5 -top $TOP
    tee -o $report stat
" 2>&1 | tail -5 || true

echo "----- synth/${TOP}_ecp5.txt -----"
sed -n '/^=== /,$p' "$report"
