#!/usr/bin/env python3
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2021-2025 FPGA Ninja, LLC

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

from cocotbext.axi import AxiBus, AxiRam
from cocotbext.axi.stream import define_stream

try:
    from dma_psdp_ram import PsdpRam, PsdpRamBus
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        from dma_psdp_ram import PsdpRam, PsdpRamBus
    finally:
        del sys.path[0]

DescBus, DescTransaction, DescSource, DescSink, DescMonitor = define_stream("Desc",
    signals=["req_src_addr", "req_src_sel", "req_src_asid", "req_dst_addr", "req_dst_sel", "req_dst_asid", "req_len", "req_tag", "req_valid", "req_ready"],
    optional_signals=["req_imm", "req_imm_en", "req_id", "req_dest", "req_user"]
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

        # AXI RAM
        self.axi_ram = AxiRam(AxiBus.from_entity(dut.m_axi), dut.clk, dut.rst, size=2**16)

        # DMA RAM
        self.dma_ram = PsdpRam(PsdpRamBus.from_entity(dut.dma_ram), dut.clk, dut.rst, size=2**16)

        # Control
        self.read_desc_source = DescSource(DescBus.from_entity(dut.rd_desc), dut.clk, dut.rst)
        self.read_desc_status_sink = DescStatusSink(DescStatusBus.from_entity(dut.rd_desc), dut.clk, dut.rst)

        self.write_desc_source = DescSource(DescBus.from_entity(dut.wr_desc), dut.clk, dut.rst)
        self.write_desc_status_sink = DescStatusSink(DescStatusBus.from_entity(dut.wr_desc), dut.clk, dut.rst)

        dut.read_enable.setimmediatevalue(0)
        dut.write_enable.setimmediatevalue(0)

    def set_idle_generator(self, generator=None):
        if generator:
            self.axi_ram.write_if.b_channel.set_pause_generator(generator())
            self.axi_ram.read_if.r_channel.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.axi_ram.write_if.aw_channel.set_pause_generator(generator())
            self.axi_ram.write_if.w_channel.set_pause_generator(generator())
            self.axi_ram.read_if.ar_channel.set_pause_generator(generator())
            self.dma_ram.write_if.set_pause_generator(generator())
            self.dma_ram.read_if.set_pause_generator(generator())

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
async def run_test_write(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    axi_byte_lanes = tb.axi_ram.write_if.byte_lanes
    ram_byte_lanes = tb.dma_ram.write_if.byte_lanes
    tag_count = 2**len(tb.write_desc_source.bus.req_tag)

    axi_offsets = list(range(axi_byte_lanes+1))+list(range(4096-axi_byte_lanes, 4096))
    if os.getenv("OFFSET_GROUP") is not None:
        group = int(os.getenv("OFFSET_GROUP"))
        axi_offsets = axi_offsets[group::8]

    cur_tag = 1

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.cycle_reset()

    tb.dut.write_enable.value = 1

    for length in list(range(1, ram_byte_lanes+3))+list(range(128-4, 128+4))+[1024]:
        for axi_offset in axi_offsets:
            for ram_offset in range(1):
                tb.log.info("length %d, axi_offset %d, ram_offset %d", length, axi_offset, ram_offset)
                axi_addr = axi_offset+0x1000
                ram_addr = ram_offset+0x1000
                test_data = bytearray([x % 256 for x in range(length)])

                tb.dma_ram.write(ram_addr & 0xffff80, b'\x55'*(len(test_data)+256))
                tb.axi_ram.write(axi_addr-128, b'\xaa'*(len(test_data)+256))
                tb.dma_ram.write(ram_addr, test_data)

                tb.log.debug("%s", tb.dma_ram.hexdump_str((ram_addr & ~0xf)-16, (((ram_addr & 0xf)+length-1) & ~0xf)+48, prefix="RAM "))

                desc = DescTransaction(req_dst_addr=axi_addr, req_src_addr=ram_addr, req_src_sel=0, req_len=len(test_data), req_tag=cur_tag)
                await tb.write_desc_source.send(desc)

                status = await tb.write_desc_status_sink.recv()

                tb.log.info("status: %s", status)

                assert int(status.sts_tag) == cur_tag
                assert int(status.sts_error) == 0

                tb.log.debug("%s", tb.axi_ram.hexdump_str((axi_addr & ~0xf)-16, (((axi_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

                assert tb.axi_ram.read(axi_addr-1, len(test_data)+2) == b'\xaa'+test_data+b'\xaa'

                cur_tag = (cur_tag + 1) % tag_count

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_read(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    axi_byte_lanes = tb.axi_ram.write_if.byte_lanes
    ram_byte_lanes = tb.dma_ram.write_if.byte_lanes
    tag_count = 2**len(tb.read_desc_source.bus.req_tag)

    axi_offsets = list(range(axi_byte_lanes+1))+list(range(4096-axi_byte_lanes, 4096))
    if os.getenv("OFFSET_GROUP") is not None:
        group = int(os.getenv("OFFSET_GROUP"))
        axi_offsets = axi_offsets[group::8]

    cur_tag = 1

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.cycle_reset()

    tb.dut.read_enable.value = 1

    for length in list(range(1, ram_byte_lanes+3))+list(range(128-4, 128+4))+[1024]:
        for axi_offset in axi_offsets:
            for ram_offset in range(1):
                tb.log.info("length %d, axi_offset %d, ram_offset %d", length, axi_offset, ram_offset)
                axi_addr = axi_offset+0x1000
                ram_addr = ram_offset+0x1000
                test_data = bytearray([x % 256 for x in range(length)])

                tb.axi_ram.write(axi_addr, test_data)

                tb.log.debug("%s", tb.axi_ram.hexdump_str((axi_addr & ~0xf)-16, (((axi_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

                tb.dma_ram.write(ram_addr-256, b'\xaa'*(len(test_data)+512))

                desc = DescTransaction(req_src_addr=axi_addr, req_dst_addr=ram_addr, req_dst_sel=0, req_len=len(test_data), req_tag=cur_tag)
                await tb.read_desc_source.send(desc)

                status = await tb.read_desc_status_sink.recv()

                tb.log.info("status: %s", status)

                assert int(status.sts_tag) == cur_tag
                assert int(status.sts_error) == 0

                tb.log.debug("%s", tb.dma_ram.hexdump_str((ram_addr & ~0xf)-16, (((ram_addr & 0xf)+length-1) & ~0xf)+48, prefix="RAM "))

                assert tb.dma_ram.read(ram_addr-8, len(test_data)+16) == b'\xaa'*8+test_data+b'\xaa'*8

                cur_tag = (cur_tag + 1) % tag_count

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_write_imm(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    axi_byte_lanes = tb.axi_ram.write_if.byte_lanes
    tag_count = 2**len(tb.write_desc_source.bus.req_tag)

    axi_offsets = list(range(axi_byte_lanes+1))+list(range(4096-axi_byte_lanes, 4096))
    if os.getenv("OFFSET_GROUP") is not None:
        group = int(os.getenv("OFFSET_GROUP"))
        axi_offsets = axi_offsets[group::8]

    cur_tag = 1

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.cycle_reset()

    tb.dut.write_enable.value = 1

    for length in list(range(1, len(dut.wr_desc.req_imm) // 8)):
        for axi_offset in axi_offsets:
            tb.log.info("length %d, axi_offset %d", length, axi_offset)
            axi_addr = axi_offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])
            imm = int.from_bytes(test_data, 'little')

            tb.axi_ram.write(axi_addr-128, b'\xaa'*(len(test_data)+256))

            tb.log.debug("Immediate: 0x%x", imm)

            desc = DescTransaction(req_dst_addr=axi_addr, req_src_addr=0, req_src_sel=0, req_imm=imm, req_imm_en=1, req_len=len(test_data), req_tag=cur_tag)
            await tb.write_desc_source.send(desc)

            status = await tb.write_desc_status_sink.recv()

            tb.log.info("status: %s", status)

            assert int(status.sts_tag) == cur_tag
            assert int(status.sts_error) == 0

            tb.log.debug("%s", tb.axi_ram.hexdump_str((axi_addr & ~0xf)-16, (((axi_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

            assert tb.axi_ram.read(axi_addr-1, len(test_data)+2) == b'\xaa'+test_data+b'\xaa'

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


@pytest.mark.parametrize("offset_group", list(range(8)))
@pytest.mark.parametrize("axi_data_w", [64, 128])
def test_taxi_dma_if_axi(request, axi_data_w, offset_group):
    dut = "taxi_dma_if_axi"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.f"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['AXI_DATA_W'] = axi_data_w
    parameters['AXI_ADDR_W'] = 16
    parameters['AXI_STRB_W'] = parameters['AXI_DATA_W'] // 8
    parameters['AXI_ID_W'] = 8
    parameters['AXI_MAX_BURST_LEN'] = 256
    parameters['RAM_SEL_W'] = 2
    parameters['RAM_ADDR_W'] = 16
    parameters['RAM_SEGS'] = 2
    parameters['IMM_EN'] = 1
    parameters['IMM_W'] = parameters['AXI_DATA_W']
    parameters['LEN_W'] = 16
    parameters['TAG_W'] = 8
    parameters['RD_OP_TBL_SIZE'] = 2**parameters['AXI_ID_W']
    parameters['WR_OP_TBL_SIZE'] = 2**parameters['AXI_ID_W']
    parameters['RD_USE_AXI_ID'] = 0
    parameters['WR_USE_AXI_ID'] = 1

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}

    extra_env['OFFSET_GROUP'] = str(offset_group)

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
