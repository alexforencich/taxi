#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2021-2025 FPGA Ninja, LLC

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
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Timer

from cocotbext.axi import AxiLiteBus, AxiLiteMaster
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamFrame


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

        self.stat_source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis_stat), dut.clk, dut.rst)

        self.axil_master = AxiLiteMaster(AxiLiteBus.from_entity(dut.s_axil), dut.clk, dut.rst)

    def set_idle_generator(self, generator=None):
        if generator:
            self.stat_source.set_pause_generator(generator())
            self.axil_master.write_if.aw_channel.set_pause_generator(generator())
            self.axil_master.write_if.w_channel.set_pause_generator(generator())
            self.axil_master.read_if.ar_channel.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.axil_master.write_if.b_channel.set_pause_generator(generator())
            self.axil_master.read_if.r_channel.set_pause_generator(generator())

    async def cycle_reset(self):
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
async def run_test_acc(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    byte_lanes = tb.axil_master.read_if.byte_lanes
    counter_size = max(int(dut.STAT_COUNT_W.value) // 8, byte_lanes)

    await tb.cycle_reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await Timer(4000, 'ns')

    for n in range(10):
        for k in range(10):
            await tb.stat_source.send(AxiStreamFrame([k], tid=k))

        await Timer(1000, 'ns')

    data = await tb.axil_master.read_words(0, 10, ws=counter_size)

    print(data)

    for n in range(10):
        assert data[n] == n*10

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_stress_test(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    byte_lanes = tb.axil_master.read_if.byte_lanes
    counter_size = max(int(dut.STAT_COUNT_W.value) // 8, byte_lanes)
    stat_inc_width = len(dut.s_axis_stat.tdata)
    stat_id_width = len(dut.s_axis_stat.tid)

    await tb.cycle_reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await Timer(4000, 'ns')

    async def worker(source, queue, count=128):
        for k in range(count):
            count = random.randrange(1, 2**stat_inc_width)
            num = random.randrange(0, 2**stat_id_width)

            await tb.stat_source.send(AxiStreamFrame([count], tid=num))

            await queue.put((num, count))

            await Timer(random.randint(1, 1000), 'ns')

    workers = []
    queue = Queue()

    for k in range(16):
        workers.append(cocotb.start_soon(worker(tb.stat_source, queue, count=128)))

    while workers:
        await workers.pop(0).join()

    await Timer(1000, 'ns')

    data_ref = [0]*2**stat_id_width

    while not queue.empty():
        num, count = await queue.get()
        data_ref[num] += count

    print(data_ref)

    data = await tb.axil_master.read_words(0, 2**stat_id_width, ws=counter_size)

    print(data)

    assert data == data_ref

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


@pytest.mark.parametrize("stat_count_w", [32, 64])
def test_taxi_stats_counter(request, stat_count_w):
    dut = "taxi_stats_counter"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(taxi_src_dir, "axis", "rtl", "taxi_axis_if.sv"),
        os.path.join(taxi_src_dir, "axi", "rtl", "taxi_axil_if.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['STAT_COUNT_W'] = stat_count_w
    parameters['PIPELINE'] = 2
    parameters['STAT_INC_W'] = 16
    parameters['STAT_ID_W'] = 8
    parameters['AXIL_DATA_W'] = 32
    parameters['AXIL_ADDR_W'] = parameters['STAT_ID_W'] + ((parameters['STAT_COUNT_W']+7)//8-1).bit_length()

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
