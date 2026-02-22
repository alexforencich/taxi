# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Opal Kelley XEM8320 board
# part: xcau25p-ffvb676-2-e

# General configuration
set_property CFGBVS GND                                [current_design]
set_property CONFIG_VOLTAGE 1.8                        [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true           [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup         [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 85            [current_design]
set_property CONFIG_MODE SPIx4                         [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4           [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE Yes        [current_design]
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable  [current_design]

# System clocks
# 100 MHz system clock
set_property -dict {LOC T24  IOSTANDARD LVDS} [get_ports clk_100mhz_p] ;# from U42
set_property -dict {LOC U24  IOSTANDARD LVDS} [get_ports clk_100mhz_n] ;# from U42
create_clock -period 10.000 -name clk_100mhz [get_ports clk_100mhz_p]

# 100 MHz DDR4 clock
#set_property -dict {LOC AD20 IOSTANDARD DIFF_SSTL12} [get_ports clk_ddr4_p] ;# from U43
#set_property -dict {LOC AE20 IOSTANDARD DIFF_SSTL12} [get_ports clk_ddr4_n] ;# from U43
#create_clock -period 10.000 -name clk_ddr4 [get_ports clk_ddr4_p]

# LEDs
set_property -dict {LOC G19  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[0]}] ;# to D1
set_property -dict {LOC B16  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[1]}] ;# to D2
set_property -dict {LOC F22  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[2]}] ;# to D3
set_property -dict {LOC E22  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[3]}] ;# to D4
set_property -dict {LOC M24  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[4]}] ;# to D5
set_property -dict {LOC G22  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[5]}] ;# to D6

set_false_path -to [get_ports {led[*]}]
set_output_delay 0 [get_ports {led[*]}]

# SFP+ interfaces
set_property -dict {LOC M2  } [get_ports {sfp_rx_p[0]}] ;# MGTYRXP0_226 GTYE3_CHANNEL_X0Y9  / GTYE3_COMMON_X0Y2
set_property -dict {LOC M1  } [get_ports {sfp_rx_n[0]}] ;# MGTYRXN0_226 GTYE3_CHANNEL_X0Y9  / GTYE3_COMMON_X0Y2
set_property -dict {LOC N5  } [get_ports {sfp_tx_p[0]}] ;# MGTYTXP0_226 GTYE3_CHANNEL_X0Y9  / GTYE3_COMMON_X0Y2
set_property -dict {LOC N4  } [get_ports {sfp_tx_n[0]}] ;# MGTYTXN0_226 GTYE3_CHANNEL_X0Y9  / GTYE3_COMMON_X0Y2
set_property -dict {LOC K2  } [get_ports {sfp_rx_p[1]}] ;# MGTYRXP1_226 GTYE3_CHANNEL_X0Y10 / GTYE3_COMMON_X0Y2
set_property -dict {LOC K1  } [get_ports {sfp_rx_n[1]}] ;# MGTYRXN1_226 GTYE3_CHANNEL_X0Y10 / GTYE3_COMMON_X0Y2
set_property -dict {LOC L5  } [get_ports {sfp_tx_p[1]}] ;# MGTYTXP1_226 GTYE3_CHANNEL_X0Y10 / GTYE3_COMMON_X0Y2
set_property -dict {LOC L4  } [get_ports {sfp_tx_n[1]}] ;# MGTYTXN1_226 GTYE3_CHANNEL_X0Y10 / GTYE3_COMMON_X0Y2
#set_property -dict {LOC P7  } [get_ports sfp_mgt_refclk_0_p] ;# MGTREFCLK0P_226 from U39
#set_property -dict {LOC P6  } [get_ports sfp_mgt_refclk_0_n] ;# MGTREFCLK0N_226 from U39
#set_property -dict {LOC M7  } [get_ports sfp_mgt_refclk_1_p] ;# MGTREFCLK1P_226 from J19
#set_property -dict {LOC M6  } [get_ports sfp_mgt_refclk_1_n] ;# MGTREFCLK1N_226 from J20
set_property -dict {LOC Y7  } [get_ports sfp_mgt_refclk_2_p] ;# MGTREFCLK0P_224 from U52
set_property -dict {LOC Y6  } [get_ports sfp_mgt_refclk_2_n] ;# MGTREFCLK0N_224 from U52
set_property -dict {LOC C13 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_tx_disable[0]}]
set_property -dict {LOC F13 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_tx_disable[1]}]
set_property -dict {LOC C14 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_tx_fault[0]}]
set_property -dict {LOC F14 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_tx_fault[1]}]
set_property -dict {LOC D14 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_npres[0]}]
set_property -dict {LOC A14 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_npres[1]}]
set_property -dict {LOC E13 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_los[0]}]
set_property -dict {LOC A13 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {sfp_los[1]}]
set_property -dict {LOC D13 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_rs[0][0]}]
set_property -dict {LOC E12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_rs[0][1]}]
set_property -dict {LOC B14 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_rs[1][0]}]
set_property -dict {LOC A12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports {sfp_rs[1][1]}]
#set_property -dict {LOC B12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_sda[0]}]
#set_property -dict {LOC C12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_scl[0]}]
#set_property -dict {LOC F12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_sda[1]}]
#set_property -dict {LOC G12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {sfp_i2c_scl[1]}]

# 156.25 MHz MGT reference clock
#create_clock -period 8.000 -name sfp_mgt_refclk_0 [get_ports sfp_mgt_refclk_0_p]

# MGT reference clock from SMA
#create_clock -period 6.400 -name sfp_mgt_refclk_1 [get_ports sfp_mgt_refclk_1_p]

# 156.25 MHz MGT reference clock
create_clock -period 6.400 -name sfp_mgt_refclk_2 [get_ports sfp_mgt_refclk_2_p]

set_false_path -to [get_ports {sfp_tx_disable[*] sfp_rs[*]}]
set_output_delay 0 [get_ports {sfp_tx_disable[*] sfp_rs[*]}]
set_false_path -from [get_ports {sfp_tx_fault[*] sfp_npres[*] sfp_los[*]}]
set_input_delay 0 [get_ports {sfp_tx_fault[*] sfp_npres[*] sfp_los[*]}]

#set_false_path -to [get_ports {sfp_i2c_sda[*] sfp_i2c_scl[*]}]
#set_output_delay 0 [get_ports {sfp_i2c_sda[*] sfp_i2c_scl[*]}]
#set_false_path -from [get_ports {sfp_i2c_sda[*] sfp_i2c_scl[*]}]
#set_input_delay 0 [get_ports {sfp_i2c_sda[*] sfp_i2c_scl[*]}]

# DDR4
# MT40A512M16LY-075:E U16
#set_property -dict {LOC AD18 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[0]}]
#set_property -dict {LOC AE17 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[1]}]
#set_property -dict {LOC AB17 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[2]}]
#set_property -dict {LOC AE18 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[3]}]
#set_property -dict {LOC AD19 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[4]}]
#set_property -dict {LOC AF17 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[5]}]
#set_property -dict {LOC Y17  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[6]}]
#set_property -dict {LOC AE16 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[7]}]
#set_property -dict {LOC AA17 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[8]}]
#set_property -dict {LOC AC17 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[9]}]
#set_property -dict {LOC AC19 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[10]}]
#set_property -dict {LOC AC16 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[11]}]
#set_property -dict {LOC AF20 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[12]}]
#set_property -dict {LOC AD16 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[13]}]
#set_property -dict {LOC AA19 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[14]}]
#set_property -dict {LOC AF19 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[15]}]
#set_property -dict {LOC AA18 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[16]}]
#set_property -dict {LOC AC18 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_ba[0]}]
#set_property -dict {LOC AF18 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_ba[1]}]
#set_property -dict {LOC AB19 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_bg[0]}]
#set_property -dict {LOC Y20  IOSTANDARD DIFF_SSTL12_DCI} [get_ports {ddr4_ck_t}]
#set_property -dict {LOC Y21  IOSTANDARD DIFF_SSTL12_DCI} [get_ports {ddr4_ck_c}]
#set_property -dict {LOC AA20 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_cke}]
#set_property -dict {LOC AF22 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_cs_n}]
#set_property -dict {LOC Y18  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_act_n}]
#set_property -dict {LOC AB20 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_odt}]
#set_property -dict {LOC AE26 IOSTANDARD LVCMOS12       } [get_ports {ddr4_reset_n}]

#set_property -dict {LOC AF24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[0]}]
#set_property -dict {LOC AB25 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[1]}]
#set_property -dict {LOC AB26 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[2]}]
#set_property -dict {LOC AC24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[3]}]
#set_property -dict {LOC AF25 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[4]}]
#set_property -dict {LOC AB24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[5]}]
#set_property -dict {LOC AD24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[6]}]
#set_property -dict {LOC AD25 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[7]}]
#set_property -dict {LOC AB21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[8]}]
#set_property -dict {LOC AE21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[9]}]
#set_property -dict {LOC AE23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[10]}]
#set_property -dict {LOC AD23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[11]}]
#set_property -dict {LOC AC23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[12]}]
#set_property -dict {LOC AD21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[13]}]
#set_property -dict {LOC AC22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[14]}]
#set_property -dict {LOC AC21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[15]}]
#set_property -dict {LOC AC26 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[0]}]     ;# U16.G3 DQSL_T
#set_property -dict {LOC AD26 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[0]}]     ;# U16.F3 DQSL_C
#set_property -dict {LOC AA22 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[1]}]     ;# U16.B7 DQSU_T
#set_property -dict {LOC AB22 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[1]}]     ;# U16.A7 DQSU_C
#set_property -dict {LOC AE25 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[0]}]  ;# U16.E7 DML_B/DBIL_B
#set_property -dict {LOC AE22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[1]}]  ;# U16.E2 DMU_B/DBIU_B
