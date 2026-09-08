# Source this to put the fluxNIC toolchain on PATH.
#   source scripts/env.sh
# Locally this adds the micromamba `eda` env (verilator/iverilog/yosys) and the
# uv `.venv` (cocotb). In CI, where the tools are already on PATH, both guards
# fall through harmlessly.
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-$HOME/micromamba}"
if [ -d "$MAMBA_ROOT_PREFIX/envs/eda/bin" ]; then
    export PATH="$MAMBA_ROOT_PREFIX/envs/eda/bin:$PATH"
fi
export PATH="$HOME/.local/bin:$PATH"
if [ -f "$_here/.venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$_here/.venv/bin/activate"
fi
