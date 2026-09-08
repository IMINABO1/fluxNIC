import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

from packet import udp_ipv4_frame, to_words, words_to_bytes, ip_int
from axil import axil_write, axil_read

REG_IPDST, REG_DPORT, REG_ACTION, REG_CTRL, REG_DFLT = 0x00, 0x04, 0x08, 0x0C, 0x10
STAT_PKTS, STAT_HITS, STAT_DROPS, STAT_FWD = 0x20, 0x24, 0x28, 0x2C


async def reset(dut):
    for sig in ("awvalid", "wvalid", "bready", "arvalid", "rready",
                "s_tvalid", "s_tlast", "m_tready"):
        getattr(dut, sig).value = 0
    dut.s_tdata.value = 0
    dut.s_tkeep.value = 0
    dut.rst_n.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def add_rule(dut, ip_dst, dport, action):
    await axil_write(dut, REG_IPDST, ip_dst)
    await axil_write(dut, REG_DPORT, dport)
    await axil_write(dut, REG_ACTION, action)
    await axil_write(dut, REG_CTRL, 1)  # commit


async def send_frames(dut, frames, seed=1):
    rnd = random.Random(seed)
    words = []
    for f in frames:
        words += to_words(f)
    i = 0
    dut.s_tvalid.value = 0
    while i < len(words):
        if rnd.random() < 0.15:
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
        dut.m_tready.value = 1 if rnd.random() < 0.85 else 0
        await ReadOnly()
        if dut.m_tvalid.value == 1 and dut.m_tready.value == 1:
            cur.append((int(dut.m_tdata.value), int(dut.m_tkeep.value)))
            dest = int(dut.m_tdest.value)
            if int(dut.m_tlast.value) == 1:
                out.append((dest, words_to_bytes(cur)))
                cur = []
        await RisingEdge(dut.clk)


@cocotb.test(timeout_time=400, timeout_unit="us")
async def control_plane_over_axil(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # default action = drop; one forward rule, all loaded over AXI-Lite
    await axil_write(dut, REG_DFLT, 0x01)
    await add_rule(dut, ip_int("10.0.0.9"), 5001, (2 << 1))  # forward port 2

    f_hit = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                           "10.0.0.1", "10.0.0.9", 3333, 5001, b"hi over axil")
    f_miss = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                            "10.0.0.1", "10.0.0.44", 3333, 6000, b"dropme")

    out = []
    cocotb.start_soon(recv(dut, out))
    await send_frames(dut, [f_hit, f_miss, f_hit])

    for _ in range(400):
        if len(out) >= 2:
            break
        await RisingEdge(dut.clk)

    assert out == [(2, f_hit), (2, f_hit)], "AXI-Lite-programmed forwarding failed"

    # read stats back over AXI-Lite
    assert await axil_read(dut, STAT_PKTS) == 3
    assert await axil_read(dut, STAT_HITS) == 2
    assert await axil_read(dut, STAT_DROPS) == 1
    assert await axil_read(dut, STAT_FWD) == 2


@cocotb.test(timeout_time=100, timeout_unit="us")
async def register_readback(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await axil_write(dut, REG_IPDST, 0x0A000009)
    await axil_write(dut, REG_DPORT, 5001)
    await axil_write(dut, REG_DFLT, 0x01)

    assert await axil_read(dut, REG_IPDST) == 0x0A000009
    assert await axil_read(dut, REG_DPORT) == 5001
    assert await axil_read(dut, REG_DFLT) == 0x01
