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

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink
from cocotbext.i2c import I2cMemory

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

        self.i2c_mem = []

        self.i2c_mem.append(I2cMemory(sda=dut.i2c_sda_o, sda_o=dut.i2c_sda_i,
            scl=dut.i2c_scl_o, scl_o=dut.i2c_scl_i, addr=0x50, size=1024))
        self.i2c_mem.append(I2cMemory(sda=dut.i2c_sda_o, sda_o=dut.i2c_sda_i,
            scl=dut.i2c_scl_o, scl_o=dut.i2c_scl_i, addr=0x51, size=1024))

    def set_idle_generator(self, generator=None):
        if generator:
            self.usp_source.set_pause_generator(generator())

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

    async def get_status(self):
        self.log.debug("Get status")

        pkt = XfcpFrame()
        pkt.ptype = 0x2C
        pkt.payload = b'\x40'

        self.log.debug("TX packet: %s", pkt)

        await self.usp_source.send(pkt.build())

        rx_frame = await self.usp_sink.recv()
        rx_pkt = XfcpFrame.parse(rx_frame.tdata)

        self.log.debug("RX packet: %s", rx_pkt)

        status = rx_pkt.payload[-1]

        self.log.debug("Status: 0x%x", status)

        return status

    async def set_prescale(self, val):
        self.log.debug("Set prescale: %s", val)

        payload = bytearray()
        payload.append(0x60)  # set prescale
        payload.extend(struct.pack('<H', val))  # prescale

        pkt = XfcpFrame()
        pkt.ptype = 0x2C
        pkt.payload = payload

        self.log.debug("TX packet: %s", pkt)

        await self.usp_source.send(pkt.build())

        rx_frame = await self.usp_sink.recv()
        rx_pkt = XfcpFrame.parse(rx_frame.tdata)

        self.log.debug("RX packet: %s", rx_pkt)


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_write(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    # change prescale setting
    await tb.set_prescale(125000000//4000000//4)

    test_data = b'\x11\x22\x33\x44'

    for mem in tb.i2c_mem:

        data = struct.pack('>H', 0x0004)+test_data
        payload = bytearray()
        payload.append(0x80 | mem.addr)  # set address
        payload.append(0x1C)  # start write
        payload.append(len(data))  # length
        payload.extend(data)  # data

        pkt = XfcpFrame()
        pkt.ptype = 0x2C
        pkt.payload = payload

        tb.log.debug("TX packet: %s", pkt)

        await tb.usp_source.send(pkt.build())

        rx_frame = await tb.usp_sink.recv()
        rx_pkt = XfcpFrame.parse(rx_frame.tdata)

        tb.log.debug("RX packet: %s", rx_pkt)

        for k in range(1000):
            await RisingEdge(dut.clk)

        data = mem.read_mem(4, 4)

        tb.log.info("Read data: %s", data)

        assert data == test_data

        status = await tb.get_status()

        # no missed ACKs
        assert not (status & 8)

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_read(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    # change prescale setting
    await tb.set_prescale(125000000//4000000//4)

    test_data = b'\x11\x22\x33\x44'

    for mem in tb.i2c_mem:

        mem.write_mem(4, test_data)

        payload = bytearray()
        payload.append(0x80 | mem.addr)  # set address
        payload.append(0x14)  # start write
        payload.append(2)  # length
        payload.extend(struct.pack('>H', 0x0004))  # address
        payload.append(0x1A)  # start read
        payload.append(4)  # length

        pkt = XfcpFrame()
        pkt.ptype = 0x2C
        pkt.payload = payload

        tb.log.debug("TX packet: %s", pkt)

        await tb.usp_source.send(pkt.build())

        rx_frame = await tb.usp_sink.recv()
        rx_pkt = XfcpFrame.parse(rx_frame.tdata)

        tb.log.debug("RX packet: %s", rx_pkt)

        data = rx_pkt.payload[-4:]

        tb.log.info("Read data: %s", data)

        assert data == test_data

        status = await tb.get_status()

        # no missed ACKs
        assert not (status & 8)

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_nack(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    # change prescale setting
    await tb.set_prescale(125000000//4000000//4)

    payload = bytearray()
    payload.append(0x80 | 0x55)  # set address
    payload.append(0x14)  # start write
    payload.append(2)  # length
    payload.extend(struct.pack('>H', 0x0004))  # address

    pkt = XfcpFrame()
    pkt.ptype = 0x2C
    pkt.payload = payload

    tb.log.debug("TX packet: %s", pkt)

    await tb.usp_source.send(pkt.build())

    rx_frame = await tb.usp_sink.recv()
    rx_pkt = XfcpFrame.parse(rx_frame.tdata)

    tb.log.debug("RX packet: %s", rx_pkt)

    status = await tb.get_status()

    # no missed ACKs
    assert (status & 8)

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


def test_taxi_xfcp_mod_i2c_master(request):

    dut = "taxi_xfcp_mod_i2c_master"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.f"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['DEFAULT_PRESCALE'] = 125000000//400000//4

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
