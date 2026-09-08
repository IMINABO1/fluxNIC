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

## 2026-09-08 — V1b Option 1: register slice (forward-registered)

- Wrote `axis_skid_buffer` as a simple register slice: registers tdata/tvalid,
  but `s_tready` is combinational in `m_tready`.
- Wrote a reusable AXI-Stream BFM (`tb/axis.py`) with randomized source idle and
  sink backpressure; beats sampled in the ReadOnly phase to avoid driver races.
- Tests pass: 500-word stream integrity under random backpressure, and full
  one-word/cycle throughput.
- Built `axis_slice_chain` (N buffers back-to-back) to measure how the critical
  path scales, and `scripts/ltp.sh` (yosys `ltp -noff`, ECP5 cells).
- **Measurement — Option 1, 8-stage chain:** longest path = **31 cells**;
  72 flip-flops (9/stage). The ready path is combinational, so it ripples: the
  path grows with chain depth. This is the number to beat with the skid buffer.

**Next:** revert to Option 2 (full skid buffer, ready registered), re-measure,
pick the winner.

---

## 2026-09-08 — V1b Option 2: full skid buffer (CHOSEN)

- Rewrote `axis_skid_buffer` as a full skid buffer: `s_tready = !skid_valid` is a
  registered output, and a one-entry skid register catches the word arriving as
  ready deasserts. Both handshake directions are now registered.
- Chasing why it "deadlocked" uncovered a **testbench** bug, not an RTL bug: the
  BFM sampled the handshake one cycle late (logged in problems). With that fixed,
  *both* options pass, and all cocotb tests now carry a `timeout_time` watchdog.
- Also moved the sim build tree to WSL-native ext4 (`scripts/test.sh`); a run that
  took minutes on the /mnt/c 9p mount now takes ~0.03 s.

**Decision (Option 1 vs Option 2):**
| | ready path | FF (8-stage chain) | pipeline-depth timing |
|---|---|---|---|
| Opt 1 register slice | combinational (ripples) | 72 | degrades with depth |
| Opt 2 skid buffer | registered (no ripple) | 144 | flat with depth |

The measurable tell: Option 1's chain has a 31-cell pure combinational
input->output path (the ready ripple); Option 2 registers ready so no such
cross-stage path exists. fluxNIC is a deep pipeline aiming at 250 MHz, so a ready
path that grows with stage count is disqualifying. **Kept Option 2** and paid the
2x flip-flops. (Real Fmax to be confirmed on Vivado; yosys `ltp` mixes pipeline
depth into its number, so it isn't a clean Fmax proxy -- the decision rests on the
structural ready-path argument.)

**Concepts learned:** why skid buffers exist (breaking the ready timing arc); the
FF-vs-timing tradeoff; sampling a handshake on the correct side of the edge.

**Next:** V2 — AXI-Stream FIFO (packs data+keep+last into the tested sync_fifo),
then the Ethernet/IPv4/UDP parsers.

---

## 2026-09-08 — V2a: AXI-Stream FIFO

- `axis_fifo` packs {tlast, tkeep, tdata} into one `sync_fifo` (reusing the tested
  primitive); `s_tready = !full`, `m_tvalid = !empty`, FWFT so no read latency.
- Test: 400-item payload round-trip under random source idle + sink backpressure,
  checking data, keep, and last all survive in order. Passes.

**Next:** V2b — Ethernet / IPv4 / UDP header parsers over a 64-bit AXI-Stream.

---

## 2026-09-08 — V2b: header parser (Ethernet / IPv4 / UDP)

- `header_parser` snoops the 64-bit AXI-Stream (observes beat = tvalid && tready,
  never drives ready) and accumulates the first 5 words (40 bytes) into a header
  buffer, then extracts eth_type, IPv4 src/dst/proto, and UDP src/dst ports,
  with `is_ipv4`/`is_udp` flags and a 1-cycle `hdr_valid` strobe. `hdr_error`
  fires if the packet ends before the headers are complete.
- Design choice: snoop rather than inline-forward, so the parser sits beside a
  packet buffer without touching flow control -- a clean store-and-decide split.
- Built `tb/packet.py` to construct genuine Ethernet/IPv4/UDP frames (with a real
  IP checksum) and chunk them to AXI-Stream words. Tests: correct field
  extraction, extraction under random backpressure, short-packet -> error, and
  TCP -> is_ipv4 but not is_udp. All pass.
- Assumes IPv4 without options (IHL == 5); options would shift the UDP offset.
- Synthesis (ECP5): 134 flip-flops, 173 LUT4.

**Next:** V3 — the configurable exact-match flow table (BRAM), then the
match-action engine.

---

## 2026-09-08 — V3: exact-match flow table (BRAM)

- `flow_table` is a direct-mapped hash table: 256 slots of {key, action} in block
  RAM, plus a resettable 256-bit "occupied" vector in flip-flops so the whole
  table clears in one cycle. XOR-fold hash -> slot; a hit needs occupied && exact
  key match. One insert port, one lookup port, 1-cycle registered result.
- Tests (all pass): insert->hit, miss-when-absent, overwrite-same-slot, and a
  300-op randomized run against a Python direct-mapped model that replicates the
  exact hash.
- Had to rewrite the hash function in Verilog-2005 style for yosys (see problems).
- **Synthesis (ECP5): 2x DP16KD block RAMs**, 428 FF, 912 LUT4 -- real evidence
  that the flow table is BRAM-backed, as the design claims.

**Next:** V4 — the action engine and the match-action pipeline that ties the
parser, flow table, and packet buffer together.

---

## 2026-09-08 — V4: match-action engine

- `match_action` wires the parser + flow table together: on `hdr_valid` it builds
  the key `{ip_dst, udp_dst_port}`, looks it up, and (one cycle later) decodes the
  action into a decision — drop, out_port, count_en, timestamp — with a
  configurable default action on a miss and live packet/hit/drop counters.
- Action word: [0]=drop, [3:1]=out_port, [4]=count_en, [5]=timestamp.
- Tests (all pass): rule hit forwards to the right port with count set; a miss
  falls back to default-drop; a TCP packet (non-UDP) takes the default; and the
  stat counters tally 5 packets / 3 hits / 2 drops across a mixed run.
- Synthesis (ECP5): 2x DP16KD, 608 FF, 1044 LUT4 — the whole match-action core.

This is the heart of the design: a programmable, table-driven decision per packet.

**Next:** V5 — top-level integration (store-and-forward: buffer the packet while
the decision is computed, then drop/forward), then the pipeline-depth sweep.

---

## 2026-09-08 — V5: top-level integration (the data plane works)

- `fluxnic_top` ties it together as store-and-forward: the packet buffers in an
  `axis_fifo` while `match_action` computes its decision from the headers; the
  decision (out_port + drop) is pushed to a small decision FIFO; an egress FSM
  drains each packet in order and forwards it to the decided port or drops it.
- Decisions stay aligned to packets because both FIFOs are strictly in order,
  exactly one decision per packet.
- **End-to-end test passes:** rules loaded via the config port, a mix of
  matching/non-matching packets streamed with random backpressure on *both*
  sides; matching packets come out intact on the right ports, misses are dropped,
  and stat_pkts/hits/drops/forwarded all check out.
- **Full regression: 23/23 tests pass** across all 8 modules.
- **Whole-design synthesis (ECP5): 761 FF, 1202 LUT4, 5x DP16KD block RAMs.**

The programmable data plane is real: load rules, stream packets, get per-packet
drop/forward decisions at one word/cycle. This is the résumé project, working.

**Next:** V6 — packet rewrite + checksum update; then SVA assertions and the
pipeline-depth PPA study.

---

## 2026-09-08 — CI + V6 packet rewrite

- **CI:** added a GitHub Actions workflow that builds the exact toolchain with
  micromamba (verilator + yosys + python 3.13), installs cocotb, runs the full
  regression, and synthesizes the top for ECP5 on every push. First run failed
  with `test.sh: Permission denied` (Windows git dropped the exec bit); fixed by
  invoking test.sh via `bash` and marking the scripts executable in git.
- **V6 rewrite:** widened the action word to 32 bits ([6]=rewrite dst port,
  [31:16]=new port). `match_action` decodes it; the top carries it through the
  decision FIFO and the egress FSM splices the new UDP dst port into word 4
  (bytes 36-37) as the packet forwards. Test confirms the port becomes 7000 while
  the rest of the frame stays byte-for-byte identical. (Assumes UDP checksum 0,
  as our frames use; a nonzero checksum would need an incremental update.)
- "drop, forward, or rewrite" is now all implemented and tested.
- Whole-design synthesis (ECP5): 837 FF, 1265 LUT4, 7x DP16KD.

**Next:** V7 (rate limiting / timestamp) and the pipeline-depth PPA study.

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
