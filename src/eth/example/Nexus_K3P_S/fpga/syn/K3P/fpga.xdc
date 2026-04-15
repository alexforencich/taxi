# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Cisco Nexus K3P-S / ExaNIC X25
# part: xcku3p-ffvb676-2-e

# General configuration
set_property CFGBVS GND                                      [current_design]
set_property CONFIG_VOLTAGE 1.8                              [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true                 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup               [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 31.9                [current_design]
set_property BITSTREAM.CONFIG.BPI_PAGE_SIZE 8                [current_design]
set_property BITSTREAM.CONFIG.BPI_1ST_READ_CYCLE 4           [current_design]
set_property CONFIG_MODE BPI16                               [current_design]
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable        [current_design]

# 10 MHz TXCO
#set_property -dict {LOC D14  IOSTANDARD LVCMOS33} [get_ports clk_10mhz]
#create_clock -period 100 -name clk_100mhz [get_ports clk_10mhz]
