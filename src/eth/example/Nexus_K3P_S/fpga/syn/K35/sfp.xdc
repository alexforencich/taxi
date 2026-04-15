# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Cisco Nexus K35-S / ExaNIC X10
# part: xcku035-fbva676-2-e

# SFP+ Interfaces
set_property -dict {LOC D2  } [get_ports {sfp_rx_p[0]}] ;# MGTHRXP0_227 GTHE3_CHANNEL_X0Y12 / GTHE3_COMMON_X0Y3
set_property -dict {LOC D1  } [get_ports {sfp_rx_n[0]}] ;# MGTHRXN0_227 GTHE3_CHANNEL_X0Y12 / GTHE3_COMMON_X0Y3
set_property -dict {LOC E4  } [get_ports {sfp_tx_p[0]}] ;# MGTHTXP0_227 GTHE3_CHANNEL_X0Y12 / GTHE3_COMMON_X0Y3
set_property -dict {LOC E3  } [get_ports {sfp_tx_n[0]}] ;# MGTHTXN0_227 GTHE3_CHANNEL_X0Y12 / GTHE3_COMMON_X0Y3
set_property -dict {LOC C4  } [get_ports {sfp_rx_p[1]}] ;# MGTHRXP1_227 GTHE3_CHANNEL_X0Y13 / GTHE3_COMMON_X0Y3
set_property -dict {LOC C3  } [get_ports {sfp_rx_n[1]}] ;# MGTHRXN1_227 GTHE3_CHANNEL_X0Y13 / GTHE3_COMMON_X0Y3
set_property -dict {LOC D6  } [get_ports {sfp_tx_p[1]}] ;# MGTHTXP1_227 GTHE3_CHANNEL_X0Y13 / GTHE3_COMMON_X0Y3
set_property -dict {LOC D5  } [get_ports {sfp_tx_n[1]}] ;# MGTHTXN1_227 GTHE3_CHANNEL_X0Y13 / GTHE3_COMMON_X0Y3
set_property -dict {LOC H6  } [get_ports {sfp_mgt_refclk_p}] ;# MGTREFCLK0P_227 from X2
set_property -dict {LOC H5  } [get_ports {sfp_mgt_refclk_n}] ;# MGTREFCLK0N_227 from X2
set_property -dict {LOC AA12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_tx_disable[0]}]
set_property -dict {LOC W14  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_tx_disable[1]}]
set_property -dict {LOC C24  IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_npres[0]}]
set_property -dict {LOC D24  IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_npres[1]}]
set_property -dict {LOC W13  IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_los[0]}]
set_property -dict {LOC AB12 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_los[1]}]
set_property -dict {LOC B25  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_rs[0]}]
set_property -dict {LOC D25  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_rs[1]}]
#set_property -dict {LOC W11  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_scl}]
#set_property -dict {LOC Y11  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_sda[0]}]
#set_property -dict {LOC Y13  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_sda[1]}]

# 161.1328125 MHz MGT reference clock
create_clock -period 6.206 -name sfp_mgt_refclk [get_ports {sfp_mgt_refclk_p}]

set_false_path -to [get_ports {sfp_tx_disable[*] sfp_rs[*]}]
set_output_delay 0 [get_ports {sfp_tx_disable[*] sfp_rs[*]}]
set_false_path -from [get_ports {sfp_npres[*] sfp_los[*]}]
set_input_delay 0 [get_ports {sfp_npres[*] sfp_los[*]}]

#set_false_path -to [get_ports {sfp_1_i2c_sda sfp_2_i2c_sda sfp_i2c_scl}]
#set_output_delay 0 [get_ports {sfp_1_i2c_sda sfp_2_i2c_sda sfp_i2c_scl}]
#set_false_path -from [get_ports {sfp_1_i2c_sda sfp_2_i2c_sda sfp_i2c_scl}]
#set_input_delay 0 [get_ports {sfp_1_i2c_sda sfp_2_i2c_sda sfp_i2c_scl}]
