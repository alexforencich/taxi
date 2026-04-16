# SPDX-License-Identifier: MIT
#
# Copyright (c) 2014-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the fb2CG@KU15P
# part: xcku15p-ffve1760-2-e

# PCIe Interface
set_property -dict {LOC AG2 } [get_ports {pcie_rx_p[0]}]  ;# MGTHRXP3_227 GTHE4_CHANNEL_X0Y15 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AG1 } [get_ports {pcie_rx_n[0]}]  ;# MGTHRXN3_227 GTHE4_CHANNEL_X0Y15 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AG6 } [get_ports {pcie_tx_p[0]}]  ;# MGTHTXP3_227 GTHE4_CHANNEL_X0Y15 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AG5 } [get_ports {pcie_tx_n[0]}]  ;# MGTHTXN3_227 GTHE4_CHANNEL_X0Y15 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AH4 } [get_ports {pcie_rx_p[1]}]  ;# MGTHRXP2_227 GTHE4_CHANNEL_X0Y14 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AH3 } [get_ports {pcie_rx_n[1]}]  ;# MGTHRXN2_227 GTHE4_CHANNEL_X0Y14 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AH8 } [get_ports {pcie_tx_p[1]}]  ;# MGTHTXP2_227 GTHE4_CHANNEL_X0Y14 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AH7 } [get_ports {pcie_tx_n[1]}]  ;# MGTHTXN2_227 GTHE4_CHANNEL_X0Y14 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AJ2 } [get_ports {pcie_rx_p[2]}]  ;# MGTHRXP1_227 GTHE4_CHANNEL_X0Y13 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AJ1 } [get_ports {pcie_rx_n[2]}]  ;# MGTHRXN1_227 GTHE4_CHANNEL_X0Y13 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AJ6 } [get_ports {pcie_tx_p[2]}]  ;# MGTHTXP1_227 GTHE4_CHANNEL_X0Y13 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AJ5 } [get_ports {pcie_tx_n[2]}]  ;# MGTHTXN1_227 GTHE4_CHANNEL_X0Y13 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AK4 } [get_ports {pcie_rx_p[3]}]  ;# MGTHRXP0_227 GTHE4_CHANNEL_X0Y12 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AK3 } [get_ports {pcie_rx_n[3]}]  ;# MGTHRXN0_227 GTHE4_CHANNEL_X0Y12 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AK8 } [get_ports {pcie_tx_p[3]}]  ;# MGTHTXP0_227 GTHE4_CHANNEL_X0Y12 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AK7 } [get_ports {pcie_tx_n[3]}]  ;# MGTHTXN0_227 GTHE4_CHANNEL_X0Y12 / GTHE4_COMMON_X0Y3
set_property -dict {LOC AL2 } [get_ports {pcie_rx_p[4]}]  ;# MGTHRXP3_226 GTHE4_CHANNEL_X0Y11 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AL1 } [get_ports {pcie_rx_n[4]}]  ;# MGTHRXN3_226 GTHE4_CHANNEL_X0Y11 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AL6 } [get_ports {pcie_tx_p[4]}]  ;# MGTHTXP3_226 GTHE4_CHANNEL_X0Y11 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AL5 } [get_ports {pcie_tx_n[4]}]  ;# MGTHTXN3_226 GTHE4_CHANNEL_X0Y11 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AM4 } [get_ports {pcie_rx_p[5]}]  ;# MGTHRXP2_226 GTHE4_CHANNEL_X0Y10 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AM3 } [get_ports {pcie_rx_n[5]}]  ;# MGTHRXN2_226 GTHE4_CHANNEL_X0Y10 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AM8 } [get_ports {pcie_tx_p[5]}]  ;# MGTHTXP2_226 GTHE4_CHANNEL_X0Y10 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AM7 } [get_ports {pcie_tx_n[5]}]  ;# MGTHTXN2_226 GTHE4_CHANNEL_X0Y10 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AN2 } [get_ports {pcie_rx_p[6]}]  ;# MGTHRXP1_226 GTHE4_CHANNEL_X0Y9 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AN1 } [get_ports {pcie_rx_n[6]}]  ;# MGTHRXN1_226 GTHE4_CHANNEL_X0Y9 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AN6 } [get_ports {pcie_tx_p[6]}]  ;# MGTHTXP1_226 GTHE4_CHANNEL_X0Y9 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AN5 } [get_ports {pcie_tx_n[6]}]  ;# MGTHTXN1_226 GTHE4_CHANNEL_X0Y9 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AP4 } [get_ports {pcie_rx_p[7]}]  ;# MGTHRXP0_226 GTHE4_CHANNEL_X0Y8 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AP3 } [get_ports {pcie_rx_n[7]}]  ;# MGTHRXN0_226 GTHE4_CHANNEL_X0Y8 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AP8 } [get_ports {pcie_tx_p[7]}]  ;# MGTHTXP0_226 GTHE4_CHANNEL_X0Y8 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AP7 } [get_ports {pcie_tx_n[7]}]  ;# MGTHTXN0_226 GTHE4_CHANNEL_X0Y8 / GTHE4_COMMON_X0Y2
set_property -dict {LOC AR2 } [get_ports {pcie_rx_p[8]}]  ;# MGTHRXP3_225 GTHE4_CHANNEL_X0Y7 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AR1 } [get_ports {pcie_rx_n[8]}]  ;# MGTHRXN3_225 GTHE4_CHANNEL_X0Y7 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AR6 } [get_ports {pcie_tx_p[8]}]  ;# MGTHTXP3_225 GTHE4_CHANNEL_X0Y7 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AR5 } [get_ports {pcie_tx_n[8]}]  ;# MGTHTXN3_225 GTHE4_CHANNEL_X0Y7 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AT4 } [get_ports {pcie_rx_p[9]}]  ;# MGTHRXP2_225 GTHE4_CHANNEL_X0Y6 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AT3 } [get_ports {pcie_rx_n[9]}]  ;# MGTHRXN2_225 GTHE4_CHANNEL_X0Y6 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AT8 } [get_ports {pcie_tx_p[9]}]  ;# MGTHTXP2_225 GTHE4_CHANNEL_X0Y6 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AT7 } [get_ports {pcie_tx_n[9]}]  ;# MGTHTXN2_225 GTHE4_CHANNEL_X0Y6 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AU2 } [get_ports {pcie_rx_p[10]}] ;# MGTHRXP1_225 GTHE4_CHANNEL_X0Y5 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AU1 } [get_ports {pcie_rx_n[10]}] ;# MGTHRXN1_225 GTHE4_CHANNEL_X0Y5 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AU6 } [get_ports {pcie_tx_p[10]}] ;# MGTHTXP1_225 GTHE4_CHANNEL_X0Y5 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AU5 } [get_ports {pcie_tx_n[10]}] ;# MGTHTXN1_225 GTHE4_CHANNEL_X0Y5 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AV4 } [get_ports {pcie_rx_p[11]}] ;# MGTHRXP0_225 GTHE4_CHANNEL_X0Y4 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AV3 } [get_ports {pcie_rx_n[11]}] ;# MGTHRXN0_225 GTHE4_CHANNEL_X0Y4 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AV8 } [get_ports {pcie_tx_p[11]}] ;# MGTHTXP0_225 GTHE4_CHANNEL_X0Y4 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AV7 } [get_ports {pcie_tx_n[11]}] ;# MGTHTXN0_225 GTHE4_CHANNEL_X0Y4 / GTHE4_COMMON_X0Y1
set_property -dict {LOC AW2 } [get_ports {pcie_rx_p[12]}] ;# MGTHRXP3_224 GTHE4_CHANNEL_X0Y3 / GTHE4_COMMON_X0Y0
set_property -dict {LOC AW1 } [get_ports {pcie_rx_n[12]}] ;# MGTHRXN3_224 GTHE4_CHANNEL_X0Y3 / GTHE4_COMMON_X0Y0
set_property -dict {LOC AW6 } [get_ports {pcie_tx_p[12]}] ;# MGTHTXP3_224 GTHE4_CHANNEL_X0Y3 / GTHE4_COMMON_X0Y0
set_property -dict {LOC AW5 } [get_ports {pcie_tx_n[12]}] ;# MGTHTXN3_224 GTHE4_CHANNEL_X0Y3 / GTHE4_COMMON_X0Y0
set_property -dict {LOC AY4 } [get_ports {pcie_rx_p[13]}] ;# MGTHRXP2_224 GTHE4_CHANNEL_X0Y2 / GTHE4_COMMON_X0Y0
set_property -dict {LOC AY3 } [get_ports {pcie_rx_n[13]}] ;# MGTHRXN2_224 GTHE4_CHANNEL_X0Y2 / GTHE4_COMMON_X0Y0
set_property -dict {LOC AY8 } [get_ports {pcie_tx_p[13]}] ;# MGTHTXP2_224 GTHE4_CHANNEL_X0Y2 / GTHE4_COMMON_X0Y0
set_property -dict {LOC AY7 } [get_ports {pcie_tx_n[13]}] ;# MGTHTXN2_224 GTHE4_CHANNEL_X0Y2 / GTHE4_COMMON_X0Y0
set_property -dict {LOC BA2 } [get_ports {pcie_rx_p[14]}] ;# MGTHRXP1_224 GTHE4_CHANNEL_X0Y1 / GTHE4_COMMON_X0Y0
set_property -dict {LOC BA1 } [get_ports {pcie_rx_n[14]}] ;# MGTHRXN1_224 GTHE4_CHANNEL_X0Y1 / GTHE4_COMMON_X0Y0
set_property -dict {LOC BA6 } [get_ports {pcie_tx_p[14]}] ;# MGTHTXP1_224 GTHE4_CHANNEL_X0Y1 / GTHE4_COMMON_X0Y0
set_property -dict {LOC BA5 } [get_ports {pcie_tx_n[14]}] ;# MGTHTXN1_224 GTHE4_CHANNEL_X0Y1 / GTHE4_COMMON_X0Y0
set_property -dict {LOC BB4 } [get_ports {pcie_rx_p[15]}] ;# MGTHRXP0_224 GTHE4_CHANNEL_X0Y0 / GTHE4_COMMON_X0Y0
set_property -dict {LOC BB3 } [get_ports {pcie_rx_n[15]}] ;# MGTHRXN0_224 GTHE4_CHANNEL_X0Y0 / GTHE4_COMMON_X0Y0
set_property -dict {LOC BB8 } [get_ports {pcie_tx_p[15]}] ;# MGTHTXP0_224 GTHE4_CHANNEL_X0Y0 / GTHE4_COMMON_X0Y0
set_property -dict {LOC BB7 } [get_ports {pcie_tx_n[15]}] ;# MGTHTXN0_224 GTHE4_CHANNEL_X0Y0 / GTHE4_COMMON_X0Y0
set_property -dict {LOC AN10} [get_ports {pcie_refclk_p}] ;# MGTREFCLK0P_226
set_property -dict {LOC AN9 } [get_ports {pcie_refclk_n}] ;# MGTREFCLK0N_226
set_property -dict {LOC G1   IOSTANDARD LVCMOS33 PULLUP true} [get_ports pcie_reset_n]

# 100 MHz MGT reference clock
create_clock -period 10.000 -name pcie_mgt_refclk [get_ports pcie_refclk_p]

set_false_path -from [get_ports {pcie_reset_n}]
set_input_delay 0 [get_ports {pcie_reset_n}]
