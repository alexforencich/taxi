# SPDX-License-Identifier: MIT
#
# Copyright (c) 2021-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the HiTech Global HTG-9200 board
# part: xcvu9p-flgb2104-2-e
# part: xcvu13p-fhgb2104-2-e

# I2C
# U12 PCA9548 0x70
#     S0 4/5: J8 QSFP28 5 0x50
#     S1 6/7: J7 QSFP28 4 0x50
#     S2 8/9: J5 QSFP28 3 0x50
#     S3 10/11: J4 QSFP28 2 0x50
#     S4 13/14: J1 QSFP28 1 0x50
#     S5 15/16: J14 QSFP28 6 0x50
#     S6 17/18: J10 QSFP28 7 0x50
#     S7 19/20: J11 QSFP28 8 0x50
# U30 PCA9548 0x71
#     S0 4/5: U29 ICS8N4Q001L OSC GTH 0x6E
#     S1 6/7: J9 FMC
#     S2 8/9: U48 SI5341A-A-GM CLK GTY2 0x77
#     S3 10/11: U5 ICS8N4Q001L OSC DDR4 0x6E
#     S4 13/14: U47 ICS8N4Q001L OSC GTY2 0x6E
#     S5 15/16: J15 QSFP28 9 0x50
#     S6 17/18: U27 5P49V6901AdddNLGI CLK GTH 0xD4
#     S7 19/20: U24 ICS8N4Q001L OSC REFCLK 0x6E
set_property -dict {LOC BB21 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports i2c_main_scl]
set_property -dict {LOC BC21 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports i2c_main_sda]
set_property -dict {LOC BF20 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports i2c_main_rst_n]

set_false_path -to [get_ports {i2c_main_sda i2c_main_scl i2c_main_rst_n}]
set_output_delay 0 [get_ports {i2c_main_sda i2c_main_scl i2c_main_rst_n}]
set_false_path -from [get_ports {i2c_main_sda i2c_main_scl}]
set_input_delay 0 [get_ports {i2c_main_sda i2c_main_scl}]
