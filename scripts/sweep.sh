#!/usr/bin/env bash
# Sweep pipeline depth (STAGES) of the skid-buffer chain and report, per depth:
# LUT4, flip-flops, and the longest combinational path (ltp -noff, ECP5 cells).
# Latency in cycles equals STAGES. Real Fmax needs place-and-route (Vivado /
# nextpnr); this captures the resource/latency side of the tradeoff.
#   scripts/sweep.sh [stages...]   (default: 1 2 4 8 16)
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$here/scripts/env.sh"

STAGES_LIST=("$@")
if [ "${#STAGES_LIST[@]}" -eq 0 ]; then STAGES_LIST=(1 2 4 8 16); fi
SRCS="$here/rtl/axis_skid_buffer.sv $here/rtl/axis_slice_chain.sv"

printf "%-8s %-8s %-8s %-10s\n" "STAGES" "LUT4" "FF" "critpath"
printf "%-8s %-8s %-8s %-10s\n" "------" "----" "--" "--------"
for n in "${STAGES_LIST[@]}"; do
    log=$(yosys -p "
        read_verilog -sv $SRCS
        chparam -set STAGES $n axis_slice_chain
        synth_ecp5 -noabc9 -top axis_slice_chain
        ltp -noff
    " 2>&1)
    lut=$(echo "$log" | grep -E "[0-9]+[[:space:]]+LUT4" | tail -1 | awk '{print $1}')
    ff=$(echo "$log"  | grep -E "[0-9]+[[:space:]]+TRELLIS_FF" | tail -1 | awk '{print $1}')
    ltp=$(echo "$log" | grep -i "Longest topological path" | grep -oE "length=[0-9]+" | cut -d= -f2)
    printf "%-8s %-8s %-8s %-10s\n" "$n" "${lut:-?}" "${ff:-?}" "${ltp:-?}"
done
