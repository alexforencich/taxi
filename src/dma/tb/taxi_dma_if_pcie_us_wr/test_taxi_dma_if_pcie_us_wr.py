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
from cocotb.triggers import RisingEdge, FallingEdge, Timer

from cocotbext.axi import AxiStreamBus
from cocotbext.pcie.core import RootComplex
from cocotbext.pcie.xilinx.us import UltraScalePlusPcieDevice
from cocotbext.axi.stream import define_stream
from cocotbext.axi.utils import hexdump_str

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

        # PCIe
        self.rc = RootComplex()

        self.dev = UltraScalePlusPcieDevice(
            # configuration options
            pcie_generation=3,
            # pcie_link_width=2,
            # user_clk_frequency=250e6,
            alignment="dword",
            cq_straddle=False,
            cc_straddle=False,
            rq_straddle=False,
            rc_straddle=False,
            rc_4tlp_straddle=False,
            pf_count=1,
            max_payload_size=1024,
            enable_client_tag=True,
            enable_extended_tag=True,
            enable_parity=False,
            enable_rx_msg_interface=False,
            enable_sriov=False,
            enable_extended_configuration=False,

            pf0_msi_enable=True,
            pf0_msi_count=32,
            pf1_msi_enable=False,
            pf1_msi_count=1,
            pf2_msi_enable=False,
            pf2_msi_count=1,
            pf3_msi_enable=False,
            pf3_msi_count=1,
            pf0_msix_enable=False,
            pf0_msix_table_size=0,
            pf0_msix_table_bir=0,
            pf0_msix_table_offset=0x00000000,
            pf0_msix_pba_bir=0,
            pf0_msix_pba_offset=0x00000000,
            pf1_msix_enable=False,
            pf1_msix_table_size=0,
            pf1_msix_table_bir=0,
            pf1_msix_table_offset=0x00000000,
            pf1_msix_pba_bir=0,
            pf1_msix_pba_offset=0x00000000,
            pf2_msix_enable=False,
            pf2_msix_table_size=0,
            pf2_msix_table_bir=0,
            pf2_msix_table_offset=0x00000000,
            pf2_msix_pba_bir=0,
            pf2_msix_pba_offset=0x00000000,
            pf3_msix_enable=False,
            pf3_msix_table_size=0,
            pf3_msix_table_bir=0,
            pf3_msix_table_offset=0x00000000,
            pf3_msix_pba_bir=0,
            pf3_msix_pba_offset=0x00000000,

            # signals
            user_clk=dut.clk,
            user_reset=dut.rst,

            rq_bus=AxiStreamBus.from_entity(dut.m_axis_rq),
            pcie_rq_seq_num0=dut.s_axis_rq_seq_num_0,
            pcie_rq_seq_num_vld0=dut.s_axis_rq_seq_num_valid_0,
            pcie_rq_seq_num1=dut.s_axis_rq_seq_num_1,
            pcie_rq_seq_num_vld1=dut.s_axis_rq_seq_num_valid_1,

            cfg_max_payload=dut.max_payload_size,

            cfg_fc_sel=0b100,
            cfg_fc_ph=dut.pcie_tx_fc_ph_av,
            cfg_fc_pd=dut.pcie_tx_fc_pd_av,
        )

        self.dev.log.setLevel(logging.DEBUG)

        self.rc.make_port().connect(self.dev)

        # tie off RQ input
        dut.s_axis_rq.tdata.setimmediatevalue(0)
        dut.s_axis_rq.tkeep.setimmediatevalue(0)
        dut.s_axis_rq.tlast.setimmediatevalue(0)
        dut.s_axis_rq.tuser.setimmediatevalue(0)
        dut.s_axis_rq.tvalid.setimmediatevalue(0)

        # DMA RAM
        self.dma_ram = PsdpRamRead(PsdpRamReadBus.from_entity(dut.dma_ram), dut.clk, dut.rst, size=2**16)

        # Control
        self.write_desc_source = DescSource(DescBus.from_entity(dut.wr_desc), dut.clk, dut.rst)
        self.write_desc_status_sink = DescStatusSink(DescStatusBus.from_entity(dut.wr_desc), dut.clk, dut.rst)

        dut.requester_id.setimmediatevalue(0)
        dut.requester_id_en.setimmediatevalue(0)

        dut.enable.setimmediatevalue(0)

    def set_idle_generator(self, generator=None):
        pass
    #     if generator:
    #         self.dma_ram.r_channel.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.dev.rq_sink.set_pause_generator(generator())
            self.dma_ram.set_pause_generator(generator())


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


@cocotb.test()
@cocotb.parametrize(
    (("idle_inserter", "backpressure_inserter"), [(None, None), (cycle_pause, cycle_pause)]),
)
async def run_test_write(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    if os.getenv("PCIE_OFFSET") is None:
        pcie_offsets = list(range(4))+list(range(4096-4, 4096))
    else:
        pcie_offsets = [int(os.getenv("PCIE_OFFSET"))]

    byte_lanes = tb.dma_ram.byte_lanes
    tag_count = 2**len(tb.write_desc_source.bus.req_tag)

    cur_tag = 1

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await FallingEdge(dut.rst)
    await Timer(100, 'ns')

    await tb.rc.enumerate()

    dev = tb.rc.find_device(tb.dev.functions[0].pcie_id)
    await dev.enable_device()
    await dev.set_master()

    mem = tb.rc.mem_pool.alloc_region(16*1024*1024)
    mem_base = mem.get_absolute_address(0)

    tb.dut.enable.value = 1

    for length in list(range(0, byte_lanes+3))+list(range(128-4, 128+4))+[1024]:
        for pcie_offset in pcie_offsets:
            for ram_offset in range(byte_lanes+1):
                tb.log.info("length %d, pcie_offset %d, ram_offset %d", length, pcie_offset, ram_offset)
                pcie_addr = pcie_offset+0x1000
                ram_addr = ram_offset+0x1000
                test_data = bytearray([x % 256 for x in range(length)])

                tb.dma_ram.write(ram_addr & 0xffff80, b'\x55'*(len(test_data)+256))
                mem[pcie_addr-128:pcie_addr-128+len(test_data)+256] = b'\xaa'*(len(test_data)+256)
                tb.dma_ram.write(ram_addr, test_data)

                tb.log.debug("%s", tb.dma_ram.hexdump_str((ram_addr & ~0xf)-16, (((ram_addr & 0xf)+length-1) & ~0xf)+48, prefix="RAM "))

                desc = DescTransaction(req_dst_addr=mem_base+pcie_addr, req_src_addr=ram_addr, req_src_sel=0, req_len=len(test_data), req_tag=cur_tag)
                await tb.write_desc_source.send(desc)

                status = await tb.write_desc_status_sink.recv()
                await Timer(100 + (length // byte_lanes), 'ns')

                tb.log.info("status: %s", status)

                assert int(status.sts_tag) == cur_tag
                assert int(status.sts_error) == 0

                tb.log.debug("%s", hexdump_str(mem, (pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48, prefix="PCIe "))

                assert mem[pcie_addr-1:pcie_addr+len(test_data)+1] == b'\xaa'+test_data+b'\xaa'

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


@pytest.mark.parametrize("pcie_offset", list(range(4))+list(range(4096-4, 4096)))
@pytest.mark.parametrize("axis_pcie_data_w", [64, 128, 256, 512])
def test_taxi_dma_if_pcie_us_wr(request, axis_pcie_data_w, pcie_offset):
    dut = "taxi_dma_if_pcie_us_wr"
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

    parameters['AXIS_PCIE_DATA_W'] = axis_pcie_data_w
    parameters['AXIS_PCIE_KEEP_W'] = parameters['AXIS_PCIE_DATA_W'] // 32
    parameters['AXIS_PCIE_RQ_USER_W'] = 62 if parameters['AXIS_PCIE_DATA_W'] < 512 else 137
    parameters['RQ_SEQ_NUM_W'] = 4 if parameters['AXIS_PCIE_RQ_USER_W'] == 60 else 6
    parameters['RQ_SEQ_NUM_EN'] = 1
    parameters['RAM_SEL_W'] = 2
    parameters['RAM_ADDR_W'] = 16
    parameters['RAM_SEGS'] = max(2, parameters['AXIS_PCIE_DATA_W']*2 // 128)
    parameters['PCIE_TAG_CNT'] = 64 if parameters['AXIS_PCIE_RQ_USER_W'] == 60 else 256
    parameters['IMM_EN'] = 1
    parameters['IMM_W'] = parameters['AXIS_PCIE_DATA_W']
    parameters['LEN_W'] = 20
    parameters['TAG_W'] = 8
    parameters['OP_TBL_SIZE'] = 2**(parameters['RQ_SEQ_NUM_W']-1)
    parameters['TX_LIMIT'] = 2**(parameters['RQ_SEQ_NUM_W']-1)
    parameters['TX_FC_EN'] = 1

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}

    extra_env['PCIE_OFFSET'] = str(pcie_offset)

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
