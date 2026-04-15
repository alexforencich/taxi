# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Cisco Nexus K35-S / ExaNIC X10
# part: xcku035-fbva676-2-e

# LEDs
set_property -dict {LOC A25 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_led[0][0]}]
set_property -dict {LOC A24 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_led[0][1]}]
set_property -dict {LOC E23 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_led[1][0]}]
set_property -dict {LOC D26 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_led[1][1]}]
set_property -dict {LOC C23 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sma_led[0]}]
set_property -dict {LOC D23 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sma_led[1]}]

set_false_path -to [get_ports {sfp_led[*][*] sma_led[*]}]
set_output_delay 0 [get_ports {sfp_led[*][*] sma_led[*]}]

# GPIO
#set_property -dict {LOC W26  IOSTANDARD LVCMOS18} [get_ports {gpio[0]}]
#set_property -dict {LOC Y26  IOSTANDARD LVCMOS18} [get_ports {gpio[1]}]
#set_property -dict {LOC AB26 IOSTANDARD LVCMOS18} [get_ports {gpio[2]}]
#set_property -dict {LOC AC26 IOSTANDARD LVCMOS18} [get_ports {gpio[3]}]

# SMA
#set_property -dict {LOC B17  IOSTANDARD LVCMOS18} [get_ports {sma_in}]
#set_property -dict {LOC B16  IOSTANDARD LVCMOS18 SLEW FAST DRIVE 12} [get_ports {sma_out}]
#set_property -dict {LOC B19  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sma_out_en}]
#set_property -dict {LOC C16  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sma_term_en}]

#set_false_path -to [get_ports {sma_out sma_out_en sma_term_en}]
#set_output_delay 0 [get_ports {sma_out sma_out_en sma_term_en}]
#set_false_path -from [get_ports {sma_in}]
#set_input_delay 0 [get_ports {sma_in}]
