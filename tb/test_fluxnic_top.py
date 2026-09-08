import random
import struct

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

from packet import udp_ipv4_frame, to_words, words_to_bytes, ip_int

DROP = 0x01


def fwd(port):
    return (port << 1) & 0x0E  # drop=0, out_port=port


def fwd_rewrite(port, new_dport):
    return (port << 1) | (1 << 6) | (new_dport << 16)  # + rewrite UDP dport


async def reset(dut):
    dut.s_tvalid.value = 0
    dut.s_tlast.value = 0
    dut.s_tdata.value = 0
    dut.s_tkeep.value = 0
    dut.m_tready.value = 0
    dut.ins_valid.value = 0
    dut.ins_ip_dst.value = 0
    dut.ins_udp_dport.value = 0
    dut.ins_action.value = 0
    dut.dflt_action.value = DROP
    dut.rst_n.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def insert_rule(dut, ip_dst, dport, action):
    dut.ins_valid.value = 1
    dut.ins_ip_dst.value = ip_dst
    dut.ins_udp_dport.value = dport
    dut.ins_action.value = action
    await RisingEdge(dut.clk)
    dut.ins_valid.value = 0


async def send_frames(dut, frames, seed=1):
    rnd = random.Random(seed)
    words = []
    for f in frames:
        words += to_words(f)
    i = 0
    dut.s_tvalid.value = 0
    while i < len(words):
        if rnd.random() < 0.2:
            dut.s_tvalid.value = 0
            await RisingEdge(dut.clk)
            continue
        val, keep, last = words[i]
        dut.s_tdata.value = val
        dut.s_tkeep.value = keep
        dut.s_tlast.value = last
        dut.s_tvalid.value = 1
        await ReadOnly()
        accepted = dut.s_tready.value == 1
        await RisingEdge(dut.clk)
        if accepted:
            i += 1
    dut.s_tvalid.value = 0
    dut.s_tlast.value = 0


async def recv(dut, out, seed=2):
    rnd = random.Random(seed)
    cur = []
    dest = 0
    dut.m_tready.value = 0
    while True:
        dut.m_tready.value = 1 if rnd.random() < 0.8 else 0
        await ReadOnly()
        if dut.m_tvalid.value == 1 and dut.m_tready.value == 1:
            cur.append((int(dut.m_tdata.value), int(dut.m_tkeep.value)))
            dest = int(dut.m_tdest.value)
            if int(dut.m_tlast.value) == 1:
                out.append((dest, words_to_bytes(cur)))
                cur = []
        await RisingEdge(dut.clk)


@cocotb.test(timeout_time=500, timeout_unit="us")
async def forwards_hits_drops_misses(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await insert_rule(dut, ip_int("10.0.0.9"), 5001, fwd(2))
    await insert_rule(dut, ip_int("10.0.0.20"), 1234, fwd(5))

    f_hit1 = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                            "10.0.0.1", "10.0.0.9", 3333, 5001, b"first pkt")
    f_miss = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                            "10.0.0.1", "10.0.0.99", 3333, 8888, b"dropme")
    f_hit2 = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                            "10.0.0.1", "10.0.0.20", 3333, 1234, b"second packet here")

    frames = [f_hit1, f_miss, f_hit2, f_hit1]
    expected = [(2, f_hit1), (5, f_hit2), (2, f_hit1)]

    out = []
    cocotb.start_soon(recv(dut, out))
    await send_frames(dut, frames)

    for _ in range(400):
        if len(out) >= len(expected):
            break
        await RisingEdge(dut.clk)

    assert out == expected, f"egress mismatch:\n got {[(p,b[:20]) for p,b in out]}"

    await ReadOnly()
    assert int(dut.stat_pkts.value) == 4
    assert int(dut.stat_hits.value) == 3
    assert int(dut.stat_drops.value) == 1
    assert int(dut.stat_forwarded.value) == 3


@cocotb.test(timeout_time=300, timeout_unit="us")
async def rewrites_udp_dport(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await insert_rule(dut, ip_int("10.0.0.9"), 5001, fwd_rewrite(3, 7000))

    frame = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                           "10.0.0.1", "10.0.0.9", 3333, 5001, b"rewrite me")
    expected = bytearray(frame)
    expected[36:38] = struct.pack("!H", 7000)  # UDP dst port rewritten

    out = []
    cocotb.start_soon(recv(dut, out))
    await send_frames(dut, [frame])
    for _ in range(400):
        if len(out) >= 1:
            break
        await RisingEdge(dut.clk)

    assert len(out) == 1, "packet was not forwarded"
    dest, data = out[0]
    assert dest == 3, f"wrong egress port {dest}"
    assert data == bytes(expected), "UDP dst port not rewritten correctly (or frame corrupted)"
