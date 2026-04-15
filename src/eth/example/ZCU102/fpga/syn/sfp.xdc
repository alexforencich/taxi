# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Xilinx ZCU102 board
# part: xczu9eg-ffvb1156-2-e

# SFP+ Interface
set_property -dict {LOC D2  } [get_ports {sfp_rx_p[0]}] ;# MGTHRXP0_230 GTHE4_CHANNEL_X1Y12 / GTHE4_COMMON_X1Y3
set_property -dict {LOC D1  } [get_ports {sfp_rx_n[0]}] ;# MGTHRXN0_230 GTHE4_CHANNEL_X1Y12 / GTHE4_COMMON_X1Y3
set_property -dict {LOC E4  } [get_ports {sfp_tx_p[0]}] ;# MGTHTXP0_230 GTHE4_CHANNEL_X1Y12 / GTHE4_COMMON_X1Y3
set_property -dict {LOC E3  } [get_ports {sfp_tx_n[0]}] ;# MGTHTXN0_230 GTHE4_CHANNEL_X1Y12 / GTHE4_COMMON_X1Y3
set_property -dict {LOC C4  } [get_ports {sfp_rx_p[1]}] ;# MGTHRXP1_230 GTHE4_CHANNEL_X1Y13 / GTHE4_COMMON_X1Y3
set_property -dict {LOC C3  } [get_ports {sfp_rx_n[1]}] ;# MGTHRXN1_230 GTHE4_CHANNEL_X1Y13 / GTHE4_COMMON_X1Y3
set_property -dict {LOC D6  } [get_ports {sfp_tx_p[1]}] ;# MGTHTXP1_230 GTHE4_CHANNEL_X1Y13 / GTHE4_COMMON_X1Y3
set_property -dict {LOC D5  } [get_ports {sfp_tx_n[1]}] ;# MGTHTXN1_230 GTHE4_CHANNEL_X1Y13 / GTHE4_COMMON_X1Y3
set_property -dict {LOC B2  } [get_ports {sfp_rx_p[2]}] ;# MGTHRXP2_230 GTHE4_CHANNEL_X1Y14 / GTHE4_COMMON_X1Y3
set_property -dict {LOC B1  } [get_ports {sfp_rx_n[2]}] ;# MGTHRXN2_230 GTHE4_CHANNEL_X1Y14 / GTHE4_COMMON_X1Y3
set_property -dict {LOC B6  } [get_ports {sfp_tx_p[2]}] ;# MGTHTXP2_230 GTHE4_CHANNEL_X1Y14 / GTHE4_COMMON_X1Y3
set_property -dict {LOC B5  } [get_ports {sfp_tx_n[2]}] ;# MGTHTXN2_230 GTHE4_CHANNEL_X1Y14 / GTHE4_COMMON_X1Y3
set_property -dict {LOC A4  } [get_ports {sfp_rx_p[3]}] ;# MGTHRXP3_230 GTHE4_CHANNEL_X1Y15 / GTHE4_COMMON_X1Y3
set_property -dict {LOC A3  } [get_ports {sfp_rx_n[3]}] ;# MGTHRXN3_230 GTHE4_CHANNEL_X1Y15 / GTHE4_COMMON_X1Y3
set_property -dict {LOC A8  } [get_ports {sfp_tx_p[3]}] ;# MGTHTXP3_230 GTHE4_CHANNEL_X1Y15 / GTHE4_COMMON_X1Y3
set_property -dict {LOC A7  } [get_ports {sfp_tx_n[3]}] ;# MGTHTXN3_230 GTHE4_CHANNEL_X1Y15 / GTHE4_COMMON_X1Y3
set_property -dict {LOC C8  } [get_ports {sfp_mgt_refclk_0_p}] ;# MGTREFCLK0P_230 from U56 SI570 via U51 SI53340
set_property -dict {LOC C7  } [get_ports {sfp_mgt_refclk_0_n}] ;# MGTREFCLK0N_230 from U56 SI570 via U51 SI53340
#set_property -dict {LOC B10 } [get_ports {sfp_mgt_refclk_1_p}] ;# MGTREFCLK1P_230 from U20 CKOUT2 SI5328
#set_property -dict {LOC B9  } [get_ports {sfp_mgt_refclk_1_n}] ;# MGTREFCLK1N_230 from U20 CKOUT2 SI5328
#set_property -dict {LOC R10  IOSTANDARD LVDS} [get_ports {sfp_recclk_p}] ;# to U20 CKIN1 SI5328
#set_property -dict {LOC R9   IOSTANDARD LVDS} [get_ports {sfp_recclk_n}] ;# to U20 CKIN1 SI5328
set_property -dict {LOC A12  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {sfp_tx_disable_b[0]}]
set_property -dict {LOC A13  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {sfp_tx_disable_b[1]}]
set_property -dict {LOC B13  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {sfp_tx_disable_b[2]}]
set_property -dict {LOC C13  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {sfp_tx_disable_b[3]}]

# 156.25 MHz MGT reference clock
create_clock -period 6.400 -name sfp_mgt_refclk_0 [get_ports {sfp_mgt_refclk_0_p}]

set_false_path -to [get_ports {sfp_tx_disable_b[*]}]
set_output_delay 0 [get_ports {sfp_tx_disable_b[*]}]
