# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Opal Kelley XEM8320 board
# part: xcau25p-ffvb676-2-e

# DDR4
# MT40A512M16LY-075:E U16
set_property -dict {LOC AD18 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[0]}]
set_property -dict {LOC AE17 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[1]}]
set_property -dict {LOC AB17 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[2]}]
set_property -dict {LOC AE18 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[3]}]
set_property -dict {LOC AD19 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[4]}]
set_property -dict {LOC AF17 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[5]}]
set_property -dict {LOC Y17  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[6]}]
set_property -dict {LOC AE16 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[7]}]
set_property -dict {LOC AA17 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[8]}]
set_property -dict {LOC AC17 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[9]}]
set_property -dict {LOC AC19 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[10]}]
set_property -dict {LOC AC16 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[11]}]
set_property -dict {LOC AF20 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[12]}]
set_property -dict {LOC AD16 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[13]}]
set_property -dict {LOC AA19 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[14]}]
set_property -dict {LOC AF19 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[15]}]
set_property -dict {LOC AA18 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[16]}]
set_property -dict {LOC AC18 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_ba[0]}]
set_property -dict {LOC AF18 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_ba[1]}]
set_property -dict {LOC AB19 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_bg[0]}]
set_property -dict {LOC Y20  IOSTANDARD DIFF_SSTL12_DCI} [get_ports {ddr4_ck_t}]
set_property -dict {LOC Y21  IOSTANDARD DIFF_SSTL12_DCI} [get_ports {ddr4_ck_c}]
set_property -dict {LOC AA20 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_cke}]
set_property -dict {LOC AF22 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_cs_n}]
set_property -dict {LOC Y18  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_act_n}]
set_property -dict {LOC AB20 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_odt}]
set_property -dict {LOC AE26 IOSTANDARD LVCMOS12       } [get_ports {ddr4_reset_n}]

set_property -dict {LOC AF24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[0]}]
set_property -dict {LOC AB25 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[1]}]
set_property -dict {LOC AB26 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[2]}]
set_property -dict {LOC AC24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[3]}]
set_property -dict {LOC AF25 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[4]}]
set_property -dict {LOC AB24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[5]}]
set_property -dict {LOC AD24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[6]}]
set_property -dict {LOC AD25 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[7]}]
set_property -dict {LOC AB21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[8]}]
set_property -dict {LOC AE21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[9]}]
set_property -dict {LOC AE23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[10]}]
set_property -dict {LOC AD23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[11]}]
set_property -dict {LOC AC23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[12]}]
set_property -dict {LOC AD21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[13]}]
set_property -dict {LOC AC22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[14]}]
set_property -dict {LOC AC21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[15]}]
set_property -dict {LOC AC26 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[0]}]     ;# U16.G3 DQSL_T
set_property -dict {LOC AD26 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[0]}]     ;# U16.F3 DQSL_C
set_property -dict {LOC AA22 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[1]}]     ;# U16.B7 DQSU_T
set_property -dict {LOC AB22 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[1]}]     ;# U16.A7 DQSU_C
set_property -dict {LOC AE25 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[0]}]  ;# U16.E7 DML_B/DBIL_B
set_property -dict {LOC AE22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[1]}]  ;# U16.E2 DMU_B/DBIU_B
