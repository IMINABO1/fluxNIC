# fluxNIC — Problems Encountered

Bugs, environment gotchas, and how they were solved. Newest at the top. Each
entry: what broke, why, and the fix — so the same wall is only hit once.

---

## 2026-09-08 — AXI-Stream BFM sampled the handshake one cycle too late

**Symptom:** the skid buffer's random-backpressure test hung forever (26 min of
CPU before it was killed), while the same buffer passed the no-backpressure test.
The RTL looked correct on paper.

**Cause:** the BFM sampled `tready`/`tvalid` in the ReadOnly phase *after*
`await RisingEdge`. `tready` is combinational, so after the edge it already shows
the *next* cycle's value. The source therefore mis-credited a beat, advanced past
a word the DUT never accepted, and the sink then waited forever for a word that
was never sent. Option 1 had passed only by luck of the random seed.

**Fix:** sample the handshake in the ReadOnly phase *before* the edge it governs:
`await ReadOnly()` -> read tready/tvalid -> `await RisingEdge`. Both BFM roles now
follow this order (`tb/axis.py`).

**Lesson:** for a valid/ready handshake, the beat is decided by the values
present *going into* the edge. Sample before the edge, not after. Also: always put
a `timeout_time` on cocotb tests so a deadlock fails in seconds instead of hanging.

---

## 2026-09-08 — cocotb: reading a signal right after RisingEdge is stale

**Symptom:** `sync_fifo` tests failed with `count 0 != model 1` even though the
RTL was correct (it synthesized fine and the logic was right).

**Cause:** after `await RisingEdge(dut.clk)`, the simulator is *at* the edge.
Registered outputs update there, but combinational outputs derived from them
(`count`, `empty`, `full`) have not settled yet at the moment `.value` is read.
So the testbench sampled pre-edge values.

**Fix (the project idiom):** drive inputs, `await RisingEdge` to commit, then
`await FallingEdge(dut.clk)` before sampling. The falling edge is a settled,
stable point in the middle of the cycle. All testbenches sample outputs on the
falling edge and drive inputs after it. (`await Timer(1, unit="ns")` or
`await ReadOnly()` also work, but FallingEdge reads cleanest.)

---

## 2026-09-08 — verilator/iverilog need sudo; installed via conda-forge instead

**Symptom:** `apt install verilator gtkwave` requires a password; this is an
unattended session with no passwordless sudo.

**Fix:** installed the simulators into a user-local micromamba env, no root:

```bash
curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj bin/micromamba
export MAMBA_ROOT_PREFIX="$HOME/micromamba"
micromamba create -y -n eda -c conda-forge verilator iverilog yosys
```

Cocotb (in the uv `.venv`) drives Verilator from this env via `scripts/env.sh`,
which prepends `$HOME/micromamba/envs/eda/bin` to PATH.

**Lesson:** conda-forge is the no-sudo escape hatch for EDA tools on a locked-down
box.

---

## 2026-09-08 — nextpnr not available headless; Fmax deferred

**Symptom:** `nextpnr-ecp5` is on neither conda-forge nor litex-hub in a form
micromamba could solve here.

**Impact:** yosys gives real *resource* numbers (LUT/FF/BRAM), but MHz-level Fmax
needs place-and-route. Fmax is therefore a documented target, closed later with
Vivado or a working nextpnr — not fabricated in the meantime.

---

## 2026-09-08 — yosys `stat -tech ecp5` is not valid

**Symptom:** `ERROR: Unsupported technology: 'ecp5'` from `stat -tech ecp5`.

**Cause:** after `synth_ecp5` the netlist is already ECP5 primitives, so `stat`
needs no `-tech`. `-tech` only accepts a couple of generic libraries.

**Fix:** call plain `stat` (see `scripts/synth.sh`).

---

## 2026-09-01 — cocotb won't install on Python 3.14

**Symptom:** `pip install cocotb` failed with
`RuntimeError: cocotb 2.0.1 only supports a maximum Python version of 3.13.`

**Cause:** Ubuntu 26.04 ships Python 3.14 as its default `python3`. cocotb 2.0.1
does not yet support 3.14.

**Fix:** Installed a standalone Python 3.13 with uv and built the project venv on
it, so the system Python is left untouched:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv python install 3.13
uv venv --python 3.13 .venv
uv pip install --python .venv/bin/python cocotb
```

**Lesson:** pin the interpreter for tools with strict version ceilings; don't
rely on the distro default.

---

## 2026-09-01 — WSL project on /mnt/c is slow

**Symptom:** uv warned it could not hardlink files and fell back to full copies.

**Cause:** the project lives on `/mnt/c/...` (the Windows filesystem seen from
WSL). Cross-filesystem operations there are slower than on WSL's native ext4.

**Status:** accepted for now — fine for small simulations, keeps the files
reachable from Windows editors and Vivado. Revisit (move to `~/` in WSL) only if
simulation time becomes a bottleneck.
