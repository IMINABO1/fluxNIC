import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

KEY_W = 48
ACTION_W = 8
ENTRIES = 256
INDEX_W = 8


def model_hash(key):
    chunks = (KEY_W + INDEX_W - 1) // INDEX_W
    h = 0
    for i in range(chunks):
        h ^= (key >> (i * INDEX_W)) & ((1 << INDEX_W) - 1)
    return h & ((1 << INDEX_W) - 1)


async def reset(dut):
    dut.ins_valid.value = 0
    dut.lu_valid.value = 0
    dut.ins_key.value = 0
    dut.ins_action.value = 0
    dut.lu_key.value = 0
    dut.rst_n.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def insert(dut, key, action):
    dut.ins_valid.value = 1
    dut.ins_key.value = key
    dut.ins_action.value = action
    await RisingEdge(dut.clk)
    dut.ins_valid.value = 0


async def lookup(dut, key):
    dut.lu_valid.value = 1
    dut.lu_key.value = key
    await RisingEdge(dut.clk)
    dut.lu_valid.value = 0
    await ReadOnly()
    result = (int(dut.res_valid.value), int(dut.res_hit.value), int(dut.res_action.value))
    await RisingEdge(dut.clk)
    return result


@cocotb.test(timeout_time=100, timeout_unit="us")
async def insert_then_hit(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    await insert(dut, 0x0A0000090BB8, 0x3)  # dst 10.0.0.9, port 3000 -> action 3
    valid, hit, action = await lookup(dut, 0x0A0000090BB8)
    assert valid == 1 and hit == 1 and action == 0x3


@cocotb.test(timeout_time=100, timeout_unit="us")
async def miss_when_absent(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    valid, hit, _ = await lookup(dut, 0x123456789ABC)
    assert valid == 1 and hit == 0


@cocotb.test(timeout_time=100, timeout_unit="us")
async def overwrite_same_slot(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    key = 0xAABBCCDDEEFF
    await insert(dut, key, 0x1)
    await insert(dut, key, 0x9)  # same key, new action
    _, hit, action = await lookup(dut, key)
    assert hit == 1 and action == 0x9


@cocotb.test(timeout_time=500, timeout_unit="us")
async def random_matches_model(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    rnd = random.Random(0x5EED)
    slots = {}          # direct-mapped reference model, keyed by hash slot
    keys = [rnd.randrange(1 << KEY_W) for _ in range(60)]

    for _ in range(300):
        if rnd.random() < 0.4:
            k = rnd.choice(keys)
            a = rnd.randrange(1 << ACTION_W)
            await insert(dut, k, a)
            slots[model_hash(k)] = (k, a)
        else:
            k = rnd.choice(keys)
            _, hit, action = await lookup(dut, k)
            entry = slots.get(model_hash(k))
            exp_hit = 1 if (entry is not None and entry[0] == k) else 0
            assert hit == exp_hit, f"hit mismatch for key {k:#x}"
            if exp_hit:
                assert action == entry[1], f"action mismatch for key {k:#x}"
