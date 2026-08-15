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
import re
import sys
from contextlib import contextmanager

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from cocotbext.pcie.core import RootComplex
from cocotbext.axi import AxiLiteBus, AxiLiteRam


try:
    from pcie_if import PcieIfDevice, PcieIfRxBus, PcieIfTxBus
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        from pcie_if import PcieIfDevice, PcieIfRxBus, PcieIfTxBus
    finally:
        del sys.path[0]


@contextmanager
def assert_raises(exc_type, pattern=None):
    try:
        yield
    except exc_type as e:
        if pattern:
            assert re.match(pattern, str(e)), \
                "Correct exception type caught, but message did not match pattern"
        pass
    else:
        raise AssertionError("{} was not raised".format(exc_type.__name__))


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        # PCIe
        self.rc = RootComplex()

        self.dev = PcieIfDevice(
            clk=dut.clk,
            rst=dut.rst,

            rx_req_tlp_bus=PcieIfRxBus.from_entity(dut.rx_req_tlp),
            tx_cpl_tlp_bus=PcieIfTxBus.from_entity(dut.tx_cpl_tlp)
        )

        self.dev.log.setLevel(logging.DEBUG)

        self.dev.functions[0].configure_bar(0, 16*1024*1024)
        self.dev.functions[0].configure_bar(1, 16*1024, io=True)

        self.rc.make_port().connect(self.dev)

        # AXI
        self.axil_ram = AxiLiteRam(AxiLiteBus.from_entity(dut.m_axil), dut.clk, dut.rst, size=2**16)

        dut.bus_num.setimmediatevalue(0)

        # monitor error outputs
        self.stat_err_cor_asserted = False
        self.stat_err_uncor_asserted = False
        cocotb.start_soon(self._run_monitor_stat_err_cor())
        cocotb.start_soon(self._run_monitor_stat_err_uncor())

    def set_idle_generator(self, generator=None):
        if generator:
            self.dev.rx_req_tlp_source.set_pause_generator(generator())
            self.axil_ram.write_if.b_channel.set_pause_generator(generator())
            self.axil_ram.read_if.r_channel.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.dev.tx_cpl_tlp_sink.set_pause_generator(generator())
            self.axil_ram.write_if.aw_channel.set_pause_generator(generator())
            self.axil_ram.write_if.w_channel.set_pause_generator(generator())
            self.axil_ram.read_if.ar_channel.set_pause_generator(generator())

    async def _run_monitor_stat_err_cor(self):
        while True:
            await RisingEdge(self.dut.stat_err_cor)
            self.log.info("stat_err_cor (correctable error) was asserted")
            self.stat_err_cor_asserted = True

    async def _run_monitor_stat_err_uncor(self):
        while True:
            await RisingEdge(self.dut.stat_err_uncor)
            self.log.info("stat_err_uncor (uncorrectable error) was asserted")
            self.stat_err_uncor_asserted = True

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

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.cycle_reset()

    await tb.rc.enumerate()

    dev = tb.rc.find_device(tb.dev.functions[0].pcie_id)
    await dev.enable_device()

    dev_bar0 = dev.bar_window[0]

    tb.dut.bus_num.value = tb.dev.functions[0].pcie_id.bus

    for length in range(0, 5):
        for pcie_offset in range(4-length+1):
            tb.log.info("length %d, pcie_offset %d", length, pcie_offset)
            pcie_addr = pcie_offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])

            tb.axil_ram.write(pcie_addr-128, b'\x55'*(len(test_data)+256))

            await dev_bar0.write(pcie_addr, test_data)

            # wait for write to complete
            val = await dev_bar0.read(pcie_addr, len(test_data), timeout=1000, timeout_unit='ns')

            tb.log.debug("%s", tb.axil_ram.hexdump_str((pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48))

            assert tb.axil_ram.read(pcie_addr-1, len(test_data)+2) == b'\x55'+test_data+b'\x55'

            assert not tb.stat_err_cor_asserted
            assert not tb.stat_err_uncor_asserted

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_read(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.cycle_reset()

    await tb.rc.enumerate()

    dev = tb.rc.find_device(tb.dev.functions[0].pcie_id)
    await dev.enable_device()

    dev_bar0 = dev.bar_window[0]

    tb.dut.bus_num.value = tb.dev.functions[0].pcie_id.bus

    for length in range(0, 5):
        for pcie_offset in range(4-length+1):
            tb.log.info("length %d, pcie_offset %d", length, pcie_offset)
            pcie_addr = pcie_offset+0x1000
            test_data = bytearray([x % 256 for x in range(length)])

            tb.axil_ram.write(pcie_addr-128, b'\x55'*(len(test_data)+256))
            tb.axil_ram.write(pcie_addr, test_data)

            tb.log.debug("%s", tb.axil_ram.hexdump_str((pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48))

            val = await dev_bar0.read(pcie_addr, len(test_data), timeout=1000, timeout_unit='ns')

            tb.log.debug("read data: %s", val)

            assert val == test_data

            assert not tb.stat_err_cor_asserted
            assert not tb.stat_err_uncor_asserted

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("idle_inserter", [None, cycle_pause]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_bad_ops(dut, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.cycle_reset()

    await tb.rc.enumerate()

    dev = tb.rc.find_device(tb.dev.functions[0].pcie_id)
    await dev.enable_device()

    dev_bar0 = dev.bar_window[0]
    dev_bar1 = dev.bar_window[1]

    tb.dut.bus_num.value = tb.dev.functions[0].pcie_id.bus

    tb.log.info("Test IO write")

    length = 4
    pcie_addr = 0x1000
    test_data = bytearray([x % 256 for x in range(length)])

    tb.axil_ram.write(pcie_addr-128, b'\x55'*(len(test_data)+256))

    with assert_raises(Exception, "Unsuccessful completion"):
        await dev_bar1.write(pcie_addr, test_data, timeout=1000, timeout_unit='ns')

    await Timer(100, 'ns')

    tb.log.debug("%s", tb.axil_ram.hexdump_str((pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

    assert tb.axil_ram.read(pcie_addr-1, len(test_data)+2) == b'\x55'*(len(test_data)+2)

    assert tb.stat_err_cor_asserted
    assert not tb.stat_err_uncor_asserted

    tb.stat_err_cor_asserted = False
    tb.stat_err_uncor_asserted = False

    tb.log.info("Test IO read")

    length = 4
    pcie_addr = 0x1000
    test_data = bytearray([x % 256 for x in range(length)])

    tb.axil_ram.write(pcie_addr-128, b'\x55'*(len(test_data)+256))
    tb.axil_ram.write(pcie_addr, test_data)

    tb.log.debug("%s", tb.axil_ram.hexdump_str((pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

    with assert_raises(Exception, "Unsuccessful completion"):
        val = await dev_bar1.read(pcie_addr, len(test_data), timeout=1000, timeout_unit='ns')

    assert tb.stat_err_cor_asserted
    assert not tb.stat_err_uncor_asserted

    tb.stat_err_cor_asserted = False
    tb.stat_err_uncor_asserted = False

    tb.log.info("Test bad write")

    length = 32
    pcie_addr = 0x1000
    test_data = bytearray([x % 256 for x in range(length)])

    tb.axil_ram.write(pcie_addr-128, b'\x55'*(len(test_data)+256))

    await dev_bar0.write(pcie_addr, test_data)

    await Timer(100, 'ns')

    tb.log.debug("%s", tb.axil_ram.hexdump_str((pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

    assert tb.axil_ram.read(pcie_addr-1, len(test_data)+2) == b'\x55'*(len(test_data)+2)

    assert not tb.stat_err_cor_asserted
    assert tb.stat_err_uncor_asserted

    tb.stat_err_cor_asserted = False
    tb.stat_err_uncor_asserted = False

    tb.log.info("Test bad read")

    length = 32
    pcie_addr = 0x1000
    test_data = bytearray([x % 256 for x in range(length)])

    tb.axil_ram.write(pcie_addr-128, b'\x55'*(len(test_data)+256))
    tb.axil_ram.write(pcie_addr, test_data)

    tb.log.debug("%s", tb.axil_ram.hexdump_str((pcie_addr & ~0xf)-16, (((pcie_addr & 0xf)+length-1) & ~0xf)+48, prefix="AXI "))

    with assert_raises(Exception, "Unsuccessful completion"):
        val = await dev_bar0.read(pcie_addr, len(test_data), timeout=1000, timeout_unit='ns')

    assert tb.stat_err_cor_asserted
    assert not tb.stat_err_uncor_asserted

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


@pytest.mark.parametrize("axil_data_w", [32])
@pytest.mark.parametrize("pcie_data_w", [64, 128, 256, 512])
def test_taxi_pcie_axil_master_minimal(request, pcie_data_w, axil_data_w):
    dut = "taxi_pcie_axil_master_minimal"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(rtl_dir, "taxi_pcie_tlp_if.sv"),
        os.path.join(taxi_src_dir, "axi", "rtl", "taxi_axil_if.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['TLP_SEG_DATA_W'] = pcie_data_w
    parameters['TLP_SEGS'] = 1
    parameters['AXIL_DATA_W'] = axil_data_w
    parameters['AXIL_ADDR_W'] = 64
    parameters['TLP_FORCE_64_BIT_ADDR'] = 0

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
