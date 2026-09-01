import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge


async def reset(dut):
    dut.en.value = 0
    dut.rst_n.value = 0
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def counts_when_enabled(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    assert dut.count.value == 0, f"after reset count should be 0, got {dut.count.value}"

    dut.en.value = 1
    for expected in range(1, 11):
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)  # read after the edge has settled
        assert dut.count.value == expected, \
            f"expected {expected}, got {int(dut.count.value)}"


@cocotb.test()
async def holds_when_disabled(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    dut.en.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    held = int(dut.count.value)

    dut.en.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    assert int(dut.count.value) == held, \
        f"count changed while disabled: {held} -> {int(dut.count.value)}"


@cocotb.test()
async def wraps_around(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    width = len(dut.count)
    dut.en.value = 1
    for _ in range((1 << width) - 1):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    assert int(dut.count.value) == (1 << width) - 1

    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    assert int(dut.count.value) == 0, "counter should wrap to 0"
