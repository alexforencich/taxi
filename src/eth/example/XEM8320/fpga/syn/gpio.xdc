# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Opal Kelley XEM8320 board
# part: xcau25p-ffvb676-2-e

# LEDs
set_property -dict {LOC G19  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[0]}] ;# to D1
set_property -dict {LOC B16  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[1]}] ;# to D2
set_property -dict {LOC F22  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[2]}] ;# to D3
set_property -dict {LOC E22  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[3]}] ;# to D4
set_property -dict {LOC M24  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[4]}] ;# to D5
set_property -dict {LOC G22  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[5]}] ;# to D6

set_false_path -to [get_ports {led[*]}]
set_output_delay 0 [get_ports {led[*]}]
