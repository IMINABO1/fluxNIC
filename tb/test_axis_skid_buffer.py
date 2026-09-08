import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, NextTimeStep

from axis import axis_source, axis_sink


async def reset(dut):
    dut.s_tvalid.value = 0
    dut.s_tdata.value = 0
    dut.m_tready.value = 0
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test(timeout_time=200, timeout_unit="us")
async def stream_integrity_random_backpressure(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    width = len(dut.s_tdata)
    rnd = random.Random(0xC0FFEE)
    words = [rnd.randrange(1 << width) for _ in range(500)]
    received = []

    src = cocotb.start_soon(
        axis_source(dut.clk, dut.s_tdata, dut.s_tvalid, dut.s_tready, words, seed=1)
    )
    snk = cocotb.start_soon(
        axis_sink(dut.clk, dut.m_tdata, dut.m_tvalid, dut.m_tready, received,
                  want=len(words), seed=2)
    )
    await src
    await snk

    assert received == words, "stream corrupted under random backpressure"


@cocotb.test(timeout_time=100, timeout_unit="us")
async def full_throughput_no_backpressure(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    width = len(dut.s_tdata)
    n = 200
    dut.s_tvalid.value = 1
    dut.m_tready.value = 1

    beats = 0
    for i in range(n):
        dut.s_tdata.value = i % (1 << width)
        await RisingEdge(dut.clk)
        await ReadOnly()
        if dut.m_tvalid.value == 1 and dut.m_tready.value == 1:
            beats += 1
        await NextTimeStep()

    # one word/cycle throughput: at most a couple cycles of pipeline fill lost
    assert beats >= n - 2, f"throughput dropped: {beats}/{n} beats"
