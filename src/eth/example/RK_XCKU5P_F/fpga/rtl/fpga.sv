// SPDX-License-Identifier: MIT
/*

Copyright (c) 2014-2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * FPGA top-level module
 */
module fpga #
(
    // simulation (set to avoid vendor primitives)
    parameter logic SIM = 1'b0,
    // vendor ("GENERIC", "XILINX", "ALTERA")
    parameter string VENDOR = "XILINX",
    // device family
    parameter string FAMILY = "kintexuplus",
    // 10G/25G MAC configuration
    parameter logic CFG_LOW_LATENCY = 1'b1,
    parameter logic COMBINED_MAC_PCS = 1'b1,
    parameter MAC_DATA_W = 64
)
(
    /*
     * Clock: 200MHz LVDS
     */
    input  wire logic        clk_200mhz_p,
    input  wire logic        clk_200mhz_n,

    /*
     * GPIO
     */
    input  wire logic [3:0]  btn,
    output wire logic [3:0]  led,

    /*
     * UART: 300000 bps, 8N1
     */
    input  wire logic        uart_rxd,
    output wire logic        uart_txd,

    /*
     * Ethernet: 1000BASE-T SGMII
     */
    input  wire logic        phy_rx_clk,
    input  wire logic [3:0]  phy_rxd,
    input  wire logic        phy_rx_ctl,
    output wire logic        phy_tx_clk,
    output wire logic [3:0]  phy_txd,
    output wire logic        phy_tx_ctl,
    // output wire logic        phy_mdc,
    // inout  wire logic        phy_mdio,

    /*
     * Ethernet: QSFP28
     */
    input  wire logic        qsfp_rx_p[4],
    input  wire logic        qsfp_rx_n[4],
    output wire logic        qsfp_tx_p[4],
    output wire logic        qsfp_tx_n[4],
    input  wire logic        qsfp_mgt_refclk_p,
    input  wire logic        qsfp_mgt_refclk_n,
    output wire logic        qsfp_modsell,
    output wire logic        qsfp_resetl,
    input  wire logic        qsfp_modprsl,
    input  wire logic        qsfp_intl,
    output wire logic        qsfp_lpmode//,
    // inout  wire logic        qsfp_i2c_scl,
    // inout  wire logic        qsfp_i2c_sda
);

// Clock and reset

wire clk_200mhz_ibufg;

// Internal 125 MHz clock
wire clk_125mhz_mmcm_out;
wire clk90_125mhz_mmcm_out;
wire clk_125mhz_int;
wire clk90_125mhz_int;
wire rst_125mhz_int;

// Internal 312.5 MHz clock
wire clk_312mhz_mmcm_out;
wire clk_312mhz_int;
wire rst_312mhz_int;

wire mmcm_rst = 1'b0;
wire mmcm_locked;
wire mmcm_clkfb;

IBUFGDS #(
   .DIFF_TERM("FALSE"),
   .IBUF_LOW_PWR("FALSE")
)
clk_200mhz_ibufg_inst (
   .O   (clk_200mhz_ibufg),
   .I   (clk_200mhz_p),
   .IB  (clk_200mhz_n)
);

// MMCM instance
MMCME4_BASE #(
    // 200 MHz input
    .CLKIN1_PERIOD(5.0),
    .REF_JITTER1(0.010),
    // 200 MHz input / 4 = 50 MHz PFD (range 10 MHz to 500 MHz)
    .DIVCLK_DIVIDE(4),
    // 50 MHz PFD * 25 = 1250 MHz VCO (range 800 MHz to 1600 MHz)
    .CLKFBOUT_MULT_F(25),
    .CLKFBOUT_PHASE(0),
    // 1250 MHz / 10 = 125 MHz, 0 degrees
    .CLKOUT0_DIVIDE_F(10),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    // 1250 MHz / 10 = 125 MHz, 90 degrees
    .CLKOUT1_DIVIDE(10),
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(90),
    // 1250 MHz / 4 = 312.5 MHz, 0 degrees
    .CLKOUT2_DIVIDE(4),
    .CLKOUT2_DUTY_CYCLE(0.5),
    .CLKOUT2_PHASE(0),
    // Not used
    .CLKOUT3_DIVIDE(1),
    .CLKOUT3_DUTY_CYCLE(0.5),
    .CLKOUT3_PHASE(0),
    // Not used
    .CLKOUT4_DIVIDE(1),
    .CLKOUT4_DUTY_CYCLE(0.5),
    .CLKOUT4_PHASE(0),
    .CLKOUT4_CASCADE("FALSE"),
    // Not used
    .CLKOUT5_DIVIDE(1),
    .CLKOUT5_DUTY_CYCLE(0.5),
    .CLKOUT5_PHASE(0),
    // Not used
    .CLKOUT6_DIVIDE(1),
    .CLKOUT6_DUTY_CYCLE(0.5),
    .CLKOUT6_PHASE(0),

    // optimized bandwidth
    .BANDWIDTH("OPTIMIZED"),
    // don't wait for lock during startup
    .STARTUP_WAIT("FALSE")
)
clk_mmcm_inst (
    // 200 MHz input
    .CLKIN1(clk_200mhz_ibufg),
    // direct clkfb feeback
    .CLKFBIN(mmcm_clkfb),
    .CLKFBOUT(mmcm_clkfb),
    .CLKFBOUTB(),
    // 125 MHz, 0 degrees
    .CLKOUT0(clk_125mhz_mmcm_out),
    .CLKOUT0B(),
    // 125 MHz, 90 degrees
    .CLKOUT1(clk90_125mhz_mmcm_out),
    .CLKOUT1B(),
    // 312.5 MHz, 0 degrees
    .CLKOUT2(clk_312mhz_mmcm_out),
    .CLKOUT2B(),
    // Not used
    .CLKOUT3(),
    .CLKOUT3B(),
    // Not used
    .CLKOUT4(),
    // Not used
    .CLKOUT5(),
    // Not used
    .CLKOUT6(),
    // reset input
    .RST(mmcm_rst),
    // don't power down
    .PWRDWN(1'b0),
    // locked output
    .LOCKED(mmcm_locked)
);

BUFG
clk_125mhz_bufg_inst (
    .I(clk_125mhz_mmcm_out),
    .O(clk_125mhz_int)
);

BUFG
clk90_125mhz_bufg_inst (
    .I(clk90_125mhz_mmcm_out),
    .O(clk90_125mhz_int)
);

BUFG
clk_312mhz_bufg_inst (
    .I(clk_312mhz_mmcm_out),
    .O(clk_312mhz_int)
);

taxi_sync_reset #(
    .N(4)
)
sync_reset_125mhz_inst (
    .clk(clk_125mhz_int),
    .rst(~mmcm_locked),
    .out(rst_125mhz_int)
);

taxi_sync_reset #(
    .N(4)
)
sync_reset_312mhz_inst (
    .clk(clk_312mhz_int),
    .rst(~mmcm_locked),
    .out(rst_312mhz_int)
);

// GPIO
wire [3:0] btn_int;

taxi_debounce_switch #(
    .WIDTH(4),
    .N(4),
    .RATE(125000)
)
debounce_switch_inst (
    .clk(clk_125mhz_int),
    .rst(rst_125mhz_int),
    .in({btn}),
    .out({btn_int})
);

wire uart_rxd_int;

taxi_sync_signal #(
    .WIDTH(1),
    .N(2)
)
sync_signal_inst (
    .clk(clk_125mhz_int),
    .in({uart_rxd}),
    .out({uart_rxd_int})
);

// IODELAY elements for RGMII interface to PHY
wire [3:0] phy_rxd_int;
wire phy_rx_ctl_int;

IDELAYCTRL #(
    .SIM_DEVICE("ULTRASCALE")
)
idelayctrl_inst (
    .REFCLK(clk_312mhz_int),
    .RST(rst_312mhz_int),
    .RDY()
);

for (genvar n = 0; n < 4; n = n + 1) begin : phy_rxd_idelay_bit

    IDELAYE3 #(
        .DELAY_SRC("IDATAIN"),
        .CASCADE("NONE"),
        .DELAY_TYPE("FIXED"),
        .DELAY_VALUE(0),
        .REFCLK_FREQUENCY(312.5),
        .DELAY_FORMAT("TIME"),
        .UPDATE_MODE("SYNC"),
        .SIM_DEVICE("ULTRASCALE_PLUS")
    )
    idelay_inst (
        .CASC_IN(1'b0),
        .CASC_RETURN(1'b0),
        .CASC_OUT(),
        .IDATAIN(phy_rxd[n]),
        .DATAIN(1'b0),
        .DATAOUT(phy_rxd_int[n]),
        .CLK(1'b0),
        .EN_VTC(1'b1),
        .CE(1'b0),
        .INC(1'b0),
        .LOAD(1'b0),
        .RST(1'b0),
        .CNTVALUEIN(9'd0),
        .CNTVALUEOUT()
    );

end

IDELAYE3 #(
    .DELAY_SRC("IDATAIN"),
    .CASCADE("NONE"),
    .DELAY_TYPE("FIXED"),
    .DELAY_VALUE(0),
    .REFCLK_FREQUENCY(312.5),
    .DELAY_FORMAT("TIME"),
    .UPDATE_MODE("SYNC"),
    .SIM_DEVICE("ULTRASCALE_PLUS")
)
phy_rx_ctl_idelay (
    .CASC_IN(1'b0),
    .CASC_RETURN(1'b0),
    .CASC_OUT(),
    .IDATAIN(phy_rx_ctl),
    .DATAIN(1'b0),
    .DATAOUT(phy_rx_ctl_int),
    .CLK(1'b0),
    .EN_VTC(1'b1),
    .CE(1'b0),
    .INC(1'b0),
    .LOAD(1'b0),
    .RST(1'b0),
    .CNTVALUEIN(9'd0),
    .CNTVALUEOUT()
);

fpga_core #(
    .SIM(SIM),
    .VENDOR(VENDOR),
    .FAMILY(FAMILY),
    .CFG_LOW_LATENCY(CFG_LOW_LATENCY),
    .COMBINED_MAC_PCS(COMBINED_MAC_PCS),
    .MAC_DATA_W(MAC_DATA_W)
)
core_inst (
    /*
     * Clock: 125MHz
     * Synchronous reset
     */
    .clk(clk_125mhz_int),
    .clk90(clk90_125mhz_int),
    .rst(rst_125mhz_int),

    /*
     * GPIO
     */
    .btn(btn_int),
    .led(led),

    /*
     * UART: 115200 bps, 8N1
     */
    .uart_rxd(uart_rxd_int),
    .uart_txd(uart_txd),

    /*
     * Ethernet: 1000BASE-T RGMII
     */
    .phy_rgmii_rx_clk(phy_rx_clk),
    .phy_rgmii_rxd(phy_rxd_int),
    .phy_rgmii_rx_ctl(phy_rx_ctl_int),
    .phy_rgmii_tx_clk(phy_tx_clk),
    .phy_rgmii_txd(phy_txd),
    .phy_rgmii_tx_ctl(phy_tx_ctl),

    /*
     * Ethernet: QSFP28
     */
    .qsfp_rx_p(qsfp_rx_p),
    .qsfp_rx_n(qsfp_rx_n),
    .qsfp_tx_p(qsfp_tx_p),
    .qsfp_tx_n(qsfp_tx_n),
    .qsfp_mgt_refclk_p(qsfp_mgt_refclk_p),
    .qsfp_mgt_refclk_n(qsfp_mgt_refclk_n),
    .qsfp_modsell(qsfp_modsell),
    .qsfp_resetl(qsfp_resetl),
    .qsfp_modprsl(qsfp_modprsl),
    .qsfp_intl(qsfp_intl),
    .qsfp_lpmode(qsfp_lpmode)
);

endmodule

`resetall
