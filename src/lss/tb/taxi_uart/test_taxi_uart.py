#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2020-2025 FPGA Ninja, LLC

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
from cocotbext.uart import UartSource, UartSink


class TB:
    def __init__(self, dut, baud=3e6):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())

        self.uart_source = UartSource(dut.rxd, baud=baud, bits=len(dut.m_axis_rx.tdata), stop_bits=1)
        self.uart_sink = UartSink(dut.txd, baud=baud, bits=len(dut.s_axis_tx.tdata), stop_bits=1)

        self.axis_source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis_tx), dut.clk, dut.rst)
        self.axis_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis_rx), dut.clk, dut.rst)

        dut.prescale.setimmediatevalue(int(1/8e-9/baud))

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


def prbs31(state=0x7fffffff):
    while True:
        for i in range(8):
            if bool(state & 0x08000000) ^ bool(state & 0x40000000):
                state = ((state & 0x3fffffff) << 1) | 1
            else:
                state = (state & 0x3fffffff) << 1
        yield state & 0xff


def size_list():
    return list(range(1, 16)) + [128]


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))


def prbs_payload(length):
    gen = prbs31()
    return bytearray([next(gen) for x in range(length)])


@cocotb.test()
@cocotb.parametrize(
    ("payload_lengths", [size_list]),
    ("payload_data", [incrementing_payload, prbs_payload]),
)
async def run_test_tx(dut, payload_lengths=None, payload_data=None):

    tb = TB(dut)

    await tb.reset()

    for test_data in [payload_data(x) for x in payload_lengths()]:

        await tb.axis_source.write(test_data)

        rx_data = bytearray()

        while len(rx_data) < len(test_data):
            rx_data.extend(await tb.uart_sink.read())

        tb.log.info("Read data: %s", rx_data)

        assert tb.uart_sink.empty()

        await Timer(2, 'us')

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("payload_lengths", [size_list]),
    ("payload_data", [incrementing_payload, prbs_payload]),
)
async def run_test_rx(dut, payload_lengths=None, payload_data=None):

    tb = TB(dut)

    await tb.reset()

    for test_data in [payload_data(x) for x in payload_lengths()]:

        await tb.uart_source.write(test_data)

        rx_data = bytearray()

        while len(rx_data) < len(test_data):
            rx_data.extend(await tb.axis_sink.read())

        tb.log.info("Read data: %s", rx_data)

        assert tb.axis_sink.empty()

        await Timer(2, 'us')

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


def test_taxi_uart(request):
    dut = "taxi_uart"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.f"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['PRE_W'] = 16
    parameters['DATA_W'] = 8

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
