# fluxNIC — Journal

A running log of what was built, why, and what was learned. Newest entries at the top.

---

## 2026-09-08 — Toolchain fully working, autonomous build begins

**Goal:** get build/test/synth/commit/push working without root, then work the
milestone ladder autonomously.

- **Simulators without sudo:** `verilator` and `iverilog` were not installable
  via `apt` (no passwordless sudo). Bootstrapped **micromamba** (a static binary,
  no root) and installed Verilator 5.052 + Icarus Verilog 13.0 from conda-forge
  into an `eda` env. See `problems-encountered.md`.
- **Synthesis:** added **yosys 0.68** to the same env. `synth_ecp5` gives real,
  measured Lattice ECP5 resource numbers (LUT4 / flip-flops / carry / BRAM).
  Fmax needs place-and-route (nextpnr/Vivado) which isn't available headless, so
  Fmax stays a documented target to close later; resource counts are real now.
- **Push:** the WSL git has no credentials, but Windows Git Credential Manager is
  logged in as the repo owner. So commits + pushes go through Windows git; builds
  and tests run in WSL. `.git` is shared on the Windows filesystem.
- Added `scripts/env.sh` (PATH setup), `scripts/test.sh` (run one cocotb test),
  `scripts/synth.sh` (yosys ECP5 resource report), `scripts/regress.sh` (full
  regression).
- **V0 counter** now verified (3/3) *and* synthesized: 8 flip-flops, 4 carry
  cells (CCU2C), 2 LUT4 — exactly what an 8-bit up-counter should cost.

**Next:** V1 — parameterized synchronous FIFO, then the AXI-Stream skid buffer.

---

## 2026-09-08 — V1a: synchronous FIFO

- Wrote `sync_fifo` — parameterized (WIDTH, DEPTH), first-word-fall-through reads,
  pointer-with-extra-MSB scheme for unambiguous full vs empty, live `count`.
- Verified with 4 cocotb tests including a 2000-cycle randomized check against a
  Python `deque` reference model (order, count, full/empty all match).
- Hit the cocotb read-after-edge staleness gotcha; established the project idiom
  of sampling on the falling edge (logged in `problems-encountered.md`).
- Synthesis (ECP5): the 16-deep memory maps to distributed RAM
  (`TRELLIS_DPR16X4`) — correct for a small FIFO; large buffers will want BRAM.

**Concepts learned:** FWFT semantics; the extra-bit pointer trick; why a small
FIFO becomes LUTRAM not BRAM; deterministic verification via a reference model.

**Next:** V1b — AXI-Stream skid buffer. This is a real design fork (simple
half-rate register slice vs. full skid buffer), so both will be tried and
compared.

---

## 2026-09-01 — Project setup + V0 scaffold

**Goal:** stand up the toolchain and get the first module simulating.

- Chose the stack: **SystemVerilog RTL, Verilator + cocotb for verification,
  Vivado for the final synthesis/timing milestone.** cocotb lets testbenches be
  written in Python, which is why this stack was picked over a
  SystemVerilog-only flow.
- Python environment managed with **uv**. cocotb 2.0.1 does not support Python
  3.14 (Ubuntu 26.04's default), so a standalone **Python 3.13** was installed
  via uv and the `.venv` was built on it. See `problems-encountered.md`.
- Scaffolded the repo: `rtl/`, `tb/`, `docs/`, this journal, and the problems log.
- Wrote **V0: `counter`** — an 8-bit synchronous counter with active-low reset
  and an enable. First real SystemVerilog module. Its job is to teach the four
  building blocks every module uses: `clk`, `rst_n`, registered logic
  (`always_ff`), and a cocotb testbench that drives and checks it.

**Concepts learned (V0):**
- `always_ff @(posedge clk)` describes a block of flip-flops: on each rising
  clock edge, the left-hand signals take their new values.
- `<=` (non-blocking assignment) is how you write registers. All the updates in
  a clocked block happen "together" at the edge.
- Active-low reset (`rst_n`): the register is forced to a known value while
  `rst_n` is 0. Real hardware powers up in an unknown state, so every register
  that matters gets a reset.
- A cocotb test drives inputs, waits for clock edges (`await RisingEdge(dut.clk)`),
  and asserts on outputs — the same read/drive/check loop as any test framework.

**Next:** V1 — a parameterized synchronous FIFO and an AXI-Stream skid buffer
with backpressure.
