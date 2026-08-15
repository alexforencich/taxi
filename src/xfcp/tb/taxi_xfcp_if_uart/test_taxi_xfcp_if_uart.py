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
import sys

import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink
from cocotbext.uart import UartSource, UartSink

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
    def __init__(self, dut, baud=3e6):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 8, units="ns").start())

        self.uart_source = UartSource(dut.uart_rxd, baud=baud, bits=8, stop_bits=1)
        self.uart_sink = UartSink(dut.uart_txd, baud=baud, bits=8, stop_bits=1)

        self.dsp_source = AxiStreamSource(AxiStreamBus.from_entity(dut.xfcp_dsp_us), dut.clk, dut.rst)
        self.dsp_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.xfcp_dsp_ds), dut.clk, dut.rst)

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


def size_list():
    return list(range(1, 16)) + [128]


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))


@cocotb.test()
@cocotb.parametrize(
    ("payload_lengths", [size_list]),
    ("payload_data", [incrementing_payload]),
)
async def run_test_tx(dut, payload_lengths=None, payload_data=None):

    tb = TB(dut)

    await tb.reset()

    for test_data in [payload_data(x) for x in payload_lengths()]:

        pkt = XfcpFrame()
        pkt.path = [1, 2, 3]
        pkt.rpath = [4]
        pkt.ptype = 1
        pkt.payload = test_data

        await tb.dsp_source.write(pkt.build())

        rx_data = bytearray()
        while True:
            b = await tb.uart_sink.read(1)
            if b[0] == 0:
                break
            rx_data.extend(b)

        rx_pkt = XfcpFrame.parse_cobs(rx_data)

        print(rx_pkt)
        assert rx_pkt == pkt

        assert tb.uart_sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("payload_lengths", [size_list]),
    ("payload_data", [incrementing_payload]),
)
async def run_test_rx(dut, payload_lengths=None, payload_data=None):

    tb = TB(dut)

    await tb.reset()

    for test_data in [payload_data(x) for x in payload_lengths()]:

        pkt = XfcpFrame()
        pkt.path = [1, 2, 3]
        pkt.rpath = [4]
        pkt.ptype = 1
        pkt.payload = test_data

        await tb.uart_source.write(pkt.build_cobs())

        rx_frame = await tb.dsp_sink.recv()
        rx_pkt = XfcpFrame.parse(rx_frame.tdata)

        print(rx_pkt)
        assert rx_pkt == pkt

        assert tb.dsp_sink.empty()

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


def test_taxi_xfcp_if_uart(request):

    dut = "taxi_xfcp_if_uart"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.f"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['PRE_W'] = 16
    parameters['TX_FIFO_DEPTH'] = 512
    parameters['RX_FIFO_DEPTH'] = 512

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
