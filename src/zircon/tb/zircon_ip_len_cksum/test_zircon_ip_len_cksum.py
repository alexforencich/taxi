#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import logging
import os
import struct

import scapy.config
import scapy.utils
import scapy.pton_ntop
from scapy.layers.l2 import Ether, Dot1Q, Dot1AD, ARP
from scapy.layers.inet import IP, ICMP, UDP, TCP
from scapy.layers.inet import IPOption_MTU_Probe
from scapy.layers.inet6 import IPv6, ICMPv6ND_NS
from scapy.layers.inet6 import IPv6ExtHdrFragment, IPv6ExtHdrHopByHop, RouterAlert

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamFrame


# don't hide ports
scapy.config.conf.noenum.add(TCP.sport, TCP.dport)
scapy.config.conf.noenum.add(UDP.sport, UDP.dport)


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 3.2, units="ns").start())

        self.pkt_source = AxiStreamSource(AxiStreamBus.from_entity(dut.s_axis_pkt), dut.clk, dut.rst)
        self.pkt_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis_pkt), dut.clk, dut.rst)
        self.meta_sink = AxiStreamSink(AxiStreamBus.from_entity(dut.m_axis_meta), dut.clk, dut.rst)

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


@cocotb.test()
async def run_test(dut):

    tb = TB(dut)

    await tb.reset()

    test_pkts = []

    payload = bytearray(range(64))

    ip_id = 0

    l2hdrs = []

    # Ethernet
    eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5')
    l2hdrs.append(eth)

    # Ethernet with 802.1Q VLAN
    eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5')
    vlan = Dot1Q(vlan=123)
    l2hdrs.append(eth / vlan)

    # Ethernet with 802.1Q QinQ
    eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5')
    vlan = Dot1AD(vlan=456)
    l2hdrs.append(eth / vlan)

    # Ethernet with 802.1Q QinQ and VLAN
    eth = Ether(src='5A:51:52:53:54:55', dst='DA:D1:D2:D3:D4:D5')
    vlan = Dot1AD(vlan=456) / Dot1Q(vlan=123)
    l2hdrs.append(eth / vlan)

    for l2hdr in l2hdrs:

        # Raw ethernet
        test_pkts.append(l2hdr / payload)

        # ARP
        arp = ARP(hwtype=1, ptype=0x0800, hwlen=6, plen=4, op=2,
            hwsrc='5A:51:52:53:54:55', psrc='192.168.1.100',
            hwdst='DA:D1:D2:D3:D4:D5', pdst='192.168.1.101')
        test_pkts.append(l2hdr / arp)

        l3hdrs = []

        # IPv4
        ip = IP(src='10.1.0.1', dst='10.2.0.1', id=ip_id)
        l3hdrs.append(ip)

        # IPv4 (fragmented)
        ip = IP(src='10.1.0.1', dst='10.2.0.1', flags=1, id=ip_id)
        l3hdrs.append(ip)

        # IPv4 with options
        ip = IP(src='10.1.0.1', dst='10.2.0.1', id=ip_id, options=[IPOption_MTU_Probe()])
        l3hdrs.append(ip)

        # IPv6
        ip6 = IPv6(src='fd12:3456:789a:1::1', dst='fd12:3456:789a:2::1', fl=ip_id)
        l3hdrs.append(ip6)

        # IPv6 with extensions (fragmented)
        ip6 = IPv6(src='fd12:3456:789a:1::1', dst='fd12:3456:789a:2::1', fl=ip_id)
        frag = IPv6ExtHdrFragment()
        l3hdrs.append(ip6 / frag)

        # IPv6 with extensions
        ip6 = IPv6(src='fd12:3456:789a:1::1', dst='fd12:3456:789a:2::1', fl=ip_id)
        hbh = IPv6ExtHdrHopByHop(options=[RouterAlert()])
        l3hdrs.append(ip6 / hbh)

        # IPv6 with extensions 2
        ip6 = IPv6(src='fd12:3456:789a:1::1', dst='fd12:3456:789a:2::1', fl=ip_id)
        hbh = IPv6ExtHdrHopByHop(options=[RouterAlert(), RouterAlert(), RouterAlert(), RouterAlert()])
        l3hdrs.append(ip6 / hbh)

        for l3hdr in l3hdrs:

            l3hdr = l3hdr.copy()
            if IP in l3hdr:
                l3hdr.id = ip_id
            if IPv6 in l3hdr:
                l3hdr.fl = ip_id

            # IP (empty)
            if IP in l3hdr:
                hdr = l3hdr.copy()
                hdr.proto = 59
                test_pkts.append(l2hdr / hdr)
            else:
                test_pkts.append(l2hdr / l3hdr)

            # IP (unsupported protocol)
            if IP in l3hdr:
                hdr = l3hdr.copy()
                hdr.proto = 59
                test_pkts.append(l2hdr / hdr / payload)
            else:
                test_pkts.append(l2hdr / l3hdr / payload)

            if IP in l3hdr:
                # ICMP
                icmp = ICMP(type=8)
                test_pkts.append(l2hdr / l3hdr / icmp / payload)

            if IPv6 in l3hdr:
                # ICMPv6 / NDP
                ns = ICMPv6ND_NS(tgt='::')
                test_pkts.append(l2hdr / l3hdr / ns)

            # UDP (empty)
            udp = UDP(sport=ip_id, dport=0x1000+ip_id)
            test_pkts.append(l2hdr / l3hdr / udp)

            # UDP
            udp = UDP(sport=ip_id, dport=0x1000+ip_id)
            test_pkts.append(l2hdr / l3hdr / udp / payload)

            # TCP (empty)
            tcp = TCP(sport=ip_id, dport=0x1000+ip_id, seq=54321, ack=12345, window=8192)
            test_pkts.append(l2hdr / l3hdr / tcp)

            # TCP with options (empty)
            tcp = TCP(sport=ip_id, dport=0x1000+ip_id, seq=54321, ack=12345, window=8192, options=[('Timestamp',(0,0))])
            test_pkts.append(l2hdr / l3hdr / tcp)

            # TCP
            tcp = TCP(sport=ip_id, dport=0x1000+ip_id, seq=54321, ack=12345, window=8192)
            test_pkts.append(l2hdr / l3hdr / tcp / payload)

            # TCP with options
            tcp = TCP(sport=ip_id, dport=0x1000+ip_id, seq=54321, ack=12345, window=8192, options=[('Timestamp',(0,0))])
            test_pkts.append(l2hdr / l3hdr / tcp / payload)

            ip_id += 1

    for pkt in test_pkts:
        tb.log.info("Packet: %r", pkt)

        pkt_b = pkt.build()

        rx_csum = ~scapy.utils.checksum(bytes(pkt_b[14:])) & 0xffff

        await tb.pkt_source.send(AxiStreamFrame(pkt_b))

        meta = await tb.meta_sink.recv()

        tb.log.info("Metadata: %r", meta)

        pkt_len, pkt_sum = struct.unpack_from('<HH', meta.tdata, 0)

        tb.log.info("Payload length: %d", pkt_len)
        tb.log.info("Packet checksum: 0x%04x", pkt_sum)

        assert pkt_len == len(pkt_b)
        assert pkt_sum == rx_csum

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


@pytest.mark.parametrize("data_w", [32, 64, 128, 256, 512])
def test_zircon_ip_len_cksum(request, data_w):
    dut = "zircon_ip_len_cksum"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.sv"),
        os.path.join(taxi_src_dir, "axis", "rtl", "taxi_axis_tie.sv"),
        os.path.join(taxi_src_dir, "axis", "rtl", "taxi_axis_if.sv"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

    parameters['DATA_W'] = data_w
    parameters['META_W'] = 32
    parameters['START_OFFSET'] = 14

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
