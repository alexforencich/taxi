#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2023-2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import itertools
import logging
import os

import pytest
import cocotb_test.simulator

import cocotb
from cocotb.triggers import Timer


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        dut.data_in.setimmediatevalue(0)
        dut.state_in.setimmediatevalue(0)


def chunks(lst, n, padvalue=None):
    return itertools.zip_longest(*[iter(lst)]*n, fillvalue=padvalue)


def crc32(data, crc=0xffffffff, poly=0xedb88320):
    # return zlib.crc32(data) & 0xffffffff
    for d in data:
        crc = crc ^ d
        for bit in range(0, 8):
            if crc & 1:
                crc = (crc >> 1) ^ poly
            else:
                crc = crc >> 1
    return ~crc & 0xffffffff


def crc32_shift(crc, count, poly=0xedb88320):
    crc = ~crc & 0xffffffff

    if count > 0:
        # shift forwards
        for i in range(count):
            if crc & 1:
                crc = (crc >> 1) ^ poly
            else:
                crc = crc >> 1

    elif count < 0:
        # shift backwards
        for i in range(-count):
            if crc & 0x80000000:
                crc ^= poly
                crc = (crc << 1) | 1
            else:
                crc = crc << 1
            crc = crc & 0xffffffff

    return ~crc & 0xffffffff


def crc32c(data, crc=0xffffffff, poly=0x82f63b78):
    for d in data:
        crc = crc ^ d
        for bit in range(0, 8):
            if crc & 1:
                crc = (crc >> 1) ^ poly
            else:
                crc = crc >> 1
    return ~crc & 0xffffffff


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


ref_crc = None
ref_prbs = None
if getattr(cocotb, 'top', None) is not None:
    if cocotb.top.LFSR_POLY.value == 0x4c11db7:
        if cocotb.top.STATE_SHIFT_PRE.value == 0:
            ref_crc = crc32
        else:
            pass
    if cocotb.top.LFSR_POLY.value == 0x1edc6f41:
        ref_crc = crc32c
    if cocotb.top.LFSR_POLY.value == 0x021:
        ref_prbs = prbs9
    if cocotb.top.LFSR_POLY.value == 0x10000001:
        ref_prbs = prbs31


@cocotb.test(skip=(ref_crc is None))
@cocotb.parametrize(
    ("ref_crc", [ref_crc]),
)
async def run_test_crc(dut, ref_crc):

    data_width = len(dut.data_in)
    byte_lanes = data_width // 8

    state_width = len(dut.state_in)
    state_mask = 2**state_width-1

    tb = TB(dut)

    await Timer(10, 'ns')

    block = bytes([(x+1)*0x11 for x in range(byte_lanes)])

    dut.state_in.value = state_mask
    dut.data_in.value = int.from_bytes(block, 'little')
    await Timer(10, 'ns')

    val = ~int(dut.state_out.value) & state_mask
    ref = ref_crc(block)

    tb.log.info("CRC: 0x%x (ref: 0x%x)", val, ref)

    assert val == ref

    await Timer(10, 'ns')

    block = bytearray(itertools.islice(itertools.cycle(range(256)), 1024))

    dut.state_in.value = state_mask
    for b in chunks(block, byte_lanes):
        dut.data_in.value = int.from_bytes(b, 'little')
        await Timer(10, 'ns')
        dut.state_in.value = dut.state_out.value

    val = ~int(dut.state_out.value) & state_mask
    ref = ref_crc(block)

    tb.log.info("CRC: 0x%x (ref: 0x%x)", val, ref)

    assert val == ref

    await Timer(10, 'ns')


@cocotb.test(skip=(ref_prbs is None))
@cocotb.parametrize(
    ("ref_prbs", [ref_prbs]),
)
async def run_test_prbs(dut, ref_prbs):

    data_width = len(dut.data_in)
    byte_lanes = data_width // 8
    data_mask = 2**data_width-1

    state_width = len(dut.state_in)
    state_mask = 2**state_width-1

    tb = TB(dut)

    await Timer(10, 'ns')

    dut.state_in.value = state_mask
    dut.data_in.value = 0
    gen = chunks(ref_prbs(), byte_lanes)

    await Timer(10, 'ns')

    for i in range(512):
        ref = int.from_bytes(bytes(next(gen)), 'big')
        val = ~int(dut.data_out.value) & data_mask

        tb.log.info("PRBS: 0x%x (ref: 0x%x)", val, ref)

        assert ref == val

        dut.state_in.value = dut.state_out.value

        await Timer(10, 'ns')


@cocotb.test(skip=(ref_crc is not None or ref_prbs is not None))
async def run_test_shift_crc(dut):

    data_width = len(dut.data_in)
    byte_lanes = data_width // 8

    state_width = len(dut.state_in)
    state_mask = 2**state_width-1

    shift = int(dut.STATE_SHIFT_PRE.value)
    if shift > 0 and shift & 0x80000000:
        shift -= 0x100000000

    tb = TB(dut)

    await Timer(10, 'ns')

    val = 0x12345678

    dut.state_in.value = ~val & state_mask
    dut.data_in.value = 0
    await Timer(10, 'ns')

    crc = ~int(dut.state_out.value) & state_mask
    ref = crc32_shift(val, shift)

    tb.log.info("Shifted CRC: 0x%x (ref: 0x%x)", crc, ref)

    assert crc == ref

    await Timer(10, 'ns')

    for k in range(10):

        val = crc32(bytearray(k))

        dut.state_in.value = ~val & state_mask
        dut.data_in.value = 0
        await Timer(10, 'ns')

        crc = ~int(dut.state_out.value) & state_mask
        ref = crc32_shift(val, shift)

        tb.log.info("Shifted CRC: 0x%x (ref: 0x%x)", crc, ref)

        assert crc == ref

        await Timer(10, 'ns')


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


@pytest.mark.parametrize(("lfsr_w", "lfsr_poly", "lfsr_galois", "reverse", "data_w", "data_shift", "pre_shift"), [
            (32, "32'h4c11db7", 1, 1, 8, 1, 0),
            (32, "32'h4c11db7", 1, 1, 64, 1, 0),
            (32, "32'h4c11db7", 1, 1, 64, 0, 8),
            (32, "32'h4c11db7", 1, 1, 64, 0, -8),
            (32, "32'h1edc6f41", 1, 1, 8, 1, 0),
            (32, "32'h1edc6f41", 1, 1, 64, 1, 0),
            (9,  "9'h021", 0, 0, 8, 1, 0),
            (9,  "9'h021", 0, 0, 64, 1, 0),
            (31, "31'h10000001", 0, 0, 8, 1, 0),
            (31, "31'h10000001", 0, 0, 64, 1, 0),
        ])
def test_taxi_lfsr(request, lfsr_w, lfsr_poly, lfsr_galois, reverse, data_w, data_shift, pre_shift):
    dut = "taxi_lfsr"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['LFSR_W'] = lfsr_w
    parameters['LFSR_POLY'] = lfsr_poly
    parameters['LFSR_GALOIS'] = f"1'b{lfsr_galois}"
    parameters['LFSR_FEED_FORWARD'] = "1'b0"
    parameters['REVERSE'] = f"1'b{reverse}"
    parameters['DATA_W'] = data_w
    parameters['DATA_IN_EN'] = f"1'b{data_shift}"
    parameters['DATA_OUT_EN'] = f"1'b{data_shift}"
    parameters['STATE_SHIFT_PRE'] = pre_shift
    parameters['STATE_SHIFT_POST'] = 0

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
