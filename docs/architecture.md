# fluxNIC architecture

fluxNIC is a programmable, store-and-forward packet data plane. Rules are loaded
at runtime through a config port; each packet is parsed, matched against a flow
table, and dropped, forwarded, or rewritten according to the matched action.

## Block diagram

```
                 config port (rules)
                        |
                        v
  s_axis   +----------------------------+   dec FIFO   +-----------+  m_axis
  64-bit ->| match_action                |----------->| egress FSM |------->
     |     |  header_parser -> flow_table |  {drop,    |  drop /    |  + tdest
     |     |     (BRAM) -> action decode  |   port,    |  forward / |  (out port)
     |     +----------------------------+  rewrite}   |  rewrite   |
     |                                                  +-----------+
     |                                                       ^
     +------------------> packet FIFO (axis_fifo) -----------+
                          (buffers the whole packet)
```

The packet is buffered while its decision is computed from the headers. Because
the packet FIFO and the decision FIFO are both strictly in order, with exactly
one decision per packet, decisions stay aligned to packets without tags.

## Interfaces

- **Data path:** 64-bit AXI-Stream (`tdata`, `tkeep`, `tlast`, `tvalid`,
  `tready`) in and out. `m_tdest` carries the chosen output port.
- **Config path:** `ins_valid`, `ins_ip_dst`, `ins_udp_dport`, `ins_action`
  insert one rule per pulse. `dflt_action` is applied on a miss.

## Header parser

Snoops the stream (observes `tvalid && tready`; never drives ready) and
accumulates the first 5 words (40 bytes) — enough to reach the UDP ports. It
extracts `eth_type`, IPv4 `src`/`dst`/`proto`, and UDP `src`/`dst` ports, with
`is_ipv4`/`is_udp` flags and a one-cycle `hdr_valid` strobe. Assumes IPv4 with no
options (IHL == 5). `hdr_error` fires if a packet ends before the headers finish.

## Flow table

Direct-mapped exact-match table:

- Key `{ip_dst[31:0], udp_dst_port[15:0]}` (48 bits) is XOR-folded to an 8-bit
  slot index.
- Slot contents `{key, action}` live in block RAM (256 slots).
- A resettable 256-bit "occupied" vector (flip-flops) clears the whole table in
  one cycle.
- A lookup is a hit only if the slot is occupied and its stored key matches
  exactly; the result is registered (one-cycle latency).

Being direct-mapped, distinct keys can collide on a slot; the last insert wins.
256 is the capacity, not a guaranteed simultaneous occupancy.

## Action word (32 bits)

| bits    | field              | meaning                                  |
|---------|--------------------|------------------------------------------|
| [0]     | drop               | 1 = drop the packet                      |
| [3:1]   | out_port           | egress port for forward                  |
| [4]     | count_en           | pulse a per-flow counter                 |
| [5]     | timestamp          | mark for timestamping (reserved)         |
| [6]     | rewrite_dport      | rewrite UDP dst port with [31:16]        |
| [31:16] | new_udp_dport      | new UDP destination port                 |

Example rules (as loaded through the config port):

```
match ip_dst=10.0.0.9  udp_dport=5001  -> forward port 2
match ip_dst=10.0.0.20 udp_dport=1234  -> forward port 5, rewrite dport=7000
default                                 -> drop
```

## Egress FSM

`IDLE` waits for a decision and the packet head, then enters `FWD` or `DROP`.
`FWD` streams the buffered packet to `m_axis` on the decided port, counting words
so it can splice a rewritten UDP dst port into word 4 (bytes 36-37) on the fly.
`DROP` drains the packet from the buffer without emitting it. Both honor
backpressure (`m_tready`).

## Verification

Every module has a cocotb (Python) testbench run under Verilator. Several check
against reference models: the FIFO against a `deque`, the flow table against a
Python direct-mapped model with the identical hash, and the AXI-Stream path with
randomized backpressure on both sides. Parser and top-level tests build genuine
Ethernet/IPv4/UDP frames (real IP checksums) and stream them through. All tests
carry a `timeout_time` watchdog so a deadlock fails fast. GitHub Actions runs the
full regression and an ECP5 synthesis on every push.

## Synthesis (yosys, Lattice ECP5)

Real, measured resource usage; Fmax requires place-and-route (Vivado or a working
nextpnr) and is a documented target rather than a measured number here.

| module | LUT4 | FF | BRAM |
|---|---|---|---|
| header_parser | 173 | 134 | – |
| flow_table (256) | 912 | 428 | 2× DP16KD |
| match_action | 1044 | 608 | 2× DP16KD |
| fluxnic_top | 1265 | 837 | 7× DP16KD |

## Known limitations / future work

- IPv4 only, no IP options (IHL == 5); no VLAN tags.
- Rewrite assumes UDP checksum 0; a nonzero checksum would need an incremental
  (RFC 1624) update.
- Malformed/short packets aren't given an explicit error→drop decision at the top
  level yet (the parser flags `hdr_error`; wiring it into the egress is future
  work).
- Fmax/timing closure to be done in Vivado.
