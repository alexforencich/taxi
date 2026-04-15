# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Xilinx ZCU102 board
# part: xczu9eg-ffvb1156-2-e

# FMC HPC0 J5
set_property -dict {LOC Y4   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[0]}]  ;# J5.G9  LA00_P_CC
set_property -dict {LOC Y3   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[0]}]  ;# J5.G10 LA00_N_CC
set_property -dict {LOC AB4  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[1]}]  ;# J5.D8  LA01_P_CC
set_property -dict {LOC AC4  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[1]}]  ;# J5.D9  LA01_N_CC
set_property -dict {LOC V2   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[2]}]  ;# J5.H7  LA02_P
set_property -dict {LOC V1   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[2]}]  ;# J5.H8  LA02_N
set_property -dict {LOC Y2   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[3]}]  ;# J5.G12 LA03_P
set_property -dict {LOC Y1   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[3]}]  ;# J5.G13 LA03_N
set_property -dict {LOC AA2  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[4]}]  ;# J5.H10 LA04_P
set_property -dict {LOC AA1  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[4]}]  ;# J5.H11 LA04_N
set_property -dict {LOC AB3  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[5]}]  ;# J5.D11 LA05_P
set_property -dict {LOC AC3  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[5]}]  ;# J5.D12 LA05_N
set_property -dict {LOC AC2  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[6]}]  ;# J5.C10 LA06_P
set_property -dict {LOC AC1  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[6]}]  ;# J5.C11 LA06_N
set_property -dict {LOC U5   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[7]}]  ;# J5.H13 LA07_P
set_property -dict {LOC U4   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[7]}]  ;# J5.H14 LA07_N
set_property -dict {LOC V4   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[8]}]  ;# J5.G12 LA08_P
set_property -dict {LOC V3   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[8]}]  ;# J5.G13 LA08_N
set_property -dict {LOC W2   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[9]}]  ;# J5.D14 LA09_P
set_property -dict {LOC W1   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[9]}]  ;# J5.D15 LA09_N
set_property -dict {LOC W5   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[10]}] ;# J5.C14 LA10_P
set_property -dict {LOC W4   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[10]}] ;# J5.C15 LA10_N
set_property -dict {LOC AB6  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[11]}] ;# J5.H16 LA11_P
set_property -dict {LOC AB5  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[11]}] ;# J5.H17 LA11_N
set_property -dict {LOC W7   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[12]}] ;# J5.G15 LA12_P
set_property -dict {LOC W6   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[12]}] ;# J5.G16 LA12_N
set_property -dict {LOC AB8  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[13]}] ;# J5.D17 LA13_P
set_property -dict {LOC AC8  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[13]}] ;# J5.D18 LA13_N
set_property -dict {LOC AC7  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[14]}] ;# J5.C18 LA14_P
set_property -dict {LOC AC6  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[14]}] ;# J5.C19 LA14_N
set_property -dict {LOC Y10  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[15]}] ;# J5.H19 LA15_P
set_property -dict {LOC Y9   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[15]}] ;# J5.H20 LA15_N
set_property -dict {LOC Y12  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[16]}] ;# J5.G18 LA16_P
set_property -dict {LOC AA12 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[16]}] ;# J5.G19 LA16_N
set_property -dict {LOC P11  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[17]}] ;# J5.D20 LA17_P_CC
set_property -dict {LOC N11  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[17]}] ;# J5.D21 LA17_N_CC
set_property -dict {LOC N9   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[18]}] ;# J5.C22 LA18_P_CC
set_property -dict {LOC N8   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[18]}] ;# J5.C23 LA18_N_CC
set_property -dict {LOC L13  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[19]}] ;# J5.H22 LA19_P
set_property -dict {LOC K13  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[19]}] ;# J5.H23 LA19_N
set_property -dict {LOC N13  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[20]}] ;# J5.G21 LA20_P
set_property -dict {LOC M13  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[20]}] ;# J5.G22 LA20_N
set_property -dict {LOC P12  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[21]}] ;# J5.H25 LA21_P
set_property -dict {LOC N12  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[21]}] ;# J5.H26 LA21_N
set_property -dict {LOC M15  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[22]}] ;# J5.G24 LA22_P
set_property -dict {LOC M14  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[22]}] ;# J5.G25 LA22_N
set_property -dict {LOC L16  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[23]}] ;# J5.D23 LA23_P
set_property -dict {LOC K16  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[23]}] ;# J5.D24 LA23_N
set_property -dict {LOC L12  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[24]}] ;# J5.H28 LA24_P
set_property -dict {LOC K12  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[24]}] ;# J5.H29 LA24_N
set_property -dict {LOC M11  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[25]}] ;# J5.G27 LA25_P
set_property -dict {LOC L11  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[25]}] ;# J5.G28 LA25_N
set_property -dict {LOC L15  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[26]}] ;# J5.D26 LA26_P
set_property -dict {LOC K15  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[26]}] ;# J5.D27 LA26_N
set_property -dict {LOC M10  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[27]}] ;# J5.C26 LA27_P
set_property -dict {LOC L10  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[27]}] ;# J5.C27 LA27_N
set_property -dict {LOC T7   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[28]}] ;# J5.H31 LA28_P
set_property -dict {LOC T6   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[28]}] ;# J5.H32 LA28_N
set_property -dict {LOC U9   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[29]}] ;# J5.G30 LA29_P
set_property -dict {LOC U8   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[29]}] ;# J5.G31 LA29_N
set_property -dict {LOC V6   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[30]}] ;# J5.H34 LA30_P
set_property -dict {LOC U6   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[30]}] ;# J5.H35 LA30_N
set_property -dict {LOC V8   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[31]}] ;# J5.G33 LA31_P
set_property -dict {LOC V7   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[31]}] ;# J5.G34 LA31_N
set_property -dict {LOC U11  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[32]}] ;# J5.H37 LA32_P
set_property -dict {LOC T11  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[32]}] ;# J5.H38 LA32_N
set_property -dict {LOC V12  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_p[33]}] ;# J5.G36 LA33_P
set_property -dict {LOC V11  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_la_n[33]}] ;# J5.G37 LA33_N

set_property -dict {LOC AA7  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_clk0_m2c_p}] ;# J5.H4 CLK0_M2C_P
set_property -dict {LOC AA6  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_clk0_m2c_n}] ;# J5.H5 CLK0_M2C_N
set_property -dict {LOC T8   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_clk1_m2c_p}] ;# J5.G2 CLK1_M2C_P
set_property -dict {LOC R8   IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc0_clk1_m2c_n}] ;# J5.G3 CLK1_M2C_N

set_property -dict {LOC G4  } [get_ports {fmc_hpc0_dp_c2m_p[0]}] ;# MGTHTXP2_229 GTHE4_CHANNEL_X1Y10 / GTHE4_COMMON_X1Y2 from J5.C2  DP0_C2M_P
set_property -dict {LOC G3  } [get_ports {fmc_hpc0_dp_c2m_n[0]}] ;# MGTHTXN2_229 GTHE4_CHANNEL_X1Y10 / GTHE4_COMMON_X1Y2 from J5.C3  DP0_C2M_N
set_property -dict {LOC H2  } [get_ports {fmc_hpc0_dp_m2c_p[0]}] ;# MGTHRXP2_229 GTHE4_CHANNEL_X1Y10 / GTHE4_COMMON_X1Y2 from J5.C6  DP0_M2C_P
set_property -dict {LOC H1  } [get_ports {fmc_hpc0_dp_m2c_n[0]}] ;# MGTHRXN2_229 GTHE4_CHANNEL_X1Y10 / GTHE4_COMMON_X1Y2 from J5.C7  DP0_M2C_N
set_property -dict {LOC H6  } [get_ports {fmc_hpc0_dp_c2m_p[1]}] ;# MGTHTXP1_229 GTHE4_CHANNEL_X1Y9  / GTHE4_COMMON_X1Y2 from J5.A22 DP1_C2M_P
set_property -dict {LOC H5  } [get_ports {fmc_hpc0_dp_c2m_n[1]}] ;# MGTHTXN1_229 GTHE4_CHANNEL_X1Y9  / GTHE4_COMMON_X1Y2 from J5.A23 DP1_C2M_N
set_property -dict {LOC J4  } [get_ports {fmc_hpc0_dp_m2c_p[1]}] ;# MGTHRXP1_229 GTHE4_CHANNEL_X1Y9  / GTHE4_COMMON_X1Y2 from J5.A2  DP1_M2C_P
set_property -dict {LOC J3  } [get_ports {fmc_hpc0_dp_m2c_n[1]}] ;# MGTHRXN1_229 GTHE4_CHANNEL_X1Y9  / GTHE4_COMMON_X1Y2 from J5.A3  DP1_M2C_N
set_property -dict {LOC F6  } [get_ports {fmc_hpc0_dp_c2m_p[2]}] ;# MGTHTXP3_229 GTHE4_CHANNEL_X1Y11 / GTHE4_COMMON_X1Y2 from J5.A26 DP2_C2M_P
set_property -dict {LOC F5  } [get_ports {fmc_hpc0_dp_c2m_n[2]}] ;# MGTHTXN3_229 GTHE4_CHANNEL_X1Y11 / GTHE4_COMMON_X1Y2 from J5.A27 DP2_C2M_N
set_property -dict {LOC F2  } [get_ports {fmc_hpc0_dp_m2c_p[2]}] ;# MGTHRXP3_229 GTHE4_CHANNEL_X1Y11 / GTHE4_COMMON_X1Y2 from J5.A6  DP2_M2C_P
set_property -dict {LOC F1  } [get_ports {fmc_hpc0_dp_m2c_n[2]}] ;# MGTHRXN3_229 GTHE4_CHANNEL_X1Y11 / GTHE4_COMMON_X1Y2 from J5.A7  DP2_M2C_N
set_property -dict {LOC K6  } [get_ports {fmc_hpc0_dp_c2m_p[3]}] ;# MGTHTXP0_229 GTHE4_CHANNEL_X1Y8  / GTHE4_COMMON_X1Y2 from J5.A30 DP3_C2M_P
set_property -dict {LOC K5  } [get_ports {fmc_hpc0_dp_c2m_n[3]}] ;# MGTHTXN0_229 GTHE4_CHANNEL_X1Y8  / GTHE4_COMMON_X1Y2 from J5.A31 DP3_C2M_N
set_property -dict {LOC K2  } [get_ports {fmc_hpc0_dp_m2c_p[3]}] ;# MGTHRXP0_229 GTHE4_CHANNEL_X1Y8  / GTHE4_COMMON_X1Y2 from J5.A10 DP3_M2C_P
set_property -dict {LOC K1  } [get_ports {fmc_hpc0_dp_m2c_n[3]}] ;# MGTHRXN0_229 GTHE4_CHANNEL_X1Y8  / GTHE4_COMMON_X1Y2 from J5.A11 DP3_M2C_N

set_property -dict {LOC M6  } [get_ports {fmc_hpc0_dp_c2m_p[4]}] ;# MGTHTXP3_228 GTHE4_CHANNEL_X1Y7 / GTHE4_COMMON_X1Y1 from J5.A34 DP4_C2M_P
set_property -dict {LOC M5  } [get_ports {fmc_hpc0_dp_c2m_n[4]}] ;# MGTHTXN3_228 GTHE4_CHANNEL_X1Y7 / GTHE4_COMMON_X1Y1 from J5.A35 DP4_C2M_N
set_property -dict {LOC L4  } [get_ports {fmc_hpc0_dp_m2c_p[4]}] ;# MGTHRXP3_228 GTHE4_CHANNEL_X1Y7 / GTHE4_COMMON_X1Y1 from J5.A14 DP4_M2C_P
set_property -dict {LOC L3  } [get_ports {fmc_hpc0_dp_m2c_n[4]}] ;# MGTHRXN3_228 GTHE4_CHANNEL_X1Y7 / GTHE4_COMMON_X1Y1 from J5.A15 DP4_M2C_N
set_property -dict {LOC P6  } [get_ports {fmc_hpc0_dp_c2m_p[5]}] ;# MGTHTXP1_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from J5.A38 DP5_C2M_P
set_property -dict {LOC P5  } [get_ports {fmc_hpc0_dp_c2m_n[5]}] ;# MGTHTXN1_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from J5.A39 DP5_C2M_N
set_property -dict {LOC P2  } [get_ports {fmc_hpc0_dp_m2c_p[5]}] ;# MGTHRXP1_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from J5.A18 DP5_M2C_P
set_property -dict {LOC P1  } [get_ports {fmc_hpc0_dp_m2c_n[5]}] ;# MGTHRXN1_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from J5.A19 DP5_M2C_N
set_property -dict {LOC R4  } [get_ports {fmc_hpc0_dp_c2m_p[6]}] ;# MGTHTXP0_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from J5.B36 DP6_C2M_P
set_property -dict {LOC R3  } [get_ports {fmc_hpc0_dp_c2m_n[6]}] ;# MGTHTXN0_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from J5.B37 DP6_C2M_N
set_property -dict {LOC T2  } [get_ports {fmc_hpc0_dp_m2c_p[6]}] ;# MGTHRXP0_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from J5.B16 DP6_M2C_P
set_property -dict {LOC T1  } [get_ports {fmc_hpc0_dp_m2c_n[6]}] ;# MGTHRXN0_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from J5.B17 DP6_M2C_N
set_property -dict {LOC N4  } [get_ports {fmc_hpc0_dp_c2m_p[7]}] ;# MGTHTXP2_228 GTHE4_CHANNEL_X1Y6 / GTHE4_COMMON_X1Y1 from J5.B32 DP7_C2M_P
set_property -dict {LOC N3  } [get_ports {fmc_hpc0_dp_c2m_n[7]}] ;# MGTHTXN2_228 GTHE4_CHANNEL_X1Y6 / GTHE4_COMMON_X1Y1 from J5.B33 DP7_C2M_N
set_property -dict {LOC M2  } [get_ports {fmc_hpc0_dp_m2c_p[7]}] ;# MGTHRXP2_228 GTHE4_CHANNEL_X1Y6 / GTHE4_COMMON_X1Y1 from J5.B12 DP7_M2C_P
set_property -dict {LOC M1  } [get_ports {fmc_hpc0_dp_m2c_n[7]}] ;# MGTHRXN2_228 GTHE4_CHANNEL_X1Y6 / GTHE4_COMMON_X1Y1 from J5.B13 DP7_M2C_N
set_property -dict {LOC G8  } [get_ports {fmc_hpc0_mgt_refclk_0_p}] ;# MGTREFCLK0P_229 from J5.D4 GBTCLK0_M2C_P
set_property -dict {LOC G7  } [get_ports {fmc_hpc0_mgt_refclk_0_n}] ;# MGTREFCLK0N_229 from J5.D5 GBTCLK0_M2C_N
set_property -dict {LOC L8  } [get_ports {fmc_hpc0_mgt_refclk_1_p}] ;# MGTREFCLK0P_228 from J5.B20 GBTCLK1_M2C_P
set_property -dict {LOC L7  } [get_ports {fmc_hpc0_mgt_refclk_1_n}] ;# MGTREFCLK0N_228 from J5.B21 GBTCLK1_M2C_N

# reference clock
create_clock -period 6.400 -name fmc_hpc0_mgt_refclk_0 [get_ports {fmc_hpc0_mgt_refclk_0_p}]
create_clock -period 6.400 -name fmc_hpc0_mgt_refclk_1 [get_ports {fmc_hpc0_mgt_refclk_1_p}]
