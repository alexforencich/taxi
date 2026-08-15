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
import zlib

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


def crc32(data):
    return zlib.crc32(data) & 0xffffffff


def crc32c(data, crc=0xffffffff, poly=0x82f63b78):
    for d in data:
        crc = crc ^ d
        for bit in range(0, 8):
            if crc & 1:
                crc = (crc >> 1) ^ poly
            else:
                crc = crc >> 1
    return ~crc & 0xffffffff


ref_crc = None
if getattr(cocotb, 'top', None) is not None:
    if int(cocotb.top.LFSR_POLY.value) == 0x4c11db7:
        ref_crc = crc32
    if int(cocotb.top.LFSR_POLY.value) == 0x1edc6f41:
        ref_crc = crc32c


@cocotb.test()
@cocotb.parametrize(
    ("ref_crc", [ref_crc]),
)
async def run_test_crc(dut, ref_crc):

    data_width = len(dut.data_in)
    byte_lanes = data_width // 8

    tb = TB(dut)

    await tb.reset()

    block = bytes([(x+1)*0x11 for x in range(byte_lanes)])

    dut.data_in.value = int.from_bytes(block, 'little')
    dut.data_in_valid.value = 1
    await RisingEdge(dut.clk)
    dut.data_in_valid.value = 0

    await RisingEdge(dut.clk)
    val = int(dut.crc_out.value)
    ref = ref_crc(block)

    tb.log.info("CRC: 0x%x (ref: 0x%x)", val, ref)

    assert val == ref

    await tb.reset()

    block = bytearray(itertools.islice(itertools.cycle(range(256)), 1024))

    for b in chunks(block, byte_lanes):
        dut.data_in.value = int.from_bytes(b, 'little')
        dut.data_in_valid.value = 1
        await RisingEdge(dut.clk)
    dut.data_in_valid.value = 0

    await RisingEdge(dut.clk)
    val = int(dut.crc_out.value)
    ref = ref_crc(block)

    tb.log.info("CRC: 0x%x (ref: 0x%x)", val, ref)

    assert val == ref

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


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
            (32, "32'h4c11db7", "'1", 1, 1, 1, 8),
            (32, "32'h4c11db7", "'1", 1, 1, 1, 64),
            (32, "32'h1edc6f41", "'1", 1, 1, 1, 8),
            (32, "32'h1edc6f41", "'1", 1, 1, 1, 64),
        ])
def test_taxi_lfsr_crc(request, lfsr_w, lfsr_poly, lfsr_init, lfsr_galois, reverse, invert, data_w):
    dut = "taxi_lfsr_crc"
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
