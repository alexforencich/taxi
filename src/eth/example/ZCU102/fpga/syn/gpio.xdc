# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Xilinx ZCU102 board
# part: xczu9eg-ffvb1156-2-e

# LEDs
set_property -dict {LOC AG14 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[0]}]
set_property -dict {LOC AF13 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[1]}]
set_property -dict {LOC AE13 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[2]}]
set_property -dict {LOC AJ14 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[3]}]
set_property -dict {LOC AJ15 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[4]}]
set_property -dict {LOC AH13 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[5]}]
set_property -dict {LOC AH14 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[6]}]
set_property -dict {LOC AL12 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {led[7]}]

set_false_path -to [get_ports {led[*]}]
set_output_delay 0 [get_ports {led[*]}]

# Reset button
set_property -dict {LOC AM13 IOSTANDARD LVCMOS33} [get_ports reset]

set_false_path -from [get_ports {reset}]
set_input_delay 0 [get_ports {reset}]

# Push buttons
set_property -dict {LOC AG15 IOSTANDARD LVCMOS33} [get_ports btnu]
set_property -dict {LOC AF15 IOSTANDARD LVCMOS33} [get_ports btnl]
set_property -dict {LOC AE15 IOSTANDARD LVCMOS33} [get_ports btnd]
set_property -dict {LOC AE14 IOSTANDARD LVCMOS33} [get_ports btnr]
set_property -dict {LOC AG13 IOSTANDARD LVCMOS33} [get_ports btnc]

set_false_path -from [get_ports {btnu btnl btnd btnr btnc}]
set_input_delay 0 [get_ports {btnu btnl btnd btnr btnc}]

# DIP switches
set_property -dict {LOC AN14 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {LOC AP14 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]
set_property -dict {LOC AM14 IOSTANDARD LVCMOS33} [get_ports {sw[2]}]
set_property -dict {LOC AN13 IOSTANDARD LVCMOS33} [get_ports {sw[3]}]
set_property -dict {LOC AN12 IOSTANDARD LVCMOS33} [get_ports {sw[4]}]
set_property -dict {LOC AP12 IOSTANDARD LVCMOS33} [get_ports {sw[5]}]
set_property -dict {LOC AL13 IOSTANDARD LVCMOS33} [get_ports {sw[6]}]
set_property -dict {LOC AK13 IOSTANDARD LVCMOS33} [get_ports {sw[7]}]

set_false_path -from [get_ports {sw[*]}]
set_input_delay 0 [get_ports {sw[*]}]

# UART (U40 CP2108 ch 2)
set_property -dict {LOC F13  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports uart_txd] ;# U40.15 RX_2
set_property -dict {LOC E13  IOSTANDARD LVCMOS33} [get_ports uart_rxd] ;# U40.16 TX_2
set_property -dict {LOC D12  IOSTANDARD LVCMOS33} [get_ports uart_rts] ;# U40.14 RTS_2
set_property -dict {LOC E12  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports uart_cts] ;# U40.13 CTS_2

set_false_path -to [get_ports {uart_txd uart_cts}]
set_output_delay 0 [get_ports {uart_txd uart_cts}]
set_false_path -from [get_ports {uart_rxd uart_rts}]
set_input_delay 0 [get_ports {uart_rxd uart_rts}]
