# SPDX-License-Identifier: MIT
#
# Copyright (c) 2014-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the fb2CG@KU15P
# part: xcku15p-ffve1760-2-e

# Expansion connector
set_property -dict {LOC AG41} [get_ports {exp_rx_p[0]}] ;# MGTYRXP0_128 GTYE4_CHANNEL_X0Y5 / GTYE4_COMMON_X0Y1
set_property -dict {LOC AG42} [get_ports {exp_rx_n[0]}] ;# MGTYRXN0_128 GTYE4_CHANNEL_X0Y5 / GTYE4_COMMON_X0Y1
set_property -dict {LOC AG36} [get_ports {exp_tx_p[0]}] ;# MGTYTXP0_128 GTYE4_CHANNEL_X0Y5 / GTYE4_COMMON_X0Y1
set_property -dict {LOC AG37} [get_ports {exp_tx_n[0]}] ;# MGTYTXN0_128 GTYE4_CHANNEL_X0Y5 / GTYE4_COMMON_X0Y1
set_property -dict {LOC AH39} [get_ports {exp_rx_p[1]}] ;# MGTYRXP0_128 GTYE4_CHANNEL_X0Y4 / GTYE4_COMMON_X0Y1
set_property -dict {LOC AH40} [get_ports {exp_rx_n[1]}] ;# MGTYRXN0_128 GTYE4_CHANNEL_X0Y4 / GTYE4_COMMON_X0Y1
set_property -dict {LOC AH34} [get_ports {exp_tx_p[1]}] ;# MGTYTXP0_128 GTYE4_CHANNEL_X0Y4 / GTYE4_COMMON_X0Y1
set_property -dict {LOC AH35} [get_ports {exp_tx_n[1]}] ;# MGTYTXN0_128 GTYE4_CHANNEL_X0Y4 / GTYE4_COMMON_X0Y1
set_property -dict {LOC AJ41} [get_ports {exp_rx_p[2]}] ;# MGTYRXP0_127 GTYE4_CHANNEL_X0Y3 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AJ42} [get_ports {exp_rx_n[2]}] ;# MGTYRXN0_127 GTYE4_CHANNEL_X0Y3 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AJ36} [get_ports {exp_tx_p[2]}] ;# MGTYTXP0_127 GTYE4_CHANNEL_X0Y3 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AJ37} [get_ports {exp_tx_n[2]}] ;# MGTYTXN0_127 GTYE4_CHANNEL_X0Y3 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AK39} [get_ports {exp_rx_p[3]}] ;# MGTYRXP0_127 GTYE4_CHANNEL_X0Y2 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AK40} [get_ports {exp_rx_n[3]}] ;# MGTYRXN0_127 GTYE4_CHANNEL_X0Y2 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AK34} [get_ports {exp_tx_p[3]}] ;# MGTYTXP0_127 GTYE4_CHANNEL_X0Y2 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AK35} [get_ports {exp_tx_n[3]}] ;# MGTYTXN0_127 GTYE4_CHANNEL_X0Y2 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AL41} [get_ports {exp_rx_p[4]}] ;# MGTYRXP0_127 GTYE4_CHANNEL_X0Y1 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AL42} [get_ports {exp_rx_n[4]}] ;# MGTYRXN0_127 GTYE4_CHANNEL_X0Y1 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AL36} [get_ports {exp_tx_p[4]}] ;# MGTYTXP0_127 GTYE4_CHANNEL_X0Y1 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AL37} [get_ports {exp_tx_n[4]}] ;# MGTYTXN0_127 GTYE4_CHANNEL_X0Y1 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AM39} [get_ports {exp_rx_p[5]}] ;# MGTYRXP0_127 GTYE4_CHANNEL_X0Y0 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AM40} [get_ports {exp_rx_n[5]}] ;# MGTYRXN0_127 GTYE4_CHANNEL_X0Y0 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AM34} [get_ports {exp_tx_p[5]}] ;# MGTYTXP0_127 GTYE4_CHANNEL_X0Y0 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AM35} [get_ports {exp_tx_n[5]}] ;# MGTYTXN0_127 GTYE4_CHANNEL_X0Y0 / GTYE4_COMMON_X0Y0
set_property -dict {LOC AL32} [get_ports {exp_refclk_0_p}] ;# MGTREFCLK0P_128 from U28
set_property -dict {LOC AL33} [get_ports {exp_refclk_0_n}] ;# MGTREFCLK0N_128 from U28
set_property -dict {LOC AG32} [get_ports {exp_refclk_1_p}] ;# MGTREFCLK0P_127 from U28
set_property -dict {LOC AG33} [get_ports {exp_refclk_1_n}] ;# MGTREFCLK0N_127 from U28
set_property -dict {LOC E3   IOSTANDARD LVCMOS33} [get_ports {exp_gpio[0]}]
set_property -dict {LOC F3   IOSTANDARD LVCMOS33} [get_ports {exp_gpio[1]}]

# 161.1328125 MHz MGT reference clock
create_clock -period 6.206 -name exp_refclk_0 [get_ports {exp_refclk_0_p}]
create_clock -period 6.206 -name exp_refclk_1 [get_ports {exp_refclk_1_p}]
