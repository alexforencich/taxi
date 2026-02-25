// SPDX-License-Identifier: MIT
/*

Copyright (c) 2014-2025 FPGA Ninja, LLC

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
    parameter string FAMILY = "virtexuplus",
    // 10G/25G MAC configuration
    parameter logic CFG_LOW_LATENCY = 1'b1,
    parameter logic COMBINED_MAC_PCS = 1'b1,
    parameter MAC_DATA_W = 64
)
(
    /*
     * Clock: 300MHz LVDS
     */
    input  wire logic        clk_300mhz_p,
    input  wire logic        clk_300mhz_n,

    /*
     * GPIO
     */
    output wire logic [1:0]  user_led_g,
    output wire logic        user_led_r,
    output wire logic [1:0]  front_led,
    input  wire logic [1:0]  user_sw,

    /*
     * Ethernet: QSFP28
     */
    output wire logic        qsfp_0_tx_p[4],
    output wire logic        qsfp_0_tx_n[4],
    input  wire logic        qsfp_0_rx_p[4],
    input  wire logic        qsfp_0_rx_n[4],
    input  wire logic        qsfp_0_mgt_refclk_p,
    input  wire logic        qsfp_0_mgt_refclk_n,
    input  wire logic        qsfp_0_modprs_l,
    output wire logic        qsfp_0_sel_l,

    output wire logic        qsfp_1_tx_p[4],
    output wire logic        qsfp_1_tx_n[4],
    input  wire logic        qsfp_1_rx_p[4],
    input  wire logic        qsfp_1_rx_n[4],
    // input  wire logic        qsfp_1_mgt_refclk_p,
    // input  wire logic        qsfp_1_mgt_refclk_n,
    input  wire logic        qsfp_1_modprs_l,
    output wire logic        qsfp_1_sel_l,

    output wire logic        qsfp_reset_l,
    input  wire logic        qsfp_int_l
);

// Clock and reset

wire clk_300mhz_ibufg;

// Internal 125 MHz clock
wire clk_125mhz_mmcm_out;
wire clk_125mhz_int;
wire rst_125mhz_int;

wire mmcm_rst = 1'b0;
wire mmcm_locked;
wire mmcm_clkfb;

IBUFGDS #(
   .DIFF_TERM("FALSE"),
   .IBUF_LOW_PWR("FALSE")
)
clk_300mhz_ibufg_inst (
   .O   (clk_300mhz_ibufg),
   .I   (clk_300mhz_p),
   .IB  (clk_300mhz_n)
);

// MMCM instance
MMCME4_BASE #(
    // 300 MHz input
    .CLKIN1_PERIOD(3.333),
    .REF_JITTER1(0.010),
    // 300 MHz input / 3 = 100 MHz PFD (range 10 MHz to 500 MHz)
    .DIVCLK_DIVIDE(3),
    // 100 MHz PFD * 12.5 = 1250 MHz VCO (range 800 MHz to 1600 MHz)
    .CLKFBOUT_MULT_F(12.5),
    .CLKFBOUT_PHASE(0),
    // 1250 MHz / 10 = 125 MHz, 0 degrees
    .CLKOUT0_DIVIDE_F(10),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    // Not used
    .CLKOUT1_DIVIDE(1),
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(90),
    // Not used
    .CLKOUT2_DIVIDE(1),
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
    // 300 MHz input
    .CLKIN1(clk_300mhz_ibufg),
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

// GPIO
wire [1:0] user_sw_int;

taxi_debounce_switch #(
    .WIDTH(2),
    .N(4),
    .RATE(125000)
)
debounce_switch_inst (
    .clk(clk_125mhz_int),
    .rst(rst_125mhz_int),
    .in({user_sw}),
    .out({user_sw_int})
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
    .user_led_g(user_led_g),
    .user_led_r(user_led_r),
    .front_led(front_led),
    .user_sw(user_sw_int),

    /*
     * Ethernet: QSFP28
     */
    .qsfp_0_tx_p(qsfp_0_tx_p),
    .qsfp_0_tx_n(qsfp_0_tx_n),
    .qsfp_0_rx_p(qsfp_0_rx_p),
    .qsfp_0_rx_n(qsfp_0_rx_n),
    .qsfp_0_mgt_refclk_p(qsfp_0_mgt_refclk_p),
    .qsfp_0_mgt_refclk_n(qsfp_0_mgt_refclk_n),
    .qsfp_0_modprs_l(qsfp_0_modprs_l),
    .qsfp_0_sel_l(qsfp_0_sel_l),

    .qsfp_1_tx_p(qsfp_1_tx_p),
    .qsfp_1_tx_n(qsfp_1_tx_n),
    .qsfp_1_rx_p(qsfp_1_rx_p),
    .qsfp_1_rx_n(qsfp_1_rx_n),
    // .qsfp_1_mgt_refclk_p(qsfp_1_mgt_refclk_p),
    // .qsfp_1_mgt_refclk_n(qsfp_1_mgt_refclk_n),
    .qsfp_1_modprs_l(qsfp_1_modprs_l),
    .qsfp_1_sel_l(qsfp_1_sel_l),

    .qsfp_reset_l(qsfp_reset_l),
    .qsfp_int_l(qsfp_int_l)
);

endmodule

`resetall
