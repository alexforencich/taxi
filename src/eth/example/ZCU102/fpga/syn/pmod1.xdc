# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Xilinx ZCU102 board
# part: xczu9eg-ffvb1156-2-e

# PMOD1
set_property -dict {LOC D20  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod1[0]}] ;# J87.1
set_property -dict {LOC E20  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod1[1]}] ;# J87.3
set_property -dict {LOC D22  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod1[2]}] ;# J87.5
set_property -dict {LOC E22  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod1[3]}] ;# J87.7
set_property -dict {LOC F20  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod1[4]}] ;# J87.2
set_property -dict {LOC G20  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod1[5]}] ;# J87.4
set_property -dict {LOC J20  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod1[6]}] ;# J87.6
set_property -dict {LOC J19  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {pmod1[7]}] ;# J87.8

set_false_path -to [get_ports {pmod1[*]}]
set_output_delay 0 [get_ports {pmod1[*]}]
