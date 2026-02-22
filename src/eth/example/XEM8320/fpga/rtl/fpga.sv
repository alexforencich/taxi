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
    parameter string FAMILY = "artixuplus"
)
(
    /*
     * Clock: 125MHz LVDS
     */
    input  wire logic        clk_100mhz_p,
    input  wire logic        clk_100mhz_n,

    /*
     * GPIO
     */
    output wire logic [5:0]  led,

    /*
     * Ethernet: SFP+
     */
    input  wire logic        sfp_rx_p[2],
    input  wire logic        sfp_rx_n[2],
    output wire logic        sfp_tx_p[2],
    output wire logic        sfp_tx_n[2],
    // input  wire logic        sfp_mgt_refclk_0_p,
    // input  wire logic        sfp_mgt_refclk_0_n,
    // input  wire logic        sfp_mgt_refclk_1_p,
    // input  wire logic        sfp_mgt_refclk_1_n,
    input  wire logic        sfp_mgt_refclk_2_p,
    input  wire logic        sfp_mgt_refclk_2_n,

    output wire logic        sfp_tx_disable[2],
    input  wire logic        sfp_tx_fault[2],
    input  wire logic        sfp_npres[2],
    input  wire logic        sfp_los[2],
    output wire logic [1:0]  sfp_rs[2]

    // inout  wire logic        sfp_i2c_sda[2],
    // inout  wire logic        sfp_i2c_scl[2]
);

// Clock and reset

wire clk_100mhz_ibufg;

// Internal 125 MHz clock
wire clk_125mhz_mmcm_out;
wire clk_125mhz_int;
wire rst_125mhz_int;

// Internal 62.5 MHz clock
wire clk_62mhz_mmcm_out;
wire clk_62mhz_int;

wire mmcm_rst = 1'b0;
wire mmcm_locked;
wire mmcm_clkfb;

IBUFGDS #(
   .DIFF_TERM("FALSE"),
   .IBUF_LOW_PWR("FALSE")
)
clk_100mhz_ibufg_inst (
   .O   (clk_100mhz_ibufg),
   .I   (clk_100mhz_p),
   .IB  (clk_100mhz_n)
);

// MMCM instance
MMCME3_BASE #(
    // 125 MHz input
    .CLKIN1_PERIOD(8.0),
    .REF_JITTER1(0.010),
    // 100 MHz input / 2 = 50 MHz PFD (range 10 MHz to 500 MHz)
    .DIVCLK_DIVIDE(2),
    // 50 MHz PFD * 25 = 1250 MHz VCO (range 600 MHz to 1440 MHz)
    .CLKFBOUT_MULT_F(25),
    .CLKFBOUT_PHASE(0),
    // 1250 MHz / 10 = 125 MHz, 0 degrees
    .CLKOUT0_DIVIDE_F(10),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    // 1250 MHz / 20 = 62.5 MHz, 0 degrees
    .CLKOUT1_DIVIDE(20),
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(0),
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
    // 125 MHz input
    .CLKIN1(clk_100mhz_ibufg),
    // direct clkfb feeback
    .CLKFBIN(mmcm_clkfb),
    .CLKFBOUT(mmcm_clkfb),
    .CLKFBOUTB(),
    // 125 MHz, 0 degrees
    .CLKOUT0(clk_125mhz_mmcm_out),
    .CLKOUT0B(),
    // 62.5 MHz, 0 degrees
    .CLKOUT1(clk_62mhz_mmcm_out),
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

BUFG
clk_62mhz_bufg_inst (
    .I(clk_62mhz_mmcm_out),
    .O(clk_62mhz_int)
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
    .FAMILY(FAMILY)
)
core_inst (
    /*
     * Clock: 125MHz
     * Synchronous reset
     */
    .clk_125mhz(clk_125mhz_int),
    .rst_125mhz(rst_125mhz_int),

    /*
     * GPIO
     */
    .led(led),

    /*
     * Ethernet: SFP+
     */
    .sfp_rx_p(sfp_rx_p),
    .sfp_rx_n(sfp_rx_n),
    .sfp_tx_p(sfp_tx_p),
    .sfp_tx_n(sfp_tx_n),
    // .sfp_mgt_refclk_0_p(sfp_mgt_refclk_0_p),
    // .sfp_mgt_refclk_0_n(sfp_mgt_refclk_0_n),
    // .sfp_mgt_refclk_1_p(sfp_mgt_refclk_1_p),
    // .sfp_mgt_refclk_1_n(sfp_mgt_refclk_1_n),
    .sfp_mgt_refclk_2_p(sfp_mgt_refclk_2_p),
    .sfp_mgt_refclk_2_n(sfp_mgt_refclk_2_n),

    .sfp_tx_disable(sfp_tx_disable),
    .sfp_tx_fault(sfp_tx_fault),
    .sfp_npres(sfp_npres),
    .sfp_los(sfp_los),
    .sfp_rs(sfp_rs)
);

endmodule

`resetall
