"""Minimal AXI-Stream BFM for cocotb: a source that drives s_* and a sink that
reads m_*, both with randomized handshake gaps. Beats are sampled in the
ReadOnly phase so valid/ready are read exactly as they stand at the clock edge,
free of driver-ordering races."""
import random

from cocotb.triggers import RisingEdge, ReadOnly, NextTimeStep


async def axis_source(clk, tdata, tvalid, tready, words, *, idle_prob=0.3, seed=1):
    rnd = random.Random(seed)
    tvalid.value = 0
    idx = 0
    while idx < len(words):
        if rnd.random() < idle_prob:
            tvalid.value = 0
            await RisingEdge(clk)
            continue
        tvalid.value = 1
        tdata.value = words[idx]
        await RisingEdge(clk)
        await ReadOnly()
        accepted = tready.value == 1
        await NextTimeStep()
        if accepted:
            idx += 1
    tvalid.value = 0


async def axis_sink(clk, tdata, tvalid, tready, out, want, *, ready_prob=0.7, seed=2):
    rnd = random.Random(seed)
    tready.value = 0
    while len(out) < want:
        tready.value = 1 if rnd.random() < ready_prob else 0
        await RisingEdge(clk)
        await ReadOnly()
        if tvalid.value == 1 and tready.value == 1:
            out.append(int(tdata.value))
        await NextTimeStep()
    tready.value = 0
