#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2023-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import itertools
import logging
import os
import random

from scapy.layers.l2 import Ether
from scapy.utils import mac2str

import pytest
import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Event

from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamFrame
from cocotbext.axi.stream import define_stream


McfBus, McfTransaction, McfSource, McfSink, McfMonitor = define_stream("Mcf",
    signals=["valid", "eth_dst", "eth_src", "eth_type", "opcode", "params"],
    optional_signals=["ready", "id", "dest", "user"]
)


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())

        self.source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis), dut.clk, dut.rst)
        self.sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis), dut.clk, dut.rst)
        self.mcf_source = McfSource(McfBus.from_prefix(dut, "mcf"), dut.clk, dut.rst)

        dut.tx_pause_req.setimmediatevalue(0)

    def set_idle_generator(self, generator=None):
        if generator:
            self.source.set_pause_generator(generator())
            self.mcf_source.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.sink.set_pause_generator(generator())

    async def reset(self):
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

    async def send(self, pkt):
        await self.source.send(bytes(pkt))

    async def send_mcf(self, pkt):
        mcf = McfTransaction()
        mcf.eth_dst = int.from_bytes(mac2str(pkt[Ether].dst), 'big')
        mcf.eth_src = int.from_bytes(mac2str(pkt[Ether].src), 'big')
        mcf.eth_type = pkt[Ether].type
        mcf.opcode = int.from_bytes(bytes(pkt[Ether].payload)[0:2], 'big')
        mcf.params = int.from_bytes(bytes(pkt[Ether].payload)[2:], 'little')

        await self.mcf_source.send(mcf)

    async def recv(self):
        rx_frame = await self.sink.recv()

        assert not rx_frame.tuser

        return Ether(bytes(rx_frame))


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


def size_list():
    return list(range(1, 128)) + [512, 1514, 9214] + [60]*10


def mcf_size_list():
    return list(range(1, 19))


def incrementing_payload(length):
    return bytes(itertools.islice(itertools.cycle(range(256)), length))


@cocotb.test()
@cocotb.parametrize(
    ("payload_lengths", [size_list]),
    ("payload_data", [incrementing_payload]),
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_data(dut, payload_lengths=None, payload_data=None, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    id_width = len(tb.source.bus.tid)
    id_count = 2**id_width
    id_mask = id_count-1

    src_width = 1
    src_mask = 2**src_width-1 if src_width else 0
    src_shift = id_width-src_width
    max_count = 2**src_shift
    count_mask = max_count-1

    cur_id = 1

    await tb.reset()

    dut.tx_pause_req.value = 0

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    test_frames = []

    for test_data in [payload_data(x) for x in payload_lengths()]:
        test_frame = AxiStreamFrame(test_data)
        test_frame.tid = cur_id | (0 << src_shift)
        test_frame.tdest = cur_id

        test_frames.append(test_frame)
        await tb.source.send(test_frame)

        cur_id = (cur_id + 1) % max_count

    for test_frame in test_frames:
        rx_frame = await tb.sink.recv()

        assert rx_frame.tdata == test_frame.tdata
        assert rx_frame.tid == test_frame.tid
        assert rx_frame.tdest == test_frame.tdest
        assert not rx_frame.tuser

    assert tb.sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("payload_lengths", [mcf_size_list]),
    ("payload_data", [incrementing_payload]),
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_mcf(dut, payload_lengths=None, payload_data=None, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    await tb.reset()

    dut.tx_pause_req.value = 0

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    test_pkts = []

    opcode = 1

    for payload in [payload_data(x) for x in payload_lengths()]:
        eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
        test_pkt = eth / (opcode.to_bytes(2, 'big') + payload)
        test_pkts.append(test_pkt.copy())

        await tb.send_mcf(test_pkt)

        opcode += 1

    for test_pkt in test_pkts:
        rx_pkt = await tb.recv()

        tb.log.info("RX packet: %s", repr(rx_pkt))

        # check prefix as frame gets zero-padded
        assert bytes(rx_pkt).find(bytes(test_pkt)) == 0

    assert tb.sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
async def run_test_tuser_assert(dut):

    tb = TB(dut)

    await tb.reset()

    dut.tx_pause_req.value = 0

    test_data = bytearray(itertools.islice(itertools.cycle(range(256)), 32))
    test_frame = AxiStreamFrame(test_data, tuser=1)
    await tb.source.send(test_frame)

    rx_frame = await tb.sink.recv()

    assert rx_frame.tdata == test_frame.tdata
    assert rx_frame.tuser

    assert tb.sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
async def run_arb_test(dut):

    tb = TB(dut)

    byte_lanes = tb.source.byte_lanes
    id_width = len(tb.source.bus.tid)
    id_count = 2**id_width
    id_mask = id_count-1

    src_width = 1
    src_mask = 2**src_width-1 if src_width else 0
    src_shift = id_width-src_width
    max_count = 2**src_shift
    count_mask = max_count-1

    cur_id = 1

    await tb.reset()

    dut.tx_pause_req.value = 0

    test_pkts = []
    test_frames = []

    for k in range(4):
        length = byte_lanes*16
        payload = bytearray(itertools.islice(itertools.cycle(range(256)), length))

        eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5', type=0x8000)
        test_pkt = eth / (cur_id.to_bytes(2, 'big') + payload)
        test_pkts.append((cur_id, test_pkt.copy()))

        test_frame = AxiStreamFrame(bytes(test_pkt), tx_complete=Event())
        test_frame.tid = cur_id | (0 << src_shift)
        test_frame.tdest = cur_id
        test_frames.append(test_frame)

        await tb.source.send(test_frame)

        cur_id = (cur_id + 1) % max_count

    length = random.randint(1, 18)
    payload = bytearray(itertools.islice(itertools.cycle(range(256)), length))

    eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
    test_pkt = eth / (cur_id.to_bytes(2, 'big') + payload)
    test_pkts.append((cur_id, test_pkt.copy()))

    # start transmit in the middle of frame 2
    await test_frames[1].tx_complete.wait()
    for j in range(8):
        await RisingEdge(dut.clk)
    await tb.send_mcf(test_pkt)
    await FallingEdge(dut.mcf_valid)

    cur_id = (cur_id + 1) % max_count

    for k in [0, 1, 2, 4, 3]:
        rx_frame = await tb.sink.recv()

        rx_pkt = Ether(bytes(rx_frame))

        tb.log.info("RX packet: %s", repr(rx_pkt))

        cur_id, test_pkt = test_pkts[k]

        if rx_pkt.type == 0x8808:
            # check prefix as frame gets zero-padded
            assert bytes(rx_pkt).find(bytes(test_pkt)) == 0
            assert rx_frame.tid == 0
            assert rx_frame.tdest == 0
        else:
            assert bytes(rx_pkt) == bytes(test_pkt)
            assert rx_frame.tid == cur_id | (0 << src_shift)
            assert rx_frame.tdest == cur_id

        assert not rx_frame.tuser

    assert tb.sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_stress_test(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    byte_lanes = tb.source.byte_lanes
    id_width = len(tb.source.bus.tid)
    id_count = 2**id_width
    id_mask = id_count-1

    src_width = 1
    src_mask = 2**src_width-1 if src_width else 0
    src_shift = id_width-src_width
    max_count = 2**src_shift
    count_mask = max_count-1

    cur_id = 1

    await tb.reset()

    dut.tx_pause_req.value = 0

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    test_pkts = [list() for x in range(2)]

    for k in range(256):
        length = random.randint(1, byte_lanes*16)
        payload = bytearray(itertools.islice(itertools.cycle(range(256)), length))

        eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5', type=0x8000)
        test_pkt = eth / (cur_id.to_bytes(2, 'big') + payload)
        test_pkts[0].append((cur_id, test_pkt.copy()))

        test_frame = AxiStreamFrame(bytes(test_pkt))
        test_frame.tid = cur_id | (0 << src_shift)
        test_frame.tdest = cur_id

        await tb.source.send(test_frame)

        cur_id = (cur_id + 1) % max_count

    for k in range(16):
        length = random.randint(1, 18)
        payload = bytearray(itertools.islice(itertools.cycle(range(256)), length))

        eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
        test_pkt = eth / (cur_id.to_bytes(2, 'big') + payload)
        test_pkts[1].append((cur_id, test_pkt.copy()))

        for c in range(random.randint(8, 64)):
            await RisingEdge(dut.clk)
        await tb.send_mcf(test_pkt)
        await FallingEdge(dut.mcf_valid)

        cur_id = (cur_id + 1) % max_count

    while any(test_pkts):
        rx_frame = await tb.sink.recv()

        rx_pkt = Ether(bytes(rx_frame))

        tb.log.info("RX packet: %s", repr(rx_pkt))

        test_pkt = None

        if rx_pkt.type == 0x8808:
            cur_id, test_pkt = test_pkts[1].pop(0)
            # check prefix as frame gets zero-padded
            assert bytes(rx_pkt).find(bytes(test_pkt)) == 0
            assert rx_frame.tid == 0
            assert rx_frame.tdest == 0
        else:
            cur_id, test_pkt = test_pkts[0].pop(0)
            assert bytes(rx_pkt) == bytes(test_pkt)
            assert rx_frame.tid == cur_id | (0 << src_shift)
            assert rx_frame.tdest == cur_id

        assert not rx_frame.tuser

    assert tb.sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


# cocotb-test

tests_dir = os.path.abspath(os.path.dirname(__file__))
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', '..', 'rtl'))
lib_dir = os.path.abspath(os.path.join(tests_dir, '..', '..', 'lib'))
taxi_src_dir = os.path.abspath(os.path.join(lib_dir, 'taxi', 'src'))


def process_f_files(files):
    lst = {}
    for f in files:
        if f[-2:].lower() == '.f':
            with open(f, 'r') as fp:
                l = fp.read().split()
            for f in process_f_files([os.path.join(os.path.dirname(f), x) for x in l]):
                lst[os.path.basename(f)] = f
        else:
            lst[os.path.basename(f)] = f
    return list(lst.values())


@pytest.mark.parametrize("data_w", [8, 16, 32, 64, 128, 256, 512])
def test_taxi_mac_ctrl_tx(request, data_w):
    dut = "taxi_mac_ctrl_tx"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(taxi_src_dir, "axis", "rtl", "taxi_axis_if.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['DATA_W'] = data_w
    parameters['ID_W'] = 8
    parameters['DEST_W'] = 8
    parameters['USER_W'] = 1
    parameters['MCF_PARAMS_SIZE'] = 18

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}

    sim_build = os.path.join(tests_dir, "sim_build",
        request.node.name.replace('[', '-').replace(']', ''))

    cocotb_test.simulator.run(
        simulator="verilator",
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
    )
