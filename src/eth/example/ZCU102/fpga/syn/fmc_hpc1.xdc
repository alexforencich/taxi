# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Xilinx ZCU102 board
# part: xczu9eg-ffvb1156-2-e

# FMC HPC1 J4
set_property -dict {LOC AE5  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[0]}]  ;# J4.G9  LA00_P_CC
set_property -dict {LOC AF5  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[0]}]  ;# J4.G10 LA00_N_CC
set_property -dict {LOC AJ6  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[1]}]  ;# J4.D8  LA01_P_CC
set_property -dict {LOC AJ5  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[1]}]  ;# J4.D9  LA01_N_CC
set_property -dict {LOC AD2  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[2]}]  ;# J4.H7  LA02_P
set_property -dict {LOC AD1  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[2]}]  ;# J4.H8  LA02_N
set_property -dict {LOC AH1  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[3]}]  ;# J4.G12 LA03_P
set_property -dict {LOC AJ1  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[3]}]  ;# J4.G13 LA03_N
set_property -dict {LOC AF2  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[4]}]  ;# J4.H10 LA04_P
set_property -dict {LOC AF1  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[4]}]  ;# J4.H11 LA04_N
set_property -dict {LOC AG3  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[5]}]  ;# J4.D11 LA05_P
set_property -dict {LOC AH3  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[5]}]  ;# J4.D12 LA05_N
set_property -dict {LOC AH2  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[6]}]  ;# J4.C10 LA06_P
set_property -dict {LOC AJ2  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[6]}]  ;# J4.C11 LA06_N
set_property -dict {LOC AD4  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[7]}]  ;# J4.H13 LA07_P
set_property -dict {LOC AE4  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[7]}]  ;# J4.H14 LA07_N
set_property -dict {LOC AE3  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[8]}]  ;# J4.G12 LA08_P
set_property -dict {LOC AF3  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[8]}]  ;# J4.G13 LA08_N
set_property -dict {LOC AE2  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[9]}]  ;# J4.D14 LA09_P
set_property -dict {LOC AE1  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[9]}]  ;# J4.D15 LA09_N
set_property -dict {LOC AH4  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[10]}] ;# J4.C14 LA10_P
set_property -dict {LOC AJ4  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[10]}] ;# J4.C15 LA10_N
set_property -dict {LOC AE8  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[11]}] ;# J4.H16 LA11_P
set_property -dict {LOC AF8  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[11]}] ;# J4.H17 LA11_N
set_property -dict {LOC AD7  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[12]}] ;# J4.G15 LA12_P
set_property -dict {LOC AD6  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[12]}] ;# J4.G16 LA12_N
set_property -dict {LOC AG8  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[13]}] ;# J4.D17 LA13_P
set_property -dict {LOC AH8  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[13]}] ;# J4.D18 LA13_N
set_property -dict {LOC AH7  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[14]}] ;# J4.C18 LA14_P
set_property -dict {LOC AH6  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[14]}] ;# J4.C19 LA14_N
set_property -dict {LOC AD10 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[15]}] ;# J4.H19 LA15_P
set_property -dict {LOC AE9  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[15]}] ;# J4.H20 LA15_N
set_property -dict {LOC AG10 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[16]}] ;# J4.G18 LA16_P
set_property -dict {LOC AG9  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[16]}] ;# J4.G19 LA16_N
set_property -dict {LOC Y5   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[17]}] ;# J4.D20 LA17_P_CC
set_property -dict {LOC AA5  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[17]}] ;# J4.D21 LA17_N_CC
set_property -dict {LOC Y8   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[18]}] ;# J4.C22 LA18_P_CC
set_property -dict {LOC Y7   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[18]}] ;# J4.C23 LA18_N_CC
set_property -dict {LOC AA11 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[19]}] ;# J4.H22 LA19_P
set_property -dict {LOC AA10 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[19]}] ;# J4.H23 LA19_N
set_property -dict {LOC AB11 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[20]}] ;# J4.G21 LA20_P
set_property -dict {LOC AB10 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[20]}] ;# J4.G22 LA20_N
set_property -dict {LOC AC12 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[21]}] ;# J4.H25 LA21_P
set_property -dict {LOC AC11 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[21]}] ;# J4.H26 LA21_N
set_property -dict {LOC AF11 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[22]}] ;# J4.G24 LA22_P
set_property -dict {LOC AG11 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[22]}] ;# J4.G25 LA22_N
set_property -dict {LOC AE12 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[23]}] ;# J4.D23 LA23_P
set_property -dict {LOC AF12 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[23]}] ;# J4.D24 LA23_N
set_property -dict {LOC AH12 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[24]}] ;# J4.H28 LA24_P
set_property -dict {LOC AH11 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[24]}] ;# J4.H29 LA24_N
set_property -dict {LOC AE10 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[25]}] ;# J4.G27 LA25_P
set_property -dict {LOC AF10 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[25]}] ;# J4.G28 LA25_N
set_property -dict {LOC T12  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[26]}] ;# J4.D26 LA26_P
set_property -dict {LOC R12  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[26]}] ;# J4.D27 LA26_N
set_property -dict {LOC U10  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[27]}] ;# J4.C26 LA27_P
set_property -dict {LOC T10  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[27]}] ;# J4.C27 LA27_N
set_property -dict {LOC T13  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[28]}] ;# J4.H31 LA28_P
set_property -dict {LOC R13  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[28]}] ;# J4.H32 LA28_N
set_property -dict {LOC W12  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_p[29]}] ;# J4.G30 LA29_P
set_property -dict {LOC W11  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_la_n[29]}] ;# J4.G31 LA29_N

set_property -dict {LOC AE7  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_clk0_m2c_p}] ;# J4.H4 CLK0_M2C_P
set_property -dict {LOC AF7  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_clk0_m2c_n}] ;# J4.H5 CLK0_M2C_N
set_property -dict {LOC P10  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_clk1_m2c_p}] ;# J4.G2 CLK1_M2C_P
set_property -dict {LOC P9   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc1_clk1_m2c_n}] ;# J4.G3 CLK1_M2C_N

set_property -dict {LOC F29 } [get_ports {fmc_hpc1_dp_c2m_p[0]}] ;# MGTHTXP0_130 GTHE4_CHANNEL_X0Y14 / GTHE4_COMMON_X0Y3 from J4.C2  DP0_C2M_P
set_property -dict {LOC F30 } [get_ports {fmc_hpc1_dp_c2m_n[0]}] ;# MGTHTXN0_130 GTHE4_CHANNEL_X0Y14 / GTHE4_COMMON_X0Y3 from J4.C3  DP0_C2M_N
set_property -dict {LOC E31 } [get_ports {fmc_hpc1_dp_m2c_p[0]}] ;# MGTHRXP0_130 GTHE4_CHANNEL_X0Y14 / GTHE4_COMMON_X0Y3 from J4.C6  DP0_M2C_P
set_property -dict {LOC E32 } [get_ports {fmc_hpc1_dp_m2c_n[0]}] ;# MGTHRXN0_130 GTHE4_CHANNEL_X0Y14 / GTHE4_COMMON_X0Y3 from J4.C7  DP0_M2C_N
set_property -dict {LOC D29 } [get_ports {fmc_hpc1_dp_c2m_p[1]}] ;# MGTHTXP1_130 GTHE4_CHANNEL_X0Y13 / GTHE4_COMMON_X0Y3 from J4.A22 DP1_C2M_P
set_property -dict {LOC D30 } [get_ports {fmc_hpc1_dp_c2m_n[1]}] ;# MGTHTXN1_130 GTHE4_CHANNEL_X0Y13 / GTHE4_COMMON_X0Y3 from J4.A23 DP1_C2M_N
set_property -dict {LOC D33 } [get_ports {fmc_hpc1_dp_m2c_p[1]}] ;# MGTHRXP1_130 GTHE4_CHANNEL_X0Y13 / GTHE4_COMMON_X0Y3 from J4.A2  DP1_M2C_P
set_property -dict {LOC D34 } [get_ports {fmc_hpc1_dp_m2c_n[1]}] ;# MGTHRXN1_130 GTHE4_CHANNEL_X0Y13 / GTHE4_COMMON_X0Y3 from J4.A3  DP1_M2C_N
set_property -dict {LOC B29 } [get_ports {fmc_hpc1_dp_c2m_p[2]}] ;# MGTHTXP2_130 GTHE4_CHANNEL_X0Y15 / GTHE4_COMMON_X0Y3 from J4.A26 DP2_C2M_P
set_property -dict {LOC B30 } [get_ports {fmc_hpc1_dp_c2m_n[2]}] ;# MGTHTXN2_130 GTHE4_CHANNEL_X0Y15 / GTHE4_COMMON_X0Y3 from J4.A27 DP2_C2M_N
set_property -dict {LOC C31 } [get_ports {fmc_hpc1_dp_m2c_p[2]}] ;# MGTHRXP2_130 GTHE4_CHANNEL_X0Y15 / GTHE4_COMMON_X0Y3 from J4.A6  DP2_M2C_P
set_property -dict {LOC C32 } [get_ports {fmc_hpc1_dp_m2c_n[2]}] ;# MGTHRXN2_130 GTHE4_CHANNEL_X0Y15 / GTHE4_COMMON_X0Y3 from J4.A7  DP2_M2C_N
set_property -dict {LOC A31 } [get_ports {fmc_hpc1_dp_c2m_p[3]}] ;# MGTHTXP3_130 GTHE4_CHANNEL_X0Y12 / GTHE4_COMMON_X0Y3 from J4.A30 DP3_C2M_P
set_property -dict {LOC A32 } [get_ports {fmc_hpc1_dp_c2m_n[3]}] ;# MGTHTXN3_130 GTHE4_CHANNEL_X0Y12 / GTHE4_COMMON_X0Y3 from J4.A31 DP3_C2M_N
set_property -dict {LOC B33 } [get_ports {fmc_hpc1_dp_m2c_p[3]}] ;# MGTHRXP3_130 GTHE4_CHANNEL_X0Y12 / GTHE4_COMMON_X0Y3 from J4.A10 DP3_M2C_P
set_property -dict {LOC B34 } [get_ports {fmc_hpc1_dp_m2c_n[3]}] ;# MGTHRXN3_130 GTHE4_CHANNEL_X0Y12 / GTHE4_COMMON_X0Y3 from J4.A11 DP3_M2C_N

set_property -dict {LOC K29 } [get_ports {fmc_hpc1_dp_c2m_p[4]}] ;# MGTHTXP0_129 GTHE4_CHANNEL_X0Y8  / GTHE4_COMMON_X0Y2 from J4.A34 DP4_C2M_P
set_property -dict {LOC K30 } [get_ports {fmc_hpc1_dp_c2m_n[4]}] ;# MGTHTXN0_129 GTHE4_CHANNEL_X0Y8  / GTHE4_COMMON_X0Y2 from J4.A35 DP4_C2M_N
set_property -dict {LOC L31 } [get_ports {fmc_hpc1_dp_m2c_p[4]}] ;# MGTHRXP0_129 GTHE4_CHANNEL_X0Y8  / GTHE4_COMMON_X0Y2 from J4.A14 DP4_M2C_P
set_property -dict {LOC L32 } [get_ports {fmc_hpc1_dp_m2c_n[4]}] ;# MGTHRXN0_129 GTHE4_CHANNEL_X0Y8  / GTHE4_COMMON_X0Y2 from J4.A15 DP4_M2C_N
set_property -dict {LOC J31 } [get_ports {fmc_hpc1_dp_c2m_p[5]}] ;# MGTHTXP1_129 GTHE4_CHANNEL_X0Y9  / GTHE4_COMMON_X0Y2 from J4.A38 DP5_C2M_P
set_property -dict {LOC J32 } [get_ports {fmc_hpc1_dp_c2m_n[5]}] ;# MGTHTXN1_129 GTHE4_CHANNEL_X0Y9  / GTHE4_COMMON_X0Y2 from J4.A39 DP5_C2M_N
set_property -dict {LOC K33 } [get_ports {fmc_hpc1_dp_m2c_p[5]}] ;# MGTHRXP1_129 GTHE4_CHANNEL_X0Y9  / GTHE4_COMMON_X0Y2 from J4.A18 DP5_M2C_P
set_property -dict {LOC K34 } [get_ports {fmc_hpc1_dp_m2c_n[5]}] ;# MGTHRXN1_129 GTHE4_CHANNEL_X0Y9  / GTHE4_COMMON_X0Y2 from J4.A19 DP5_M2C_N
set_property -dict {LOC H29 } [get_ports {fmc_hpc1_dp_c2m_p[6]}] ;# MGTHTXP2_129 GTHE4_CHANNEL_X0Y10 / GTHE4_COMMON_X0Y2 from J4.B36 DP6_C2M_P
set_property -dict {LOC H30 } [get_ports {fmc_hpc1_dp_c2m_n[6]}] ;# MGTHTXN2_129 GTHE4_CHANNEL_X0Y10 / GTHE4_COMMON_X0Y2 from J4.B37 DP6_C2M_N
set_property -dict {LOC H33 } [get_ports {fmc_hpc1_dp_m2c_p[6]}] ;# MGTHRXP2_129 GTHE4_CHANNEL_X0Y10 / GTHE4_COMMON_X0Y2 from J4.B16 DP6_M2C_P
set_property -dict {LOC H34 } [get_ports {fmc_hpc1_dp_m2c_n[6]}] ;# MGTHRXN2_129 GTHE4_CHANNEL_X0Y10 / GTHE4_COMMON_X0Y2 from J4.B17 DP6_M2C_N
set_property -dict {LOC G31 } [get_ports {fmc_hpc1_dp_c2m_p[7]}] ;# MGTHTXP3_129 GTHE4_CHANNEL_X0Y11 / GTHE4_COMMON_X0Y2 from J4.B32 DP7_C2M_P
set_property -dict {LOC G32 } [get_ports {fmc_hpc1_dp_c2m_n[7]}] ;# MGTHTXN3_129 GTHE4_CHANNEL_X0Y11 / GTHE4_COMMON_X0Y2 from J4.B33 DP7_C2M_N
set_property -dict {LOC F33 } [get_ports {fmc_hpc1_dp_m2c_p[7]}] ;# MGTHRXP3_129 GTHE4_CHANNEL_X0Y11 / GTHE4_COMMON_X0Y2 from J4.B12 DP7_M2C_P
set_property -dict {LOC F34 } [get_ports {fmc_hpc1_dp_m2c_n[7]}] ;# MGTHRXN3_129 GTHE4_CHANNEL_X0Y11 / GTHE4_COMMON_X0Y2 from J4.B13 DP7_M2C_N
set_property -dict {LOC G27 } [get_ports {fmc_hpc1_mgt_refclk_0_p}] ;# MGTREFCLK0P_130 from J4.D4 GBTCLK0_M2C_P
set_property -dict {LOC G28 } [get_ports {fmc_hpc1_mgt_refclk_0_n}] ;# MGTREFCLK0N_130 from J4.D5 GBTCLK0_M2C_N
set_property -dict {LOC E27 } [get_ports {fmc_hpc1_mgt_refclk_1_p}] ;# MGTREFCLK1P_130 from J4.B20 GBTCLK1_M2C_P
set_property -dict {LOC E28 } [get_ports {fmc_hpc1_mgt_refclk_1_n}] ;# MGTREFCLK1N_130 from J4.B21 GBTCLK1_M2C_N
set_property -dict {LOC L27 } [get_ports {fmc_hpc1_mgt_refclk_2_p}] ;# MGTREFCLK0P_129 from U56 SI570 via U51 SI53340
set_property -dict {LOC L28 } [get_ports {fmc_hpc1_mgt_refclk_2_n}] ;# MGTREFCLK0N_129 from U56 SI570 via U51 SI53340
set_property -dict {LOC J27 } [get_ports {fmc_hpc1_mgt_refclk_3_p}] ;# MGTREFCLK1P_129 from J79
set_property -dict {LOC J28 } [get_ports {fmc_hpc1_mgt_refclk_3_n}] ;# MGTREFCLK1N_129 from J80

# reference clock
create_clock -period 6.400 -name fmc_hpc1_mgt_refclk_0 [get_ports {fmc_hpc1_mgt_refclk_0_p}]
create_clock -period 6.400 -name fmc_hpc1_mgt_refclk_1 [get_ports {fmc_hpc1_mgt_refclk_1_p}]
