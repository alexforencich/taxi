#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2021-2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import itertools
import logging
import os
import random

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge

from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSource, AxiStreamSink


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

        self.source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis), dut.clk, dut.rst)
        self.sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis), dut.clk, dut.rst)

        dut.cfg_pad_en.setimmediatevalue(1)
        dut.cfg_min_pkt_len.setimmediatevalue(60-1)

        self.stats = {}
        self.stats["stat_pad_frame"] = 0
        self.stats["stat_err_user"] = 0
        self.stats["stat_err_underflow"] = 0

        cocotb.start_soon(self._run_stats_counters())

    def set_idle_generator(self, generator=None):
        if generator:
            self.source.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.sink.set_pause_generator(generator())

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

        self.stats_reset()

    def stats_reset(self):
        for stat in self.stats:
            self.stats[stat] = 0

    async def _run_stats_counters(self):
        while True:
            await RisingEdge(self.dut.clk)
            for stat in self.stats:
                self.stats[stat] += int(getattr(self.dut, stat).value)


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


def size_list():
    data_width = len(cocotb.top.m_axis.tdata)
    byte_lanes = data_width // 8
    return list(range(1, max(byte_lanes*4, 128))) + [512, 1514, 9214] + [1]*10


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))


underflow_drop = False
idle_list = [None, cycle_pause]
if getattr(cocotb, 'top', None) is not None:
    if cocotb.top.UNDERFLOW_DROP_EN.value:
        underflow_drop = True
        idle_list = [None]


@cocotb.test()
@cocotb.parametrize(
    ("payload_lengths", [size_list]),
    ("payload_data", [incrementing_payload]),
    ("pad_en", [True, False]),
    ("idle_inserter", idle_list),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test(dut, pad_en=True, payload_lengths=None, payload_data=None, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    id_count = 2**len(tb.source.bus.tid)

    cur_id = 1

    min_pkt_len = 60

    dut.cfg_pad_en.value = pad_en
    dut.cfg_min_pkt_len.value = min_pkt_len-1

    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    test_frames = []

    for test_data in [payload_data(x) for x in payload_lengths()]:
        test_frame = AxiStreamFrame(test_data)
        test_frame.tid = cur_id
        test_frame.tdest = cur_id

        test_frames.append(test_frame)
        await tb.source.send(test_frame)

        cur_id = (cur_id + 1) % id_count

    for test_frame in test_frames:
        rx_frame = await tb.sink.recv()

        tb.log.info("Packet len: %d", len(rx_frame))
        if pad_en:
            assert len(rx_frame) >= min_pkt_len
            assert rx_frame.tdata == test_frame.tdata.ljust(min_pkt_len, b'\x00')
        else:
            assert rx_frame.tdata == test_frame.tdata
        assert rx_frame.tid == test_frame.tid
        assert rx_frame.tdest == test_frame.tdest
        assert not rx_frame.tuser

    assert tb.sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("pad_en", [True, False]),
    ("idle_inserter", idle_list),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_pad(dut, pad_en=True, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    byte_lanes = tb.source.byte_lanes
    id_count = 2**len(tb.source.bus.tid)

    cur_id = 1

    min_pkt_len = 60

    dut.cfg_pad_en.value = pad_en
    dut.cfg_min_pkt_len.value = min_pkt_len-1

    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    for min_pkt_len in range(1, byte_lanes*3+1):

        tb.dut.cfg_min_pkt_len.value = min_pkt_len-1
        await RisingEdge(dut.clk)

        for test_pkt_len in range(max(min_pkt_len-byte_lanes*2, 1), min_pkt_len+byte_lanes*2+1):

            short = test_pkt_len < min_pkt_len

            tb.log.info("min len %d, test len %d", min_pkt_len, test_pkt_len)

            tb.stats_reset()

            test_data_1 = bytearray(itertools.islice(itertools.cycle(range(256)), min_pkt_len))
            test_data_2 = bytearray(itertools.islice(itertools.cycle(range(256)), test_pkt_len))

            test_frames = []

            for k in range(3):
                if k == 1:
                    test_data = test_data_2
                else:
                    test_data = test_data_1
                test_frame = AxiStreamFrame(test_data)
                test_frame.tid = cur_id
                test_frame.tdest = cur_id

                test_frames.append(test_frame)
                await tb.source.send(test_frame)

                cur_id = (cur_id + 1) % id_count

            for test_frame in test_frames:
                rx_frame = await tb.sink.recv()

                tb.log.info("Packet len: %d", len(rx_frame))
                if pad_en:
                    assert len(rx_frame) >= min_pkt_len
                    assert rx_frame.tdata == test_frame.tdata.ljust(min_pkt_len, b'\x00')
                else:
                    assert rx_frame.tdata == test_frame.tdata
                assert rx_frame.tid == test_frame.tid
                assert rx_frame.tdest == test_frame.tdest
                assert not rx_frame.tuser

            assert tb.stats["stat_pad_frame"] == (1 if short and pad_en else 0)
            assert tb.stats["stat_err_user"] == 0
            assert tb.stats["stat_err_underflow"] == 0

        assert tb.sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("pad_en", [True, False]),
    ("idle_inserter", idle_list),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_tuser_assert(dut, pad_en=True, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    byte_lanes = tb.source.byte_lanes
    id_count = 2**len(tb.source.bus.tid)

    cur_id = 1

    min_pkt_len = 60

    dut.cfg_pad_en.value = pad_en
    dut.cfg_min_pkt_len.value = min_pkt_len-1

    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    for min_pkt_len in range(1, byte_lanes*3+1):

        tb.dut.cfg_min_pkt_len.value = min_pkt_len-1
        await RisingEdge(dut.clk)

        for test_pkt_len in range(max(min_pkt_len-byte_lanes*2, 1), min_pkt_len+byte_lanes*2+1):

            short = test_pkt_len < min_pkt_len

            tb.log.info("min len %d, test len %d", min_pkt_len, test_pkt_len)

            tb.stats_reset()

            test_data_1 = bytearray(itertools.islice(itertools.cycle(range(256)), min_pkt_len))
            test_data_2 = bytearray(itertools.islice(itertools.cycle(range(256)), test_pkt_len))

            test_frames = []

            for k in range(3):
                if k == 1:
                    test_data = test_data_2
                else:
                    test_data = test_data_1
                test_frame = AxiStreamFrame(test_data)
                test_frame.tid = cur_id
                test_frame.tdest = cur_id
                if k == 1:
                    test_frame.tuser = 1

                test_frames.append(test_frame)
                await tb.source.send(test_frame)

                cur_id = (cur_id + 1) % id_count

            for k, test_frame in enumerate(test_frames):
                rx_frame = await tb.sink.recv()

                tb.log.info("Packet len: %d", len(rx_frame))
                if pad_en:
                    assert len(rx_frame) >= min_pkt_len
                    assert rx_frame.tdata == test_frame.tdata.ljust(min_pkt_len, b'\x00')
                else:
                    assert rx_frame.tdata == test_frame.tdata
                assert rx_frame.tid == test_frame.tid
                assert rx_frame.tdest == test_frame.tdest
                if k == 1:
                    if isinstance(rx_frame.tuser, list):
                        assert rx_frame.tuser[-1]
                    else:
                        assert rx_frame.tuser
                else:
                    assert not rx_frame.tuser

            assert tb.stats["stat_pad_frame"] == (1 if short and pad_en else 0)
            assert tb.stats["stat_err_user"] == 1
            assert tb.stats["stat_err_underflow"] == 0

        assert tb.sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test(skip=(not underflow_drop))
@cocotb.parametrize(
    ("pad_en", [True, False]),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_test_underflow(dut, pad_en=True, backpressure_inserter=None):

    tb = TB(dut)

    byte_lanes = tb.source.byte_lanes
    id_count = 2**len(tb.source.bus.tid)

    cur_id = 1

    min_pkt_len = 60

    dut.cfg_pad_en.value = pad_en
    dut.cfg_min_pkt_len.value = min_pkt_len-1

    await tb.reset()

    tb.set_backpressure_generator(backpressure_inserter)

    for min_pkt_len in range(byte_lanes, byte_lanes*4+1, byte_lanes):

        tb.dut.cfg_min_pkt_len.value = min_pkt_len-1
        await RisingEdge(dut.clk)

        for test_pkt_len in range(byte_lanes, byte_lanes*8+1, byte_lanes):

            for delay_cyc in range(0, (test_pkt_len // byte_lanes) + 1):

                short = test_pkt_len < min_pkt_len
                drop = delay_cyc > 0 and delay_cyc < (test_pkt_len // byte_lanes)
                short_drop = drop and delay_cyc < (min_pkt_len // byte_lanes)-1

                tb.log.info("min len %d, test len %d, delay %d, short %d, drop %d, short_drop %d", min_pkt_len, test_pkt_len, delay_cyc, short, drop, short_drop)

                await FallingEdge(dut.clk)
                for k in range(10):
                    await FallingEdge(dut.clk)
                tb.stats_reset()

                test_data_1 = bytearray(itertools.islice(itertools.cycle(range(256)), min_pkt_len))
                test_data_2 = bytearray(itertools.islice(itertools.cycle(range(256)), test_pkt_len))

                test_frames = []

                for k in range(3):
                    if k == 1:
                        test_data = test_data_2
                    else:
                        test_data = test_data_1
                    test_frame = AxiStreamFrame(test_data)
                    test_frame.tid = cur_id
                    test_frame.tdest = cur_id

                    test_frames.append(test_frame)
                    await tb.source.send(test_frame)

                    cur_id = (cur_id + 1) % id_count

                cycle_delay = (min_pkt_len // byte_lanes) + delay_cyc

                while cycle_delay > 0:
                    await FallingEdge(dut.clk)
                    if not int(dut.m_axis.tvalid.value) or not int(dut.m_axis.tready.value):
                        continue
                    cycle_delay -= 1

                tb.source.pause = True
                await FallingEdge(dut.clk)
                while not int(dut.m_axis.tready.value):
                    await FallingEdge(dut.clk)
                tb.source.pause = False

                for k, test_frame in enumerate(test_frames):
                    rx_frame = await tb.sink.recv()

                    tb.log.info("Packet len: %d", len(rx_frame))
                    if pad_en:
                        assert len(rx_frame) >= min_pkt_len

                    if k == 1 and drop:
                        if isinstance(rx_frame.tuser, list):
                            assert rx_frame.tuser[-1]
                        else:
                            assert rx_frame.tuser
                    else:
                        if pad_en:
                            assert rx_frame.tdata == test_frame.tdata.ljust(min_pkt_len, b'\x00')
                        else:
                            assert rx_frame.tdata == test_frame.tdata
                        assert rx_frame.tid == test_frame.tid
                        assert rx_frame.tdest == test_frame.tdest
                        assert not rx_frame.tuser

                assert tb.stats["stat_pad_frame"] == (1 if (short or short_drop) and pad_en else 0)
                assert tb.stats["stat_err_user"] == 0
                assert tb.stats["stat_err_underflow"] == (1 if drop else 0)

        assert tb.sink.empty()

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("pad_en", [True, False]),
    ("idle_inserter", idle_list),
    ("backpressure_inserter", [None, cycle_pause]),
)
async def run_stress_test(dut, pad_en=True, idle_inserter=None, backpressure_inserter=None):

    tb = TB(dut)

    byte_lanes = tb.source.byte_lanes
    id_count = 2**len(tb.source.bus.tid)

    cur_id = 1

    min_pkt_len = 60

    dut.cfg_pad_en.value = pad_en
    dut.cfg_min_pkt_len.value = min_pkt_len-1

    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    test_frames = []

    for k in range(128):
        length = random.randint(1, max(byte_lanes*16, min_pkt_len*4))
        test_data = bytearray(itertools.islice(itertools.cycle(range(256)), length))
        test_frame = AxiStreamFrame(test_data)
        test_frame.tid = cur_id
        test_frame.tdest = cur_id

        test_frames.append(test_frame)
        await tb.source.send(test_frame)

        cur_id = (cur_id + 1) % id_count

    for test_frame in test_frames:
        rx_frame = await tb.sink.recv()

        tb.log.info("Packet len: %d", len(rx_frame))
        if pad_en:
            assert len(rx_frame) >= min_pkt_len
            assert rx_frame.tdata == test_frame.tdata.ljust(min_pkt_len, b'\x00')
        else:
            assert rx_frame.tdata == test_frame.tdata
        assert rx_frame.tid == test_frame.tid
        assert rx_frame.tdest == test_frame.tdest
        assert not rx_frame.tuser

    assert tb.sink.empty()

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


@pytest.mark.parametrize("data_w", [8, 16, 32, 64])
@pytest.mark.parametrize("underflow_drop", [0, 1])
def test_taxi_axis_pad(request, data_w, underflow_drop):
    dut = "taxi_axis_pad"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(rtl_dir, "taxi_axis_if.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['DATA_W'] = data_w
    parameters['KEEP_EN'] = int(parameters['DATA_W'] > 8)
    parameters['KEEP_W'] = (parameters['DATA_W'] + 7) // 8
    parameters['STRB_EN'] = 0
    parameters['LAST_EN'] = 1
    parameters['ID_EN'] = 1
    parameters['ID_W'] = 8
    parameters['DEST_EN'] = 1
    parameters['DEST_W'] = 8
    parameters['USER_EN'] = 1
    parameters['USER_W'] = 1
    parameters['ID_PAD_REG_EN'] = 1
    parameters['DEST_PAD_REG_EN'] = 1
    parameters['USER_PAD_REG_EN'] = 1
    parameters['MIN_LEN_W'] = 16
    parameters['UNDERFLOW_DROP_EN'] = underflow_drop

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
