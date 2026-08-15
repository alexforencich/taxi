#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import itertools
import logging
import os
import struct
import sys

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink
from cocotbext.axi import ApbBus, ApbRam

try:
    from xfcp import XfcpFrame
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        from xfcp import XfcpFrame
    finally:
        del sys.path[0]


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())

        self.usp_source = AxiStreamSource(AxiStreamBus.from_entity(dut.xfcp_usp_ds), dut.clk, dut.rst)
        self.usp_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.xfcp_usp_us), dut.clk, dut.rst)

        self.apb_ram = ApbRam(ApbBus.from_entity(dut.m_apb), dut.clk, dut.rst, size=2**16)

    def set_idle_generator(self, generator=None):
        if generator:
            self.usp_source.set_pause_generator(generator())
            self.apb_ram.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.usp_sink.set_pause_generator(generator())

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


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_write(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    byte_lanes = tb.apb_ram.byte_lanes

    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    for length in range(1, byte_lanes*4):
        for offset in range(byte_lanes):
            tb.log.info("length %d, offset %d", length, offset)
            addr = offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])

            tb.apb_ram.write(addr-128, b'\xaa'*(length+256))

            pkt = XfcpFrame()
            pkt.ptype = 0x12
            pkt.payload = bytearray(struct.pack('<IH', addr, length)+test_data)

            tb.log.debug("TX packet: %s", pkt)

            await tb.usp_source.send(pkt.build())

            rx_frame = await tb.usp_sink.recv()
            rx_pkt = XfcpFrame.parse(rx_frame.tdata)

            tb.log.debug("RX packet: %s", rx_pkt)

            for k in range(100):
                await RisingEdge(dut.clk)

            tb.log.debug("%s", tb.apb_ram.hexdump_str((addr & ~0xf)-16, (((addr & 0xf)+length-1) & ~0xf)+48))

            assert tb.apb_ram.read(addr, length) == test_data
            assert tb.apb_ram.read(addr-1, 1) == b'\xaa'
            assert tb.apb_ram.read(addr+length, 1) == b'\xaa'

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_read(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    byte_lanes = tb.apb_ram.byte_lanes

    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    for length in range(1, byte_lanes*4):
        for offset in range(byte_lanes):
            tb.log.info("length %d, offset %d", length, offset)
            addr = offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])

            tb.apb_ram.write(addr, test_data)

            pkt = XfcpFrame()
            pkt.ptype = 0x10
            pkt.payload = bytearray(struct.pack('<IH', addr, length))

            tb.log.debug("TX packet: %s", pkt)

            await tb.usp_source.send(pkt.build())

            rx_frame = await tb.usp_sink.recv()
            rx_pkt = XfcpFrame.parse(rx_frame.tdata)

            tb.log.debug("RX packet: %s", rx_pkt)

            assert rx_pkt.payload[6:] == test_data

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_id(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    pkt = XfcpFrame()
    pkt.ptype = 0xFE
    pkt.payload = b''

    tb.log.debug("TX packet: %s", pkt)

    await tb.usp_source.send(pkt.build())

    rx_frame = await tb.usp_sink.recv()
    rx_pkt = XfcpFrame.parse(rx_frame.tdata)

    tb.log.debug("RX packet: %s", rx_pkt)

    assert len(rx_pkt.payload) == 32

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


# cocotb-test

tests_dir = os.path.dirname(__file__)
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


@pytest.mark.parametrize("data_w", [8, 16, 32])
def test_taxi_xfcp_mod_apb(request, data_w):

    dut = "taxi_xfcp_mod_apb"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(taxi_src_dir, "apb", "rtl", "taxi_apb_if.sv"),
        os.path.join(taxi_src_dir, "axis", "rtl", "taxi_axis_if.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['COUNT_SIZE'] = 16
    parameters['APB_DATA_W'] = data_w
    parameters['APB_ADDR_W'] = 32
    parameters['APB_STRB_W'] = parameters['APB_DATA_W'] // 8

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
