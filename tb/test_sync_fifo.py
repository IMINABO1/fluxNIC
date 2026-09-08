import random
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge


async def reset(dut):
    dut.wr_en.value = 0
    dut.rd_en.value = 0
    dut.wr_data.value = 0
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)


def depth_of(dut):
    return 1 << (len(dut.count) - 1)


@cocotb.test()
async def empty_after_reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    assert dut.empty.value == 1
    assert dut.full.value == 0
    assert int(dut.count.value) == 0


@cocotb.test()
async def fifo_order_preserved(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    data = [random.randrange(256) for _ in range(8)]
    for d in data:
        dut.wr_data.value = d
        dut.wr_en.value = 1
        await RisingEdge(dut.clk)
    dut.wr_en.value = 0
    await FallingEdge(dut.clk)

    out = []
    while dut.empty.value == 0:
        out.append(int(dut.rd_data.value))  # FWFT: head is already presented
        dut.rd_en.value = 1
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
    dut.rd_en.value = 0

    assert out == data, f"FIFO reordered data: wrote {data}, read {out}"


@cocotb.test()
async def fills_and_reports_full(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    depth = depth_of(dut)
    dut.wr_en.value = 1
    for i in range(depth):
        dut.wr_data.value = i & 0xFF
        await RisingEdge(dut.clk)
    dut.wr_en.value = 0
    await FallingEdge(dut.clk)

    assert dut.full.value == 1, "FIFO should be full"
    assert int(dut.count.value) == depth


@cocotb.test()
async def random_stream_matches_model(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    model = deque()
    depth = depth_of(dut)

    for _ in range(2000):
        is_full = bool(dut.full.value)
        is_empty = bool(dut.empty.value)

        if not is_empty:
            assert int(dut.rd_data.value) == model[0], "FWFT head mismatch vs model"

        want_wr = (random.random() < 0.5) and not is_full
        want_rd = (random.random() < 0.5) and not is_empty
        wr_val = random.randrange(256)

        dut.wr_en.value = 1 if want_wr else 0
        dut.rd_en.value = 1 if want_rd else 0
        dut.wr_data.value = wr_val

        await RisingEdge(dut.clk)
        if want_rd:
            model.popleft()
        if want_wr:
            model.append(wr_val)
        await FallingEdge(dut.clk)

        assert len(model) <= depth
        assert int(dut.count.value) == len(model), \
            f"count {int(dut.count.value)} != model {len(model)}"

    dut.wr_en.value = 0
    dut.rd_en.value = 0
