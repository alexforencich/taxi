# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Xilinx ZCU102 board
# part: xczu9eg-ffvb1156-2-e

# PMOD0
set_property -dict {LOC A20  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod0[0]}] ;# J55.1
set_property -dict {LOC B20  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod0[1]}] ;# J55.3
set_property -dict {LOC A22  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod0[2]}] ;# J55.5
set_property -dict {LOC A21  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod0[3]}] ;# J55.7
set_property -dict {LOC B21  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod0[4]}] ;# J55.2
set_property -dict {LOC C21  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod0[5]}] ;# J55.4
set_property -dict {LOC C22  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod0[6]}] ;# J55.6
set_property -dict {LOC D21  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod0[7]}] ;# J55.8

set_false_path -to [get_ports {pmod0[*]}]
set_output_delay 0 [get_ports {pmod0[*]}]
