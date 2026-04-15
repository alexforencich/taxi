# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Cisco Nexus K35-S / ExaNIC X10
# part: xcku035-fbva676-2-e

# General configuration
set_property CFGBVS GND                                [current_design]
set_property CONFIG_VOLTAGE 1.8                        [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true           [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup         [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50            [current_design]
set_property BITSTREAM.CONFIG.BPI_SYNC_MODE Type2      [current_design]
set_property CONFIG_MODE BPI16                         [current_design]
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable  [current_design]

# 100 MHz system clock
set_property -dict {LOC D18  IOSTANDARD LVDS} [get_ports {clk_100mhz_p}]
set_property -dict {LOC C18  IOSTANDARD LVDS} [get_ports {clk_100mhz_n}]
create_clock -period 10 -name clk_100mhz [get_ports {clk_100mhz_p}]
