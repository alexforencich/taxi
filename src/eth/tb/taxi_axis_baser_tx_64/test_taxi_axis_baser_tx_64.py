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

import pytest
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.utils import get_time_from_sim_steps
from cocotb_tools.runner import get_runner

from cocotbext.eth import PtpClockSimTime
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamFrame

try:
    from baser import BaseRSerdesSink
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        from baser import BaseRSerdesSink
    finally:
        del sys.path[0]


class TB:
    def __init__(self, dut, gbx_cfg=None, usxgmii_speed=None):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        if gbx_cfg:
            self.clk_period = 6.206206
        else:
            self.clk_period = 6.4

        cocotb.start_soon(Clock(dut.clk, self.clk_period, units="ns").start())

        self.source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis_tx), dut.clk, dut.rst)
        self.sink = BaseRSerdesSink(
            data=dut.encoded_tx_data,
            data_valid=dut.encoded_tx_data_valid,
            hdr=dut.encoded_tx_hdr,
            hdr_valid=dut.encoded_tx_hdr_valid,
            gbx_req_sync=dut.tx_gbx_req_sync,
            gbx_req_stall=dut.tx_gbx_req_stall,
            gbx_sync=dut.tx_gbx_sync,
            clock=dut.clk,
            scramble=False,
            gbx_cfg=gbx_cfg
        )

        self.ptp_clock = PtpClockSimTime(ts_tod=dut.ptp_ts, clock=dut.clk)
        self.tx_cpl_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis_tx_cpl), dut.clk, dut.rst)

        dut.tx_os.setimmediatevalue(0)
        dut.tx_os_sig.setimmediatevalue(0)
        dut.tx_os_valid.setimmediatevalue(0)

        dut.ptp_ts_cor_val.setimmediatevalue(0)

        dut.cfg_tx_max_pkt_len.setimmediatevalue(0)
        dut.cfg_tx_ifg.setimmediatevalue(0)
        dut.cfg_tx_enable.setimmediatevalue(0)
        if usxgmii_speed is not None:
            dut.cfg_tx_usxgmii_en.setimmediatevalue(1)
            if usxgmii_speed & 8 == 0:
                dut.cfg_tx_usxgmii_5g.setimmediatevalue(0)
                dut.cfg_tx_usxgmii_speed.setimmediatevalue(usxgmii_speed & 0x7)
                if usxgmii_speed == 0:
                    self.sink.set_xgmii_rep_count(999) # 10 Mbps
                elif usxgmii_speed == 1:
                    self.sink.set_xgmii_rep_count(99) # 100 Mbps
                elif usxgmii_speed == 2:
                    self.sink.set_xgmii_rep_count(9) # 1 Gbps
                elif usxgmii_speed == 4:
                    self.sink.set_xgmii_rep_count(3) # 2.5 Gbps
                elif usxgmii_speed == 5:
                    self.sink.set_xgmii_rep_count(1) # 5 Gbps
                else:
                    self.sink.set_xgmii_rep_count(0) # 10 Gbps
            else:
                dut.cfg_tx_usxgmii_5g.setimmediatevalue(1)
                dut.cfg_tx_usxgmii_speed.setimmediatevalue(usxgmii_speed & 0x7)
                if usxgmii_speed == 8:
                    self.sink.set_xgmii_rep_count(499) # 10 Mbps
                elif usxgmii_speed == 9:
                    self.sink.set_xgmii_rep_count(49) # 100 Mbps
                elif usxgmii_speed == 10:
                    self.sink.set_xgmii_rep_count(4) # 1 Gbps
                elif usxgmii_speed == 12:
                    self.sink.set_xgmii_rep_count(1) # 2.5 Gbps
                else:
                    self.sink.set_xgmii_rep_count(0) # 5 Gbps
        else:
            dut.cfg_tx_usxgmii_en.setimmediatevalue(0)
            dut.cfg_tx_usxgmii_5g.setimmediatevalue(0)
            dut.cfg_tx_usxgmii_speed.setimmediatevalue(0b011)
            self.sink.set_xgmii_rep_count(0)

        self.stats = {}
        self.stats["stat_tx_byte"] = 0
        self.stats["stat_tx_pkt_len"] = 0
        self.stats["stat_tx_pkt_ucast"] = 0
        self.stats["stat_tx_pkt_mcast"] = 0
        self.stats["stat_tx_pkt_bcast"] = 0
        self.stats["stat_tx_pkt_vlan"] = 0
        self.stats["stat_tx_pkt_good"] = 0
        self.stats["stat_tx_pkt_bad"] = 0
        self.stats["stat_tx_err_oversize"] = 0
        self.stats["stat_tx_err_user"] = 0
        self.stats["stat_tx_err_underflow"] = 0

        cocotb.start_soon(self._run_stats_counters())
        if gbx_cfg:
            cocotb.start_soon(self._run_ts_cor())

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

    async def _run_ts_cor(self):
        seq_len = self.sink.gbx_seq_len
        seq = 0
        val = 0
        ui = self.clk_period / self.sink.width
        step = int(ui*2*65536+0.5)
        while True:
            await RisingEdge(self.dut.clk)
            seq += 1
            val += step
            if seq >= seq_len:
                seq = 0
                val = 0
            self.dut.ptp_ts_cor_val.value = val
            if int(self.dut.ptp_ts_cor_sync.value):
                seq = 1


def size_list():
    return list(range(16, 128)) + [512, 1514, 9214] + [60]*10 + [i for i in range(64, 73) for k in range(8)]


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))


gbx_cfgs = [None]
usxgmii_speeds = [None]
if getattr(cocotb, 'top', None) is not None:
    if cocotb.top.GBX_IF_EN.value:
        gbx_cfgs.append((33, [32]))
        gbx_cfgs.append((66, [64, 65]))
    if cocotb.top.USXGMII_EN.value:
        usxgmii_speeds.extend([2, 4, 5, 3, 10, 12, 13])


@cocotb.test()
@cocotb.parametrize(
    ("payload_lengths", [size_list]),
    ("payload_data", [incrementing_payload]),
    ("ifg", [12]),
    ("usxgmii_speed", usxgmii_speeds),
    ("gbx_cfg", gbx_cfgs),
)
async def run_test(dut, gbx_cfg=None, usxgmii_speed=None, payload_lengths=None, payload_data=None, ifg=12):

    tb = TB(dut, gbx_cfg, usxgmii_speed)

    tb.dut.cfg_tx_max_pkt_len.value = 9218-1
    tb.dut.cfg_tx_ifg.value = ifg

    await tb.reset()

    for k in range(100):
        await RisingEdge(dut.clk)

    tb.dut.cfg_tx_enable.value = 1

    test_frames = [payload_data(x) for x in payload_lengths()]

    total_bytes = 0
    total_pkts = 0

    for test_data in test_frames:
        await tb.source.send(AxiStreamFrame(test_data, tid=0, tuser=0))
        total_bytes += len(test_data)+4
        total_pkts += 1

    for test_data in test_frames:
        rx_frame = await tb.sink.recv()
        tx_cpl = await tb.tx_cpl_sink.recv()

        ptp_ts_ns = int(tx_cpl.tdata[0]) / 2**16

        rx_frame_sfd_ns = get_time_from_sim_steps(rx_frame.sim_time_sfd, "ns")

        tb.log.info("TX frame PTP TS: %f ns", ptp_ts_ns)
        tb.log.info("RX frame SFD sim time: %f ns", rx_frame_sfd_ns)
        tb.log.info("Difference: %f ns", abs(rx_frame_sfd_ns - ptp_ts_ns))

        assert rx_frame.get_payload() == test_data
        assert rx_frame.check_fcs()
        assert rx_frame.ctrl is None
        assert abs(rx_frame_sfd_ns - ptp_ts_ns - tb.clk_period*1) < 0.001

    assert tb.sink.empty()

    for stat, val in tb.stats.items():
        tb.log.info("%s: %d", stat, val)

    assert tb.stats["stat_tx_byte"] == total_bytes
    assert tb.stats["stat_tx_pkt_len"] == total_bytes
    assert tb.stats["stat_tx_pkt_ucast"] == total_pkts
    assert tb.stats["stat_tx_pkt_mcast"] == 0
    assert tb.stats["stat_tx_pkt_bcast"] == 0
    assert tb.stats["stat_tx_pkt_vlan"] == 0
    assert tb.stats["stat_tx_pkt_good"] == total_pkts
    assert tb.stats["stat_tx_pkt_bad"] == 0
    assert tb.stats["stat_tx_err_oversize"] == 0
    assert tb.stats["stat_tx_err_user"] == 0
    assert tb.stats["stat_tx_err_underflow"] == 0

    for k in range(10):
        await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("payload_data", [incrementing_payload]),
    ("ifg", [12]),
    # ("usxgmii_speed", usxgmii_speeds),
    ("gbx_cfg", gbx_cfgs),
)
async def run_test_alignment(dut, gbx_cfg=None, usxgmii_speed=None, payload_data=None, ifg=12):

    enable_dic = int(dut.DIC_EN.value)

    tb = TB(dut, gbx_cfg, usxgmii_speed)

    byte_width = tb.source.width // 8

    tb.dut.cfg_tx_max_pkt_len.value = 9218-1
    tb.dut.cfg_tx_ifg.value = ifg

    await tb.reset()

    for k in range(100):
        await RisingEdge(dut.clk)

    tb.dut.cfg_tx_enable.value = 1

    total_bytes = 0
    total_pkts = 0

    for length in range(60, 92):

        for k in range(10):
            await RisingEdge(dut.clk)

        test_frames = [payload_data(length) for k in range(10)]
        start_lane = []

        for test_data in test_frames:
            await tb.source.send(AxiStreamFrame(test_data, tid=0, tuser=0))
            total_bytes += max(len(test_data), 60)+4
            total_pkts += 1

        for test_data in test_frames:
            rx_frame = await tb.sink.recv()
            tx_cpl = await tb.tx_cpl_sink.recv()

            ptp_ts_ns = int(tx_cpl.tdata[0]) / 2**16

            rx_frame_sfd_ns = get_time_from_sim_steps(rx_frame.sim_time_sfd, "ns")

            tb.log.info("TX frame PTP TS: %f ns", ptp_ts_ns)
            tb.log.info("RX frame SFD sim time: %f ns", rx_frame_sfd_ns)
            tb.log.info("Difference: %f ns", abs(rx_frame_sfd_ns - ptp_ts_ns))

            assert rx_frame.get_payload() == test_data
            assert rx_frame.check_fcs()
            assert rx_frame.ctrl is None
            assert abs(rx_frame_sfd_ns - ptp_ts_ns - tb.clk_period*1) < 0.001

            start_lane.append(rx_frame.start_lane)

        tb.log.info("length: %d", length)
        tb.log.info("start_lane: %s", start_lane)

        start_lane_ref = []

        # compute expected starting lanes
        lane = 0
        deficit_idle_count = 0

        for test_data in test_frames:
            if ifg == 0:
                lane = 0

            start_lane_ref.append(lane)
            lane = (lane + len(test_data)+4+ifg) % byte_width

            if enable_dic:
                offset = lane % 4
                if deficit_idle_count+offset >= 4:
                    offset += 4
                lane = (lane - offset) % byte_width
                deficit_idle_count = (deficit_idle_count + offset) % 4
            else:
                offset = lane % 4
                if offset > 0:
                    offset += 4
                lane = (lane - offset) % byte_width

        tb.log.info("start_lane_ref: %s", start_lane_ref)

        assert start_lane_ref == start_lane

        await RisingEdge(dut.clk)

    assert tb.sink.empty()

    for stat, val in tb.stats.items():
        tb.log.info("%s: %d", stat, val)

    assert tb.stats["stat_tx_byte"] == total_bytes
    assert tb.stats["stat_tx_pkt_len"] == total_bytes
    assert tb.stats["stat_tx_pkt_ucast"] == total_pkts
    assert tb.stats["stat_tx_pkt_mcast"] == 0
    assert tb.stats["stat_tx_pkt_bcast"] == 0
    assert tb.stats["stat_tx_pkt_vlan"] == 0
    assert tb.stats["stat_tx_pkt_good"] == total_pkts
    assert tb.stats["stat_tx_pkt_bad"] == 0
    assert tb.stats["stat_tx_err_oversize"] == 0
    assert tb.stats["stat_tx_err_user"] == 0
    assert tb.stats["stat_tx_err_underflow"] == 0

    for k in range(10):
        await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("ifg", [12]),
    ("usxgmii_speed", usxgmii_speeds),
    ("gbx_cfg", gbx_cfgs),
)
async def run_test_underrun(dut, gbx_cfg=None, usxgmii_speed=None, ifg=12):

    tb = TB(dut, gbx_cfg, usxgmii_speed)

    tb.dut.cfg_tx_max_pkt_len.value = 9218-1
    tb.dut.cfg_tx_ifg.value = ifg

    await tb.reset()

    for k in range(100):
        await RisingEdge(dut.clk)

    tb.dut.cfg_tx_enable.value = 1

    test_data = bytes(x for x in range(60))

    for k in range(3):
        test_frame = AxiStreamFrame(test_data)
        await tb.source.send(test_frame)

    for k in range(16*(tb.sink.get_xgmii_rep_count()+1)):
        await RisingEdge(dut.clk)

    tb.source.pause = True

    for k in range(4*(tb.sink.get_xgmii_rep_count()+1)):
        await RisingEdge(dut.clk)

    tb.source.pause = False

    for k in range(3):
        rx_frame = await tb.sink.recv()

        if k == 1:
            assert rx_frame.data[-1] == 0xFE
            assert rx_frame.ctrl[-1] == 1
        else:
            assert rx_frame.get_payload() == test_data
            assert rx_frame.check_fcs()
            assert rx_frame.ctrl is None

    assert tb.sink.empty()

    for stat, val in tb.stats.items():
        tb.log.info("%s: %d", stat, val)

    assert tb.stats["stat_tx_byte"] > 64*2 + 8
    assert tb.stats["stat_tx_pkt_len"] > 64*2 + 8
    assert tb.stats["stat_tx_pkt_ucast"] == 3
    assert tb.stats["stat_tx_pkt_mcast"] == 0
    assert tb.stats["stat_tx_pkt_bcast"] == 0
    assert tb.stats["stat_tx_pkt_vlan"] == 0
    assert tb.stats["stat_tx_pkt_good"] == 2
    assert tb.stats["stat_tx_pkt_bad"] == 1
    assert tb.stats["stat_tx_err_oversize"] == 0
    assert tb.stats["stat_tx_err_user"] == 0
    assert tb.stats["stat_tx_err_underflow"] == 1

    for k in range(10):
        await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("ifg", [12]),
    ("usxgmii_speed", usxgmii_speeds),
    ("gbx_cfg", gbx_cfgs),
)
async def run_test_error(dut, gbx_cfg=None, usxgmii_speed=None, ifg=12):

    tb = TB(dut, gbx_cfg, usxgmii_speed)

    tb.dut.cfg_tx_max_pkt_len.value = 9218-1
    tb.dut.cfg_tx_ifg.value = ifg

    await tb.reset()

    for k in range(100):
        await RisingEdge(dut.clk)

    tb.dut.cfg_tx_enable.value = 1

    test_data = bytes(x for x in range(60))

    for k in range(3):
        test_frame = AxiStreamFrame(test_data)
        if k == 1:
            test_frame.tuser = 1
        await tb.source.send(test_frame)

    for k in range(3):
        rx_frame = await tb.sink.recv()

        if k == 1:
            assert rx_frame.data[-1] == 0xFE
            assert rx_frame.ctrl[-1] == 1
        else:
            assert rx_frame.get_payload() == test_data
            assert rx_frame.check_fcs()
            assert rx_frame.ctrl is None

    assert tb.sink.empty()

    for stat, val in tb.stats.items():
        tb.log.info("%s: %d", stat, val)

    assert tb.stats["stat_tx_byte"] > 64*2 + 32
    assert tb.stats["stat_tx_pkt_len"] > 64*2 + 32
    assert tb.stats["stat_tx_pkt_ucast"] == 3
    assert tb.stats["stat_tx_pkt_mcast"] == 0
    assert tb.stats["stat_tx_pkt_bcast"] == 0
    assert tb.stats["stat_tx_pkt_vlan"] == 0
    assert tb.stats["stat_tx_pkt_good"] == 2
    assert tb.stats["stat_tx_pkt_bad"] == 1
    assert tb.stats["stat_tx_err_oversize"] == 0
    assert tb.stats["stat_tx_err_user"] == 1
    assert tb.stats["stat_tx_err_underflow"] == 0

    for k in range(10):
        await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("ifg", [12]),
    ("usxgmii_speed", usxgmii_speeds),
    ("gbx_cfg", gbx_cfgs),
)
async def run_test_oversize(dut, gbx_cfg=None, usxgmii_speed=None, ifg=12):

    tb = TB(dut, gbx_cfg, usxgmii_speed)

    tb.dut.cfg_tx_max_pkt_len.value = 1518-1
    tb.dut.cfg_tx_ifg.value = ifg

    await tb.reset()

    for k in range(100):
        await RisingEdge(dut.clk)

    tb.dut.cfg_tx_enable.value = 1

    for max_len in range(128-4-8, 128-4+9):

        tb.stats_reset()

        total_bytes = 0
        total_pkts = 0
        good_bytes = 0
        oversz_pkts = 0
        oversz_bytes_in = 0
        oversz_bytes_out = 0

        for test_pkt_len in range(max_len-8, max_len+9):

            tb.log.info("max len %d (without FCS), test len %d (without FCS)", max_len, test_pkt_len)

            tb.dut.cfg_tx_max_pkt_len.value = max_len+4-1

            test_data_1 = bytes(x for x in range(60))
            test_data_2 = bytes(x for x in range(test_pkt_len))

            for k in range(3):
                if k == 1:
                    test_data = test_data_2
                else:
                    test_data = test_data_1
                test_frame = AxiStreamFrame(test_data)
                await tb.source.send(test_frame)
                total_bytes += max(len(test_data), 60)+4
                total_pkts += 1
                if len(test_data) > max_len:
                    oversz_pkts += 1
                    oversz_bytes_in += len(test_data)+4
                    oversz_bytes_out += max_len
                else:
                    good_bytes += len(test_data)+4

            for k in range(3):
                rx_frame = await tb.sink.recv()

                if k == 1:
                    if test_pkt_len > max_len:
                        assert rx_frame.data[-1] == 0xFE
                        assert rx_frame.ctrl[-1] == 1
                    else:
                        assert rx_frame.get_payload() == test_data_2
                        assert rx_frame.check_fcs()
                        assert rx_frame.ctrl is None
                else:
                    assert rx_frame.get_payload() == test_data_1
                    assert rx_frame.check_fcs()
                    assert rx_frame.ctrl is None

        assert tb.sink.empty()

        for stat, val in tb.stats.items():
            tb.log.info("%s: %d", stat, val)

        assert tb.stats["stat_tx_byte"] >= good_bytes+oversz_bytes_out-8*oversz_pkts
        assert tb.stats["stat_tx_byte"] <= good_bytes+oversz_bytes_in
        assert tb.stats["stat_tx_pkt_len"] >= good_bytes+oversz_bytes_out-8*oversz_pkts
        assert tb.stats["stat_tx_pkt_len"] <= good_bytes+oversz_bytes_in
        assert tb.stats["stat_tx_pkt_ucast"] == total_pkts
        assert tb.stats["stat_tx_pkt_mcast"] == 0
        assert tb.stats["stat_tx_pkt_bcast"] == 0
        assert tb.stats["stat_tx_pkt_vlan"] == 0
        assert tb.stats["stat_tx_pkt_good"] == total_pkts - oversz_pkts
        assert tb.stats["stat_tx_pkt_bad"] == oversz_pkts
        assert tb.stats["stat_tx_err_oversize"] == oversz_pkts
        assert tb.stats["stat_tx_err_user"] == 0
        assert tb.stats["stat_tx_err_underflow"] == 0

    for k in range(10):
        await RisingEdge(dut.clk)


@cocotb.test()
@cocotb.parametrize(
    ("usxgmii_speed", usxgmii_speeds),
    ("gbx_cfg", gbx_cfgs),
)
async def run_test_os(dut, gbx_cfg=None, usxgmii_speed=None):

    tb = TB(dut, gbx_cfg, usxgmii_speed)

    await tb.reset()

    for sig in [False, True]:
        for k in range(24):
            os = 1 << k

            dut.tx_os.value = os
            dut.tx_os_sig.value = sig
            dut.tx_os_valid.value = 1

            for k in range(20):
                await RisingEdge(dut.clk)

            assert tb.sink.get_os() == (os, sig)

            dut.tx_os_valid.value = 0

            for k in range(20):
                await RisingEdge(dut.clk)

    for k in range(10):
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


@pytest.mark.parametrize("dic_en", [1, 0])
@pytest.mark.parametrize("gbx_en", [1, 0])
def test_taxi_axis_baser_tx_64(request, gbx_en, dic_en):
    dut = "taxi_axis_baser_tx_64"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(taxi_src_dir, "lfsr", "rtl", "taxi_lfsr.sv"),
        os.path.join(taxi_src_dir, "axis", "rtl", "taxi_axis_if.sv"),
    ]

    sources = process_f_files(sources)

    parameters = {}

    parameters['DATA_W'] = 64
    parameters['HDR_W'] = 2
    parameters['GBX_IF_EN'] = gbx_en
    parameters['GBX_CNT'] = 1
    parameters['USXGMII_EN'] = 1
    parameters['DIC_EN'] = dic_en
    parameters['PTP_TS_EN'] = 1
    parameters['PTP_TS_FMT_TOD'] = 1
    parameters['PTP_TS_W'] = 96 if parameters['PTP_TS_FMT_TOD'] else 64
    parameters['PTP_TS_COR_EN'] = 1
    parameters['PTP_TS_COR_W'] = 16+4
    parameters['TX_TAG_W'] = 16
    parameters['TX_CPL_CTRL_IN_TUSER'] = 1

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}

    sim_build = os.path.join(tests_dir, "sim_build",
        request.node.name.replace('[', '-').replace(']', ''))

    timescale = ("1ns", "1fs")
    sim = os.getenv("SIM", "verilator")
    waves = bool(int(os.getenv("WAVES", 0)))

    sys.path.append(tests_dir)

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=toplevel,
        parameters=parameters,
        always=True,
        build_dir=sim_build,
        timescale=timescale,
        waves=waves,
    )
    runner.test(
        hdl_toplevel=toplevel,
        test_module=module,
        parameters=parameters,
        extra_env=extra_env,
        build_dir=sim_build,
        timescale=timescale,
        waves=waves,
    )
