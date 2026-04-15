# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Xilinx ZCU102 board
# part: xczu9eg-ffvb1156-2-e

# "Prototype header" GPIO
set_property -dict {LOC H14  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {proto_gpio[0]}] ;# J3.6
set_property -dict {LOC J14  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {proto_gpio[1]}] ;# J3.8
set_property -dict {LOC G14  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {proto_gpio[2]}] ;# J3.10
set_property -dict {LOC G15  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {proto_gpio[3]}] ;# J3.12
set_property -dict {LOC J15  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {proto_gpio[4]}] ;# J3.14
set_property -dict {LOC J16  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {proto_gpio[5]}] ;# J3.16
set_property -dict {LOC G16  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {proto_gpio[6]}] ;# J3.18
set_property -dict {LOC H16  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {proto_gpio[7]}] ;# J3.20
set_property -dict {LOC G13  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {proto_gpio[8]}] ;# J3.22
set_property -dict {LOC H13  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {proto_gpio[9]}] ;# J3.24

set_false_path -to [get_ports {proto_gpio[*]}]
set_output_delay 0 [get_ports {proto_gpio[*]}]
