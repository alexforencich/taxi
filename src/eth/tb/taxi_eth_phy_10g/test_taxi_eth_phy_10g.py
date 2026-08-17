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
import sys

import cocotb_test.simulator

import pytest
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.eth import XgmiiSource, XgmiiSink, XgmiiFrame

try:
    from baser import BaseRSerdesSource, BaseRSerdesSink
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        from baser import BaseRSerdesSource, BaseRSerdesSink
    finally:
        del sys.path[0]


class TB:
    def __init__(self, dut, gbx_cfg=None):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        if len(dut.xgmii_txd) == 64:
            self.clk_period = 6.4
        else:
            self.clk_period = 3.2

        cocotb.start_soon(Clock(dut.tx_clk, self.clk_period, units="ns").start())
        cocotb.start_soon(Clock(dut.rx_clk, self.clk_period, units="ns").start())

        self.xgmii_source = XgmiiSource(dut.xgmii_txd, dut.xgmii_txc, dut.tx_clk, dut.tx_rst)
        dut.xgmii_tx_valid.setimmediatevalue(1)
        self.xgmii_sink = XgmiiSink(dut.xgmii_rxd, dut.xgmii_rxc, dut.rx_clk, dut.rx_rst)

        self.serdes_source = BaseRSerdesSource(
            data=dut.serdes_rx_data,
            data_valid=dut.serdes_rx_data_valid,
            hdr=dut.serdes_rx_hdr,
            hdr_valid=dut.serdes_rx_hdr_valid,
            clock=dut.rx_clk,
            slip=dut.serdes_rx_bitslip,
            gbx_cfg=gbx_cfg
        )
        self.serdes_sink = BaseRSerdesSink(
            data=dut.serdes_tx_data,
            data_valid=dut.serdes_tx_data_valid,
            hdr=dut.serdes_tx_hdr,
            hdr_valid=dut.serdes_tx_hdr_valid,
            gbx_req_sync=dut.serdes_tx_gbx_req_sync,
            gbx_req_stall=dut.serdes_tx_gbx_req_stall,
            gbx_sync=dut.serdes_tx_gbx_sync,
            clock=dut.tx_clk,
            gbx_cfg=gbx_cfg
        )

        dut.cfg_tx_prbs31_enable.setimmediatevalue(0)
        dut.cfg_rx_prbs31_enable.setimmediatevalue(0)

    async def reset(self):
        self.dut.tx_rst.setimmediatevalue(0)
        self.dut.rx_rst.setimmediatevalue(0)
        await RisingEdge(self.dut.tx_clk)
        await RisingEdge(self.dut.tx_clk)
        self.dut.tx_rst.value = 1
        self.dut.rx_rst.value = 1
        await RisingEdge(self.dut.tx_clk)
        await RisingEdge(self.dut.tx_clk)
        self.dut.tx_rst.value = 0
        self.dut.rx_rst.value = 0
        await RisingEdge(self.dut.tx_clk)
        await RisingEdge(self.dut.tx_clk)


def size_list():
    return list(range(60, 128)) + [512, 1514, 9214] + [60]*10


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))


@cocotb.test()
@cocotb.parametrize(
    ("payload_lengths", [size_list]),
    ("payload_data", [incrementing_payload]),
    ("ifg", [12]),
)
async def run_test_rx(dut, payload_lengths=None, payload_data=None, ifg=12):

    tb = TB(dut)

    tb.xgmii_source.ifg = ifg
    tb.serdes_source.ifg = ifg

    await tb.reset()

    tb.log.info("Wait for block lock")
    while not int(dut.rx_block_lock.value):
        await RisingEdge(dut.rx_clk)

    # clear out sink buffer
    tb.xgmii_sink.clear()

    test_frames = [payload_data(x) for x in payload_lengths()]

    for test_data in test_frames:
        test_frame = XgmiiFrame.from_payload(test_data)
        await tb.serdes_source.send(test_frame)

    for test_data in test_frames:
        rx_frame = await tb.xgmii_sink.recv()

        assert rx_frame.get_payload() == test_data
        assert rx_frame.check_fcs()

    assert tb.xgmii_sink.empty()

    await RisingEdge(dut.rx_clk)
    await RisingEdge(dut.rx_clk)


@cocotb.test()
@cocotb.parametrize(
    ("payload_lengths", [size_list]),
    ("payload_data", [incrementing_payload]),
    ("ifg", [12]),
)
async def run_test_tx(dut, payload_lengths=None, payload_data=None, ifg=12):

    tb = TB(dut)

    tb.xgmii_source.ifg = ifg
    tb.serdes_source.ifg = ifg

    await tb.reset()

    test_frames = [payload_data(x) for x in payload_lengths()]

    for test_data in test_frames:
        test_frame = XgmiiFrame.from_payload(test_data)
        await tb.xgmii_source.send(test_frame)

    for test_data in test_frames:
        rx_frame = await tb.serdes_sink.recv()

        assert rx_frame.get_payload() == test_data
        assert rx_frame.check_fcs()

    assert tb.serdes_sink.empty()

    await RisingEdge(dut.tx_clk)
    await RisingEdge(dut.tx_clk)


@cocotb.test()
async def run_test_rx_frame_sync(dut):

    tb = TB(dut)

    await tb.reset()

    tb.log.info("Wait for block lock")
    while not int(dut.rx_block_lock.value):
        await RisingEdge(dut.rx_clk)

    assert int(dut.rx_block_lock.value)

    tb.log.info("Change offset")
    tb.serdes_source.bit_offset = 33

    for k in range(100):
        await RisingEdge(dut.rx_clk)

    tb.log.info("Check for lock lost")
    assert not int(dut.rx_block_lock.value)
    assert int(dut.rx_high_ber.value)

    for k in range(500):
        await RisingEdge(dut.rx_clk)

    tb.log.info("Check for block lock")
    assert int(dut.rx_block_lock.value)

    for k in range(300):
        await RisingEdge(dut.rx_clk)

    tb.log.info("Check for high BER deassert")
    assert not int(dut.rx_high_ber.value)

    await RisingEdge(dut.rx_clk)
    await RisingEdge(dut.rx_clk)


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


@pytest.mark.parametrize("data_w", [32, 64])
def test_taxi_eth_phy_10g(request, data_w):
    dut = "taxi_eth_phy_10g"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.f"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['DATA_W'] = data_w
    parameters['CTRL_W'] = parameters['DATA_W'] // 8
    parameters['HDR_W'] = 2
    parameters['TX_GBX_IF_EN'] = 0
    parameters['RX_GBX_IF_EN'] = parameters['TX_GBX_IF_EN']
    parameters['BIT_REVERSE'] = "1'b0"
    parameters['SCRAMBLER_DISABLE'] = "1'b0"
    parameters['PRBS31_EN'] = "1'b1"
    parameters['TX_SERDES_PIPELINE'] = 2
    parameters['RX_SERDES_PIPELINE'] = 2
    parameters['BITSLIP_HIGH_CYCLES'] = 0
    parameters['BITSLIP_LOW_CYCLES'] = 7
    parameters['COUNT_125US'] = int(1250/6.4)

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}

    extra_env['COCOTB_RESOLVE_X'] = 'RANDOM'

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
