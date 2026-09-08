#!/usr/bin/env bash
# Run the whole cocotb regression. Each line: <test_module> <toplevel>.
# Add a module here once its testbench passes.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TESTS=(
    "test_counter counter"
    "test_sync_fifo sync_fifo"
    "test_axis_skid_buffer axis_skid_buffer"
    "test_axis_fifo axis_fifo"
    "test_header_parser header_parser"
    "test_flow_table flow_table"
    "test_action_engine action_engine"
    "test_match_action match_action"
    "test_fluxnic_top fluxnic_top"
)

fails=0
for entry in "${TESTS[@]}"; do
    read -r mod top <<< "$entry"
    if [ ! -f "$here/tb/${mod}.py" ]; then continue; fi
    echo "==================== $mod ($top) ===================="
    if ! "$here/scripts/test.sh" "$mod" "$top"; then
        echo "FAILED: $mod"
        fails=$((fails+1))
    fi
done

echo
if [ "$fails" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "$fails TEST GROUP(S) FAILED"; fi
exit "$fails"
