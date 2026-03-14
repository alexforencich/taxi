# SPDX-License-Identifier: MIT
#
# Copyright (c) 2014-2025 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# XDC constraints for the Xilinx KC705 board
# part: xc7k325tffg900-2

# General configuration
set_property CFGBVS VCCO                               [current_design]
set_property CONFIG_VOLTAGE 2.5                        [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true           [current_design]

# System clocks
# 200 MHz system clock
set_property -dict {LOC AD12 IOSTANDARD LVDS} [get_ports clk_200mhz_p] ;# from SiT9102 U6.4
set_property -dict {LOC AD11 IOSTANDARD LVDS} [get_ports clk_200mhz_n] ;# from SiT9102 U6.5
create_clock -period 5.000 -name clk_200mhz [get_ports clk_200mhz_p]

# Si570 user clock (156.25 MHz default)
#set_property -dict {LOC K28 IOSTANDARD LVDS_25} [get_ports clk_user_p] ;# from Si570 U45.4
#set_property -dict {LOC K29 IOSTANDARD LVDS_25} [get_ports clk_user_n] ;# from Si570 U45.5
#create_clock -period 6.400 -name clk_user [get_ports clk_user_p]

# User SMA clock
#set_property -dict {LOC L25 IOSTANDARD LVDS_25} [get_ports clk_user_sma_p] ;# from J11
#set_property -dict {LOC K25 IOSTANDARD LVDS_25} [get_ports clk_user_sma_n] ;# from J12
#create_clock -period 10.000 -name clk_user_sma [get_ports clk_user_sma_p]

# LEDs
set_property -dict {LOC AB8  IOSTANDARD LVCMOS15 SLEW SLOW DRIVE 12} [get_ports {led[0]}] ;# to DS4
set_property -dict {LOC AA8  IOSTANDARD LVCMOS15 SLEW SLOW DRIVE 12} [get_ports {led[1]}] ;# to DS1
set_property -dict {LOC AC9  IOSTANDARD LVCMOS15 SLEW SLOW DRIVE 12} [get_ports {led[2]}] ;# to DS10
set_property -dict {LOC AB9  IOSTANDARD LVCMOS15 SLEW SLOW DRIVE 12} [get_ports {led[3]}] ;# to DS2
set_property -dict {LOC AE26 IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports {led[4]}] ;# to DS3
set_property -dict {LOC G19  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports {led[5]}] ;# to DS25
set_property -dict {LOC E18  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports {led[6]}] ;# to DS26
set_property -dict {LOC F16  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports {led[7]}] ;# to DS27

set_false_path -to [get_ports {led[*]}]
set_output_delay 0 [get_ports {led[*]}]

# Reset button
set_property -dict {LOC AB7  IOSTANDARD LVCMOS15} [get_ports reset] ;# from SW7

set_false_path -from [get_ports {reset}]
set_input_delay 0 [get_ports {reset}]

# Push buttons
set_property -dict {LOC AA12 IOSTANDARD LVCMOS15} [get_ports btnu] ;# from SW2
set_property -dict {LOC AC6  IOSTANDARD LVCMOS15} [get_ports btnl] ;# from SW6
set_property -dict {LOC AB12 IOSTANDARD LVCMOS15} [get_ports btnd] ;# from SW4
set_property -dict {LOC AG5  IOSTANDARD LVCMOS15} [get_ports btnr] ;# from SW3
set_property -dict {LOC G12  IOSTANDARD LVCMOS25} [get_ports btnc] ;# from SW5

set_false_path -from [get_ports {btnu btnl btnd btnr btnc}]
set_input_delay 0 [get_ports {btnu btnl btnd btnr btnc}]

# DIP switches
set_property -dict {LOC Y29  IOSTANDARD LVCMOS25} [get_ports {sw[0]}] ;# from SW4.4
set_property -dict {LOC W29  IOSTANDARD LVCMOS25} [get_ports {sw[1]}] ;# from SW4.3
set_property -dict {LOC AA28 IOSTANDARD LVCMOS25} [get_ports {sw[2]}] ;# from SW4.2
set_property -dict {LOC Y28  IOSTANDARD LVCMOS25} [get_ports {sw[3]}] ;# from SW4.1

set_false_path -from [get_ports {sw[*]}]
set_input_delay 0 [get_ports {sw[*]}]

# UART (U12 CP2103)
set_property -dict {LOC K24  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 8} [get_ports {uart_txd}] ;# U12.24 RXD_I
set_property -dict {LOC M19  IOSTANDARD LVCMOS25} [get_ports {uart_rxd}] ;# U12.25 TXD_O
set_property -dict {LOC L27  IOSTANDARD LVCMOS25} [get_ports {uart_rts}] ;# U12.23 RTS_O_B
set_property -dict {LOC K23  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 8} [get_ports {uart_cts}] ;# U12.22 CTS_I_B

set_false_path -to [get_ports {uart_txd uart_cts}]
set_output_delay 0 [get_ports {uart_txd uart_cts}]
set_false_path -from [get_ports {uart_rxd uart_rts}]
set_input_delay 0 [get_ports {uart_rxd uart_rts}]

# I2C interface
set_property -dict {LOC K21  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 8} [get_ports i2c_scl]
set_property -dict {LOC L21  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 8} [get_ports i2c_sda]
set_property -dict {LOC P23  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 8} [get_ports i2c_mux_reset]

#set_false_path -to [get_ports {i2c_sda i2c_scl}]
#set_output_delay 0 [get_ports {i2c_sda i2c_scl}]
#set_false_path -from [get_ports {i2c_sda i2c_scl}]
#set_input_delay 0 [get_ports {i2c_sda i2c_scl}]

# Gigabit Ethernet GMII PHY
set_property -dict {LOC U27  IOSTANDARD LVCMOS25} [get_ports phy_rx_clk] ;# from U37.C1 RXCLK
set_property -dict {LOC U30  IOSTANDARD LVCMOS25} [get_ports {phy_rxd[0]}] ;# from U37.B2 RXD0
set_property -dict {LOC U25  IOSTANDARD LVCMOS25} [get_ports {phy_rxd[1]}] ;# from U37.D3 RXD1
set_property -dict {LOC T25  IOSTANDARD LVCMOS25} [get_ports {phy_rxd[2]}] ;# from U37.C3 RXD2
set_property -dict {LOC U28  IOSTANDARD LVCMOS25} [get_ports {phy_rxd[3]}] ;# from U37.B3 RXD3
set_property -dict {LOC R19  IOSTANDARD LVCMOS25} [get_ports {phy_rxd[4]}] ;# from U37.C4 RXD4
set_property -dict {LOC T27  IOSTANDARD LVCMOS25} [get_ports {phy_rxd[5]}] ;# from U37.A1 RXD5
set_property -dict {LOC T26  IOSTANDARD LVCMOS25} [get_ports {phy_rxd[6]}] ;# from U37.A2 RXD6
set_property -dict {LOC T28  IOSTANDARD LVCMOS25} [get_ports {phy_rxd[7]}] ;# from U37.C5 RXD7
set_property -dict {LOC R28  IOSTANDARD LVCMOS25} [get_ports phy_rx_dv] ;# from U37.B1 RXCTL_RXDV
set_property -dict {LOC V26  IOSTANDARD LVCMOS25} [get_ports phy_rx_er] ;# from U37.D4 RXER
set_property -dict {LOC K30  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports phy_gtx_clk] ;# from U37.E2 TXC_GTXCLK
set_property -dict {LOC M28  IOSTANDARD LVCMOS25} [get_ports phy_tx_clk] ;# from U37.D1 TXCLK
set_property -dict {LOC N27  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {phy_txd[0]}] ;# from U37.F1 TXD0
set_property -dict {LOC N25  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {phy_txd[1]}] ;# from U37.G2 TXD1
set_property -dict {LOC M29  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {phy_txd[2]}] ;# from U37.G3 TXD2
set_property -dict {LOC L28  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {phy_txd[3]}] ;# from U37.H1 TXD3
set_property -dict {LOC J26  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {phy_txd[4]}] ;# from U37.H2 TXD4
set_property -dict {LOC K26  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {phy_txd[5]}] ;# from U37.H3 TXD5
set_property -dict {LOC L30  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {phy_txd[6]}] ;# from U37.J1 TXD6
set_property -dict {LOC J28  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports {phy_txd[7]}] ;# from U37.J2 TXD7
set_property -dict {LOC M27  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports phy_tx_en] ;# from U37.E1 TXCTL_TXEN
set_property -dict {LOC N29  IOSTANDARD LVCMOS25 SLEW FAST DRIVE 16} [get_ports phy_tx_er] ;# from U37.F2 TXER
set_property -dict {LOC L20  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports phy_reset_n] ;# from U37.K3 RESET_B
set_property -dict {LOC N30  IOSTANDARD LVCMOS25} [get_ports phy_int_n] ;# from U37.L1 INT_B
#set_property -dict {LOC J21  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports phy_mdio] ;# from U37.M1 MDIO
#set_property -dict {LOC R23  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports phy_mdc] ;# from U37.L3 MDC

create_clock -period 40.000 -name phy_tx_clk [get_ports phy_tx_clk]
create_clock -period 8.000 -name phy_rx_clk [get_ports phy_rx_clk]

set_false_path -to [get_ports {phy_reset_n}]
set_output_delay 0 [get_ports {phy_reset_n}]
set_false_path -from [get_ports {phy_int_n}]
set_input_delay 0 [get_ports {phy_int_n}]

#set_false_path -to [get_ports {phy_mdio phy_mdc}]
#set_output_delay 0 [get_ports {phy_mdio phy_mdc}]
#set_false_path -from [get_ports {phy_mdio}]
#set_input_delay 0 [get_ports {phy_mdio}]

# GTX for Ethernet
set_property -dict {LOC G4   } [get_ports sfp_rx_p] ;# MGTXRXP2_117 GTXE2_CHANNEL_X0Y10 / GTXE2_COMMON_X0Y2 from P5.13
set_property -dict {LOC G3   } [get_ports sfp_rx_n] ;# MGTXRXN2_117 GTXE2_CHANNEL_X0Y10 / GTXE2_COMMON_X0Y2 from P5.12
set_property -dict {LOC H2   } [get_ports sfp_tx_p] ;# MGTXTXP2_117 GTXE2_CHANNEL_X0Y10 / GTXE2_COMMON_X0Y2 from P5.18
set_property -dict {LOC H1   } [get_ports sfp_tx_n] ;# MGTXTXN2_117 GTXE2_CHANNEL_X0Y10 / GTXE2_COMMON_X0Y2 from P5.19
set_property -dict {LOC H6   } [get_ports phy_sgmii_rx_p] ;# MGTXRXP1_117 GTXE2_CHANNEL_X0Y9 / GTXE2_COMMON_X0Y2 from U37.A7 SOUT_P
set_property -dict {LOC H5   } [get_ports phy_sgmii_rx_n] ;# MGTXRXN1_117 GTXE2_CHANNEL_X0Y9 / GTXE2_COMMON_X0Y2 from U37.A8 SOUT_N
set_property -dict {LOC J4   } [get_ports phy_sgmii_tx_p] ;# MGTXTXP1_117 GTXE2_CHANNEL_X0Y9 / GTXE2_COMMON_X0Y2 from U37.A3 SIN_P
set_property -dict {LOC J3   } [get_ports phy_sgmii_tx_n] ;# MGTXTXN1_117 GTXE2_CHANNEL_X0Y9 / GTXE2_COMMON_X0Y2 from U37.A4 SIN_N
set_property -dict {LOC G8   } [get_ports sgmii_mgt_refclk_p] ;# MGTREFCLK0P_117 from U2.7
set_property -dict {LOC G7   } [get_ports sgmii_mgt_refclk_n] ;# MGTREFCLK0N_117 from U2.6
#set_property -dict {LOC L8   } [get_ports sfp_mgt_refclk_p] ;# MGTREFCLK0P_116 from Si5324 U70.28 CKOUT1_P
#set_property -dict {LOC L7   } [get_ports sfp_mgt_refclk_n] ;# MGTREFCLK0N_116 from Si5324 U70.29 CKOUT1_N
#set_property -dict {LOC W27 IOSTANDARD LVDS} [get_ports sfp_recclk_p] ;# to Si5324 U70.16 CKIN1_P
#set_property -dict {LOC W28 IOSTANDARD LVDS} [get_ports sfp_recclk_n] ;# to Si5324 U70.17 CKIN1_N

#set_property -dict {LOC AE20 IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports si5324_rst]
#set_property -dict {LOC AG24 IOSTANDARD LVCMOS25 PULLUP true} [get_ports si5324_int]

set_property -dict {LOC Y20  IOSTANDARD LVCMOS25 SLEW SLOW DRIVE 12} [get_ports {sfp_tx_disable_b}]
set_property -dict {LOC P19  IOSTANDARD LVCMOS25} [get_ports {sfp_rx_los}]

# 125 MHz MGT reference clock (SGMII, 1000BASE-X)
#create_clock -period 8.000 -name sgmii_mgt_refclk [get_ports sgmii_mgt_refclk_p]

# 156.25 MHz MGT reference clock (10GBASE-R)
#create_clock -period 6.400 -name sgmii_mgt_refclk [get_ports sfp_mgt_refclk_p]

#set_false_path -to [get_ports {si5324_rst}]
#set_output_delay 0 [get_ports {si5324_rst}]
#set_false_path -from [get_ports {si5324_int}]
#set_input_delay 0 [get_ports {si5324_int}]

set_false_path -to [get_ports {sfp_tx_disable_b}]
set_output_delay 0 [get_ports {sfp_tx_disable_b}]

# PCIe Interface
#set_property -dict {LOC M6  } [get_ports {pcie_rx_p[0]}] ;# MGTHRXP3_225 GTXE3_CHANNEL_X0Y7 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC M5  } [get_ports {pcie_rx_n[0]}] ;# MGTHRXN3_225 GTXE3_CHANNEL_X0Y7 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC L4  } [get_ports {pcie_tx_p[0]}] ;# MGTHTXP3_225 GTXE3_CHANNEL_X0Y7 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC L3  } [get_ports {pcie_tx_n[0]}] ;# MGTHTXN3_225 GTXE3_CHANNEL_X0Y7 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC P6  } [get_ports {pcie_rx_p[1]}] ;# MGTHRXP2_225 GTXE3_CHANNEL_X0Y6 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC P5  } [get_ports {pcie_rx_n[1]}] ;# MGTHRXN2_225 GTXE3_CHANNEL_X0Y6 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC M2  } [get_ports {pcie_tx_p[1]}] ;# MGTHTXP2_225 GTXE3_CHANNEL_X0Y6 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC M1  } [get_ports {pcie_tx_n[1]}] ;# MGTHTXN2_225 GTXE3_CHANNEL_X0Y6 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC R4  } [get_ports {pcie_rx_p[2]}] ;# MGTHRXP1_225 GTXE3_CHANNEL_X0Y5 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC R3  } [get_ports {pcie_rx_n[2]}] ;# MGTHRXN1_225 GTXE3_CHANNEL_X0Y5 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC N4  } [get_ports {pcie_tx_p[2]}] ;# MGTHTXP1_225 GTXE3_CHANNEL_X0Y5 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC N3  } [get_ports {pcie_tx_n[2]}] ;# MGTHTXN1_225 GTXE3_CHANNEL_X0Y5 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC T6  } [get_ports {pcie_rx_p[3]}] ;# MGTHRXP0_225 GTXE3_CHANNEL_X0Y4 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC T5  } [get_ports {pcie_rx_n[3]}] ;# MGTHRXN0_225 GTXE3_CHANNEL_X0Y4 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC P2  } [get_ports {pcie_tx_p[3]}] ;# MGTHTXP0_225 GTXE3_CHANNEL_X0Y4 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC P1  } [get_ports {pcie_tx_n[3]}] ;# MGTHTXN0_225 GTXE3_CHANNEL_X0Y4 / GTXE3_COMMON_X0Y1
#set_property -dict {LOC V6  } [get_ports {pcie_rx_p[4]}] ;# MGTHRXP3_224 GTXE3_CHANNEL_X0Y3 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC V5  } [get_ports {pcie_rx_n[4]}] ;# MGTHRXN3_224 GTXE3_CHANNEL_X0Y3 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC T2  } [get_ports {pcie_tx_p[4]}] ;# MGTHTXP3_224 GTXE3_CHANNEL_X0Y3 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC T1  } [get_ports {pcie_tx_n[4]}] ;# MGTHTXN3_224 GTXE3_CHANNEL_X0Y3 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC W4  } [get_ports {pcie_rx_p[5]}] ;# MGTHRXP2_224 GTXE3_CHANNEL_X0Y2 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC W3  } [get_ports {pcie_rx_n[5]}] ;# MGTHRXN2_224 GTXE3_CHANNEL_X0Y2 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC U4  } [get_ports {pcie_tx_p[5]}] ;# MGTHTXP2_224 GTXE3_CHANNEL_X0Y2 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC U3  } [get_ports {pcie_tx_n[5]}] ;# MGTHTXN2_224 GTXE3_CHANNEL_X0Y2 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC Y6  } [get_ports {pcie_rx_p[6]}] ;# MGTHRXP1_224 GTXE3_CHANNEL_X0Y1 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC Y5  } [get_ports {pcie_rx_n[6]}] ;# MGTHRXN1_224 GTXE3_CHANNEL_X0Y1 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC V2  } [get_ports {pcie_tx_p[6]}] ;# MGTHTXP1_224 GTXE3_CHANNEL_X0Y1 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC V1  } [get_ports {pcie_tx_n[6]}] ;# MGTHTXN1_224 GTXE3_CHANNEL_X0Y1 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC AA4 } [get_ports {pcie_rx_p[7]}] ;# MGTHRXP0_224 GTXE3_CHANNEL_X0Y0 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC AA3 } [get_ports {pcie_rx_n[7]}] ;# MGTHRXN0_224 GTXE3_CHANNEL_X0Y0 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC Y2  } [get_ports {pcie_tx_p[7]}] ;# MGTHTXP0_224 GTXE3_CHANNEL_X0Y0 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC Y1  } [get_ports {pcie_tx_n[7]}] ;# MGTHTXN0_224 GTXE3_CHANNEL_X0Y0 / GTXE3_COMMON_X0Y0
#set_property -dict {LOC U8  } [get_ports pcie_mgt_refclk_p] ;# MGTREFCLK0P_225
#set_property -dict {LOC U7  } [get_ports pcie_mgt_refclk_n] ;# MGTREFCLK0N_225
#set_property -dict {LOC G25  IOSTANDARD LVCMOS25 PULLUP true} [get_ports pcie_reset_n]

# 100 MHz MGT reference clock
#create_clock -period 10 -name pcie_mgt_refclk [get_ports pcie_mgt_refclk_p]

#set_false_path -from [get_ports {pcie_reset_n}]
#set_input_delay 0 [get_ports {pcie_reset_n}]
