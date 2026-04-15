# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Xilinx ZCU102 board
# part: xczu9eg-ffvb1156-2-e

# General configuration
set_property BITSTREAM.GENERAL.COMPRESS true           [current_design]

# System clocks
# 125 MHz
set_property -dict {LOC G21  IOSTANDARD LVDS_25} [get_ports clk_125mhz_p]
set_property -dict {LOC F21  IOSTANDARD LVDS_25} [get_ports clk_125mhz_n]
create_clock -period 8.000 -name clk_125mhz [get_ports clk_125mhz_p]
