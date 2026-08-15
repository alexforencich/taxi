#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2023-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import itertools
import logging
import os

import pytest
import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

        dut.data_in.setimmediatevalue(0)
        dut.data_in_valid.setimmediatevalue(0)

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


def chunks(lst, n, padvalue=None):
    return itertools.zip_longest(*[iter(lst)]*n, fillvalue=padvalue)


def prbs9(state=0x1ff):
    while True:
        for i in range(8):
            if bool(state & 0x10) ^ bool(state & 0x100):
                state = ((state & 0xff) << 1) | 1
            else:
                state = (state & 0xff) << 1
        yield ~state & 0xff


def prbs31(state=0x7fffffff):
    while True:
        for i in range(8):
            if bool(state & 0x08000000) ^ bool(state & 0x40000000):
                state = ((state & 0x3fffffff) << 1) | 1
            else:
                state = (state & 0x3fffffff) << 1
        yield ~state & 0xff


def count_set_bits(n):
    cnt = 0
    while n:
        n &= n - 1
        cnt += 1
    return cnt


ref_prbs = None
if getattr(cocotb, 'top', None) is not None:
    if int(cocotb.top.LFSR_POLY.value) == 0x021:
        ref_prbs = prbs9
    if int(cocotb.top.LFSR_POLY.value) == 0x10000001:
        ref_prbs = prbs31


@cocotb.test()
@cocotb.parametrize(
    ("ref_prbs", [ref_prbs]),
)
async def run_test_prbs(dut, ref_prbs):

    data_width = len(dut.data_out)
    byte_lanes = data_width // 8

    tb = TB(dut)

    await tb.reset()

    gen = chunks(ref_prbs(), byte_lanes)

    err_cnt = 0

    for i in range(512):

        dut.data_in.value = int.from_bytes(bytes(next(gen)), 'big')
        dut.data_in_valid.value = 1

        val = int(dut.data_out.value)

        tb.log.info("Error value: 0x%x", val)

        err_cnt += count_set_bits(val)

        assert val == 0

        await RisingEdge(dut.clk)

    dut.data_in_valid.value = 0

    tb.log.info("Error count: %d", err_cnt)

    assert err_cnt == 0

    await tb.reset()

    tb.log.info("Single error test")

    gen = chunks(ref_prbs(), byte_lanes)

    err_cnt = 0

    for i in range(64):

        val = int.from_bytes(bytes(next(gen)), 'big')

        if i == 32:
            val = val ^ (1 << (data_width // 2))

        dut.data_in.value = val
        dut.data_in_valid.value = 1

        val = int(dut.data_out.value)

        tb.log.info("Error value: 0x%x", val)

        err_cnt += count_set_bits(val)

        await RisingEdge(dut.clk)

    dut.data_in_valid.value = 0

    tb.log.info("Error count: %d", err_cnt)

    # one bit set per tap
    assert err_cnt == 3


# cocotb-test

tests_dir = os.path.abspath(os.path.dirname(__file__))
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', '..', 'rtl'))


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


@pytest.mark.parametrize(("lfsr_w", "lfsr_poly", "lfsr_init", "lfsr_galois", "reverse", "invert", "data_w"), [
            (9,  "9'h021", "'1", 0, 0, 1, 8),
            (9,  "9'h021", "'1", 0, 0, 1, 64),
            (31, "31'h10000001", "'1", 0, 0, 1, 8),
            (31, "31'h10000001", "'1", 0, 0, 1, 64),
        ])
def test_taxi_lfsr_prbs_check(request, lfsr_w, lfsr_poly, lfsr_init, lfsr_galois, reverse, invert, data_w):
    dut = "taxi_lfsr_prbs_check"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(rtl_dir, "taxi_lfsr.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['LFSR_W'] = lfsr_w
    parameters['LFSR_POLY'] = lfsr_poly
    parameters['LFSR_INIT'] = lfsr_init
    parameters['LFSR_GALOIS'] = f"1'b{lfsr_galois}"
    parameters['REVERSE'] = f"1'b{reverse}"
    parameters['INVERT'] = f"1'b{invert}"
    parameters['DATA_W'] = data_w

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
