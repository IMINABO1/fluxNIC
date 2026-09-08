import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly


async def reset(dut):
    dut.s_tvalid.value = 0
    dut.s_tdata.value = 0
    dut.s_tkeep.value = 0
    dut.s_tlast.value = 0
    dut.m_tready.value = 0
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def source(dut, items, seed):
    rnd = random.Random(seed)
    dut.s_tvalid.value = 0
    i = 0
    while i < len(items):
        if rnd.random() < 0.3:
            dut.s_tvalid.value = 0
            await RisingEdge(dut.clk)
            continue
        d, k, l = items[i]
        dut.s_tdata.value = d
        dut.s_tkeep.value = k
        dut.s_tlast.value = l
        dut.s_tvalid.value = 1
        await ReadOnly()
        accepted = dut.s_tready.value == 1
        await RisingEdge(dut.clk)
        if accepted:
            i += 1
    dut.s_tvalid.value = 0


async def sink(dut, out, want, seed):
    rnd = random.Random(seed)
    dut.m_tready.value = 0
    while len(out) < want:
        dut.m_tready.value = 1 if rnd.random() < 0.7 else 0
        await ReadOnly()
        if dut.m_tvalid.value == 1 and dut.m_tready.value == 1:
            out.append((int(dut.m_tdata.value),
                        int(dut.m_tkeep.value),
                        int(dut.m_tlast.value)))
        await RisingEdge(dut.clk)
    dut.m_tready.value = 0


@cocotb.test(timeout_time=300, timeout_unit="us")
async def payload_roundtrip_random_backpressure(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    data_w = len(dut.s_tdata)
    keep_w = len(dut.s_tkeep)
    rnd = random.Random(0xBEEF)
    n = 400
    items = [(rnd.randrange(1 << data_w),
              rnd.randrange(1 << keep_w),
              1 if (i % 7 == 6) else 0) for i in range(n)]
    out = []

    src = cocotb.start_soon(source(dut, items, seed=1))
    snk = cocotb.start_soon(sink(dut, out, n, seed=2))
    await src
    await snk

    assert out == items, "AXI-Stream payload (data/keep/last) corrupted or reordered"
