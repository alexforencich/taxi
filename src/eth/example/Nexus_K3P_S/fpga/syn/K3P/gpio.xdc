# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Cisco Nexus K3P-S / ExaNIC X25
# part: xcku3p-ffvb676-2-e

# LEDs
set_property -dict {LOC J12 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {sfp_led[0][0]}]
set_property -dict {LOC H12 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {sfp_led[0][1]}]
set_property -dict {LOC J13 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {sfp_led[1][0]}]
set_property -dict {LOC H13 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {sfp_led[1][1]}]
set_property -dict {LOC J14 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {sma_led[0]}]
set_property -dict {LOC G12 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {sma_led[1]}]

set_false_path -to [get_ports {sfp_led[*][*] sma_led[*]}]
set_output_delay 0 [get_ports {sfp_led[*][*] sma_led[*]}]

# GPIO
#set_property -dict {LOC F9   IOSTANDARD LVCMOS18} [get_ports {gpio[0]}]
#set_property -dict {LOC F10  IOSTANDARD LVCMOS18} [get_ports {gpio[1]}]
#set_property -dict {LOC G9   IOSTANDARD LVCMOS18} [get_ports {gpio[2]}]
#set_property -dict {LOC G10  IOSTANDARD LVCMOS18} [get_ports {gpio[3]}]

# SMA
#set_property -dict {LOC A14  IOSTANDARD LVCMOS33} [get_ports {sma_in}]
#set_property -dict {LOC A12  IOSTANDARD LVCMOS33 SLEW FAST DRIVE 12} [get_ports {sma_out}]
#set_property -dict {LOC A13  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {sma_out_en}]
#set_property -dict {LOC B12  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {sma_term_en}]

#set_false_path -to [get_ports {sma_out sma_out_en sma_term_en}]
#set_output_delay 0 [get_ports {sma_out sma_out_en sma_term_en}]
#set_false_path -from [get_ports {sma_in}]
#set_input_delay 0 [get_ports {sma_in}]

# Config
#set_property -dict {LOC C14  IOSTANDARD LVCMOS33} [get_ports {ddr_npres}]
