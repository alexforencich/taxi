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
    // MAC configuration
    parameter logic CFG_LOW_LATENCY = 1'b1,
    parameter logic COMBINED_MAC_PCS = 1'b1,
    parameter MAC_DATA_W = 512
)
(
    /*
     * Clock: 100MHz
     */
    input  wire logic        init_clk,

    /*
     * GPIO
     */
    output wire logic        led_sreg_d,
    output wire logic        led_sreg_ld,
    output wire logic        led_sreg_clk,
    output wire logic [1:0]  led_bmc,
    output wire logic [1:0]  led_exp,

    /*
     * Board status
     */
    input  wire logic [1:0]  pg,

    /*
     * Ethernet: QSFP28
     */
    output wire logic        qsfp_0_tx_p[4],
    output wire logic        qsfp_0_tx_n[4],
    input  wire logic        qsfp_0_rx_p[4],
    input  wire logic        qsfp_0_rx_n[4],
    input  wire logic        qsfp_0_mgt_refclk_p,
    input  wire logic        qsfp_0_mgt_refclk_n,
    input  wire logic        qsfp_0_mod_prsnt_n,
    output wire logic        qsfp_0_reset_n,
    output wire logic        qsfp_0_lp_mode,
    input  wire logic        qsfp_0_intr_n,

    output wire logic        qsfp_1_tx_p[4],
    output wire logic        qsfp_1_tx_n[4],
    input  wire logic        qsfp_1_rx_p[4],
    input  wire logic        qsfp_1_rx_n[4],
    input  wire logic        qsfp_1_mgt_refclk_p,
    input  wire logic        qsfp_1_mgt_refclk_n,
    input  wire logic        qsfp_1_mod_prsnt_n,
    output wire logic        qsfp_1_reset_n,
    output wire logic        qsfp_1_lp_mode,
    input  wire logic        qsfp_1_intr_n
);

// Clock and reset

wire init_clk_bufg;

// Internal 125 MHz clock
wire clk_125mhz_mmcm_out;
wire clk_125mhz_int;
wire rst_125mhz_int;

wire mmcm_rst = !pg[0] || !pg[1];
wire mmcm_locked;
wire mmcm_clkfb;

BUFG
init_clk_bufg_inst (
    .I(init_clk),
    .O(init_clk_bufg)
);

// MMCM instance
MMCME4_BASE #(
    // 50 MHz input
    .CLKIN1_PERIOD(20.000),
    .REF_JITTER1(0.010),
    // 50 MHz input / 1 = 50 MHz PFD (range 10 MHz to 500 MHz)
    .DIVCLK_DIVIDE(1),
    // 50 MHz PFD * 25 = 1250 MHz VCO (range 800 MHz to 1600 MHz)
    .CLKFBOUT_MULT_F(25),
    .CLKFBOUT_PHASE(0),
    // 1250 MHz / 10 = 125 MHz, 0 degrees
    .CLKOUT0_DIVIDE_F(10),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    // Not used
    .CLKOUT1_DIVIDE(10),
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(90),
    // Not used
    .CLKOUT2_DIVIDE(20),
    .CLKOUT2_DUTY_CYCLE(0.5),
    .CLKOUT2_PHASE(0),
    // Not used
    .CLKOUT3_DIVIDE(4),
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
    // 300 MHz input
    .CLKIN1(init_clk_bufg),
    // direct clkfb feeback
    .CLKFBIN(mmcm_clkfb),
    .CLKFBOUT(mmcm_clkfb),
    .CLKFBOUTB(),
    // 125 MHz, 0 degrees
    .CLKOUT0(clk_125mhz_mmcm_out),
    .CLKOUT0B(),
    // Not used
    .CLKOUT1(),
    .CLKOUT1B(),
    // Not used
    .CLKOUT2(),
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

taxi_sync_reset #(
    .N(4)
)
sync_reset_125mhz_inst (
    .clk(clk_125mhz_int),
    .rst(~mmcm_locked),
    .out(rst_125mhz_int)
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
     * Clock: 125 MHz
     * Synchronous reset
     */
    .clk_125mhz(clk_125mhz_int),
    .rst_125mhz(rst_125mhz_int),

    /*
     * GPIO
     */
    .led_sreg_d(led_sreg_d),
    .led_sreg_ld(led_sreg_ld),
    .led_sreg_clk(led_sreg_clk),
    .led_bmc(led_bmc),
    .led_exp(led_exp),

    /*
     * Ethernet: QSFP28
     */
    .qsfp_0_tx_p(qsfp_0_tx_p),
    .qsfp_0_tx_n(qsfp_0_tx_n),
    .qsfp_0_rx_p(qsfp_0_rx_p),
    .qsfp_0_rx_n(qsfp_0_rx_n),
    .qsfp_0_mgt_refclk_p(qsfp_0_mgt_refclk_p),
    .qsfp_0_mgt_refclk_n(qsfp_0_mgt_refclk_n),
    .qsfp_0_mod_prsnt_n(qsfp_0_mod_prsnt_n),
    .qsfp_0_reset_n(qsfp_0_reset_n),
    .qsfp_0_lp_mode(qsfp_0_lp_mode),
    .qsfp_0_intr_n(qsfp_0_intr_n),

    .qsfp_1_tx_p(qsfp_1_tx_p),
    .qsfp_1_tx_n(qsfp_1_tx_n),
    .qsfp_1_rx_p(qsfp_1_rx_p),
    .qsfp_1_rx_n(qsfp_1_rx_n),
    .qsfp_1_mgt_refclk_p(qsfp_1_mgt_refclk_p),
    .qsfp_1_mgt_refclk_n(qsfp_1_mgt_refclk_n),
    .qsfp_1_mod_prsnt_n(qsfp_1_mod_prsnt_n),
    .qsfp_1_reset_n(qsfp_1_reset_n),
    .qsfp_1_lp_mode(qsfp_1_lp_mode),
    .qsfp_1_intr_n(qsfp_1_intr_n)
);

endmodule

`resetall
