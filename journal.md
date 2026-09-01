# fluxNIC — Journal

A running log of what was built, why, and what was learned. Newest entries at the top.

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
