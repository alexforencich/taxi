# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Cisco Nexus K35-S / ExaNIC X10
# part: xcku035-fbva676-2-e

# BPI flash
set_property -dict {LOC AE10 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[0]}]
set_property -dict {LOC AC8  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[1]}]
set_property -dict {LOC AD10 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[2]}]
set_property -dict {LOC AD9  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[3]}]
set_property -dict {LOC AC11 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[4]}]
set_property -dict {LOC AF10 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[5]}]
set_property -dict {LOC AF14 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[6]}]
set_property -dict {LOC AE12 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[7]}]
set_property -dict {LOC AD14 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[8]}]
set_property -dict {LOC AF13 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[9]}]
set_property -dict {LOC AE13 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[10]}]
set_property -dict {LOC AD8  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[11]}]
set_property -dict {LOC AC13 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[12]}]
set_property -dict {LOC AD13 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[13]}]
set_property -dict {LOC AA14 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[14]}]
set_property -dict {LOC AB15 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_dq[15]}]
set_property -dict {LOC AD11 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[0]}]
set_property -dict {LOC AE11 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[1]}]
set_property -dict {LOC AF12 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[2]}]
set_property -dict {LOC AB11 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[3]}]
set_property -dict {LOC AB9  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[4]}]
set_property -dict {LOC AB14 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[5]}]
set_property -dict {LOC AA10 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[6]}]
set_property -dict {LOC AA9  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[7]}]
set_property -dict {LOC W10  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[8]}]
set_property -dict {LOC AA13 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[9]}]
set_property -dict {LOC Y15  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[10]}]
set_property -dict {LOC AC12 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[11]}]
set_property -dict {LOC V12  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[12]}]
set_property -dict {LOC V11  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[13]}]
set_property -dict {LOC Y12  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[14]}]
set_property -dict {LOC W9   IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[15]}]
set_property -dict {LOC Y8   IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[16]}]
set_property -dict {LOC W8   IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[17]}]
set_property -dict {LOC W15  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[18]}]
set_property -dict {LOC AA15 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[19]}]
set_property -dict {LOC AE16 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[20]}]
set_property -dict {LOC AF15 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[21]}]
set_property -dict {LOC AE15 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_addr[22]}]
set_property -dict {LOC AD15 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {flash_region}]
set_property -dict {LOC AC9  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_ce_n}]
set_property -dict {LOC AC14 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_oe_n}]
set_property -dict {LOC AB10 IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_we_n}]
set_property -dict {LOC Y10  IOSTANDARD LVCMOS18 DRIVE 16} [get_ports {flash_adv_n}]

set_false_path -to [get_ports {flash_dq[*] flash_addr[*] flash_region flash_ce_n flash_oe_n flash_we_n flash_adv_n}]
set_output_delay 0 [get_ports {flash_dq[*] flash_addr[*] flash_region flash_ce_n flash_oe_n flash_we_n flash_adv_n}]
set_false_path -from [get_ports {flash_dq[*]}]
set_input_delay 0 [get_ports {flash_dq[*]}]
