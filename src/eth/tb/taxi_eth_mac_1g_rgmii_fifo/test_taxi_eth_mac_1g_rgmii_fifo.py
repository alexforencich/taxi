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

from cocotbext.eth import GmiiFrame, RgmiiPhy
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink


class TB:
    def __init__(self, dut, speed=1000e6):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.logic_clk, 8, units="ns").start())
        cocotb.start_soon(Clock(dut.stat_clk, 8, units="ns").start())

        self.rgmii_phy = RgmiiPhy(dut.rgmii_txd, dut.rgmii_tx_ctl, dut.rgmii_tx_clk,
            dut.rgmii_rxd, dut.rgmii_rx_ctl, dut.rgmii_rx_clk, speed=speed)

        self.axis_source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis_tx), dut.logic_clk, dut.logic_rst)
        self.tx_cpl_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis_tx_cpl), dut.logic_clk, dut.logic_rst)
        self.axis_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis_rx), dut.logic_clk, dut.logic_rst)

        self.stat_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis_stat), dut.stat_clk, dut.stat_rst)

        dut.cfg_tx_pad_en.setimmediatevalue(0)
        dut.cfg_tx_min_pkt_len.setimmediatevalue(0)
        dut.cfg_tx_max_pkt_len.setimmediatevalue(0)
        dut.cfg_tx_ifg.setimmediatevalue(0)
        dut.cfg_tx_enable.setimmediatevalue(0)
        dut.cfg_rx_max_pkt_len.setimmediatevalue(0)
        dut.cfg_rx_enable.setimmediatevalue(0)

        dut.gtx_clk.setimmediatevalue(0)
        dut.gtx_clk90.setimmediatevalue(0)

        cocotb.start_soon(self._run_gtx_clk())

    async def reset(self):
        self.dut.gtx_rst.setimmediatevalue(0)
        self.dut.logic_rst.setimmediatevalue(0)
        self.dut.stat_rst.setimmediatevalue(0)
        await RisingEdge(self.dut.gtx_clk)
        await RisingEdge(self.dut.gtx_clk)
        self.dut.gtx_rst.value = 1
        self.dut.logic_rst.value = 1
        self.dut.stat_rst.value = 1
        await RisingEdge(self.dut.gtx_clk)
        await RisingEdge(self.dut.gtx_clk)
        self.dut.gtx_rst.value = 0
        self.dut.logic_rst.value = 0
        self.dut.stat_rst.value = 0
        await RisingEdge(self.dut.gtx_clk)
        await RisingEdge(self.dut.gtx_clk)

    async def _run_gtx_clk(self):
        t = Timer(2, 'ns')
        while True:
            self.dut.gtx_clk.value = 1
            await t
            self.dut.gtx_clk90.value = 1
            await t
            self.dut.gtx_clk.value = 0
            await t
            self.dut.gtx_clk90.value = 0
            await t


def size_list():
    return list(range(60, 128)) + [512, 1514] + [60]*10


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))


@cocotb.test()
@cocotb.parametrize(
    ("payload_lengths", [size_list]),
    ("payload_data", [incrementing_payload]),
    ("ifg", [12]),
    ("speed", [1000e6, 100e6, 10e6]),
)
async def run_test_rx(dut, payload_lengths=None, payload_data=None, ifg=12, speed=1000e6):

    tb = TB(dut, speed)

    tb.rgmii_phy.rx.ifg = ifg
    tb.dut.cfg_tx_ifg.value = ifg
    tb.dut.cfg_rx_max_pkt_len.value = 9218-1
    tb.dut.cfg_rx_enable.value = 1

    await tb.reset()

    for k in range(100):
        await RisingEdge(dut.rgmii_rx_clk)

    if speed == 10e6:
        assert int(dut.link_speed.value) == 0
    elif speed == 100e6:
        assert int(dut.link_speed.value) == 1
    else:
        assert int(dut.link_speed.value) == 2

    test_frames = [payload_data(x) for x in payload_lengths()]

    for test_data in test_frames:
        test_frame = GmiiFrame.from_payload(test_data)
        await tb.rgmii_phy.rx.send(test_frame)

    for test_data in test_frames:
        rx_frame = await tb.axis_sink.recv()

        assert rx_frame.tdata == test_data
        assert rx_frame.tuser == 0

    assert tb.axis_sink.empty()

    await RisingEdge(dut.logic_clk)
    await RisingEdge(dut.logic_clk)


@cocotb.test()
@cocotb.parametrize(
    ("payload_lengths", [size_list]),
    ("payload_data", [incrementing_payload]),
    ("ifg", [12]),
    ("speed", [1000e6, 100e6, 10e6]),
)
async def run_test_tx(dut, payload_lengths=None, payload_data=None, ifg=12, speed=1000e6):

    tb = TB(dut, speed)

    tb.rgmii_phy.rx.ifg = ifg
    tb.dut.cfg_tx_pad_en.value = 1
    tb.dut.cfg_tx_min_pkt_len.value = 60-1
    tb.dut.cfg_tx_max_pkt_len.value = 9218-1
    tb.dut.cfg_tx_ifg.value = ifg
    tb.dut.cfg_tx_enable.value = 1

    await tb.reset()

    for k in range(100):
        await RisingEdge(dut.rgmii_rx_clk)

    if speed == 10e6:
        assert int(dut.link_speed.value) == 0
    elif speed == 100e6:
        assert int(dut.link_speed.value) == 1
    else:
        assert int(dut.link_speed.value) == 2

    test_frames = [payload_data(x) for x in payload_lengths()]

    for test_data in test_frames:
        await tb.axis_source.send(test_data)

    for test_data in test_frames:
        rx_frame = await tb.rgmii_phy.tx.recv()

        assert rx_frame.get_payload() == test_data
        assert rx_frame.check_fcs()
        assert rx_frame.error is None

    assert tb.rgmii_phy.tx.empty()

    await RisingEdge(dut.logic_clk)
    await RisingEdge(dut.logic_clk)


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


def test_taxi_eth_mac_1g_rgmii_fifo(request):
    dut = "taxi_eth_mac_1g_rgmii_fifo"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.f"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['SIM'] = 1
    parameters['VENDOR'] = "\"XILINX\""
    parameters['FAMILY'] = "\"virtex7\""
    parameters['USE_CLK90'] = 1
    parameters['AXIS_DATA_W'] = 8
    parameters['TX_TAG_W'] = 16
    parameters['STAT_EN'] = 1
    parameters['STAT_TX_LEVEL'] = 2
    parameters['STAT_RX_LEVEL'] = parameters['STAT_TX_LEVEL']
    parameters['STAT_ID_BASE'] = 0
    parameters['STAT_UPDATE_PERIOD'] = 1024
    parameters['STAT_STR_EN'] = 1
    parameters['STAT_PREFIX_STR'] = "\"MAC\""
    parameters['TX_FIFO_DEPTH'] = 16384
    parameters['TX_FIFO_RAM_PIPELINE'] = 1
    parameters['TX_FRAME_FIFO'] = 1
    parameters['TX_DROP_OVERSIZE_FRAME'] = parameters['TX_FRAME_FIFO']
    parameters['TX_DROP_BAD_FRAME'] = parameters['TX_DROP_OVERSIZE_FRAME']
    parameters['TX_DROP_WHEN_FULL'] = 0
    parameters['TX_CPL_FIFO_DEPTH'] = 64
    parameters['RX_FIFO_DEPTH'] = 16384
    parameters['RX_FIFO_RAM_PIPELINE'] = 1
    parameters['RX_FRAME_FIFO'] = 1
    parameters['RX_DROP_OVERSIZE_FRAME'] = parameters['RX_FRAME_FIFO']
    parameters['RX_DROP_BAD_FRAME'] = parameters['RX_DROP_OVERSIZE_FRAME']
    parameters['RX_DROP_WHEN_FULL'] = parameters['RX_DROP_OVERSIZE_FRAME']

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
