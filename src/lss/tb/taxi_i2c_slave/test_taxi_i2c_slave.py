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
from cocotb.triggers import RisingEdge

from cocotbext.axi import AxiStreamSource, AxiStreamSink, AxiStreamBus
from cocotbext.i2c import I2cMaster


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())

        self.data_source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis_tx), dut.clk, dut.rst)
        self.data_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis_rx), dut.clk, dut.rst)

        self.i2c_master = I2cMaster(sda=dut.sda_o, sda_o=dut.sda_i,
            scl=dut.scl_o, scl_o=dut.scl_i, speed=4000e3)

        dut.release_bus.setimmediatevalue(0)
        dut.enable.setimmediatevalue(1)
        dut.device_address.setimmediatevalue(0x50)
        dut.device_address_mask.setimmediatevalue(0x7f)

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


@cocotb.test()
async def run_test(dut):

    tb = TB(dut)

    await tb.reset()

    tb.log.info("Test write")

    test_data = b'\x11\x22\x33\x44'

    await tb.i2c_master.write(0x50, b'\x00\x04'+test_data)
    await tb.i2c_master.send_stop()

    data = await tb.data_sink.recv()

    tb.log.info("Read data: %s", data)

    assert data.tdata == b'\x00\x04'+test_data

    tb.log.info("Test read")

    await tb.data_source.send(test_data)

    await tb.i2c_master.write(0x50, b'\x00\x04')
    data = await tb.i2c_master.read(0x50, 4)
    await tb.i2c_master.send_stop()

    tb.log.info("Read data: %s", data)

    assert data == test_data

    tb.log.info("Test write to nonexistent device")

    await tb.i2c_master.write(0x55, b'\x00\x04'+b'\xde\xad\xbe\xef')
    await tb.i2c_master.send_stop()

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


def test_taxi_i2c_slave(request):
    dut = "taxi_i2c_slave"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(taxi_src_dir, "axis", "rtl", "taxi_axis_if.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['FILTER_LEN'] = 4

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
