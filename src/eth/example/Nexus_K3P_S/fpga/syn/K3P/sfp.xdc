# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Cisco Nexus K3P-S / ExaNIC X25
# part: xcku3p-ffvb676-2-e

# SFP28 Interfaces
set_property -dict {LOC D2  } [get_ports {sfp_rx_p[0]}] ;# MGTYRXP0_227 GTYE4_CHANNEL_X0Y12 / GTYE4_COMMON_X0Y3
set_property -dict {LOC D1  } [get_ports {sfp_rx_n[0]}] ;# MGTYRXN0_227 GTYE4_CHANNEL_X0Y12 / GTYE4_COMMON_X0Y3
set_property -dict {LOC A4  } [get_ports {sfp_rx_p[1]}] ;# MGTYRXP3_227 GTYE4_CHANNEL_X0Y15 / GTYE4_COMMON_X0Y3
set_property -dict {LOC A3  } [get_ports {sfp_rx_n[1]}] ;# MGTYRXN3_227 GTYE4_CHANNEL_X0Y15 / GTYE4_COMMON_X0Y3
set_property -dict {LOC F7  } [get_ports {sfp_tx_p[0]}] ;# MGTYTXP0_227 GTYE4_CHANNEL_X0Y12 / GTYE4_COMMON_X0Y3
set_property -dict {LOC F6  } [get_ports {sfp_tx_n[0]}] ;# MGTYTXN0_227 GTYE4_CHANNEL_X0Y12 / GTYE4_COMMON_X0Y3
set_property -dict {LOC B7  } [get_ports {sfp_tx_p[1]}] ;# MGTYTXP3_227 GTYE4_CHANNEL_X0Y15 / GTYE4_COMMON_X0Y3
set_property -dict {LOC B6  } [get_ports {sfp_tx_n[1]}] ;# MGTYTXN3_227 GTYE4_CHANNEL_X0Y15 / GTYE4_COMMON_X0Y3
set_property -dict {LOC K7  } [get_ports {sfp_mgt_refclk_p}] ;# MGTREFCLK0P_227 from X2
set_property -dict {LOC K6  } [get_ports {sfp_mgt_refclk_n}] ;# MGTREFCLK0N_227 from X2
set_property -dict {LOC AC17 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_tx_disable[0]}]
set_property -dict {LOC AA17 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_tx_disable[1]}]
set_property -dict {LOC F12  IOSTANDARD LVCMOS33 PULLUP true} [get_ports {sfp_npres[0]}]
set_property -dict {LOC F14  IOSTANDARD LVCMOS33 PULLUP true} [get_ports {sfp_npres[1]}]
set_property -dict {LOC AC16 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_los[0]}]
set_property -dict {LOC Y17  IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_los[1]}]
set_property -dict {LOC G14  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {sfp_rs[0]}]
set_property -dict {LOC H14  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {sfp_rs[1]}]
#set_property -dict {LOC A10  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_scl}]
#set_property -dict {LOC C11  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_sda[0]}]
#set_property -dict {LOC B11  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_sda[1]}]

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
