"""Minimal AXI4-Lite master BFM for cocotb: single-beat write and read."""
from cocotb.triggers import RisingEdge, ReadOnly


async def axil_write(dut, addr, data):
    dut.awaddr.value = addr
    dut.awvalid.value = 1
    dut.wdata.value = data
    dut.wstrb.value = 0xF
    dut.wvalid.value = 1
    dut.bready.value = 1
    while True:
        await ReadOnly()
        if dut.awready.value == 1 and dut.wready.value == 1:
            break
        await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.awvalid.value = 0
    dut.wvalid.value = 0
    while True:
        await ReadOnly()
        if dut.bvalid.value == 1:
            break
        await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.bready.value = 0


async def axil_read(dut, addr):
    dut.araddr.value = addr
    dut.arvalid.value = 1
    dut.rready.value = 1
    while True:
        await ReadOnly()
        if dut.arready.value == 1:
            break
        await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.arvalid.value = 0
    while True:
        await ReadOnly()
        if dut.rvalid.value == 1:
            val = int(dut.rdata.value)
            break
        await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rready.value = 0
    return val
