# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Cisco Nexus K3P-S / ExaNIC X25
# part: xcku3p-ffvb676-2-e

# BPI flash
set_property -dict {LOC AF20 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[0]}]
set_property -dict {LOC AE18 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[1]}]
set_property -dict {LOC AF19 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[2]}]
set_property -dict {LOC AF17 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[3]}]
set_property -dict {LOC AB19 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[4]}]
set_property -dict {LOC AD19 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[5]}]
set_property -dict {LOC AB17 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[6]}]
set_property -dict {LOC AE17 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[7]}]
set_property -dict {LOC AD16 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[8]}]
set_property -dict {LOC AE16 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[9]}]
set_property -dict {LOC AD18 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[10]}]
set_property -dict {LOC AC21 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[11]}]
set_property -dict {LOC AE22 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[12]}]
set_property -dict {LOC AF22 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[13]}]
set_property -dict {LOC AF25 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[14]}]
set_property -dict {LOC AF24 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_dq[15]}]
set_property -dict {LOC AE20 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[0]}]
set_property -dict {LOC AE26 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[1]}]
set_property -dict {LOC AD24 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[2]}]
set_property -dict {LOC AC23 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[3]}]
set_property -dict {LOC AE23 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[4]}]
set_property -dict {LOC AD20 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[5]}]
set_property -dict {LOC AC24 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[6]}]
set_property -dict {LOC AC22 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[7]}]
set_property -dict {LOC AD23 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[8]}]
set_property -dict {LOC AD21 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[9]}]
set_property -dict {LOC AB22 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[10]}]
set_property -dict {LOC AA22 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[11]}]
set_property -dict {LOC AE25 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[12]}]
set_property -dict {LOC AD26 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[13]}]
set_property -dict {LOC AB25 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[14]}]
set_property -dict {LOC AB26 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[15]}]
set_property -dict {LOC AD25 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[16]}]
set_property -dict {LOC AC26 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[17]}]
set_property -dict {LOC AB21 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[18]}]
set_property -dict {LOC AB24 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[19]}]
set_property -dict {LOC Y18  IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[20]}]
set_property -dict {LOC AA20 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[21]}]
set_property -dict {LOC AC19 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_addr[22]}]
set_property -dict {LOC Y20  IOSTANDARD LVCMOS18 PULLUP true} [get_ports {flash_region}]
set_property -dict {LOC AF18 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_ce_n}]
set_property -dict {LOC Y21  IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_oe_n}]
set_property -dict {LOC AB20 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_we_n}]
set_property -dict {LOC AF23 IOSTANDARD LVCMOS18 DRIVE 12} [get_ports {flash_adv_n}]

set_false_path -to [get_ports {flash_dq[*] flash_addr[*] flash_region flash_ce_n flash_oe_n flash_we_n flash_adv_n}]
set_output_delay 0 [get_ports {flash_dq[*] flash_addr[*] flash_region flash_ce_n flash_oe_n flash_we_n flash_adv_n}]
set_false_path -from [get_ports {flash_dq[*]}]
set_input_delay 0 [get_ports {flash_dq[*]}]
