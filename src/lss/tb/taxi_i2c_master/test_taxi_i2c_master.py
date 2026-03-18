#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2020-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import logging
import os

import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.regression import TestFactory

from cocotbext.axi import AxiStreamSource, AxiStreamSink, AxiStreamBus
from cocotbext.i2c import I2cMemory


CMD_START        = 1 << 7
CMD_READ         = 1 << 8
CMD_WRITE        = 1 << 9
CMD_WRITE_MULTI  = 1 << 10
CMD_STOP         = 1 << 11


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())

        self.cmd_source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis_cmd), dut.clk, dut.rst)

        self.data_source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis_tx), dut.clk, dut.rst)
        self.data_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis_rx), dut.clk, dut.rst)

        self.i2c_mem = []

        self.i2c_mem.append(I2cMemory(sda=dut.sda_o, sda_o=dut.sda_i,
            scl=dut.scl_o, scl_o=dut.scl_i, addr=0x50, size=1024))
        self.i2c_mem.append(I2cMemory(sda=dut.sda_o, sda_o=dut.sda_i,
            scl=dut.scl_o, scl_o=dut.scl_i, addr=0x51, size=1024))

        dut.prescale.setimmediatevalue(20)
        dut.tbuf_cyc.setimmediatevalue(20)
        dut.stop_on_idle.setimmediatevalue(0)

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

    async def i2c_write_data(self, addr, data, start=0, stop=0):
        cmd = CMD_WRITE_MULTI | addr
        if start:
            cmd |= CMD_START
        if stop:
            cmd |= CMD_STOP
        await self.cmd_source.send([cmd])
        await self.data_source.send(data)
        await self.data_source.wait()
        await self.i2c_wait()

    async def i2c_read_data(self, addr, count, start=0, stop=0):
        for k in range(count):
            cmd = CMD_READ | addr
            if start and k == 0:
                cmd |= CMD_START
            if stop and k == count-1:
                cmd |= CMD_STOP
            await self.cmd_source.send([cmd])
        return (await self.data_sink.recv()).tdata

    async def i2c_wait(self):
        if int(self.dut.busy.value):
            await FallingEdge(self.dut.busy)

    async def i2c_wait_bus_idle(self):
        if int(self.dut.bus_active.value):
            await FallingEdge(self.dut.bus_active)


async def run_test_write(dut):

    tb = TB(dut)

    await tb.reset()

    test_data = b'\x11\x22\x33\x44'

    for mem in tb.i2c_mem:

        await tb.i2c_write_data(mem.addr, b'\x00\x04'+test_data, stop=1)
        await tb.i2c_wait_bus_idle()

        data = mem.read_mem(4, 4)

        tb.log.info("Read data: %s", data)

        assert data == test_data

        # assert not missed ack

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def run_test_read(dut):

    tb = TB(dut)

    await tb.reset()

    test_data = b'\x11\x22\x33\x44'

    for mem in tb.i2c_mem:

        mem.write_mem(4, test_data)

        await tb.i2c_write_data(mem.addr, b'\x00\x04')
        read_data = await tb.i2c_read_data(mem.addr, 4, start=1, stop=1)

        tb.log.info("Read data: %s", read_data)

        assert read_data == test_data

        # assert not missed ack

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


async def run_test_nack(dut):

    tb = TB(dut)

    await tb.reset()

    await tb.i2c_write_data(0x55, b'\x00\x04'+b'\xde\xad\xbe\xef', stop=1)
    await tb.i2c_wait_bus_idle()

    # assert missed ack

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


if getattr(cocotb, 'top', None) is not None:

    for test in [
                run_test_write,
                run_test_read,
                run_test_nack,
            ]:

        factory = TestFactory(test)
        factory.generate_tests()


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


def test_taxi_i2c_master(request):
    dut = "taxi_i2c_master"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(taxi_src_dir, "axis", "rtl", "taxi_axis_if.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

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
