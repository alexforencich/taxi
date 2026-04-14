# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Opal Kelley XEM8320 board
# part: xcau25p-ffvb676-2-e

# SFP+ interfaces
set_property -dict {LOC M2  } [get_ports {sfp_rx_p[0]}] ;# MGTYRXP0_226 GTYE3_CHANNEL_X0Y9  / GTYE3_COMMON_X0Y2
set_property -dict {LOC M1  } [get_ports {sfp_rx_n[0]}] ;# MGTYRXN0_226 GTYE3_CHANNEL_X0Y9  / GTYE3_COMMON_X0Y2
set_property -dict {LOC N5  } [get_ports {sfp_tx_p[0]}] ;# MGTYTXP0_226 GTYE3_CHANNEL_X0Y9  / GTYE3_COMMON_X0Y2
set_property -dict {LOC N4  } [get_ports {sfp_tx_n[0]}] ;# MGTYTXN0_226 GTYE3_CHANNEL_X0Y9  / GTYE3_COMMON_X0Y2
set_property -dict {LOC K2  } [get_ports {sfp_rx_p[1]}] ;# MGTYRXP1_226 GTYE3_CHANNEL_X0Y10 / GTYE3_COMMON_X0Y2
set_property -dict {LOC K1  } [get_ports {sfp_rx_n[1]}] ;# MGTYRXN1_226 GTYE3_CHANNEL_X0Y10 / GTYE3_COMMON_X0Y2
set_property -dict {LOC L5  } [get_ports {sfp_tx_p[1]}] ;# MGTYTXP1_226 GTYE3_CHANNEL_X0Y10 / GTYE3_COMMON_X0Y2
set_property -dict {LOC L4  } [get_ports {sfp_tx_n[1]}] ;# MGTYTXN1_226 GTYE3_CHANNEL_X0Y10 / GTYE3_COMMON_X0Y2
#set_property -dict {LOC P7  } [get_ports sfp_mgt_refclk_0_p] ;# MGTREFCLK0P_226 from U39
#set_property -dict {LOC P6  } [get_ports sfp_mgt_refclk_0_n] ;# MGTREFCLK0N_226 from U39
#set_property -dict {LOC M7  } [get_ports sfp_mgt_refclk_1_p] ;# MGTREFCLK1P_226 from J19
#set_property -dict {LOC M6  } [get_ports sfp_mgt_refclk_1_n] ;# MGTREFCLK1N_226 from J20
set_property -dict {LOC Y7  } [get_ports sfp_mgt_refclk_2_p] ;# MGTREFCLK0P_224 from U52
set_property -dict {LOC Y6  } [get_ports sfp_mgt_refclk_2_n] ;# MGTREFCLK0N_224 from U52
set_property -dict {LOC C13 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_tx_disable[0]}]
set_property -dict {LOC F13 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_tx_disable[1]}]
set_property -dict {LOC C14 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_tx_fault[0]}]
set_property -dict {LOC F14 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_tx_fault[1]}]
set_property -dict {LOC D14 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_npres[0]}]
set_property -dict {LOC A14 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_npres[1]}]
set_property -dict {LOC E13 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_los[0]}]
set_property -dict {LOC A13 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_los[1]}]
set_property -dict {LOC D13 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_rs[0][0]}]
set_property -dict {LOC E12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_rs[0][1]}]
set_property -dict {LOC B14 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_rs[1][0]}]
set_property -dict {LOC A12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_rs[1][1]}]
#set_property -dict {LOC B12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_sda[0]}]
#set_property -dict {LOC C12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_scl[0]}]
#set_property -dict {LOC F12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_sda[1]}]
#set_property -dict {LOC G12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_scl[1]}]

# 125 MHz MGT reference clock
#create_clock -period 8.000 -name sfp_mgt_refclk_0 [get_ports sfp_mgt_refclk_0_p]

# MGT reference clock from SMA
#create_clock -period 6.400 -name sfp_mgt_refclk_1 [get_ports sfp_mgt_refclk_1_p]

# 156.25 MHz MGT reference clock
create_clock -period 6.400 -name sfp_mgt_refclk_2 [get_ports sfp_mgt_refclk_2_p]

set_false_path -to [get_ports {sfp_tx_disable[*] sfp_rs[*]}]
set_output_delay 0 [get_ports {sfp_tx_disable[*] sfp_rs[*]}]
set_false_path -from [get_ports {sfp_tx_fault[*] sfp_npres[*] sfp_los[*]}]
set_input_delay 0 [get_ports {sfp_tx_fault[*] sfp_npres[*] sfp_los[*]}]

#set_false_path -to [get_ports {sfp_i2c_sda[*] sfp_i2c_scl[*]}]
#set_output_delay 0 [get_ports {sfp_i2c_sda[*] sfp_i2c_scl[*]}]
#set_false_path -from [get_ports {sfp_i2c_sda[*] sfp_i2c_scl[*]}]
#set_input_delay 0 [get_ports {sfp_i2c_sda[*] sfp_i2c_scl[*]}]
