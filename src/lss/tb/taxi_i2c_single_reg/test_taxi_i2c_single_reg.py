#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2023-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import logging
import os

import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.i2c import I2cMaster


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())

        self.i2c_master = I2cMaster(sda=dut.sda_o, sda_o=dut.sda_i,
            scl=dut.scl_o, scl_o=dut.scl_i, speed=4000e3)

        dut.data_in.setimmediatevalue(0)
        dut.data_latch.setimmediatevalue(0)

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
async def run_test_write(dut):

    tb = TB(dut)

    await tb.reset()

    await tb.i2c_master.write(0x70, b'\x11\xAA')
    await tb.i2c_master.send_stop()

    assert int(dut.data_out.value) == 0xAA

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
async def run_test_null_write(dut):

    tb = TB(dut)

    await tb.reset()

    await RisingEdge(dut.clk)
    dut.data_in.value = 0xAA
    dut.data_latch.value = 1
    await RisingEdge(dut.clk)
    dut.data_latch.value = 0

    await tb.i2c_master.write(0x70, b'')
    await tb.i2c_master.send_stop()

    assert int(dut.data_out.value) == 0xAA

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
async def run_test_read(dut):

    tb = TB(dut)

    await tb.reset()

    await RisingEdge(dut.clk)
    dut.data_in.value = 0x55
    dut.data_latch.value = 1
    await RisingEdge(dut.clk)
    dut.data_latch.value = 0

    data = await tb.i2c_master.read(0x70, 4)
    await tb.i2c_master.send_stop()

    tb.log.info("Read data: %s", data)

    assert data == b'\x55'*4

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
async def run_test_nack(dut):

    tb = TB(dut)

    await tb.reset()

    await RisingEdge(dut.clk)
    dut.data_in.value = 0xAA
    dut.data_latch.value = 1
    await RisingEdge(dut.clk)
    dut.data_latch.value = 0

    await tb.i2c_master.write(0x55, b'\x00\x04'+b'\xde\xad\xbe\xef')
    await tb.i2c_master.send_stop()

    assert int(dut.data_out.value) == 0xAA

    # assert missed ack

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


def test_taxi_i2c_single_reg(request):
    dut = "taxi_i2c_single_reg"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['FILTER_LEN'] = 4
    parameters['DEV_ADDR'] = 0x70

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
