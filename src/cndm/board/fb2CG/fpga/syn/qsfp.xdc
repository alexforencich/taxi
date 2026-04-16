# SPDX-License-Identifier: MIT
#
# Copyright (c) 2014-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the fb2CG@KU15P
# part: xcku15p-ffve1760-2-e

# QSFP28 Interfaces
set_property -dict {LOC Y39 } [get_ports {qsfp_0_rx_p[0]}] ;# MGTYRXP0_130 GTYE4_CHANNEL_X0Y12 / GTYE4_COMMON_X0Y3
set_property -dict {LOC Y40 } [get_ports {qsfp_0_rx_n[0]}] ;# MGTYRXN0_130 GTYE4_CHANNEL_X0Y12 / GTYE4_COMMON_X0Y3
set_property -dict {LOC Y34 } [get_ports {qsfp_0_tx_p[0]}] ;# MGTYTXP0_130 GTYE4_CHANNEL_X0Y12 / GTYE4_COMMON_X0Y3
set_property -dict {LOC Y35 } [get_ports {qsfp_0_tx_n[0]}] ;# MGTYTXN0_130 GTYE4_CHANNEL_X0Y12 / GTYE4_COMMON_X0Y3
set_property -dict {LOC W41 } [get_ports {qsfp_0_rx_p[1]}] ;# MGTYRXP1_130 GTYE4_CHANNEL_X0Y13 / GTYE4_COMMON_X0Y3
set_property -dict {LOC W42 } [get_ports {qsfp_0_rx_n[1]}] ;# MGTYRXN1_130 GTYE4_CHANNEL_X0Y13 / GTYE4_COMMON_X0Y3
set_property -dict {LOC W36 } [get_ports {qsfp_0_tx_p[1]}] ;# MGTYTXP1_130 GTYE4_CHANNEL_X0Y13 / GTYE4_COMMON_X0Y3
set_property -dict {LOC W37 } [get_ports {qsfp_0_tx_n[1]}] ;# MGTYTXN1_130 GTYE4_CHANNEL_X0Y13 / GTYE4_COMMON_X0Y3
set_property -dict {LOC V39 } [get_ports {qsfp_0_rx_p[2]}] ;# MGTYRXP2_130 GTYE4_CHANNEL_X0Y14 / GTYE4_COMMON_X0Y3
set_property -dict {LOC V40 } [get_ports {qsfp_0_rx_n[2]}] ;# MGTYRXN2_130 GTYE4_CHANNEL_X0Y14 / GTYE4_COMMON_X0Y3
set_property -dict {LOC V34 } [get_ports {qsfp_0_tx_p[2]}] ;# MGTYTXP2_130 GTYE4_CHANNEL_X0Y14 / GTYE4_COMMON_X0Y3
set_property -dict {LOC V35 } [get_ports {qsfp_0_tx_n[2]}] ;# MGTYTXN2_130 GTYE4_CHANNEL_X0Y14 / GTYE4_COMMON_X0Y3
set_property -dict {LOC U41 } [get_ports {qsfp_0_rx_p[3]}] ;# MGTYRXP3_130 GTYE4_CHANNEL_X0Y15 / GTYE4_COMMON_X0Y3
set_property -dict {LOC U42 } [get_ports {qsfp_0_rx_n[3]}] ;# MGTYRXN3_130 GTYE4_CHANNEL_X0Y15 / GTYE4_COMMON_X0Y3
set_property -dict {LOC U36 } [get_ports {qsfp_0_tx_p[3]}] ;# MGTYTXP3_130 GTYE4_CHANNEL_X0Y15 / GTYE4_COMMON_X0Y3
set_property -dict {LOC U37 } [get_ports {qsfp_0_tx_n[3]}] ;# MGTYTXN3_130 GTYE4_CHANNEL_X0Y15 / GTYE4_COMMON_X0Y3
set_property -dict {LOC W32 } [get_ports {qsfp_0_mgt_refclk_p}] ;# MGTREFCLK0P_130 from U28
set_property -dict {LOC W33 } [get_ports {qsfp_0_mgt_refclk_n}] ;# MGTREFCLK0N_130 from U28
set_property -dict {LOC B9   IOSTANDARD LVCMOS33 PULLUP true} [get_ports {qsfp_0_mod_prsnt_n}]
set_property -dict {LOC A8   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {qsfp_0_reset_n}]
set_property -dict {LOC A9   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {qsfp_0_lp_mode}]
set_property -dict {LOC A10  IOSTANDARD LVCMOS33 PULLUP true} [get_ports {qsfp_0_intr_n}]
#set_property -dict {LOC B8   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {qsfp_0_i2c_scl}]
#set_property -dict {LOC B7   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {qsfp_0_i2c_sda}]

# 161.1328125 MHz MGT reference clock
create_clock -period 6.206 -name qsfp_0_mgt_refclk [get_ports {qsfp_0_mgt_refclk_p}]

set_false_path -to [get_ports {qsfp_0_reset_n qsfp_0_lp_mode}]
set_output_delay 0 [get_ports {qsfp_0_reset_n qsfp_0_lp_mode}]
set_false_path -from [get_ports {qsfp_0_mod_prsnt_n qsfp_0_intr_n}]
set_input_delay 0 [get_ports {qsfp_0_mod_prsnt_n qsfp_0_intr_n}]

#set_false_path -to [get_ports {qsfp_0_i2c_scl qsfp_0_i2c_sda}]
#set_output_delay 0 [get_ports {qsfp_0_i2c_scl qsfp_0_i2c_sda}]
#set_false_path -from [get_ports {qsfp_0_i2c_scl qsfp_0_i2c_sda}]
#set_input_delay 0 [get_ports {qsfp_0_i2c_scl qsfp_0_i2c_sda}]

set_property -dict {LOC M39 } [get_ports {qsfp_1_rx_p[0]}] ;# MGTYRXP0_132 GTYE4_CHANNEL_X0Y20 / GTYE4_COMMON_X0Y5
set_property -dict {LOC M40 } [get_ports {qsfp_1_rx_n[0]}] ;# MGTYRXN0_132 GTYE4_CHANNEL_X0Y20 / GTYE4_COMMON_X0Y5
set_property -dict {LOC M34 } [get_ports {qsfp_1_tx_p[0]}] ;# MGTYTXP0_132 GTYE4_CHANNEL_X0Y20 / GTYE4_COMMON_X0Y5
set_property -dict {LOC M35 } [get_ports {qsfp_1_tx_n[0]}] ;# MGTYTXN0_132 GTYE4_CHANNEL_X0Y20 / GTYE4_COMMON_X0Y5
set_property -dict {LOC L41 } [get_ports {qsfp_1_rx_p[1]}] ;# MGTYRXP1_132 GTYE4_CHANNEL_X0Y21 / GTYE4_COMMON_X0Y5
set_property -dict {LOC L42 } [get_ports {qsfp_1_rx_n[1]}] ;# MGTYRXN1_132 GTYE4_CHANNEL_X0Y21 / GTYE4_COMMON_X0Y5
set_property -dict {LOC L36 } [get_ports {qsfp_1_tx_p[1]}] ;# MGTYTXP1_132 GTYE4_CHANNEL_X0Y21 / GTYE4_COMMON_X0Y5
set_property -dict {LOC L37 } [get_ports {qsfp_1_tx_n[1]}] ;# MGTYTXN1_132 GTYE4_CHANNEL_X0Y21 / GTYE4_COMMON_X0Y5
set_property -dict {LOC K39 } [get_ports {qsfp_1_rx_p[2]}] ;# MGTYRXP2_132 GTYE4_CHANNEL_X0Y22 / GTYE4_COMMON_X0Y5
set_property -dict {LOC K40 } [get_ports {qsfp_1_rx_n[2]}] ;# MGTYRXN2_132 GTYE4_CHANNEL_X0Y22 / GTYE4_COMMON_X0Y5
set_property -dict {LOC K34 } [get_ports {qsfp_1_tx_p[2]}] ;# MGTYTXP2_132 GTYE4_CHANNEL_X0Y22 / GTYE4_COMMON_X0Y5
set_property -dict {LOC K35 } [get_ports {qsfp_1_tx_n[2]}] ;# MGTYTXN2_132 GTYE4_CHANNEL_X0Y22 / GTYE4_COMMON_X0Y5
set_property -dict {LOC J41 } [get_ports {qsfp_1_rx_p[3]}] ;# MGTYRXP3_132 GTYE4_CHANNEL_X0Y23 / GTYE4_COMMON_X0Y5
set_property -dict {LOC J42 } [get_ports {qsfp_1_rx_n[3]}] ;# MGTYRXN3_132 GTYE4_CHANNEL_X0Y23 / GTYE4_COMMON_X0Y5
set_property -dict {LOC J36 } [get_ports {qsfp_1_tx_p[3]}] ;# MGTYTXP3_132 GTYE4_CHANNEL_X0Y23 / GTYE4_COMMON_X0Y5
set_property -dict {LOC J37 } [get_ports {qsfp_1_tx_n[3]}] ;# MGTYTXN3_132 GTYE4_CHANNEL_X0Y23 / GTYE4_COMMON_X0Y5
set_property -dict {LOC P30 } [get_ports {qsfp_1_mgt_refclk_p}] ;# MGTREFCLK0P_132 from U28
set_property -dict {LOC P31 } [get_ports {qsfp_1_mgt_refclk_n}] ;# MGTREFCLK0N_132 from U28
set_property -dict {LOC E10  IOSTANDARD LVCMOS33 PULLUP true} [get_ports {qsfp_1_mod_prsnt_n}]
set_property -dict {LOC C10  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {qsfp_1_reset_n}]
set_property -dict {LOC D9   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {qsfp_1_lp_mode}]
set_property -dict {LOC D10  IOSTANDARD LVCMOS33 PULLUP true} [get_ports {qsfp_1_intr_n}]
#set_property -dict {LOC C9   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {qsfp_1_i2c_scl}]
#set_property -dict {LOC D8   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {qsfp_1_i2c_sda}]

# 161.1328125 MHz MGT reference clock
create_clock -period 6.206 -name qsfp_1_mgt_refclk [get_ports {qsfp_1_mgt_refclk_p}]

set_false_path -to [get_ports {qsfp_1_reset_n qsfp_1_lp_mode}]
set_output_delay 0 [get_ports {qsfp_1_reset_n qsfp_1_lp_mode}]
set_false_path -from [get_ports {qsfp_1_mod_prsnt_n qsfp_1_intr_n}]
set_input_delay 0 [get_ports {qsfp_1_mod_prsnt_n qsfp_1_intr_n}]

#set_false_path -to [get_ports {qsfp_1_i2c_scl qsfp_1_i2c_sda}]
#set_output_delay 0 [get_ports {qsfp_1_i2c_scl qsfp_1_i2c_sda}]
#set_false_path -from [get_ports {qsfp_1_i2c_scl qsfp_1_i2c_sda}]
#set_input_delay 0 [get_ports {qsfp_1_i2c_scl qsfp_1_i2c_sda}]
