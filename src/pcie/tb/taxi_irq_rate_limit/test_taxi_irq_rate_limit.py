#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2021-2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import itertools
import logging
import os

import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from cocotbext.axi import AxiStreamSource, AxiStreamSink, AxiStreamBus


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.irq_source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis_irq), dut.clk, dut.rst)
        self.irq_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis_irq), dut.clk, dut.rst)

        dut.prescale.setimmediatevalue(0)
        dut.min_interval.setimmediatevalue(0)

    def set_idle_generator(self, generator=None):
        if generator:
            self.irq_source.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.irq_sink.set_pause_generator(generator())

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
async def run_test_irq(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    await tb.cycle_reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    dut.prescale.setimmediatevalue(249)
    dut.min_interval.setimmediatevalue(100)

    tb.log.info("Test interrupts (single shot)")

    for k in range(8):
        await tb.irq_source.send([k])

    for k in range(8):
        irq = await tb.irq_sink.recv()
        tb.log.info(irq)
        assert irq.tdata[0] == k

    assert tb.irq_sink.empty()

    await Timer(110, 'us')

    assert tb.irq_sink.empty()

    tb.log.info("Test interrupts (multiple)")

    for n in range(5):
        for k in range(8):
            await tb.irq_source.send([k])

    for k in range(8):
        irq = await tb.irq_sink.recv()
        tb.log.info(irq)
        assert irq.tdata[0] == k

    assert tb.irq_sink.empty()

    await Timer(99, 'us')

    assert tb.irq_sink.empty()

    await Timer(11, 'us')

    assert not tb.irq_sink.empty()

    for k in range(8):
        irq = await tb.irq_sink.recv()
        tb.log.info(irq)
        assert irq.tdata[0] == k

    assert tb.irq_sink.empty()

    await Timer(110, 'us')

    assert tb.irq_sink.empty()

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


def test_taxi_irq_rate_limit(request):
    dut = "taxi_irq_rate_limit"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(taxi_src_dir, "axis", "rtl", "taxi_axis_if.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['IRQN_W'] = 11

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
