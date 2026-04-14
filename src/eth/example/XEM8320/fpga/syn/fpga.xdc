# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Opal Kelley XEM8320 board
# part: xcau25p-ffvb676-2-e

# General configuration
set_property CFGBVS GND                                [current_design]
set_property CONFIG_VOLTAGE 1.8                        [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true           [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup         [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 85            [current_design]
set_property CONFIG_MODE SPIx4                         [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4           [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE Yes        [current_design]
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable  [current_design]

# System clocks
# 100 MHz system clock
set_property -dict {LOC T24  IOSTANDARD LVDS} [get_ports clk_100mhz_p] ;# from U42
set_property -dict {LOC U24  IOSTANDARD LVDS} [get_ports clk_100mhz_n] ;# from U42
create_clock -period 10.000 -name clk_100mhz [get_ports clk_100mhz_p]

# 100 MHz DDR4 clock
#set_property -dict {LOC AD20 IOSTANDARD DIFF_SSTL12} [get_ports clk_ddr4_p] ;# from U43
#set_property -dict {LOC AE20 IOSTANDARD DIFF_SSTL12} [get_ports clk_ddr4_n] ;# from U43
#create_clock -period 10.000 -name clk_ddr4 [get_ports clk_ddr4_p]
