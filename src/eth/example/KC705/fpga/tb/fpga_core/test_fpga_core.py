#!/usr/bin/env python
# SPDX-License-Identifier: MIT
"""

Copyright (c) 2020-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import logging
import os

import pytest
import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, Combine

from cocotbext.eth import GmiiFrame, GmiiSource, GmiiSink, GmiiPhy, RgmiiPhy
from cocotbext.uart import UartSource, UartSink


class TB:
    def __init__(self, dut, speed=1000e6):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.phy_sgmii_clk, 8, units="ns").start())

        if hasattr(dut, "baset_mac_gmii"):
            self.baset_phy = GmiiPhy(dut.phy_gmii_txd, dut.phy_gmii_tx_er, dut.phy_gmii_tx_en, dut.phy_gmii_tx_clk, dut.phy_gmii_gtx_clk,
                dut.phy_gmii_rxd, dut.phy_gmii_rx_er, dut.phy_gmii_rx_dv, dut.phy_gmii_rx_clk, speed=speed)
        elif hasattr(dut, "baset_mac_rgmii"):
            self.baset_phy = RgmiiPhy(dut.phy_rgmii_txd, dut.phy_rgmii_tx_ctl, dut.phy_rgmii_tx_clk,
                dut.phy_rgmii_rxd, dut.phy_rgmii_rx_ctl, dut.phy_rgmii_rx_clk, speed=speed)
        elif hasattr(dut, "baset_mac_sgmii"):
            self.sgmii_source = GmiiSource(dut.phy_sgmii_rxd, dut.phy_sgmii_rx_er, dut.phy_sgmii_rx_dv,
                dut.phy_sgmii_clk, dut.phy_sgmii_rst, dut.phy_sgmii_clk_en)
            self.sgmii_sink = GmiiSink(dut.phy_sgmii_txd, dut.phy_sgmii_tx_er, dut.phy_sgmii_tx_en,
                dut.phy_sgmii_clk, dut.phy_sgmii_rst, dut.phy_sgmii_clk_en)

        cocotb.start_soon(Clock(dut.sfp_gmii_clk, 8, units="ns").start())

        self.sfp_source = GmiiSource(dut.sfp_gmii_rxd, dut.sfp_gmii_rx_er, dut.sfp_gmii_rx_dv,
            dut.sfp_gmii_clk, dut.sfp_gmii_rst, dut.sfp_gmii_clk_en)
        self.sfp_sink = GmiiSink(dut.sfp_gmii_txd, dut.sfp_gmii_tx_er, dut.sfp_gmii_tx_en,
            dut.sfp_gmii_clk, dut.sfp_gmii_rst, dut.sfp_gmii_clk_en)

        self.uart_source = UartSource(dut.uart_rxd, baud=921600, bits=8, stop_bits=1)
        self.uart_sink = UartSink(dut.uart_txd, baud=921600, bits=8, stop_bits=1)

        dut.phy_sgmii_clk_en.setimmediatevalue(1)
        dut.sfp_gmii_clk_en.setimmediatevalue(1)

        dut.btnu.setimmediatevalue(0)
        dut.btnl.setimmediatevalue(0)
        dut.btnd.setimmediatevalue(0)
        dut.btnr.setimmediatevalue(0)
        dut.btnc.setimmediatevalue(0)
        dut.sw.setimmediatevalue(0)
        dut.uart_rts.setimmediatevalue(0)

        cocotb.start_soon(self._run_clk())

    async def init(self):

        self.dut.rst.setimmediatevalue(0)
        self.dut.phy_sgmii_rst.setimmediatevalue(0)
        self.dut.sfp_gmii_rst.setimmediatevalue(0)

        for k in range(10):
            await RisingEdge(self.dut.clk)

        self.dut.rst.value = 1
        self.dut.phy_sgmii_rst.value = 1
        self.dut.sfp_gmii_rst.value = 1

        for k in range(10):
            await RisingEdge(self.dut.clk)

        self.dut.rst.value = 0
        self.dut.phy_sgmii_rst.value = 0
        self.dut.sfp_gmii_rst.value = 0

    async def _run_clk(self):
        t = Timer(2, 'ns')
        while True:
            self.dut.clk.value = 1
            await t
            self.dut.clk90.value = 1
            await t
            self.dut.clk.value = 0
            await t
            self.dut.clk90.value = 0
            await t


async def mac_test(tb, source, sink):
    tb.log.info("Test MAC")

    tb.log.info("Multiple small packets")

    count = 64

    pkts = [bytearray([(x+k) % 256 for x in range(60)]) for k in range(count)]

    for p in pkts:
        await source.send(GmiiFrame.from_payload(p))

    for k in range(count):
        rx_frame = await sink.recv()

        tb.log.info("RX frame: %s", rx_frame)

        assert rx_frame.get_payload() == pkts[k]
        assert rx_frame.check_fcs()
        assert rx_frame.error is None

    tb.log.info("Multiple large packets")

    count = 32

    pkts = [bytearray([(x+k) % 256 for x in range(1514)]) for k in range(count)]

    for p in pkts:
        await source.send(GmiiFrame.from_payload(p))

    for k in range(count):
        rx_frame = await sink.recv()

        tb.log.info("RX frame: %s", rx_frame)

        assert rx_frame.get_payload() == pkts[k]
        assert rx_frame.check_fcs()
        assert rx_frame.error is None

    tb.log.info("MAC test done")


@cocotb.test()
async def run_test(dut):

    tb = TB(dut)

    await tb.init()

    tests = []

    tb.log.info("Start BASE-T MAC loopback test")

    if hasattr(dut, "baset_mac_gmii"):
        tests.append(cocotb.start_soon(mac_test(tb, tb.baset_phy.rx, tb.baset_phy.tx)))
    elif hasattr(dut, "baset_mac_rgmii"):
        tests.append(cocotb.start_soon(mac_test(tb, tb.baset_phy.rx, tb.baset_phy.tx)))
    elif hasattr(dut, "baset_mac_sgmii"):
        tests.append(cocotb.start_soon(mac_test(tb, tb.sgmii_source, tb.sgmii_sink)))

    tb.log.info("Start SFP MAC loopback test")

    tests.append(cocotb.start_soon(mac_test(tb, tb.sfp_source, tb.sfp_sink)))

    await Combine(*tests)

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


@pytest.mark.parametrize("phy_type", ["GMII", "RGMII", "SGMII"])
def test_fpga_core(request, phy_type):
    dut = "fpga_core"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(taxi_src_dir, "eth", "rtl", "taxi_eth_mac_1g_fifo.f"),
        os.path.join(taxi_src_dir, "eth", "rtl", "taxi_eth_mac_1g_gmii_fifo.f"),
        os.path.join(taxi_src_dir, "eth", "rtl", "taxi_eth_mac_1g_rgmii_fifo.f"),
        os.path.join(taxi_src_dir, "xfcp", "rtl", "taxi_xfcp_if_uart.f"),
        os.path.join(taxi_src_dir, "xfcp", "rtl", "taxi_xfcp_switch.sv"),
        os.path.join(taxi_src_dir, "xfcp", "rtl", "taxi_xfcp_mod_i2c_master.f"),
        os.path.join(taxi_src_dir, "xfcp", "rtl", "taxi_xfcp_mod_stats.f"),
        os.path.join(taxi_src_dir, "sync", "rtl", "taxi_sync_reset.sv"),
        os.path.join(taxi_src_dir, "sync", "rtl", "taxi_sync_signal.sv"),
        os.path.join(taxi_src_dir, "io", "rtl", "taxi_debounce_switch.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['SIM'] = "1'b1"
    parameters['VENDOR'] = "\"XILINX\""
    parameters['FAMILY'] = "\"kintex7\""
    parameters['USE_CLK90'] = "1'b1"
    parameters['BASET_PHY_TYPE'] = f"\"{phy_type}\""
    parameters['SFP_INVERT'] = "1'b1"

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
