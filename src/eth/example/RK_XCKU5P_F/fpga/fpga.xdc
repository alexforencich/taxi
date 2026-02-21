# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the RK-XCKU5P-F
# part: xcku5p-ffvb676-2-e

# General configuration
set_property CFGBVS GND                                      [current_design]
set_property CONFIG_VOLTAGE 1.8                              [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true                 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup               [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 72.9                [current_design]
set_property CONFIG_MODE SPIx4                               [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4                 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE Yes              [current_design]
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable        [current_design]

# 200 MHz system clock (Y2)
set_property -dict {LOC T24  IOSTANDARD LVDS} [get_ports {clk_200mhz_p}]
set_property -dict {LOC U24  IOSTANDARD LVDS} [get_ports {clk_200mhz_n}]
create_clock -period 5.000 -name clk_200mhz [get_ports {clk_200mhz_p}]

# LEDs
set_property -dict {LOC H9   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {led[0]}]
set_property -dict {LOC J9   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {led[1]}]
set_property -dict {LOC G11  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {led[2]}]
set_property -dict {LOC H11  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12} [get_ports {led[3]}]

set_false_path -to [get_ports {led[*]}]
set_output_delay 0 [get_ports {led[*]}]

# Buttons
set_property -dict {LOC K9   IOSTANDARD LVCMOS33} [get_ports {btn[0]}]
set_property -dict {LOC K10  IOSTANDARD LVCMOS33} [get_ports {btn[1]}]
set_property -dict {LOC J10  IOSTANDARD LVCMOS33} [get_ports {btn[2]}]
set_property -dict {LOC J11  IOSTANDARD LVCMOS33} [get_ports {btn[3]}]

set_false_path -from [get_ports {btn[*]}]
set_input_delay 0 [get_ports {btn[*]}]

# GPIO
#set_property -dict {LOC D10  IOSTANDARD LVCMOS33} [get_ports {gpio[0]}]  ;# 3
#set_property -dict {LOC D11  IOSTANDARD LVCMOS33} [get_ports {gpio[1]}]  ;# 4
#set_property -dict {LOC E10  IOSTANDARD LVCMOS33} [get_ports {gpio[2]}]  ;# 5
#set_property -dict {LOC E11  IOSTANDARD LVCMOS33} [get_ports {gpio[3]}]  ;# 6
#set_property -dict {LOC B11  IOSTANDARD LVCMOS33} [get_ports {gpio[4]}]  ;# 7
#set_property -dict {LOC C11  IOSTANDARD LVCMOS33} [get_ports {gpio[5]}]  ;# 8
#set_property -dict {LOC C9   IOSTANDARD LVCMOS33} [get_ports {gpio[6]}]  ;# 9
#set_property -dict {LOC D9   IOSTANDARD LVCMOS33} [get_ports {gpio[7]}]  ;# 10
#set_property -dict {LOC A9   IOSTANDARD LVCMOS33} [get_ports {gpio[8]}]  ;# 11
#set_property -dict {LOC B9   IOSTANDARD LVCMOS33} [get_ports {gpio[9]}]  ;# 12
#set_property -dict {LOC A10  IOSTANDARD LVCMOS33} [get_ports {gpio[10]}] ;# 13
#set_property -dict {LOC B10  IOSTANDARD LVCMOS33} [get_ports {gpio[11]}] ;# 14
#set_property -dict {LOC A12  IOSTANDARD LVCMOS33} [get_ports {gpio[12]}] ;# 15
#set_property -dict {LOC A13  IOSTANDARD LVCMOS33} [get_ports {gpio[13]}] ;# 16
#set_property -dict {LOC A14  IOSTANDARD LVCMOS33} [get_ports {gpio[14]}] ;# 17
#set_property -dict {LOC B14  IOSTANDARD LVCMOS33} [get_ports {gpio[15]}] ;# 18
#set_property -dict {LOC C13  IOSTANDARD LVCMOS33} [get_ports {gpio[16]}] ;# 19
#set_property -dict {LOC C14  IOSTANDARD LVCMOS33} [get_ports {gpio[17]}] ;# 20
#set_property -dict {LOC B12  IOSTANDARD LVCMOS33} [get_ports {gpio[18]}] ;# 21
#set_property -dict {LOC C12  IOSTANDARD LVCMOS33} [get_ports {gpio[19]}] ;# 22
#set_property -dict {LOC D13  IOSTANDARD LVCMOS33} [get_ports {gpio[20]}] ;# 23
#set_property -dict {LOC D14  IOSTANDARD LVCMOS33} [get_ports {gpio[21]}] ;# 24
#set_property -dict {LOC E12  IOSTANDARD LVCMOS33} [get_ports {gpio[22]}] ;# 25
#set_property -dict {LOC E13  IOSTANDARD LVCMOS33} [get_ports {gpio[23]}] ;# 26
#set_property -dict {LOC F13  IOSTANDARD LVCMOS33} [get_ports {gpio[24]}] ;# 27
#set_property -dict {LOC F14  IOSTANDARD LVCMOS33} [get_ports {gpio[25]}] ;# 28
#set_property -dict {LOC F12  IOSTANDARD LVCMOS33} [get_ports {gpio[26]}] ;# 29
#set_property -dict {LOC G12  IOSTANDARD LVCMOS33} [get_ports {gpio[27]}] ;# 30
#set_property -dict {LOC G14  IOSTANDARD LVCMOS33} [get_ports {gpio[28]}] ;# 31
#set_property -dict {LOC H14  IOSTANDARD LVCMOS33} [get_ports {gpio[29]}] ;# 32
#set_property -dict {LOC J14  IOSTANDARD LVCMOS33} [get_ports {gpio[30]}] ;# 33
#set_property -dict {LOC J15  IOSTANDARD LVCMOS33} [get_ports {gpio[31]}] ;# 34
#set_property -dict {LOC H13  IOSTANDARD LVCMOS33} [get_ports {gpio[32]}] ;# 35
#set_property -dict {LOC J13  IOSTANDARD LVCMOS33} [get_ports {gpio[33]}] ;# 36

# UART
set_property -dict {LOC AC14 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {uart_txd}]
set_property -dict {LOC AD13 IOSTANDARD LVCMOS18} [get_ports {uart_rxd}]

set_false_path -to [get_ports {uart_txd}]
set_output_delay 0 [get_ports {uart_txd}]
set_false_path -from [get_ports {uart_rxd}]
set_input_delay 0 [get_ports {uart_rxd}]

# Micro SD
#set_property -dict {LOC Y15  IOSTANDARD LVCMOS18 SLEW FAST DRIVE 8} [get_ports {sdio_clk}] ;# 5 CLK SCLK
#set_property -dict {LOC AA15 IOSTANDARD LVCMOS18 SLEW FAST DRIVE 8} [get_ports {sdio_cmd}] ;# 3 CMD DI
#set_property -dict {LOC AB14 IOSTANDARD LVCMOS18 SLEW FAST DRIVE 8} [get_ports {sdio_dat[0]}] ;# 7 DAT0 DO
#set_property -dict {LOC AA14 IOSTANDARD LVCMOS18 SLEW FAST DRIVE 8} [get_ports {sdio_dat[1]}] ;# 8 DAT1
#set_property -dict {LOC AB16 IOSTANDARD LVCMOS18 SLEW FAST DRIVE 8} [get_ports {sdio_dat[2]}] ;# 1 DAT2
#set_property -dict {LOC AB15 IOSTANDARD LVCMOS18 SLEW FAST DRIVE 8} [get_ports {sdio_dat[3]}] ;# 2 CD/DAT3 CS
#set_property -dict {LOC Y16  IOSTANDARD LVCMOS18 SLEW FAST DRIVE 8} [get_ports {sdio_det}] ;# 9 DET

# Fan
#set_property -dict {LOC G9 IOSTANDARD LVCMOS18 QUIETIO SLOW DRIVE 8} [get_ports {fan}]

# Gigabit Ethernet RGMII PHY
set_property -dict {LOC K22  IOSTANDARD LVCMOS18} [get_ports {phy_rx_clk}] ;# from 28 RXC
set_property -dict {LOC L24  IOSTANDARD LVCMOS18} [get_ports {phy_rxd[0]}] ;# from 26 RXD0
set_property -dict {LOC L25  IOSTANDARD LVCMOS18} [get_ports {phy_rxd[1]}] ;# from 25 RXD1
set_property -dict {LOC K25  IOSTANDARD LVCMOS18} [get_ports {phy_rxd[2]}] ;# from 24 RXD2
set_property -dict {LOC K26  IOSTANDARD LVCMOS18} [get_ports {phy_rxd[3]}] ;# from 23 RXD3
set_property -dict {LOC K23  IOSTANDARD LVCMOS18} [get_ports {phy_rx_ctl}] ;# from 27 RXCTL
set_property -dict {LOC M25  IOSTANDARD LVCMOS18 SLEW FAST DRIVE 12} [get_ports {phy_tx_clk}] ;# from 21 TXC
set_property -dict {LOC L23  IOSTANDARD LVCMOS18 SLEW FAST DRIVE 12} [get_ports {phy_txd[0]}] ;# from 19 TXD0
set_property -dict {LOC L22  IOSTANDARD LVCMOS18 SLEW FAST DRIVE 12} [get_ports {phy_txd[1]}] ;# from 18 TXD1
set_property -dict {LOC L20  IOSTANDARD LVCMOS18 SLEW FAST DRIVE 12} [get_ports {phy_txd[2]}] ;# from 17 TXD2
set_property -dict {LOC K20  IOSTANDARD LVCMOS18 SLEW FAST DRIVE 12} [get_ports {phy_txd[3]}] ;# from 16 TXD3
set_property -dict {LOC M26  IOSTANDARD LVCMOS18 SLEW FAST DRIVE 12} [get_ports {phy_tx_ctl}] ;# from 20 TXCTL

create_clock -period 8.000 -name {phy_rx_clk} [get_ports {phy_rx_clk}]

# QSFP28 Interface
set_property -dict {LOC Y2  } [get_ports {qsfp_rx_p[0]}] ;# MGTYRXP0_225 GTYE4_CHANNEL_X0Y4 / GTYE4_COMMON_X0Y1
set_property -dict {LOC Y1  } [get_ports {qsfp_rx_n[0]}] ;# MGTYRXN0_225 GTYE4_CHANNEL_X0Y4 / GTYE4_COMMON_X0Y1
set_property -dict {LOC AA5 } [get_ports {qsfp_tx_p[0]}] ;# MGTYTXP0_225 GTYE4_CHANNEL_X0Y4 / GTYE4_COMMON_X0Y1
set_property -dict {LOC AA4 } [get_ports {qsfp_tx_n[0]}] ;# MGTYTXN0_225 GTYE4_CHANNEL_X0Y4 / GTYE4_COMMON_X0Y1
set_property -dict {LOC V2  } [get_ports {qsfp_rx_p[1]}] ;# MGTYRXP1_225 GTYE4_CHANNEL_X0Y5 / GTYE4_COMMON_X0Y1
set_property -dict {LOC V1  } [get_ports {qsfp_rx_n[1]}] ;# MGTYRXN1_225 GTYE4_CHANNEL_X0Y5 / GTYE4_COMMON_X0Y1
set_property -dict {LOC W5  } [get_ports {qsfp_tx_p[1]}] ;# MGTYTXP1_225 GTYE4_CHANNEL_X0Y5 / GTYE4_COMMON_X0Y1
set_property -dict {LOC W4  } [get_ports {qsfp_tx_n[1]}] ;# MGTYTXN1_225 GTYE4_CHANNEL_X0Y5 / GTYE4_COMMON_X0Y1
set_property -dict {LOC T2  } [get_ports {qsfp_rx_p[2]}] ;# MGTYRXP2_225 GTYE4_CHANNEL_X0Y6 / GTYE4_COMMON_X0Y1
set_property -dict {LOC T1  } [get_ports {qsfp_rx_n[2]}] ;# MGTYRXN2_225 GTYE4_CHANNEL_X0Y6 / GTYE4_COMMON_X0Y1
set_property -dict {LOC U5  } [get_ports {qsfp_tx_p[2]}] ;# MGTYTXP2_225 GTYE4_CHANNEL_X0Y6 / GTYE4_COMMON_X0Y1
set_property -dict {LOC U4  } [get_ports {qsfp_tx_n[2]}] ;# MGTYTXN2_225 GTYE4_CHANNEL_X0Y6 / GTYE4_COMMON_X0Y1
set_property -dict {LOC P2  } [get_ports {qsfp_rx_p[3]}] ;# MGTYRXP3_225 GTYE4_CHANNEL_X0Y7 / GTYE4_COMMON_X0Y1
set_property -dict {LOC P1  } [get_ports {qsfp_rx_n[3]}] ;# MGTYRXN3_225 GTYE4_CHANNEL_X0Y7 / GTYE4_COMMON_X0Y1
set_property -dict {LOC R5  } [get_ports {qsfp_tx_p[3]}] ;# MGTYTXP3_225 GTYE4_CHANNEL_X0Y7 / GTYE4_COMMON_X0Y1
set_property -dict {LOC R4  } [get_ports {qsfp_tx_n[3]}] ;# MGTYTXN3_225 GTYE4_CHANNEL_X0Y7 / GTYE4_COMMON_X0Y1
set_property -dict {LOC V7  } [get_ports {qsfp_mgt_refclk_p}] ;# MGTREFCLK0P_225
set_property -dict {LOC V6  } [get_ports {qsfp_mgt_refclk_n}] ;# MGTREFCLK0N_225
set_property -dict {LOC W13  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports qsfp_modsell]
set_property -dict {LOC W12  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports qsfp_resetl]
set_property -dict {LOC AA13 IOSTANDARD LVCMOS18 PULLUP true} [get_ports qsfp_modprsl]
set_property -dict {LOC Y13  IOSTANDARD LVCMOS18 PULLUP true} [get_ports qsfp_intl]
set_property -dict {LOC W14  IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports qsfp_lpmode]
#set_property -dict {LOC AE15 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {qsfp_i2c_scl}]
#set_property -dict {LOC AE13 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 12 PULLUP true} [get_ports {qsfp_i2c_sda}]

# 156.25 MHz MGT reference clock
create_clock -period 6.4 -name qsfp_mgt_refclk [get_ports {qsfp_mgt_refclk_p}]

set_false_path -to [get_ports {qsfp_modsell qsfp_resetl qsfp_lpmode}]
set_output_delay 0 [get_ports {qsfp_modsell qsfp_resetl qsfp_lpmode}]
set_false_path -from [get_ports {qsfp_modprsl qsfp_intl}]
set_input_delay 0 [get_ports {qsfp_modprsl qsfp_intl}]

#set_false_path -to [get_ports {qsfp_i2c_sda[*] qsfp_i2c_scl[*]}]
#set_output_delay 0 [get_ports {qsfp_i2c_sda[*] qsfp_i2c_scl[*]}]
#set_false_path -from [get_ports {qsfp_i2c_sda[*] qsfp_i2c_scl[*]}]
#set_input_delay 0 [get_ports {qsfp_i2c_sda[*] qsfp_i2c_scl[*]}]

# PCIe Interface
#set_property -dict {LOC AB2 } [get_ports {pcie_rx_p[4]}] ;# MGTYRXP3_224 GTYE4_CHANNEL_X0Y3 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AB1 } [get_ports {pcie_rx_n[4]}] ;# MGTYRXN3_224 GTYE4_CHANNEL_X0Y3 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AC5 } [get_ports {pcie_tx_p[4]}] ;# MGTYTXP3_224 GTYE4_CHANNEL_X0Y3 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AC4 } [get_ports {pcie_tx_n[4]}] ;# MGTYTXN3_224 GTYE4_CHANNEL_X0Y3 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AD2 } [get_ports {pcie_rx_p[5]}] ;# MGTYRXP2_224 GTYE4_CHANNEL_X0Y2 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AD1 } [get_ports {pcie_rx_n[5]}] ;# MGTYRXN2_224 GTYE4_CHANNEL_X0Y2 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AD7 } [get_ports {pcie_tx_p[5]}] ;# MGTYTXP2_224 GTYE4_CHANNEL_X0Y2 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AD6 } [get_ports {pcie_tx_n[5]}] ;# MGTYTXN2_224 GTYE4_CHANNEL_X0Y2 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AE4 } [get_ports {pcie_rx_p[6]}] ;# MGTYRXP1_224 GTYE4_CHANNEL_X0Y1 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AE3 } [get_ports {pcie_rx_n[6]}] ;# MGTYRXN1_224 GTYE4_CHANNEL_X0Y1 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AE9 } [get_ports {pcie_tx_p[6]}] ;# MGTYTXP1_224 GTYE4_CHANNEL_X0Y1 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AE8 } [get_ports {pcie_tx_n[6]}] ;# MGTYTXN1_224 GTYE4_CHANNEL_X0Y1 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AF2 } [get_ports {pcie_rx_p[7]}] ;# MGTYRXP0_224 GTYE4_CHANNEL_X0Y0 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AF1 } [get_ports {pcie_rx_n[7]}] ;# MGTYRXN0_224 GTYE4_CHANNEL_X0Y0 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AF7 } [get_ports {pcie_tx_p[7]}] ;# MGTYTXP0_224 GTYE4_CHANNEL_X0Y0 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AF6 } [get_ports {pcie_tx_n[7]}] ;# MGTYTXN0_224 GTYE4_CHANNEL_X0Y0 / GTYE4_COMMON_X0Y0
#set_property -dict {LOC AB7 } [get_ports pcie_refclk_p] ;# MGTREFCLK1P_224
#set_property -dict {LOC AB6 } [get_ports pcie_refclk_n] ;# MGTREFCLK1N_224
#set_property -dict {LOC T19 IOSTANDARD LVCMOS12 PULLUP true} [get_ports pcie_reset_n]

#set_false_path -from [get_ports {pcie_reset_n}]
#set_input_delay 0 [get_ports {pcie_reset_n}]

# 100 MHz MGT reference clock
#create_clock -period 10 -name pcie_mgt_refclk [get_ports pcie_refclk_p]

# FMC interface
# FMC HPC
#set_property -dict {LOC F10  IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {fmc_hpc_i2c_scl}] ;# C30 SCL
#set_property -dict {LOC F9   IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports {fmc_hpc_i2c_sda}] ;# C31 SDA

#set_property -dict {LOC G24  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[0]}]  ;# G9  LA00_P_CC
#set_property -dict {LOC G25  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[0]}]  ;# G10 LA00_N_CC
#set_property -dict {LOC J23  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[1]}]  ;# D8  LA01_P_CC
#set_property -dict {LOC J24  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[1]}]  ;# D9  LA01_N_CC
#set_property -dict {LOC H21  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[2]}]  ;# H7  LA02_P
#set_property -dict {LOC H22  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[2]}]  ;# H8  LA02_N
#set_property -dict {LOC J19  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[3]}]  ;# G12 LA03_P
#set_property -dict {LOC J20  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[3]}]  ;# G13 LA03_N
#set_property -dict {LOC H26  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[4]}]  ;# H10 LA04_P
#set_property -dict {LOC G26  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[4]}]  ;# H11 LA04_N
#set_property -dict {LOC F24  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[5]}]  ;# D11 LA05_P
#set_property -dict {LOC F25  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[5]}]  ;# D12 LA05_N
#set_property -dict {LOC G20  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[6]}]  ;# C10 LA06_P
#set_property -dict {LOC G21  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[6]}]  ;# C11 LA06_N
#set_property -dict {LOC D24  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[7]}]  ;# H13 LA07_P
#set_property -dict {LOC D25  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[7]}]  ;# H14 LA07_N
#set_property -dict {LOC D26  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[8]}]  ;# G12 LA08_P
#set_property -dict {LOC C26  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[8]}]  ;# G13 LA08_N
#set_property -dict {LOC E25  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[9]}]  ;# D14 LA09_P
#set_property -dict {LOC E26  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[9]}]  ;# D15 LA09_N
#set_property -dict {LOC B25  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[10]}] ;# C14 LA10_P
#set_property -dict {LOC B26  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[10]}] ;# C15 LA10_N
#set_property -dict {LOC A24  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[11]}] ;# H16 LA11_P
#set_property -dict {LOC A25  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[11]}] ;# H17 LA11_N
#set_property -dict {LOC D23  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[12]}] ;# G15 LA12_P
#set_property -dict {LOC C24  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[12]}] ;# G16 LA12_N
#set_property -dict {LOC F23  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[13]}] ;# D17 LA13_P
#set_property -dict {LOC E23  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[13]}] ;# D18 LA13_N
#set_property -dict {LOC C23  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[14]}] ;# C18 LA14_P
#set_property -dict {LOC B24  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[14]}] ;# C19 LA14_N
#set_property -dict {LOC H18  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[15]}] ;# H19 LA15_P
#set_property -dict {LOC H19  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[15]}] ;# H20 LA15_N
#set_property -dict {LOC E21  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[16]}] ;# G18 LA16_P
#set_property -dict {LOC D21  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[16]}] ;# G19 LA16_N
#set_property -dict {LOC C18  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[17]}] ;# D20 LA17_P_CC
#set_property -dict {LOC C19  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[17]}] ;# D21 LA17_N_CC
#set_property -dict {LOC D19  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[18]}] ;# C22 LA18_P_CC
#set_property -dict {LOC D20  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[18]}] ;# C23 LA18_N_CC
#set_property -dict {LOC A22  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[19]}] ;# H22 LA19_P
#set_property -dict {LOC A23  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[19]}] ;# H23 LA19_N
#set_property -dict {LOC F20  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[20]}] ;# G21 LA20_P
#set_property -dict {LOC E20  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[20]}] ;# G22 LA20_N
#set_property -dict {LOC C21  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[21]}] ;# H25 LA21_P
#set_property -dict {LOC B21  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[21]}] ;# H26 LA21_N
#set_property -dict {LOC H16  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[22]}] ;# G24 LA22_P
#set_property -dict {LOC G16  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[22]}] ;# G25 LA22_N
#set_property -dict {LOC C22  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[23]}] ;# D23 LA23_P
#set_property -dict {LOC B22  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[23]}] ;# D24 LA23_N
#set_property -dict {LOC A17  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[24]}] ;# H28 LA24_P
#set_property -dict {LOC A18  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[24]}] ;# H29 LA24_N
#set_property -dict {LOC E18  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[25]}] ;# G27 LA25_P
#set_property -dict {LOC D18  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[25]}] ;# G28 LA25_N
#set_property -dict {LOC A19  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[26]}] ;# D26 LA26_P
#set_property -dict {LOC A20  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[26]}] ;# D27 LA26_N
#set_property -dict {LOC F18  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[27]}] ;# C26 LA27_P
#set_property -dict {LOC F19  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[27]}] ;# C27 LA27_N
#set_property -dict {LOC C17  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[28]}] ;# H31 LA28_P
#set_property -dict {LOC B17  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[28]}] ;# H32 LA28_N
#set_property -dict {LOC E16  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[29]}] ;# G30 LA29_P
#set_property -dict {LOC E17  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[29]}] ;# G31 LA29_N
#set_property -dict {LOC D16  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[30]}] ;# H34 LA30_P
#set_property -dict {LOC C16  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[30]}] ;# H35 LA30_N
#set_property -dict {LOC G15  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[31]}] ;# G33 LA31_P
#set_property -dict {LOC F15  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[31]}] ;# G34 LA31_N
#set_property -dict {LOC B15  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[32]}] ;# H37 LA32_P
#set_property -dict {LOC A15  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[32]}] ;# H38 LA32_N
#set_property -dict {LOC E15  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_p[33]}] ;# G36 LA33_P
#set_property -dict {LOC D15  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_la_n[33]}] ;# G37 LA33_N

#set_property -dict {LOC H23  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_clk0_m2c_p}] ;# H4 CLK0_M2C_P
#set_property -dict {LOC H24  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_clk0_m2c_n}] ;# H5 CLK0_M2C_N
#set_property -dict {LOC B19  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_clk1_m2c_p}] ;# G2 CLK1_M2C_P
#set_property -dict {LOC B20  IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {fmc_hpc_clk1_m2c_n}] ;# G3 CLK1_M2C_N

#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_p[0]}] ;# MGTHTXP2_229 GTHE4_CHANNEL_X1Y10 / GTHE4_COMMON_X1Y2 from C2  DP0_C2M_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_n[0]}] ;# MGTHTXN2_229 GTHE4_CHANNEL_X1Y10 / GTHE4_COMMON_X1Y2 from C3  DP0_C2M_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_p[0]}] ;# MGTHRXP2_229 GTHE4_CHANNEL_X1Y10 / GTHE4_COMMON_X1Y2 from C6  DP0_M2C_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_n[0]}] ;# MGTHRXN2_229 GTHE4_CHANNEL_X1Y10 / GTHE4_COMMON_X1Y2 from C7  DP0_M2C_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_p[1]}] ;# MGTHTXP1_229 GTHE4_CHANNEL_X1Y9  / GTHE4_COMMON_X1Y2 from A22 DP1_C2M_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_n[1]}] ;# MGTHTXN1_229 GTHE4_CHANNEL_X1Y9  / GTHE4_COMMON_X1Y2 from A23 DP1_C2M_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_p[1]}] ;# MGTHRXP1_229 GTHE4_CHANNEL_X1Y9  / GTHE4_COMMON_X1Y2 from A2  DP1_M2C_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_n[1]}] ;# MGTHRXN1_229 GTHE4_CHANNEL_X1Y9  / GTHE4_COMMON_X1Y2 from A3  DP1_M2C_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_p[2]}] ;# MGTHTXP3_229 GTHE4_CHANNEL_X1Y11 / GTHE4_COMMON_X1Y2 from A26 DP2_C2M_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_n[2]}] ;# MGTHTXN3_229 GTHE4_CHANNEL_X1Y11 / GTHE4_COMMON_X1Y2 from A27 DP2_C2M_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_p[2]}] ;# MGTHRXP3_229 GTHE4_CHANNEL_X1Y11 / GTHE4_COMMON_X1Y2 from A6  DP2_M2C_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_n[2]}] ;# MGTHRXN3_229 GTHE4_CHANNEL_X1Y11 / GTHE4_COMMON_X1Y2 from A7  DP2_M2C_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_p[3]}] ;# MGTHTXP0_229 GTHE4_CHANNEL_X1Y8  / GTHE4_COMMON_X1Y2 from A30 DP3_C2M_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_n[3]}] ;# MGTHTXN0_229 GTHE4_CHANNEL_X1Y8  / GTHE4_COMMON_X1Y2 from A31 DP3_C2M_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_p[3]}] ;# MGTHRXP0_229 GTHE4_CHANNEL_X1Y8  / GTHE4_COMMON_X1Y2 from A10 DP3_M2C_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_n[3]}] ;# MGTHRXN0_229 GTHE4_CHANNEL_X1Y8  / GTHE4_COMMON_X1Y2 from A11 DP3_M2C_N

#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_p[4]}] ;# MGTHTXP3_228 GTHE4_CHANNEL_X1Y7 / GTHE4_COMMON_X1Y1 from A34 DP4_C2M_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_n[4]}] ;# MGTHTXN3_228 GTHE4_CHANNEL_X1Y7 / GTHE4_COMMON_X1Y1 from A35 DP4_C2M_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_p[4]}] ;# MGTHRXP3_228 GTHE4_CHANNEL_X1Y7 / GTHE4_COMMON_X1Y1 from A14 DP4_M2C_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_n[4]}] ;# MGTHRXN3_228 GTHE4_CHANNEL_X1Y7 / GTHE4_COMMON_X1Y1 from A15 DP4_M2C_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_p[5]}] ;# MGTHTXP1_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from A38 DP5_C2M_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_n[5]}] ;# MGTHTXN1_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from A39 DP5_C2M_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_p[5]}] ;# MGTHRXP1_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from A18 DP5_M2C_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_n[5]}] ;# MGTHRXN1_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from A19 DP5_M2C_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_p[6]}] ;# MGTHTXP0_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from B36 DP6_C2M_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_n[6]}] ;# MGTHTXN0_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from B37 DP6_C2M_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_p[6]}] ;# MGTHRXP0_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from B16 DP6_M2C_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_n[6]}] ;# MGTHRXN0_228 GTHE4_CHANNEL_X1Y5 / GTHE4_COMMON_X1Y1 from B17 DP6_M2C_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_p[7]}] ;# MGTHTXP2_228 GTHE4_CHANNEL_X1Y6 / GTHE4_COMMON_X1Y1 from B32 DP7_C2M_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_c2m_n[7]}] ;# MGTHTXN2_228 GTHE4_CHANNEL_X1Y6 / GTHE4_COMMON_X1Y1 from B33 DP7_C2M_N
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_p[7]}] ;# MGTHRXP2_228 GTHE4_CHANNEL_X1Y6 / GTHE4_COMMON_X1Y1 from B12 DP7_M2C_P
#set_property -dict {LOC } [get_ports {fmc_hpc_dp_m2c_n[7]}] ;# MGTHRXN2_228 GTHE4_CHANNEL_X1Y6 / GTHE4_COMMON_X1Y1 from B13 DP7_M2C_N
#set_property -dict {LOC } [get_ports {fmc_hpc_mgt_refclk_0_p}] ;# MGTREFCLK0P_229 from D4 GBTCLK0_M2C_P
#set_property -dict {LOC } [get_ports {fmc_hpc_mgt_refclk_0_n}] ;# MGTREFCLK0N_229 from D5 GBTCLK0_M2C_N
#set_property -dict {LOC } [get_ports {fmc_hpc_mgt_refclk_1_p}] ;# MGTREFCLK0P_228 from B20 GBTCLK1_M2C_P
#set_property -dict {LOC } [get_ports {fmc_hpc_mgt_refclk_1_n}] ;# MGTREFCLK0N_228 from B21 GBTCLK1_M2C_N

# reference clock
#create_clock -period 6.400 -name fmc_hpc_mgt_refclk_0 [get_ports {fmc_hpc_mgt_refclk_0_p}]
#create_clock -period 6.400 -name fmc_hpc_mgt_refclk_1 [get_ports {fmc_hpc_mgt_refclk_1_p}]

# DDR4
# 2x MT40A512M16LY-062E:E
#set_property -dict {LOC Y22  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[0]}]
#set_property -dict {LOC Y25  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[1]}]
#set_property -dict {LOC W23  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[2]}]
#set_property -dict {LOC V26  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[3]}]
#set_property -dict {LOC R26  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[4]}]
#set_property -dict {LOC U26  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[5]}]
#set_property -dict {LOC R21  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[6]}]
#set_property -dict {LOC W25  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[7]}]
#set_property -dict {LOC R20  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[8]}]
#set_property -dict {LOC Y26  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[9]}]
#set_property -dict {LOC R25  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[10]}]
#set_property -dict {LOC V23  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[11]}]
#set_property -dict {LOC AA24 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[12]}]
#set_property -dict {LOC W26  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[13]}]
#set_property -dict {LOC P23  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[14]}]
#set_property -dict {LOC AA25 IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[15]}]
#set_property -dict {LOC T25  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_adr[16]}]
#set_property -dict {LOC P21  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_ba[0]}]
#set_property -dict {LOC P26  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_ba[1]}]
#set_property -dict {LOC R22  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_bg[0]}]
#set_property -dict {LOC V24  IOSTANDARD DIFF_SSTL12_DCI} [get_ports {ddr4_ck_t}]
#set_property -dict {LOC W24  IOSTANDARD DIFF_SSTL12_DCI} [get_ports {ddr4_ck_c}]
#set_property -dict {LOC P20  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_cke}]
#set_property -dict {LOC P25  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_cs_n}]
#set_property -dict {LOC P24  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_act_n}]
#set_property -dict {LOC R23  IOSTANDARD SSTL12_DCI     } [get_ports {ddr4_odt}]
#set_property -dict {LOC P19  IOSTANDARD LVCMOS12       } [get_ports {ddr4_reset_n}]

#set_property -dict {LOC AB26 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[0]}]
#set_property -dict {LOC AB25 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[1]}]
#set_property -dict {LOC AF25 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[2]}]
#set_property -dict {LOC AF24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[3]}]
#set_property -dict {LOC AD25 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[4]}]
#set_property -dict {LOC AD24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[5]}]
#set_property -dict {LOC AC24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[6]}]
#set_property -dict {LOC AB24 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[7]}]
#set_property -dict {LOC AE23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[8]}]
#set_property -dict {LOC AD23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[9]}]
#set_property -dict {LOC AC23 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[10]}]
#set_property -dict {LOC AC22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[11]}]
#set_property -dict {LOC AE21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[12]}]
#set_property -dict {LOC AD21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[13]}]
#set_property -dict {LOC AC21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[14]}]
#set_property -dict {LOC AB21 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[15]}]
#set_property -dict {LOC AC26 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[0]}]
#set_property -dict {LOC AD26 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[0]}]
#set_property -dict {LOC AA22 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[1]}]
#set_property -dict {LOC AB22 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[1]}]
#set_property -dict {LOC AE25 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[0]}]
#set_property -dict {LOC AE22 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[1]}]

#set_property -dict {LOC AD19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[0]}]
#set_property -dict {LOC AC19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[1]}]
#set_property -dict {LOC AF19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[2]}]
#set_property -dict {LOC AF18 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[3]}]
#set_property -dict {LOC AF17 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[4]}]
#set_property -dict {LOC AE17 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[5]}]
#set_property -dict {LOC AE16 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[6]}]
#set_property -dict {LOC AD16 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[7]}]
#set_property -dict {LOC AB19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[8]}]
#set_property -dict {LOC AA19 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[9]}]
#set_property -dict {LOC AB20 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[10]}]
#set_property -dict {LOC AA20 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[11]}]
#set_property -dict {LOC AA17 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[12]}]
#set_property -dict {LOC Y17  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[13]}]
#set_property -dict {LOC AA18 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[14]}]
#set_property -dict {LOC Y18  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dq[15]}]
#set_property -dict {LOC AC18 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[2]}]
#set_property -dict {LOC AD18 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[2]}]
#set_property -dict {LOC AB17 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_t[3]}]
#set_property -dict {LOC AC17 IOSTANDARD DIFF_POD12_DCI } [get_ports {ddr4_dqs_c[3]}]
#set_property -dict {LOC AD20 IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[2]}]
#set_property -dict {LOC Y20  IOSTANDARD POD12_DCI      } [get_ports {ddr4_dm_dbi_n[3]}]
