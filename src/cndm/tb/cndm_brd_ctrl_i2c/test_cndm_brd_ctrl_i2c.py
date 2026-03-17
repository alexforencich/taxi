#!/usr/bin/env python
# SPDX-License-Identifier: CERN-OHL-S-2.0
"""

Copyright (c) 2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

"""

import logging
import os
import struct

import cocotb_test.simulator

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink
from cocotbext.axi.utils import hexdump_str
from cocotbext.i2c import I2cMemory


CMD_BRD_OP_NOP = 0x0000

CMD_BRD_OP_FLASH_RD  = 0x0100
CMD_BRD_OP_FLASH_WR  = 0x0101
CMD_BRD_OP_FLASH_CMD = 0x0108

CMD_BRD_OP_EEPROM_RD = 0x0200
CMD_BRD_OP_EEPROM_WR = 0x0201

CMD_BRD_OP_OPTIC_RD = 0x0300
CMD_BRD_OP_OPTIC_WR = 0x0301

CMD_BRD_OP_HWID_SN_RD  = 0x0400
CMD_BRD_OP_HWID_VPD_RD = 0x0410
CMD_BRD_OP_HWID_MAC_RD = 0x0480

CMD_BRD_OP_PLL_STATUS_RD   = 0x0500
CMD_BRD_OP_PLL_TUNE_RAW_RD = 0x0502
CMD_BRD_OP_PLL_TUNE_RAW_WR = 0x0503
CMD_BRD_OP_PLL_TUNE_PPT_RD = 0x0504
CMD_BRD_OP_PLL_TUNE_PPT_WR = 0x0505

CMD_BRD_OP_I2C_RD = 0x8100
CMD_BRD_OP_I2C_WR = 0x8101


class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.brd_ctrl_cmd = AxiStreamSource(AxiStreamBus(dut.s_axis_cmd), dut.clk, dut.rst)
        self.brd_ctrl_rsp = AxiStreamSink(AxiStreamBus(dut.m_axis_rsp), dut.clk, dut.rst)

        self.i2c_eeprom = I2cMemory(sda=dut.i2c_sda_o, sda_o=dut.i2c_sda_i,
            scl=dut.i2c_scl_o, scl_o=dut.i2c_scl_i, addr=0x54, size=256)
        self.sfp0 = I2cMemory(sda=dut.i2c_sda_o, sda_o=dut.i2c_sda_i,
            scl=dut.i2c_scl_o, scl_o=dut.i2c_scl_i, addr=0x50, size=256)
        self.sfp1 = I2cMemory(sda=dut.i2c_sda_o, sda_o=dut.i2c_sda_i,
            scl=dut.i2c_scl_o, scl_o=dut.i2c_scl_i, addr=0x51, size=256)
        self.si570 = I2cMemory(sda=dut.i2c_sda_o, sda_o=dut.i2c_sda_i,
            scl=dut.i2c_scl_o, scl_o=dut.i2c_scl_i, addr=0x5D, size=256)
        self.mux1 = I2cMemory(sda=dut.i2c_sda_o, sda_o=dut.i2c_sda_i,
            scl=dut.i2c_scl_o, scl_o=dut.i2c_scl_i, addr=0x74, size=256)
        self.mux2 = I2cMemory(sda=dut.i2c_sda_o, sda_o=dut.i2c_sda_i,
            scl=dut.i2c_scl_o, scl_o=dut.i2c_scl_i, addr=0x75, size=256)

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

    tb.i2c_eeprom.write_mem(0, bytes.fromhex("""
        37 35 37 35 31 39 32 37 31 37 33 32 2d 36 39 39
        39 36 20 20 20 20 20 20 20 20 20 20 20 20 20 20
        00 0a 35 03 72 c9 00 00 00 00 00 00 00 00 00 00
        54 53 53 30 31 36 35 2d 30 32 20 20 20 20 20 20
        5b 31 31 31 31 31 31 31 31 31 5d 20 20 20 20 20
        57 65 64 2c 20 31 36 20 41 75 67 20 32 30 31 37
        31 30 3a 33 35 3a 35 36 2b 30 38 30 30 20 20 20
        ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
        ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
        ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
        ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
        ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
        ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
        4b 43 55 31 30 35 20 20 20 20 20 20 20 20 20 20
        31 2e 31 20 20 20 20 20 20 20 20 20 20 20 20 20
        ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
    """))

    tb.sfp0.write_mem(0, bytes.fromhex("""
        03 04 21 00 00 00 00 00 04 00 00 00 67 00 00 00
        00 00 03 00 41 6d 70 68 65 6e 6f 6c 20 20 20 20
        20 20 20 20 00 41 50 48 35 37 31 35 34 30 30 30
        32 20 20 20 20 20 20 20 4b 20 20 20 01 00 00 f7
        00 00 00 00 41 50 46 30 39 34 38 30 30 32 30 32
        37 39 20 20 30 39 31 31 32 34 20 20 00 00 00 c1
        ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
        ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff 00
    """ + " ff"*128))

    tb.sfp1.write_mem(0, bytes.fromhex("""
        03 04 21 00 00 00 00 00 04 00 00 00 67 00 00 00
        00 00 03 00 41 6d 70 68 65 6e 6f 6c 20 20 20 20
        20 20 20 20 00 41 50 48 35 37 31 35 34 30 30 30
        32 20 20 20 20 20 20 20 4b 20 20 20 01 00 00 f7
        00 00 00 00 41 50 46 30 39 34 38 30 30 32 30 32
        37 39 20 20 30 39 31 31 32 34 20 20 00 00 00 c1
        ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
        ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff 00
    """ + " ff"*128))

    tb.si570.write_mem(0, bytes.fromhex("""
        4f 02 32 a1 3d 20 00 01 c2 bb ff 84 82 07 c2 c0
        00 00 00 00 c2 c0 00 00 00 07 c2 c0 00 00 00 0c
        b9 09 80 00 00 00 00 00 00 00 00 00 00 00 00 00
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        20 7f 86 81 7b 81 03 00 10 08 00 00 00 00 02 bb
        ff 84 82 00 00 00 62 00 00 00 00 00 00 00 00 00
    """))

    tb.log.info("Read MAC")
    cmd = struct.pack("<HHLbbbbLLL",
        0, # index
        CMD_BRD_OP_HWID_MAC_RD, # opcode
        0, # flags
        0, # page
        0, # bank
        0, # dev addr offset
        0, # rsvd
        0, # addr
        0, # len
        0, # rsvd
    )

    await tb.brd_ctrl_cmd.send(cmd)
    rsp = await tb.brd_ctrl_rsp.recv()

    tb.log.info("Response: %s", rsp)
    tb.log.info("MAC: %s", ':'.join(x.hex() for x in struct.unpack_from('6c', rsp.tdata, 24+2)))

    tb.log.info("Read SN")
    cmd = struct.pack("<HHLbbbbLLL",
        0, # index
        CMD_BRD_OP_HWID_SN_RD, # opcode
        0, # flags
        0, # page
        0, # bank
        0, # dev addr offset
        0, # rsvd
        0, # addr
        0, # len
        0, # rsvd
    )

    await tb.brd_ctrl_cmd.send(cmd)
    rsp = await tb.brd_ctrl_rsp.recv()

    tb.log.info("Response: %s", rsp)
    tb.log.info("SN: %s", rsp.tdata[24:24+32].strip(b' \x00'))

    tb.log.info("Read EEPROM")
    cmd = struct.pack("<HHLbbbbLLL",
        0, # index
        CMD_BRD_OP_EEPROM_RD, # opcode
        0, # flags
        0, # page
        0, # bank
        0, # dev addr offset
        0, # rsvd
        0x00, # addr
        32, # len
        0, # rsvd
    )

    await tb.brd_ctrl_cmd.send(cmd)
    rsp = await tb.brd_ctrl_rsp.recv()

    tb.log.info("Response: %s", rsp)
    tb.log.info("Data: %s", rsp.tdata[24:24+32])

    tb.log.info("Read SFP0")
    cmd = struct.pack("<HHLbbbbLLL",
        0, # index
        CMD_BRD_OP_OPTIC_RD, # opcode
        0, # flags
        0, # page
        0, # bank
        0, # dev addr offset
        0, # rsvd
        0x00, # addr
        32, # len
        0, # rsvd
    )

    await tb.brd_ctrl_cmd.send(cmd)
    rsp = await tb.brd_ctrl_rsp.recv()

    tb.log.info("Response: %s", rsp)
    tb.log.info("Data: %s", rsp.tdata[24:24+32])

    tb.log.info("Read SFP1")
    cmd = struct.pack("<HHLbbbbLLL",
        1, # index
        CMD_BRD_OP_OPTIC_RD, # opcode
        0, # flags
        0, # page
        0, # bank
        0, # dev addr offset
        0, # rsvd
        0x00, # addr
        32, # len
        0, # rsvd
    )

    await tb.brd_ctrl_cmd.send(cmd)
    rsp = await tb.brd_ctrl_rsp.recv()

    tb.log.info("Response: %s", rsp)
    tb.log.info("Data: %s", rsp.tdata[24:24+32])

    tb.log.info("Write EEPROM")
    data = b"EEPROM write data"

    cmd = struct.pack("<HHLbbbbLLL",
        0, # index
        CMD_BRD_OP_EEPROM_WR, # opcode
        0, # flags
        0, # page
        0, # bank
        0, # dev addr offset
        0, # rsvd
        0x80, # addr
        len(data), # len
        0, # rsvd
    )+data

    await tb.brd_ctrl_cmd.send(cmd)
    rsp = await tb.brd_ctrl_rsp.recv()

    tb.log.info("Response: %s", rsp)

    tb.log.info("Write SFP0")
    data = b"SFP0 write data"

    cmd = struct.pack("<HHLbbbbLLL",
        0, # index
        CMD_BRD_OP_OPTIC_WR, # opcode
        0, # flags
        0, # page
        0, # bank
        0, # dev addr offset
        0, # rsvd
        0x80, # addr
        len(data), # len
        0, # rsvd
    )+data

    await tb.brd_ctrl_cmd.send(cmd)
    rsp = await tb.brd_ctrl_rsp.recv()

    tb.log.info("Response: %s", rsp)

    tb.log.info("Write SFP1")
    data = b"SFP1 write data"

    cmd = struct.pack("<HHLbbbbLLL",
        1, # index
        CMD_BRD_OP_OPTIC_WR, # opcode
        0, # flags
        0, # page
        0, # bank
        0, # dev addr offset
        0, # rsvd
        0x80, # addr
        len(data), # len
        0, # rsvd
    )+data

    await tb.brd_ctrl_cmd.send(cmd)
    rsp = await tb.brd_ctrl_rsp.recv()

    tb.log.info("Response: %s", rsp)

    for k in range(1000):
        await RisingEdge(dut.clk)

    tb.log.info("EEPROM data:")
    tb.log.info(hexdump_str(tb.i2c_eeprom.mem, 0, 256))

    tb.log.info("PLL data:")
    tb.log.info(hexdump_str(tb.si570.mem, 0, 256))

    tb.log.info("SFP0 data:")
    tb.log.info(hexdump_str(tb.sfp0.mem, 0, 256))

    tb.log.info("SFP1 data:")
    tb.log.info(hexdump_str(tb.sfp1.mem, 0, 256))

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


def test_cndm_brd_ctrl_i2c(request):
    dut = "cndm_brd_ctrl_i2c"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = module

    verilog_sources = [
        os.path.join(tests_dir, f"{toplevel}.sv"),
        os.path.join(rtl_dir, f"{dut}.f"),
    ]

    verilog_sources = process_f_files(verilog_sources)

    parameters = {}

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
