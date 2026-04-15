# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Xilinx ZCU102 board
# part: xczu9eg-ffvb1156-2-e

# DDR4
# 1x MT40A256M16GE-075E
set_property -dict {LOC AM8  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[0]}]
set_property -dict {LOC AM9  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[1]}]
set_property -dict {LOC AP8  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[2]}]
set_property -dict {LOC AN8  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[3]}]
set_property -dict {LOC AK10 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[4]}]
set_property -dict {LOC AJ10 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[5]}]
set_property -dict {LOC AP9  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[6]}]
set_property -dict {LOC AN9  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[7]}]
set_property -dict {LOC AP10 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[8]}]
set_property -dict {LOC AP11 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[9]}]
set_property -dict {LOC AM10 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[10]}]
set_property -dict {LOC AL10 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[11]}]
set_property -dict {LOC AM11 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[12]}]
set_property -dict {LOC AL11 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[13]}]
set_property -dict {LOC AJ7  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[14]}]
set_property -dict {LOC AL5  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[15]}]
set_property -dict {LOC AJ9  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[16]}]
set_property -dict {LOC AK12 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_ba[0]}]
set_property -dict {LOC AJ12 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_ba[1]}]
set_property -dict {LOC AK7  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_bg[0]}]
set_property -dict {LOC AN7  IOSTANDARD DIFF_SSTL12_DCI} [get_ports {ddr4_ck_t}]
set_property -dict {LOC AP7  IOSTANDARD DIFF_SSTL12_DCI} [get_ports {ddr4_ck_c}]
set_property -dict {LOC AM3  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_cke}]
set_property -dict {LOC AP2  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_cs_n}]
set_property -dict {LOC AK8  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_act_n}]
set_property -dict {LOC AK9  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_odt}]
set_property -dict {LOC AP1  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_par}]
set_property -dict {LOC AH9  IOSTANDARD LVCMOS12       } [get_ports {ddr4_reset_n}]

set_property -dict {LOC AK4  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[0]}]       ;# U2.G2 DQL0
set_property -dict {LOC AK5  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[1]}]       ;# U2.F7 DQL1
set_property -dict {LOC AN4  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[2]}]       ;# U2.H3 DQL2
set_property -dict {LOC AM4  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[3]}]       ;# U2.H7 DQL3
set_property -dict {LOC AP4  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[4]}]       ;# U2.H2 DQL4
set_property -dict {LOC AP5  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[5]}]       ;# U2.H8 DQL5
set_property -dict {LOC AM5  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[6]}]       ;# U2.J3 DQL6
set_property -dict {LOC AM6  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[7]}]       ;# U2.J7 DQL7
set_property -dict {LOC AK2  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[8]}]       ;# U2.A3 DQU0
set_property -dict {LOC AK3  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[9]}]       ;# U2.B8 DQU1
set_property -dict {LOC AL1  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[10]}]      ;# U2.C3 DQU2
set_property -dict {LOC AK1  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[11]}]      ;# U2.C7 DQU3
set_property -dict {LOC AN1  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[12]}]      ;# U2.C2 DQU4
set_property -dict {LOC AM1  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[13]}]      ;# U2.C8 DQU5
set_property -dict {LOC AP3  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[14]}]      ;# U2.D3 DQU6
set_property -dict {LOC AN3  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[15]}]      ;# U2.D7 DQU7
set_property -dict {LOC AN6  IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[0]}]    ;# U2.G3 DQSL_T
set_property -dict {LOC AP6  IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[0]}]    ;# U2.F3 DQSL_C
set_property -dict {LOC AL3  IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[1]}]    ;# U2.B7 DQSU_T
set_property -dict {LOC AL2  IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[1]}]    ;# U2.A7 DQSU_C
set_property -dict {LOC AL6  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[0]}] ;# U2.E7 DML_B/DBIL_B
set_property -dict {LOC AN2  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[1]}] ;# U2.E2 DMU_B/DBIU_B
