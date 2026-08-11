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

# PLL U48 Si5341A-D-GM
# A1/A0: 11 (I2C addr 0x77)
# IN0: X29/X30
# IN1: U47
# IN2: NC
# FB: X31/X32
# OUT0: GTY 129
# OUT1: GTY 133
# OUT2: FF / X33/X34
# OUT3: GTY 132
# OUT4: GTY 131
# OUT5: GTY 130
# OUT6: GTY 126
# OUT7: GTY 125
# OUT8: GTY 127
# OUT9: GTY 128
set_property -dict {LOC L24  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {clk_gty2_fdec}]
set_property -dict {LOC K25  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {clk_gty2_finc}]
set_property -dict {LOC K23  IOSTANDARD LVCMOS18} [get_ports {clk_gty2_intr_n}]
set_property -dict {LOC L25  IOSTANDARD LVCMOS18} [get_ports {clk_gty2_lol_n}]
set_property -dict {LOC L23  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {clk_gty2_oe_n}]
set_property -dict {LOC L22  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {clk_gty2_sync_n}]
set_property -dict {LOC K22  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {clk_gty2_rst_n}]

set_false_path -to [get_ports {clk_gty2_fdec clk_gty2_finc clk_gty2_oe_n clk_gty2_sync_n clk_gty2_rst_n}]
set_output_delay 0 [get_ports {clk_gty2_fdec clk_gty2_finc clk_gty2_oe_n clk_gty2_sync_n clk_gty2_rst_n}]
set_false_path -from [get_ports {clk_gty2_intr_n clk_gty2_lol_n}]
set_input_delay 0 [get_ports {clk_gty2_intr_n clk_gty2_lol_n}]

# PLL U27 5P49V6901AdddNLGI
# IN: U29
# OUT1: FMC REFCLK C2M
# OUT2: FMC CLK2
# OUT3: FMC CLK1
# OUT4: FMC CLK2
#set_property -dict {LOC BE20 IOSTANDARD LVCMOS18} [get_ports {clk_gth_sd_oe}]
#set_property -dict {LOC BD20 IOSTANDARD LVCMOS18} [get_ports {clk_gth_out0_sel_i2cb}]
