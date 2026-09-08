import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

from packet import udp_ipv4_frame, to_words, ip_int

FORWARD_P2_COUNT = 0x14   # out_port=2, count_en=1, drop=0
DROP = 0x01


async def reset(dut):
    dut.s_tvalid.value = 0
    dut.s_tready.value = 0
    dut.s_tlast.value = 0
    dut.s_tdata.value = 0
    dut.s_tkeep.value = 0
    dut.ins_valid.value = 0
    dut.ins_ip_dst.value = 0
    dut.ins_udp_dport.value = 0
    dut.ins_action.value = 0
    dut.dflt_action.value = DROP
    dut.rst_n.value = 0
    for _ in range(3):
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


async def drive(dut, words):
    for val, keep, last in words:
        dut.s_tdata.value = val
        dut.s_tkeep.value = keep
        dut.s_tlast.value = last
        dut.s_tvalid.value = 1
        dut.s_tready.value = 1
        await RisingEdge(dut.clk)
    dut.s_tvalid.value = 0
    dut.s_tready.value = 0
    dut.s_tlast.value = 0


async def dec_monitor(dut, out):
    while True:
        await ReadOnly()
        if dut.dec_valid.value == 1:
            out.append(dict(
                hit=int(dut.dec_hit.value),
                drop=int(dut.dec_drop.value),
                port=int(dut.dec_out_port.value),
                count=int(dut.dec_count_en.value),
                ts=int(dut.dec_timestamp.value),
            ))
        await RisingEdge(dut.clk)


async def feed(dut, frame):
    decisions = []
    mon = cocotb.start_soon(dec_monitor(dut, decisions))
    await drive(dut, to_words(frame))
    for _ in range(6):
        await RisingEdge(dut.clk)
    mon.kill()
    assert len(decisions) == 1, f"expected exactly 1 decision, got {len(decisions)}"
    return decisions[0]


@cocotb.test(timeout_time=100, timeout_unit="us")
async def hit_forwards(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await insert_rule(dut, ip_int("10.0.0.9"), 5001, FORWARD_P2_COUNT)

    frame = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                           "10.0.0.1", "10.0.0.9", 1234, 5001, b"payload!!")
    d = await feed(dut, frame)
    assert d["hit"] == 1 and d["drop"] == 0 and d["port"] == 2 and d["count"] == 1


@cocotb.test(timeout_time=100, timeout_unit="us")
async def miss_uses_default_drop(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await insert_rule(dut, ip_int("10.0.0.9"), 5001, FORWARD_P2_COUNT)

    frame = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                           "10.0.0.1", "10.0.0.200", 1234, 9999, b"payload!!")
    d = await feed(dut, frame)
    assert d["hit"] == 0 and d["drop"] == 1


@cocotb.test(timeout_time=100, timeout_unit="us")
async def non_udp_uses_default(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await insert_rule(dut, ip_int("10.0.0.9"), 5001, FORWARD_P2_COUNT)

    frame = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                           "10.0.0.1", "10.0.0.9", 1234, 5001, b"payload!!", proto=6)
    d = await feed(dut, frame)
    assert d["hit"] == 0 and d["drop"] == 1


@cocotb.test(timeout_time=200, timeout_unit="us")
async def stats_count_correctly(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await insert_rule(dut, ip_int("10.0.0.9"), 5001, FORWARD_P2_COUNT)

    hit_frame = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                               "10.0.0.1", "10.0.0.9", 1234, 5001, b"payload!!")
    miss_frame = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                                "10.0.0.1", "10.0.0.50", 1234, 7777, b"payload!!")

    for _ in range(3):
        await feed(dut, hit_frame)
    for _ in range(2):
        await feed(dut, miss_frame)

    await ReadOnly()
    assert int(dut.stat_pkts.value) == 5
    assert int(dut.stat_hits.value) == 3
    assert int(dut.stat_drops.value) == 2   # the 2 misses default-drop
