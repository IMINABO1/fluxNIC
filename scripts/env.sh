# Source this to put the fluxNIC toolchain on PATH.
#   source scripts/env.sh
# Provides: verilator, iverilog, yosys (micromamba eda env) + cocotb (.venv).
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MAMBA_ROOT_PREFIX="$HOME/micromamba"
export PATH="$HOME/micromamba/envs/eda/bin:$HOME/.local/bin:$PATH"
if [ -f "$_here/.venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$_here/.venv/bin/activate"
fi
