#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2023-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import logging
import os
import struct

from scapy.layers.l2 import Ether

import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.utils import get_sim_time

from cocotbext.axi.stream import define_stream


McfBus, McfTransaction, McfSource, McfSink, McfMonitor = define_stream("Mcf",
    signals=["valid", "eth_dst", "eth_src", "eth_type", "opcode", "params"],
    optional_signals=["ready", "id", "dest", "user"]
)


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 6.4, units="ns").start())

        self.mcf_sink = McfSink(McfBus.from_prefix(dut, "mcf"), dut.clk, dut.rst)

        dut.tx_lfc_req.setimmediatevalue(0)
        dut.tx_lfc_resend.setimmediatevalue(0)

        dut.tx_pfc_req.setimmediatevalue(0)
        dut.tx_pfc_resend.setimmediatevalue(0)

        dut.cfg_tx_lfc_eth_dst.setimmediatevalue(0)
        dut.cfg_tx_lfc_eth_src.setimmediatevalue(0)
        dut.cfg_tx_lfc_eth_type.setimmediatevalue(0)
        dut.cfg_tx_lfc_opcode.setimmediatevalue(0)
        dut.cfg_tx_lfc_en.setimmediatevalue(0)
        dut.cfg_tx_lfc_quanta.setimmediatevalue(0)
        dut.cfg_tx_lfc_refresh.setimmediatevalue(0)
        dut.cfg_tx_pfc_eth_dst.setimmediatevalue(0)
        dut.cfg_tx_pfc_eth_src.setimmediatevalue(0)
        dut.cfg_tx_pfc_eth_type.setimmediatevalue(0)
        dut.cfg_tx_pfc_opcode.setimmediatevalue(0)
        dut.cfg_tx_pfc_en.setimmediatevalue(0)
        dut.cfg_tx_pfc_quanta.setimmediatevalue([0]*8)
        dut.cfg_tx_pfc_refresh.setimmediatevalue([0]*8)
        dut.cfg_quanta_step.setimmediatevalue(256)
        dut.cfg_quanta_clk_en.setimmediatevalue(1)

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

    async def recv_mcf(self):
        rx_frame = await self.mcf_sink.recv()

        data = bytearray()
        data.extend(int(rx_frame.eth_dst).to_bytes(6, 'big'))
        data.extend(int(rx_frame.eth_src).to_bytes(6, 'big'))
        data.extend(int(rx_frame.eth_type).to_bytes(2, 'big'))
        data.extend(int(rx_frame.opcode).to_bytes(2, 'big'))
        data.extend(int(rx_frame.params).to_bytes(44, 'little'))

        return Ether(data)


def check_lfc_frame(tb, pkt, quanta):
    tb.log.info("Pause frame: %s", repr(pkt))

    op, q = struct.unpack_from('!HH', bytes(pkt[Ether].payload), 0)
    tb.log.info("opcode: 0x%x", op)
    tb.log.info("quanta: %d", q)

    assert pkt[Ether].dst == '01:80:c2:00:00:01'
    assert pkt[Ether].src == '5a:51:52:53:54:55'
    assert pkt[Ether].type == 0x8808
    assert op == 0x0001
    assert q == quanta


@cocotb.test()
async def run_test_lfc(dut):

    tb = TB(dut)

    await tb.reset()

    dut.tx_lfc_req.value = 0
    dut.tx_lfc_resend.value = 0

    dut.cfg_tx_lfc_eth_dst.value = 0x0180C2000001
    dut.cfg_tx_lfc_eth_src.value = 0x5A5152535455
    dut.cfg_tx_lfc_eth_type.value = 0x8808
    dut.cfg_tx_lfc_opcode.value = 0x0001
    dut.cfg_tx_lfc_en.value = 1
    dut.cfg_tx_lfc_quanta.value = 0xFFFF
    dut.cfg_tx_lfc_refresh.value = 0x7F00
    dut.cfg_quanta_step.value = int(10000*256 / (512*156.25))
    dut.cfg_quanta_clk_en.value = 1

    tb.log.info("Test pause")

    dut.cfg_tx_lfc_refresh.value = 100

    dut.tx_lfc_req.value = 1
    start_time = None

    for k in range(4):
        rx_pkt = await tb.recv_mcf()
        stop_time = get_sim_time('sec')

        check_lfc_frame(tb, rx_pkt, 0xFFFF)

        if start_time:
            refresh_time = stop_time-start_time
            refresh_quanta = refresh_time / (512 * 1/10e9)

            tb.log.info("refresh time   : %g s", refresh_time)
            tb.log.info("refresh quanta : %f", refresh_quanta)

            assert round(refresh_quanta/4) == 100//4

        start_time = get_sim_time('sec')

    dut.tx_lfc_req.value = 0

    rx_pkt = await tb.recv_mcf()

    check_lfc_frame(tb, rx_pkt, 0x0)

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


def check_pfc_frame(tb, pkt, enable_mask, quanta_mask, quanta):
    tb.log.info("PFC frame: %s", repr(pkt))

    op, enable, *q = struct.unpack_from('!HH8H', bytes(pkt[Ether].payload), 0)
    tb.log.info("opcode: 0x%x", op)
    tb.log.info("enable: 0x%x", enable)
    tb.log.info("quanta: %r", q)

    assert pkt[Ether].dst == '01:80:c2:00:00:01'
    assert pkt[Ether].src == '5a:51:52:53:54:55'
    assert pkt[Ether].type == 0x8808
    assert op == 0x0101
    assert enable == enable_mask
    for k in range(8):
        if quanta_mask & (1 << k):
            assert q[k] == quanta
        else:
            assert q[k] == 0


@cocotb.test()
async def run_test_pfc(dut):

    tb = TB(dut)

    await tb.reset()

    dut.tx_pfc_req.value = 0x00
    dut.tx_pfc_resend.value = 0

    dut.cfg_tx_pfc_eth_dst.value = 0x0180C2000001
    dut.cfg_tx_pfc_eth_src.value = 0x5A5152535455
    dut.cfg_tx_pfc_eth_type.value = 0x8808
    dut.cfg_tx_pfc_opcode.value = 0x0101
    dut.cfg_tx_pfc_en.value = 1
    dut.cfg_tx_pfc_quanta.value = [0xFFFF]*8
    dut.cfg_tx_pfc_refresh.value = [0x7F00]*8
    dut.cfg_quanta_step.value = int(10000*256 / (512*156.25))
    dut.cfg_quanta_clk_en.value = 1

    tb.log.info("Test pause")

    dut.cfg_tx_pfc_refresh.value = [0x0064]*8

    dut.tx_pfc_req.value = 0x01
    start_time = None

    for k in range(4):
        rx_pkt = await tb.recv_mcf()
        stop_time = get_sim_time('sec')

        check_pfc_frame(tb, rx_pkt, 0x01, 0x01, 0xFFFF)

        if start_time:
            refresh_time = stop_time-start_time
            refresh_quanta = refresh_time / (512 * 1/10e9)

            tb.log.info("refresh time   : %g s", refresh_time)
            tb.log.info("refresh quanta : %f", refresh_quanta)

            assert round(refresh_quanta/4) == 100//4

        start_time = get_sim_time('sec')

    dut.tx_pfc_req.value = 0x00

    rx_pkt = await tb.recv_mcf()

    check_pfc_frame(tb, rx_pkt, 0x01, 0x00, 0xFFFF)

    tb.log.info("Test all channels")

    dut.cfg_tx_pfc_refresh.value = [0x0064]*8

    for ch in range(8):

        dut.tx_pfc_req.value = 0xFF >> (7-ch)
        start_time = None

        for k in range(3):
            rx_pkt = await tb.recv_mcf()
            stop_time = get_sim_time('sec')

            check_pfc_frame(tb, rx_pkt, 0xFF >> (7-ch), 0xFF >> (7-ch), 0xFFFF)

            if start_time:
                refresh_time = stop_time-start_time
                refresh_quanta = refresh_time / (512 * 1/10e9)

                tb.log.info("refresh time   : %g s", refresh_time)
                tb.log.info("refresh quanta : %f", refresh_quanta)

                assert round(refresh_quanta/4) == 100//4

            start_time = get_sim_time('sec')

    dut.tx_pfc_req.value = 0x00

    rx_pkt = await tb.recv_mcf()

    check_pfc_frame(tb, rx_pkt, 0xFF, 0x00, 0xFFFF)

    tb.log.info("Test isolation")

    dut.cfg_tx_pfc_refresh.value = [0x0064]*8

    dut.tx_pfc_req.value = 0x01
    start_time = None

    rx_pkt = await tb.recv_mcf()
    stop_time = get_sim_time('sec')

    check_pfc_frame(tb, rx_pkt, 0x01, 0x01, 0xFFFF)

    dut.tx_pfc_req.value = 0x03
    start_time = None

    rx_pkt = await tb.recv_mcf()
    stop_time = get_sim_time('sec')

    check_pfc_frame(tb, rx_pkt, 0x03, 0x03, 0xFFFF)

    dut.tx_pfc_req.value = 0x01
    start_time = None

    rx_pkt = await tb.recv_mcf()
    stop_time = get_sim_time('sec')

    check_pfc_frame(tb, rx_pkt, 0x03, 0x01, 0xFFFF)

    start_time = get_sim_time('sec')

    for k in range(4):
        rx_pkt = await tb.recv_mcf()
        stop_time = get_sim_time('sec')

        check_pfc_frame(tb, rx_pkt, 0x01, 0x01, 0xFFFF)

        if start_time:
            refresh_time = stop_time-start_time
            refresh_quanta = refresh_time / (512 * 1/10e9)

            tb.log.info("refresh time   : %g s", refresh_time)
            tb.log.info("refresh quanta : %f", refresh_quanta)

            assert round(refresh_quanta/4) == 100//4

        start_time = get_sim_time('sec')

    dut.tx_pfc_req.value = 0x00

    rx_pkt = await tb.recv_mcf()

    check_pfc_frame(tb, rx_pkt, 0x01, 0x00, 0xFFFF)

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


def test_taxi_mac_pause_ctrl_tx(request):
    dut = "taxi_mac_pause_ctrl_tx"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['MCF_PARAMS_SIZE'] = 18
    parameters['PFC_EN'] = "1'b1"

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
