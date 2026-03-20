#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2020-2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import itertools
import logging
import os
import random

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.regression import TestFactory

from cocotbext.axi import AxiBus, AxiMaster


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.a_clk, 8, units="ns").start())
        cocotb.start_soon(Clock(dut.b_clk, 10, units="ns").start())

        self.axi_master = []

        self.axi_master.append(AxiMaster(AxiBus.from_entity(dut.s_axi_a), dut.a_clk, dut.a_rst))
        self.axi_master.append(AxiMaster(AxiBus.from_entity(dut.s_axi_b), dut.b_clk, dut.b_rst))

    def set_idle_generator(self, generator=None):
        if generator:
            for axi_master in self.axi_master:
                axi_master.write_if.aw_channel.set_pause_generator(generator())
                axi_master.write_if.w_channel.set_pause_generator(generator())
                axi_master.read_if.ar_channel.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            for axi_master in self.axi_master:
                axi_master.write_if.b_channel.set_pause_generator(generator())
                axi_master.read_if.r_channel.set_pause_generator(generator())

    async def cycle_reset(self):
        self.dut.a_rst.setimmediatevalue(0)
        self.dut.b_rst.setimmediatevalue(0)
        await RisingEdge(self.dut.a_clk)
        await RisingEdge(self.dut.a_clk)
        self.dut.a_rst.value = 1
        self.dut.b_rst.value = 1
        await RisingEdge(self.dut.a_clk)
        await RisingEdge(self.dut.a_clk)
        self.dut.a_rst.value = 0
        await RisingEdge(self.dut.b_clk)
        self.dut.b_rst.value = 0
        await RisingEdge(self.dut.a_clk)
        await RisingEdge(self.dut.a_clk)


async def run_test_write(dut, port=0, data_in=None, idle_inserter=None, backpressure_inserter=None, size=None):

    tb = TB(dut)

    axi_master = tb.axi_master[port]
    byte_lanes = axi_master.write_if.byte_lanes
    max_burst_size = axi_master.write_if.max_burst_size

    if size is None:
        size = max_burst_size

    await tb.cycle_reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    for length in list(range(1, byte_lanes*2))+[1024]:
        for offset in list(range(byte_lanes, byte_lanes*2))+list(range(4096-byte_lanes, 4096)):
            tb.log.info("length %d, offset %d, size %d", length, offset, size)
            addr = offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])

            await axi_master.write(addr-4, b'\xaa'*(length+8))

            await axi_master.write(addr, test_data, size=size)

            data = await axi_master.read(addr-1, length+2)

            assert data.data == b'\xaa'+test_data+b'\xaa'

    await RisingEdge(dut.a_clk)
    await RisingEdge(dut.a_clk)


async def run_test_read(dut, port=0, data_in=None, idle_inserter=None, backpressure_inserter=None, size=None):

    tb = TB(dut)

    axi_master = tb.axi_master[port]
    byte_lanes = axi_master.write_if.byte_lanes
    max_burst_size = axi_master.write_if.max_burst_size

    if size is None:
        size = max_burst_size

    await tb.cycle_reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    for length in list(range(1, byte_lanes*2))+[1024]:
        for offset in list(range(byte_lanes, byte_lanes*2))+list(range(4096-byte_lanes, 4096)):
            tb.log.info("length %d, offset %d, size %d", length, offset, size)
            addr = offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])

            await axi_master.write(addr, test_data)

            data = await axi_master.read(addr, length, size=size)

            assert data.data == test_data

    await RisingEdge(dut.a_clk)
    await RisingEdge(dut.a_clk)


async def run_test_arb(dut, data_in=None, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    await tb.cycle_reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    async def worker(master, offset):
        wr_op = master.init_write(offset, b'\x11\x22\x33\x44')
        rd_op = master.init_read(offset, 4)

        await wr_op.wait()
        await rd_op.wait()

    workers = []

    for k in range(10):
        workers.append(cocotb.start_soon(worker(tb.axi_master[0], k*256)))
        workers.append(cocotb.start_soon(worker(tb.axi_master[1], k*256)))

    while workers:
        await workers.pop(0).join()

    await RisingEdge(dut.a_clk)
    await RisingEdge(dut.a_clk)


async def run_stress_test(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    await tb.cycle_reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    async def worker(master, offset, aperture, count=16):
        for k in range(count):
            length = random.randint(1, min(512, aperture))
            addr = offset+random.randint(0, aperture-length)
            test_data = bytearray([x % 256 for x in range(length)])

            await Timer(random.randint(1, 100), 'ns')

            await master.write(addr, test_data)

            await Timer(random.randint(1, 100), 'ns')

            data = await master.read(addr, length)
            assert data.data == test_data

    workers = []

    for k in range(16):
        workers.append(cocotb.start_soon(worker(tb.axi_master[k % len(tb.axi_master)], k*0x1000, 0x1000, count=16)))

    while workers:
        await workers.pop(0).join()

    await RisingEdge(dut.a_clk)
    await RisingEdge(dut.a_clk)


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


if getattr(cocotb, 'top', None) is not None:

    data_width = len(cocotb.top.s_axi_a.wdata)
    byte_lanes = data_width // 8
    max_burst_size = (byte_lanes-1).bit_length()

    for test in [run_test_write, run_test_read]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.add_option("size", [None]+list(range(max_burst_size)))
        factory.add_option("port", [0, 1])
        factory.generate_tests()

    factory = TestFactory(run_test_arb)
    factory.add_option("idle_inserter", [None, cycle_pause])
    factory.add_option("backpressure_inserter", [None, cycle_pause])
    factory.generate_tests()

    factory = TestFactory(run_stress_test)
    factory.add_option("idle_inserter", [None, cycle_pause])
    factory.add_option("backpressure_inserter", [None, cycle_pause])
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


@pytest.mark.parametrize("data_w", [8, 16, 32])
def test_taxi_axi_dp_ram(request, data_w):
    dut = "taxi_axi_dp_ram"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.f"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['DATA_W'] = data_w
    parameters['ADDR_W'] = 16
    parameters['STRB_W'] = parameters['DATA_W'] // 8
    parameters['ID_W'] = 8
    parameters['A_PIPELINE_OUTPUT'] = 0
    parameters['B_PIPELINE_OUTPUT'] = 0
    parameters['A_INTERLEAVE'] = 0
    parameters['B_INTERLEAVE'] = 0

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
