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

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.axi import AxiBus, AxiRam
from cocotbext.axi.stream import define_stream

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

        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

        # control interface
        self.desc_source = DescSource(DescBus.from_entity(dut.dma_desc), dut.clk, dut.rst)
        self.desc_status_sink = DescStatusSink(DescStatusBus.from_entity(dut.dma_desc), dut.clk, dut.rst)

        # AXI interface
        self.axi_ram = AxiRam(AxiBus.from_entity(dut.m_axi), dut.clk, dut.rst, size=2**16)

        dut.enable.setimmediatevalue(0)

    def set_idle_generator(self, generator=None):
        if generator:
            self.desc_source.set_pause_generator(generator())
            self.axi_ram.write_if.b_channel.set_pause_generator(generator())
            self.axi_ram.read_if.r_channel.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.axi_ram.write_if.aw_channel.set_pause_generator(generator())
            self.axi_ram.write_if.w_channel.set_pause_generator(generator())
            self.axi_ram.read_if.ar_channel.set_pause_generator(generator())

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
async def run_test(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    byte_lanes = tb.axi_ram.write_if.byte_lanes
    step_size = 1 if int(dut.UNALIGNED_EN.value) else byte_lanes
    tag_count = 2**len(tb.desc_source.bus.req_tag)

    cur_tag = 1

    await tb.cycle_reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    dut.enable.value = 1

    for length in list(range(1, byte_lanes*4+1))+[128]:
        for read_offset in list(range(8, 8+byte_lanes*2, step_size))+list(range(4096-byte_lanes*2, 4096, step_size)):
            for write_offset in list(range(8, 8+byte_lanes*2, step_size))+list(range(4096-byte_lanes*2, 4096, step_size)):
                tb.log.info("length %d, read_offset %d, write_offset %d", length, read_offset, write_offset)
                read_addr = read_offset+0x1000
                write_addr = 0x00008000+write_offset+0x1000
                test_data = bytearray([x % 256 for x in range(length)])

                tb.axi_ram.write(read_addr, test_data)
                tb.axi_ram.write(write_addr & 0xffff80, b'\xaa'*(len(test_data)+256))

                desc = DescTransaction(req_src_addr=read_addr, req_dst_addr=write_addr, req_len=len(test_data), req_tag=cur_tag)
                await tb.desc_source.send(desc)

                status = await tb.desc_status_sink.recv()

                tb.log.info("status: %s", status)
                assert int(status.sts_tag) == cur_tag
                assert int(status.sts_error) == 0

                tb.log.debug("%s", tb.axi_ram.hexdump_str((write_addr & ~0xf)-16, (((write_addr & 0xf)+length-1) & ~0xf)+48))

                assert tb.axi_ram.read(write_addr-8, len(test_data)+16) == b'\xaa'*8+test_data+b'\xaa'*8

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


@pytest.mark.parametrize("unaligned", [0, 1])
@pytest.mark.parametrize("axi_data_w", [8, 16, 32])
def test_taxi_axi_cdma(request, axi_data_w, unaligned):
    dut = "taxi_axi_cdma"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(rtl_dir, "taxi_dma_desc_if.sv"),
        os.path.join(taxi_src_dir, "axi", "rtl", "taxi_axi_if.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['AXI_DATA_W'] = axi_data_w
    parameters['AXI_ADDR_W'] = 16
    parameters['AXI_STRB_W'] = parameters['AXI_DATA_W'] // 8
    parameters['AXI_ID_W'] = 8
    parameters['AXI_MAX_BURST_LEN'] = 16
    parameters['LEN_W'] = 20
    parameters['TAG_W'] = 8
    parameters['UNALIGNED_EN'] = unaligned

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
