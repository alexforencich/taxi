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

import cocotb
from cocotb.clock import Clock
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge, Timer

from cocotbext.axi import AxiStreamBus, AxiStreamSink


def str2int(s):
    return int.from_bytes(s.encode('utf-8'), 'big')


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

        self.stat_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis_stat), dut.clk, dut.rst)

        for k in range(len(dut.stat_inc)):
            dut.stat_inc[k].setimmediatevalue(0)
            dut.stat_valid[k].setimmediatevalue(0)
            dut.stat_str[k].setimmediatevalue(str2int(f"STR_{k}"))

        dut.gate.setimmediatevalue(1)
        dut.update.setimmediatevalue(0)

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.stat_sink.set_pause_generator(generator())

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
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_acc(dut, backpressure_inserter=None):

    tb = TB(dut)

    stat_count = len(dut.stat_valid)

    await tb.cycle_reset()

    tb.set_backpressure_generator(backpressure_inserter)

    for n in range(10):
        await RisingEdge(dut.clk)
        dut.stat_inc.value = [k for k in range(stat_count)]
        dut.stat_valid.value = [1]*stat_count
        await RisingEdge(dut.clk)
        dut.stat_inc.value = [0]*stat_count
        dut.stat_valid.value = [0]*stat_count

        await Timer(1000, 'ns')

    await Timer(1000, 'ns')

    data = [0]*stat_count

    while not tb.stat_sink.empty():
        stat = await tb.stat_sink.recv()

        if not stat.tuser:
            assert stat.tdata[0] != 0

            data[stat.tid] += stat.tdata[0]

    print(data)

    for n in range(stat_count):
        assert data[n] == n*10

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_max(dut, backpressure_inserter=None):

    tb = TB(dut)

    stat_count = len(dut.stat_valid)
    stat_inc_width = len(dut.stat_inc[0])

    await tb.cycle_reset()

    tb.set_backpressure_generator(backpressure_inserter)

    dut.stat_inc.value = [2**stat_inc_width-1 for k in range(stat_count)]
    dut.stat_valid.value = [1]*stat_count
    for k in range(2048):
        await RisingEdge(dut.clk)
    dut.stat_inc.value = [0]*stat_count
    dut.stat_valid.value = [0]*stat_count

    await Timer(1000, 'ns')

    data = [0]*stat_count

    while not tb.stat_sink.empty():
        stat = await tb.stat_sink.recv()

        if not stat.tuser:
            assert stat.tdata[0] != 0

            data[stat.tid] += stat.tdata[0]

    print(data)

    for n in range(stat_count):
        assert data[n] == 2048*(2**stat_inc_width-1)

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_str(dut, backpressure_inserter=None):

    tb = TB(dut)

    stat_count = len(dut.stat_valid)

    await tb.cycle_reset()

    tb.set_backpressure_generator(backpressure_inserter)

    strings = [bytearray() for x in range(stat_count)]
    done_cnt = 0

    while done_cnt < stat_count:
        stat = await tb.stat_sink.recv()

        print(stat)

        val = stat.tdata[0]
        index = stat.tid

        ptr = (val & 0x7)*2
        b = bytearray()
        for k in range(2):
            c = (val >> (k*6 + 4)) & 0x3f
            if c & 0x20:
                c = (c & 0x1f) | 0x40
            else:
                c = (c & 0x1f) | 0x20
            b.append(c)
        if len(strings[index]) == ptr:
            strings[index].extend(b)

        if ptr == 14:
            done_cnt += 1

    print(strings)

    for i, s in enumerate(strings):
        s = (s[0:8].strip() + b"." + s[8:].strip()).decode('ascii')
        print(s)

        assert s == f'BLK.STR_{i}'

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_stress_test(dut, backpressure_inserter=None):

    tb = TB(dut)

    stat_count = len(dut.stat_valid)
    stat_inc_width = len(dut.stat_inc[0])

    await tb.cycle_reset()

    tb.set_backpressure_generator(backpressure_inserter)

    async def worker(num, queue_ref, queue_drive, count=1024):
        for k in range(count):
            count = random.randrange(1, 2**stat_inc_width)

            await queue_drive.put(count)
            await queue_ref.put((num, count))

            await Timer(random.randint(1, 100), 'ns')

    workers = []
    queue_ref = Queue()
    queue_drive = [Queue() for k in range(stat_count)]

    for k in range(stat_count):
        workers.append(cocotb.start_soon(worker(k, queue_ref, queue_drive[k], count=1024)))

    async def driver(dut, queues):
        while True:
            await RisingEdge(dut.clk)

            inc = [0]*stat_count
            valid = [0]*stat_count
            for num, queue in enumerate(queues):
                if not queue.empty():
                    count = await queue.get()
                    inc[num] += count
                    valid[num] = 1

            dut.stat_inc.value = inc
            dut.stat_valid.value = valid

    driver = cocotb.start_soon(driver(dut, queue_drive))

    while workers:
        await workers.pop(0).join()

    await Timer(1000, 'ns')

    driver.kill()

    await Timer(1000, 'ns')

    data_ref = [0]*stat_count

    while not queue_ref.empty():
        num, count = await queue_ref.get()
        data_ref[num] += count

    print(data_ref)

    data = [0]*stat_count

    while not tb.stat_sink.empty():
        stat = await tb.stat_sink.recv()

        if not stat.tuser:
            assert stat.tdata[0] != 0

            data[stat.tid] += stat.tdata[0]

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


def test_taxi_stats_collect(request):
    dut = "taxi_stats_collect"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(taxi_src_dir, "axis", "rtl", "taxi_axis_if.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['CNT'] = 8
    parameters['INC_W'] = 8
    parameters['ID_BASE'] = 0
    parameters['UPDATE_PERIOD'] = 128
    parameters['STR_EN'] = 1
    parameters['PREFIX_STR'] = "\"BLK\""
    parameters['STAT_INC_W'] = 16
    parameters['STAT_ID_W'] = (parameters['CNT']-1).bit_length()

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
