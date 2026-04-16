# SPDX-License-Identifier: MIT
#
# Copyright (c) 2014-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the fb2CG@KU15P
# part: xcku15p-ffve1760-2-e

# BMC interface
set_property -dict {LOC D7   IOSTANDARD LVCMOS18} [get_ports {bmc_miso}]
set_property -dict {LOC J4   IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports {bmc_nss}]
set_property -dict {LOC B6   IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports {bmc_clk}]
set_property -dict {LOC D5   IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports {bmc_mosi}]
set_property -dict {LOC H4   IOSTANDARD LVCMOS18} [get_ports {bmc_int}]

set_false_path -to [get_ports {bmc_nss bmc_clk bmc_mosi}]
set_output_delay 0 [get_ports {bmc_nss bmc_clk bmc_mosi}]
set_false_path -from [get_ports {bmc_miso bmc_int}]
set_input_delay 0 [get_ports {bmc_miso bmc_int}]
