#!/usr/bin/env bash
# Report the longest combinational (register-to-register) path depth of a design,
# in ECP5 cells, via yosys `ltp -noff`. A proxy for the critical path / Fmax when
# real place-and-route isn't available.
#   scripts/ltp.sh <toplevel> [src.sv ...]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$here/scripts/env.sh"

TOP="${1:?usage: ltp.sh <toplevel> [sources...]}"
shift || true
if [ "$#" -gt 0 ]; then SRCS=("$@"); else mapfile -t SRCS < <(ls "$here"/rtl/*.sv); fi

yosys -p "
    read_verilog -sv ${SRCS[*]}
    hierarchy -check -top $TOP
    flatten
    synth_ecp5 -top $TOP
    ltp -noff
" 2>&1 | grep -i "Longest topological path" | head -1
