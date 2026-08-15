#!/usr/bin/env python3
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2020-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import itertools
import logging
import os
import sys

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.axi import AxiStreamBus, AxiStreamSink
from cocotbext.axi.stream import define_stream

try:
    from dma_psdp_ram import PsdpRamRead, PsdpRamReadBus
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        from dma_psdp_ram import PsdpRamRead, PsdpRamReadBus
    finally:
        del sys.path[0]

DescBus, DescTransaction, DescSource, DescSink, DescMonitor = define_stream("Desc",
    signals=["req_src_addr", "req_dst_addr", "req_len", "req_tag", "req_valid", "req_ready"],
    optional_signals=["req_id", "req_dest", "req_user"]
)

DescStatusBus, DescStatusTransaction, DescStatusSource, DescStatusSink, DescStatusMonitor = define_stream("DescStatus",
    signals=["sts_tag", "sts_error", "sts_valid"],
    optional_signals=["sts_len", "sts_id", "sts_dest", "sts_user"]
)


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        # read interface
        self.read_desc_source = DescSource(DescBus.from_entity(dut.dma_desc), dut.clk, dut.rst)
        self.read_desc_status_sink = DescStatusSink(DescStatusBus.from_entity(dut.dma_desc), dut.clk, dut.rst)
        self.read_data_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis_rd_data), dut.clk, dut.rst)

        # DMA RAM
        self.dma_ram = PsdpRamRead(PsdpRamReadBus.from_entity(dut.dma_ram), dut.clk, dut.rst, size=2**16)

        dut.enable.setimmediatevalue(0)

    def set_idle_generator(self, generator=None):
        if generator:
            self.read_desc_source.set_pause_generator(generator())
            # self.dma_ram.r_channel.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.read_data_sink.set_pause_generator(generator())
            # self.dma_ram.ar_channel.set_pause_generator(generator())

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
async def run_test_read(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    byte_lanes = tb.dma_ram.byte_lanes
    step_size = tb.read_data_sink.byte_lanes
    tag_count = 2**len(tb.read_desc_source.bus.req_tag)

    cur_tag = 1

    await tb.cycle_reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    dut.enable.value = 1

    for length in list(range(1, byte_lanes*3+1))+[128]:
        for offset in range(0, byte_lanes*2, step_size):
            tb.log.info("length %d, offset %d", length, offset)
            ram_addr = offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])

            tb.dma_ram.write(ram_addr-128, b'\xaa'*(len(test_data)+256))
            tb.dma_ram.write(ram_addr, test_data)

            tb.log.debug("%s", tb.dma_ram.hexdump_str((ram_addr & ~0xf)-16, (((ram_addr & 0xf)+length-1) & ~0xf)+48))

            desc = DescTransaction(req_src_addr=ram_addr, req_len=len(test_data), req_tag=cur_tag, req_id=cur_tag)
            await tb.read_desc_source.send(desc)

            status = await tb.read_desc_status_sink.recv()

            read_data = await tb.read_data_sink.recv()

            tb.log.info("status: %s", status)
            tb.log.info("read_data: %s", read_data)

            assert int(status.sts_tag) == cur_tag
            assert read_data.tdata == test_data
            assert read_data.tid == cur_tag

            cur_tag = (cur_tag + 1) % tag_count

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


@pytest.mark.parametrize(("ram_data_w", "axis_data_w"), [
    (128, 64),
    (128, 128),
    (256, 64),
    (256, 128),
])
def test_taxi_dma_client_axis_source(request, ram_data_w, axis_data_w):
    dut = "taxi_dma_client_axis_source"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(rtl_dir, "taxi_dma_desc_if.sv"),
        os.path.join(rtl_dir, "taxi_dma_ram_if.sv"),
        os.path.join(taxi_src_dir, "axis", "rtl", "taxi_axis_if.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['RAM_DATA_W'] = ram_data_w
    parameters['RAM_ADDR_W'] = 16
    parameters['RAM_SEGS'] = max(2, parameters['RAM_DATA_W'] // 128)
    parameters['AXIS_DATA_W'] = axis_data_w
    parameters['AXIS_KEEP_EN'] = int(parameters['AXIS_DATA_W'] > 8)
    parameters['AXIS_KEEP_W'] = parameters['AXIS_DATA_W'] // 8
    parameters['AXIS_LAST_EN'] = 1
    parameters['AXIS_ID_EN'] = 1
    parameters['AXIS_ID_W'] = 8
    parameters['AXIS_DEST_EN'] = 1
    parameters['AXIS_DEST_W'] = 8
    parameters['AXIS_USER_EN'] = 1
    parameters['AXIS_USER_W'] = 1
    parameters['LEN_W'] = 20
    parameters['TAG_W'] = 8

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
