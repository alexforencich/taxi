# SPDX-License-Identifier: MIT
#
# Copyright (c) 2014-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the fb2CG@KU15P
# part: xcku15p-ffve1760-2-e

# General configuration
set_property CFGBVS GND                                [current_design]
set_property CONFIG_VOLTAGE 1.8                        [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true           [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN disable [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES       [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4           [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES        [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 85.0          [current_design]
set_property CONFIG_MODE SPIx4                         [current_design]
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable  [current_design]

# System clocks
# init clock 50 MHz
set_property -dict {LOC E7   IOSTANDARD LVCMOS18} [get_ports {init_clk}]
create_clock -period 20.000 -name init_clk [get_ports {init_clk}]

# E7 is not a global clock capable input, so need to set CLOCK_DEDICATED_ROUTE to satisfy DRC
#set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets init_clk_ibuf_inst/O]
set_property CLOCK_DEDICATED_ROUTE ANY_CMT_COLUMN [get_nets {init_clk_bufg}]

# DDR4 refclk1
#set_property -dict {LOC AT32 IOSTANDARD DIFF_SSTL12} [get_ports {clk_ddr4_refclk1_p}]
#set_property -dict {LOC AU32 IOSTANDARD DIFF_SSTL12} [get_ports {clk_ddr4_refclk1_n}]
#create_clock -period 3.750 -name clk_ddr4_refclk1 [get_ports {clk_ddr4_refclk1_p}]

# DDR4 refclk2
#set_property -dict {LOC G29  IOSTANDARD DIFF_SSTL12} [get_ports {clk_ddr4_refclk2_p}]
#set_property -dict {LOC G28  IOSTANDARD DIFF_SSTL12} [get_ports {clk_ddr4_refclk2_n}]
#create_clock -period 3.750 -name clk_ddr4_refclk2 [get_ports {clk_ddr4_refclk1_p}]
