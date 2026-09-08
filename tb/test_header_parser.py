import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

from packet import udp_ipv4_frame, to_words, ip_int


async def reset(dut):
    dut.s_tvalid.value = 0
    dut.s_tready.value = 0
    dut.s_tlast.value = 0
    dut.s_tdata.value = 0
    dut.s_tkeep.value = 0
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def drive(dut, words, seed=None):
    rnd = random.Random(seed) if seed is not None else None
    i = 0
    while i < len(words):
        val, keep, last = words[i]
        stall = rnd.random() < 0.3 if rnd is not None else False
        dut.s_tdata.value = val
        dut.s_tkeep.value = keep
        dut.s_tlast.value = last
        dut.s_tvalid.value = 1
        dut.s_tready.value = 0 if stall else 1
        await RisingEdge(dut.clk)
        if not stall:
            i += 1
    dut.s_tvalid.value = 0
    dut.s_tready.value = 0
    dut.s_tlast.value = 0


async def monitor(dut, res):
    while True:
        await ReadOnly()
        if dut.hdr_valid.value == 1:
            res.update(
                valid=True,
                eth=int(dut.eth_type.value),
                is_ipv4=int(dut.is_ipv4.value),
                proto=int(dut.ip_proto.value),
                ip_src=int(dut.ip_src.value),
                ip_dst=int(dut.ip_dst.value),
                is_udp=int(dut.is_udp.value),
                sport=int(dut.udp_src_port.value),
                dport=int(dut.udp_dst_port.value),
            )
        if dut.hdr_error.value == 1:
            res["error"] = True
        await RisingEdge(dut.clk)


async def run(dut, words, seed=None):
    res = {}
    cocotb.start_soon(monitor(dut, res))
    await drive(dut, words, seed=seed)
    for _ in range(5):
        await RisingEdge(dut.clk)
    return res


@cocotb.test(timeout_time=100, timeout_unit="us")
async def parses_udp_ipv4(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    frame = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                           "10.0.0.5", "10.0.0.9", 1234, 5001, b"payload!!")
    res = await run(dut, to_words(frame))

    assert res.get("valid"), "expected hdr_valid"
    assert res["eth"] == 0x0800
    assert res["is_ipv4"] == 1
    assert res["proto"] == 17
    assert res["is_udp"] == 1
    assert res["ip_src"] == ip_int("10.0.0.5")
    assert res["ip_dst"] == ip_int("10.0.0.9")
    assert res["sport"] == 1234
    assert res["dport"] == 5001


@cocotb.test(timeout_time=100, timeout_unit="us")
async def parses_under_backpressure(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    frame = udp_ipv4_frame("aa:bb:cc:dd:ee:ff", "01:02:03:04:05:06",
                           "192.168.1.100", "8.8.8.8", 53, 40000, b"query")
    res = await run(dut, to_words(frame), seed=7)

    assert res.get("valid")
    assert res["ip_src"] == ip_int("192.168.1.100")
    assert res["ip_dst"] == ip_int("8.8.8.8")
    assert res["sport"] == 53
    assert res["dport"] == 40000


@cocotb.test(timeout_time=100, timeout_unit="us")
async def short_packet_errors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    frame = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                           "10.0.0.5", "10.0.0.9", 1234, 5001)
    res = await run(dut, to_words(frame[:20]))  # 20 bytes: headers incomplete

    assert res.get("error"), "expected hdr_error on short packet"
    assert not res.get("valid"), "must not emit hdr_valid for a short packet"


@cocotb.test(timeout_time=100, timeout_unit="us")
async def tcp_is_ipv4_but_not_udp(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    frame = udp_ipv4_frame("ff:ff:ff:ff:ff:ff", "00:11:22:33:44:55",
                           "10.0.0.5", "10.0.0.9", 1234, 5001, b"payload!!", proto=6)
    res = await run(dut, to_words(frame))

    assert res.get("valid")
    assert res["is_ipv4"] == 1
    assert res["is_udp"] == 0
    assert res["proto"] == 6
