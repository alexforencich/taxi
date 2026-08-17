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

import pytest
import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

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
        self.mcf_sink = McfSink(McfBus.from_prefix(dut, "mcf"), dut.clk, dut.rst)

        dut.cfg_mcf_rx_eth_dst_mcast.setimmediatevalue(0)
        dut.cfg_mcf_rx_check_eth_dst_mcast.setimmediatevalue(0)
        dut.cfg_mcf_rx_eth_dst_ucast.setimmediatevalue(0)
        dut.cfg_mcf_rx_check_eth_dst_ucast.setimmediatevalue(0)
        dut.cfg_mcf_rx_eth_src.setimmediatevalue(0)
        dut.cfg_mcf_rx_check_eth_src.setimmediatevalue(0)
        dut.cfg_mcf_rx_eth_type.setimmediatevalue(0)
        dut.cfg_mcf_rx_opcode_lfc.setimmediatevalue(0)
        dut.cfg_mcf_rx_check_opcode_lfc.setimmediatevalue(0)
        dut.cfg_mcf_rx_opcode_pfc.setimmediatevalue(0)
        dut.cfg_mcf_rx_check_opcode_pfc.setimmediatevalue(0)

        dut.cfg_mcf_rx_forward.setimmediatevalue(0)
        dut.cfg_mcf_rx_enable.setimmediatevalue(0)

    def set_idle_generator(self, generator=None):
        if generator:
            self.source.set_pause_generator(generator())

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

    async def recv(self):
        rx_frame = await self.sink.recv()

        assert not rx_frame.tuser

        return Ether(bytes(rx_frame))

    async def recv_mcf(self):
        rx_frame = await self.mcf_sink.recv()

        data = bytearray()
        data.extend(int(rx_frame.eth_dst).to_bytes(6, 'big'))
        data.extend(int(rx_frame.eth_src).to_bytes(6, 'big'))
        data.extend(int(rx_frame.eth_type).to_bytes(2, 'big'))
        data.extend(int(rx_frame.opcode).to_bytes(2, 'big'))
        data.extend(int(rx_frame.params).to_bytes(44, 'little'))

        return Ether(data)


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

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    test_frames = []

    for test_data in [payload_data(x) for x in payload_lengths()]:
        test_frame = AxiStreamFrame(test_data)
        test_frame.tid = cur_id
        test_frame.tdest = cur_id | (0 << src_shift)

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
    assert tb.mcf_sink.empty()

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

    dut.cfg_mcf_rx_eth_dst_mcast.value = 0x0180C2000001
    dut.cfg_mcf_rx_check_eth_dst_mcast.value = 0
    dut.cfg_mcf_rx_eth_dst_ucast.value = 0xDAD1D2D3D4D5
    dut.cfg_mcf_rx_check_eth_dst_ucast.value = 0
    dut.cfg_mcf_rx_eth_src.value = 0x5A5152535455
    dut.cfg_mcf_rx_check_eth_src.value = 0
    dut.cfg_mcf_rx_eth_type.value = 0x8808
    dut.cfg_mcf_rx_opcode_lfc.value = 0x0001
    dut.cfg_mcf_rx_check_opcode_lfc.value = 0
    dut.cfg_mcf_rx_opcode_pfc.value = 0x0101
    dut.cfg_mcf_rx_check_opcode_pfc.value = 0

    dut.cfg_mcf_rx_forward.value = 0
    dut.cfg_mcf_rx_enable.value = 1

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    test_pkts = []

    for payload in [payload_data(x) for x in payload_lengths()]:
        eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
        test_pkt = eth / (cur_id.to_bytes(2, 'big') + payload)
        test_pkts.append((cur_id, test_pkt.copy()))

        test_frame = AxiStreamFrame(bytes(test_pkt))
        test_frame.tid = cur_id
        test_frame.tdest = cur_id | (1 << src_shift)

        await tb.source.send(test_frame)

        cur_id = (cur_id + 1) % max_count

    for cur_id, test_pkt in test_pkts:
        rx_frame = await tb.sink.recv()

        assert rx_frame.tdata == bytes(test_pkt)
        assert rx_frame.tid == cur_id
        assert rx_frame.tdest == cur_id | (1 << src_shift)
        assert rx_frame.tuser

        rx_pkt = await tb.recv_mcf()

        tb.log.info("RX packet: %s", repr(rx_pkt))

        # check prefix as padding may be different
        assert bytes(rx_pkt).find(bytes(test_pkt)) == 0

    assert tb.sink.empty()
    assert tb.mcf_sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
async def run_test_tuser_assert(dut):

    tb = TB(dut)

    byte_lanes = tb.source.byte_lanes

    await tb.reset()

    dut.cfg_mcf_rx_eth_dst_mcast.value = 0x0180C2000001
    dut.cfg_mcf_rx_check_eth_dst_mcast.value = 0
    dut.cfg_mcf_rx_eth_dst_ucast.value = 0xDAD1D2D3D4D5
    dut.cfg_mcf_rx_check_eth_dst_ucast.value = 0
    dut.cfg_mcf_rx_eth_src.value = 0x5A5152535455
    dut.cfg_mcf_rx_check_eth_src.value = 0
    dut.cfg_mcf_rx_eth_type.value = 0x8808
    dut.cfg_mcf_rx_opcode_lfc.value = 0x0001
    dut.cfg_mcf_rx_check_opcode_lfc.value = 0
    dut.cfg_mcf_rx_opcode_pfc.value = 0x0101
    dut.cfg_mcf_rx_check_opcode_pfc.value = 0

    dut.cfg_mcf_rx_forward.value = 0
    dut.cfg_mcf_rx_enable.value = 1

    # data
    payload = bytearray(itertools.islice(itertools.cycle(range(256)), byte_lanes*16))
    eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5', type=0x8000)
    test_pkt = eth / payload
    test_frame = AxiStreamFrame(bytes(test_pkt), tuser=1)
    await tb.source.send(test_frame)

    rx_frame = await tb.sink.recv()

    assert rx_frame.tdata == test_frame.tdata
    assert rx_frame.tuser

    # MAC control
    payload = bytearray(itertools.islice(itertools.cycle(range(256)), 18))
    eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
    test_pkt = eth / (b'\x00\x00' + payload)
    test_frame = AxiStreamFrame(bytes(test_pkt), tuser=1)
    await tb.source.send(test_frame)

    rx_frame = await tb.sink.recv()

    assert rx_frame.tdata == test_frame.tdata
    assert rx_frame.tuser

    assert tb.sink.empty()
    assert tb.mcf_sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
async def run_test_mcf_filter(dut):

    tb = TB(dut)

    await tb.reset()

    dut.cfg_mcf_rx_eth_dst_mcast.value = 0x0180C2000001
    dut.cfg_mcf_rx_check_eth_dst_mcast.value = 0
    dut.cfg_mcf_rx_eth_dst_ucast.value = 0xDAD1D2D3D4D5
    dut.cfg_mcf_rx_check_eth_dst_ucast.value = 0
    dut.cfg_mcf_rx_eth_src.value = 0x5A5152535455
    dut.cfg_mcf_rx_check_eth_src.value = 0
    dut.cfg_mcf_rx_eth_type.value = 0x8808
    dut.cfg_mcf_rx_opcode_lfc.value = 0x0001
    dut.cfg_mcf_rx_check_opcode_lfc.value = 0
    dut.cfg_mcf_rx_opcode_pfc.value = 0x0101
    dut.cfg_mcf_rx_check_opcode_pfc.value = 0

    dut.cfg_mcf_rx_forward.value = 0
    dut.cfg_mcf_rx_enable.value = 1

    async def check(tb, pkt, should_match):
        await tb.source.send(bytes(pkt))

        rx_frame = await tb.sink.recv()

        assert rx_frame.tdata == bytes(pkt)

        if should_match:
            assert rx_frame.tuser

            rx_pkt = await tb.recv_mcf()

            assert bytes(rx_pkt).find(bytes(pkt)) == 0
        else:
            assert not rx_frame.tuser

        assert tb.sink.empty()
        assert tb.mcf_sink.empty()

    payload = bytearray(itertools.islice(itertools.cycle(range(256)), 18))

    # Multicast destination address
    dut.cfg_mcf_rx_check_eth_dst_mcast.value = 1

    eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
    test_pkt = eth / (b'\x00\x00' + payload)
    await check(tb, test_pkt, True)

    eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5', type=0x8808)
    test_pkt = eth / (b'\x00\x00' + payload)
    await check(tb, test_pkt, False)

    dut.cfg_mcf_rx_check_eth_dst_mcast.value = 0

    # Unicast destination address
    dut.cfg_mcf_rx_check_eth_dst_ucast.value = 1

    eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5', type=0x8808)
    test_pkt = eth / (b'\x00\x00' + payload)
    await check(tb, test_pkt, True)

    eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
    test_pkt = eth / (b'\x00\x00' + payload)
    await check(tb, test_pkt, False)

    dut.cfg_mcf_rx_check_eth_dst_ucast.value = 0

    # Source address
    dut.cfg_mcf_rx_check_eth_src.value = 1

    eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
    test_pkt = eth / (b'\x00\x00' + payload)
    await check(tb, test_pkt, True)

    eth = Ether(src='5A:51:52:AA:AA:AA', dst='01:80:C2:00:00:01', type=0x8808)
    test_pkt = eth / (b'\x00\x00' + payload)
    await check(tb, test_pkt, False)

    dut.cfg_mcf_rx_check_eth_src.value = 0

    # Ethertype
    eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
    test_pkt = eth / (b'\x00\x00' + payload)
    await check(tb, test_pkt, True)

    eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8880)
    test_pkt = eth / (b'\x00\x00' + payload)
    await check(tb, test_pkt, False)

    # Opcode
    dut.cfg_mcf_rx_check_opcode_lfc.value = 1
    dut.cfg_mcf_rx_check_opcode_pfc.value = 1

    eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
    test_pkt = eth / (b'\x00\x01' + payload)
    await check(tb, test_pkt, True)

    eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
    test_pkt = eth / (b'\x01\x01' + payload)
    await check(tb, test_pkt, True)

    eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
    test_pkt = eth / (b'\x00\x00' + payload)
    await check(tb, test_pkt, False)

    dut.cfg_mcf_rx_check_opcode_lfc.value = 0
    dut.cfg_mcf_rx_check_opcode_pfc.value = 0

    assert tb.sink.empty()
    assert tb.mcf_sink.empty()

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

    dut.cfg_mcf_rx_eth_dst_mcast.value = 0x0180C2000001
    dut.cfg_mcf_rx_check_eth_dst_mcast.value = 0
    dut.cfg_mcf_rx_eth_dst_ucast.value = 0xDAD1D2D3D4D5
    dut.cfg_mcf_rx_check_eth_dst_ucast.value = 0
    dut.cfg_mcf_rx_eth_src.value = 0x5A5152535455
    dut.cfg_mcf_rx_check_eth_src.value = 0
    dut.cfg_mcf_rx_eth_type.value = 0x8808
    dut.cfg_mcf_rx_opcode_lfc.value = 0x0001
    dut.cfg_mcf_rx_check_opcode_lfc.value = 0
    dut.cfg_mcf_rx_opcode_pfc.value = 0x0101
    dut.cfg_mcf_rx_check_opcode_pfc.value = 0

    dut.cfg_mcf_rx_forward.value = 0
    dut.cfg_mcf_rx_enable.value = 1

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    test_pkts = []

    for k in range(256):
        if random.randrange(8) != 0:
            length = random.randint(1, byte_lanes*16)
            payload = bytearray(itertools.islice(itertools.cycle(range(256)), length))

            eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5', type=0x8000)
            test_pkt = eth / (cur_id.to_bytes(2, 'big') + payload)
            test_pkts.append((cur_id, test_pkt.copy()))
            dest = cur_id | (0 << src_shift)
        else:
            length = random.randint(1, 18)
            payload = bytearray(itertools.islice(itertools.cycle(range(256)), length))

            eth = Ether(src='5A:51:52:53:54:55', dst='01:80:C2:00:00:01', type=0x8808)
            test_pkt = eth / (cur_id.to_bytes(2, 'big') + payload)
            test_pkts.append((cur_id, test_pkt.copy()))
            dest = cur_id | (1 << src_shift)

        test_frame = AxiStreamFrame(bytes(test_pkt))
        test_frame.tid = cur_id
        test_frame.tdest = dest

        await tb.source.send(test_frame)

        cur_id = (cur_id + 1) % max_count

    for cur_id, test_pkt in test_pkts:
        rx_frame = await tb.sink.recv()

        assert rx_frame.tdata == bytes(test_pkt)
        assert rx_frame.tid == cur_id
        assert (rx_frame.tdest & count_mask) == cur_id

        if rx_frame.tdest >> src_shift:
            assert rx_frame.tuser

            rx_pkt = await tb.recv_mcf()

            tb.log.info("RX packet: %s", repr(rx_pkt))

            # check prefix as padding may be different
            assert bytes(rx_pkt).find(bytes(test_pkt)) == 0
        else:
            assert not rx_frame.tuser

    for k in range(1000):
        await RisingEdge(dut.clk)

    assert tb.sink.empty()
    assert tb.mcf_sink.empty()

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
def test_taxi_mac_ctrl_rx(request, data_w):
    dut = "taxi_mac_ctrl_rx"
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
    parameters['USE_READY'] = 1
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
