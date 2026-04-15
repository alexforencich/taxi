# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Xilinx ZCU102 board
# part: xczu9eg-ffvb1156-2-e

# I2C interfaces
set_property -dict {LOC J10  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports i2c0_scl]
set_property -dict {LOC J11  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports i2c0_sda]
set_property -dict {LOC K20  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports i2c1_scl]
set_property -dict {LOC L20  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports i2c1_sda]

set_false_path -to [get_ports {i2c1_sda i2c1_scl}]
set_output_delay 0 [get_ports {i2c1_sda i2c1_scl}]
set_false_path -from [get_ports {i2c1_sda i2c1_scl}]
set_input_delay 0 [get_ports {i2c1_sda i2c1_scl}]
