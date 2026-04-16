# SPDX-License-Identifier: MIT
#
# Copyright (c) 2014-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the fb2CG@KU15P
# part: xcku15p-ffve1760-2-e

# LEDs
set_property -dict {LOC C4   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {led_sreg_d}]
set_property -dict {LOC B3   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {led_sreg_ld}]
set_property -dict {LOC G3   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {led_sreg_clk}]
set_property -dict {LOC C5   IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {led_bmc[0]}]
set_property -dict {LOC C6   IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {led_bmc[1]}]
set_property -dict {LOC D3   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {led_exp[0]}]
set_property -dict {LOC D4   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {led_exp[1]}]

set_false_path -to [get_ports {led_sreg_d led_sreg_ld led_sreg_clk led_bmc[*] led_exp[*]}]
set_output_delay 0 [get_ports {led_sreg_d led_sreg_ld led_sreg_clk led_bmc[*] led_exp[*]}]

# GPIO
set_property -dict {LOC B4   IOSTANDARD LVCMOS33} [get_ports {pps_in}] ;# from SMA J6 via Q1 (inverted)
set_property -dict {LOC A4   IOSTANDARD LVCMOS33 SLEW FAST DRIVE 4} [get_ports {pps_out}] ;# to SMA J6 via U4 and U5, and u.FL J7 (PPS OUT) via U3
set_property -dict {LOC A3   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {pps_out_en}] ; # to U5 IN (connects pps_out to SMA J6 when high)
#set_property -dict {LOC H2   IOSTANDARD LVCMOS33} [get_ports {misc_ucoax}] ; from u.FL J5 (PPS IN)

set_false_path -to [get_ports {pps_out pps_out_en}]
set_output_delay 0 [get_ports {pps_out pps_out_en}]
set_false_path -from [get_ports {pps_in}]
set_input_delay 0 [get_ports {pps_in}]

# Board status
#set_property -dict {LOC J2   IOSTANDARD LVCMOS33} [get_ports {fan_tacho[0]}]
#set_property -dict {LOC J3   IOSTANDARD LVCMOS33} [get_ports {fan_tacho[1]}]
set_property -dict {LOC A6   IOSTANDARD LVCMOS18} [get_ports {pg[0]}]
set_property -dict {LOC C7   IOSTANDARD LVCMOS18} [get_ports {pg[1]}]
#set_property -dict {LOC E2   IOSTANDARD LVCMOS33} [get_ports {pwrbrk}]

set_false_path -from [get_ports {pg[*]}]
set_input_delay 0 [get_ports {pg[*]}]
