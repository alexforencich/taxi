// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Transceiver and MAC/PHY wrapper for UltraScale/UltraScale+
 */
module taxi_eth_mac_100g_us_ch #
(
    parameter logic SIM = 1'b0,
    parameter string VENDOR = "XILINX",
    parameter string FAMILY = "virtexuplus",

    parameter logic HAS_COMMON = 1'b1,

    // GT config
    parameter logic CFG_LOW_LATENCY = 0,

    // GT type
    parameter string GT_TYPE = "GTY",

    // PLL parameters
    parameter logic QPLL0_PD = 1'b0,
    parameter logic QPLL1_PD = 1'b1,

    // GT parameters
    parameter logic GT_TX_PD = 1'b0,
    parameter logic GT_TX_QPLL_SEL = 1'b0,
    parameter logic GT_TX_POLARITY = 1'b0,
    parameter logic GT_TX_ELECIDLE = 1'b0,
    parameter logic GT_TX_INHIBIT = 1'b0,
    parameter logic [4:0] GT_TX_DIFFCTRL = 5'd16,
    parameter logic [6:0] GT_TX_MAINCURSOR = 7'd64,
    parameter logic [4:0] GT_TX_POSTCURSOR = 5'd0,
    parameter logic [4:0] GT_TX_PRECURSOR = 5'd0,
    parameter logic GT_RX_PD = 1'b0,
    parameter logic GT_RX_QPLL_SEL = 1'b0,
    parameter logic GT_RX_LPM_EN = 1'b1,
    parameter logic GT_RX_POLARITY = 1'b0,

    // MAC/PHY parameters
    parameter TX_SERDES_PIPELINE = 1,
    parameter RX_SERDES_PIPELINE = 1
)
(
    input  wire logic                 xcvr_ctrl_clk,
    input  wire logic                 xcvr_ctrl_rst,

    /*
     * Transceiver control
     */
    taxi_apb_if.slv                   s_apb_ctrl,

    /*
     * Common
     */
    output wire logic                 xcvr_gtpowergood_out,

    /*
     * PLL out
     */
    input  wire logic                 xcvr_gtrefclk00_in = 1'b0,
    input  wire logic                 xcvr_qpll0pd_in = 1'b0,
    output wire logic                 xcvr_qpll0lock_out,
    output wire logic                 xcvr_qpll0clk_out,
    output wire logic                 xcvr_qpll0refclk_out,
    input  wire logic                 xcvr_gtrefclk01_in = 1'b0,
    input  wire logic                 xcvr_qpll1pd_in = 1'b0,
    output wire logic                 xcvr_qpll1lock_out,
    output wire logic                 xcvr_qpll1clk_out,
    output wire logic                 xcvr_qpll1refclk_out,

    /*
     * PLL in
     */
    input  wire logic                 xcvr_qpll0lock_in = 1'b0,
    input  wire logic                 xcvr_qpll0clk_in = 1'b0,
    input  wire logic                 xcvr_qpll0refclk_in = 1'b0,
    input  wire logic                 xcvr_qpll1lock_in = 1'b0,
    input  wire logic                 xcvr_qpll1clk_in = 1'b0,
    input  wire logic                 xcvr_qpll1refclk_in = 1'b0,

    /*
     * Serial data
     */
    output wire logic                 xcvr_txp,
    output wire logic                 xcvr_txn,
    input  wire logic                 xcvr_rxp,
    input  wire logic                 xcvr_rxn,

    /*
     * MAC clocks
     */
    output wire logic                 rx_clk_out,
    input  wire logic                 rx_clk_in = 1'b0,
    input  wire logic                 rx_rst_in = 1'b0,
    output wire logic                 rx_rst_out,
    output wire logic                 tx_clk_out,
    input  wire logic                 tx_clk_in = 1'b0,
    input  wire logic                 tx_rst_in = 1'b0,
    output wire logic                 tx_rst_out,

    /*
     * Serdes interface
     */
    input  wire logic [127:0]         serdes_txdata,
    input  wire logic [15:0]          serdes_txctrl0,
    input  wire logic [15:0]          serdes_txctrl1,
    output wire logic [127:0]         serdes_rxdata,
    output wire logic [15:0]          serdes_rxctrl0,
    output wire logic [15:0]          serdes_rxctrl1
);

wire rx_reset_req = 1'b0;

wire [127:0]  gt_txdata;
wire [15:0]   gt_txctrl0;
wire [15:0]   gt_txctrl1;
wire [127:0]  gt_rxdata;
wire [15:0]   gt_rxctrl0;
wire [15:0]   gt_rxctrl1;

if (TX_SERDES_PIPELINE > 0) begin : tx_pipe

    (* shreg_extract = "no" *)
    reg [127:0] serdes_txdata_pipe_reg[TX_SERDES_PIPELINE-1:0];
    (* shreg_extract = "no" *)
    reg [15:0]  serdes_txctrl0_pipe_reg[TX_SERDES_PIPELINE-1:0];
    (* shreg_extract = "no" *)
    reg [15:0]  serdes_txctrl1_pipe_reg[TX_SERDES_PIPELINE-1:0];

    always @(posedge tx_clk_in) begin
        serdes_txdata_pipe_reg[0] <= serdes_txdata;
        serdes_txctrl0_pipe_reg[0] <= serdes_txctrl0;
        serdes_txctrl1_pipe_reg[0] <= serdes_txctrl1;

        for (integer i = 1; i < TX_SERDES_PIPELINE; i = i + 1) begin
            serdes_txdata_pipe_reg[i] <= serdes_txdata_pipe_reg[i-1];
            serdes_txctrl0_pipe_reg[i] <= serdes_txctrl0_pipe_reg[i-1];
            serdes_txctrl1_pipe_reg[i] <= serdes_txctrl1_pipe_reg[i-1];
        end
    end

    assign gt_txdata = serdes_txdata_pipe_reg[TX_SERDES_PIPELINE-1];
    assign gt_txctrl0 = serdes_txctrl0_pipe_reg[TX_SERDES_PIPELINE-1];
    assign gt_txctrl1 = serdes_txctrl1_pipe_reg[TX_SERDES_PIPELINE-1];

end else begin

    assign gt_txdata = serdes_txdata;
    assign gt_txctrl0 = serdes_txctrl0;
    assign gt_txctrl1 = serdes_txctrl1;

end

if (RX_SERDES_PIPELINE > 0) begin : rx_pipe

    (* shreg_extract = "no" *)
    reg [127:0] serdes_rxdata_pipe_reg[RX_SERDES_PIPELINE-1:0];
    (* shreg_extract = "no" *)
    reg [15:0]  serdes_rxctrl0_pipe_reg[RX_SERDES_PIPELINE-1:0];
    (* shreg_extract = "no" *)
    reg [15:0]  serdes_rxctrl1_pipe_reg[RX_SERDES_PIPELINE-1:0];

    always @(posedge rx_clk_in) begin
        serdes_rxdata_pipe_reg[0] <= gt_rxdata;
        serdes_rxctrl0_pipe_reg[0] <= gt_rxctrl0;
        serdes_rxctrl1_pipe_reg[0] <= gt_rxctrl1;

        for (integer i = 1; i < RX_SERDES_PIPELINE; i = i + 1) begin
            serdes_rxdata_pipe_reg[i] <= serdes_rxdata_pipe_reg[i-1];
            serdes_rxctrl0_pipe_reg[i] <= serdes_rxctrl0_pipe_reg[i-1];
            serdes_rxctrl1_pipe_reg[i] <= serdes_rxctrl1_pipe_reg[i-1];
        end
    end

    assign serdes_rxdata = serdes_rxdata_pipe_reg[RX_SERDES_PIPELINE-1];
    assign serdes_rxctrl0 = serdes_rxctrl0_pipe_reg[RX_SERDES_PIPELINE-1];
    assign serdes_rxctrl1 = serdes_rxctrl1_pipe_reg[RX_SERDES_PIPELINE-1];

end else begin

    assign serdes_rxdata = gt_rxdata;
    assign serdes_rxctrl0 = gt_rxctrl0;
    assign serdes_rxctrl1 = gt_rxctrl1;

end

if (CFG_LOW_LATENCY) begin : gt

    taxi_eth_mac_100g_us_gt_ll #(
        .SIM(SIM),
        .VENDOR(VENDOR),
        .FAMILY(FAMILY),

        .HAS_COMMON(HAS_COMMON),

        // GT type
        .GT_TYPE(GT_TYPE),

        // PLL parameters
        .QPLL0_PD(QPLL0_PD),
        .QPLL1_PD(QPLL1_PD),

        // GT parameters
        .GT_TX_PD(GT_TX_PD),
        .GT_TX_QPLL_SEL(GT_TX_QPLL_SEL),
        .GT_TX_POLARITY(GT_TX_POLARITY),
        .GT_TX_ELECIDLE(GT_TX_ELECIDLE),
        .GT_TX_INHIBIT(GT_TX_INHIBIT),
        .GT_TX_DIFFCTRL(GT_TX_DIFFCTRL),
        .GT_TX_MAINCURSOR(GT_TX_MAINCURSOR),
        .GT_TX_POSTCURSOR(GT_TX_POSTCURSOR),
        .GT_TX_PRECURSOR(GT_TX_PRECURSOR),
        .GT_RX_PD(GT_RX_PD),
        .GT_RX_QPLL_SEL(GT_RX_QPLL_SEL),
        .GT_RX_LPM_EN(GT_RX_LPM_EN),
        .GT_RX_POLARITY(GT_RX_POLARITY)
    )
    gt_inst (
        .xcvr_ctrl_clk(xcvr_ctrl_clk),
        .xcvr_ctrl_rst(xcvr_ctrl_rst),

        /*
         * Transceiver control
         */
        .s_apb_ctrl(s_apb_ctrl),

        /*
         * Common
         */
        .xcvr_gtpowergood_out(xcvr_gtpowergood_out),

        /*
         * PLL out
         */
        .xcvr_gtrefclk00_in(xcvr_gtrefclk00_in),
        .xcvr_qpll0pd_in(xcvr_qpll0pd_in),
        .xcvr_qpll0lock_out(xcvr_qpll0lock_out),
        .xcvr_qpll0clk_out(xcvr_qpll0clk_out),
        .xcvr_qpll0refclk_out(xcvr_qpll0refclk_out),
        .xcvr_gtrefclk01_in(xcvr_gtrefclk01_in),
        .xcvr_qpll1pd_in(xcvr_qpll1pd_in),
        .xcvr_qpll1lock_out(xcvr_qpll1lock_out),
        .xcvr_qpll1clk_out(xcvr_qpll1clk_out),
        .xcvr_qpll1refclk_out(xcvr_qpll1refclk_out),

        /*
         * PLL in
         */
        .xcvr_qpll0lock_in(xcvr_qpll0lock_in),
        .xcvr_qpll0clk_in(xcvr_qpll0clk_in),
        .xcvr_qpll0refclk_in(xcvr_qpll0refclk_in),
        .xcvr_qpll1lock_in(xcvr_qpll1lock_in),
        .xcvr_qpll1clk_in(xcvr_qpll1clk_in),
        .xcvr_qpll1refclk_in(xcvr_qpll1refclk_in),

        /*
         * Serial data
         */
        .xcvr_txp(xcvr_txp),
        .xcvr_txn(xcvr_txn),
        .xcvr_rxp(xcvr_rxp),
        .xcvr_rxn(xcvr_rxn),

        /*
         * GT user clocks
         */
        .rx_clk_out(rx_clk_out),
        .rx_clk_in(rx_clk_in),
        .rx_rst_in(rx_rst_in || rx_reset_req),
        .rx_rst_out(rx_rst_out),
        .tx_clk_out(tx_clk_out),
        .tx_clk_in(tx_clk_in),
        .tx_rst_in(tx_rst_in),
        .tx_rst_out(tx_rst_out),

        /*
         * Serdes interface
         */
        .serdes_txdata(gt_txdata),
        .serdes_txctrl0(gt_txctrl0),
        .serdes_txctrl1(gt_txctrl1),
        .serdes_rxdata(gt_rxdata),
        .serdes_rxctrl0(gt_rxctrl0),
        .serdes_rxctrl1(gt_rxctrl1)
    );

end else if (!CFG_LOW_LATENCY) begin : gt

    taxi_eth_mac_100g_us_gt #(
        .SIM(SIM),
        .VENDOR(VENDOR),
        .FAMILY(FAMILY),

        .HAS_COMMON(HAS_COMMON),

        // GT type
        .GT_TYPE(GT_TYPE),

        // PLL parameters
        .QPLL0_PD(QPLL0_PD),
        .QPLL1_PD(QPLL1_PD),

        // GT parameters
        .GT_TX_PD(GT_TX_PD),
        .GT_TX_QPLL_SEL(GT_TX_QPLL_SEL),
        .GT_TX_POLARITY(GT_TX_POLARITY),
        .GT_TX_ELECIDLE(GT_TX_ELECIDLE),
        .GT_TX_INHIBIT(GT_TX_INHIBIT),
        .GT_TX_DIFFCTRL(GT_TX_DIFFCTRL),
        .GT_TX_MAINCURSOR(GT_TX_MAINCURSOR),
        .GT_TX_POSTCURSOR(GT_TX_POSTCURSOR),
        .GT_TX_PRECURSOR(GT_TX_PRECURSOR),
        .GT_RX_PD(GT_RX_PD),
        .GT_RX_QPLL_SEL(GT_RX_QPLL_SEL),
        .GT_RX_LPM_EN(GT_RX_LPM_EN),
        .GT_RX_POLARITY(GT_RX_POLARITY)
    )
    gt_inst (
        .xcvr_ctrl_clk(xcvr_ctrl_clk),
        .xcvr_ctrl_rst(xcvr_ctrl_rst),

        /*
         * Transceiver control
         */
        .s_apb_ctrl(s_apb_ctrl),

        /*
         * Common
         */
        .xcvr_gtpowergood_out(xcvr_gtpowergood_out),

        /*
         * PLL out
         */
        .xcvr_gtrefclk00_in(xcvr_gtrefclk00_in),
        .xcvr_qpll0pd_in(xcvr_qpll0pd_in),
        .xcvr_qpll0lock_out(xcvr_qpll0lock_out),
        .xcvr_qpll0clk_out(xcvr_qpll0clk_out),
        .xcvr_qpll0refclk_out(xcvr_qpll0refclk_out),
        .xcvr_gtrefclk01_in(xcvr_gtrefclk01_in),
        .xcvr_qpll1pd_in(xcvr_qpll1pd_in),
        .xcvr_qpll1lock_out(xcvr_qpll1lock_out),
        .xcvr_qpll1clk_out(xcvr_qpll1clk_out),
        .xcvr_qpll1refclk_out(xcvr_qpll1refclk_out),

        /*
         * PLL in
         */
        .xcvr_qpll0lock_in(xcvr_qpll0lock_in),
        .xcvr_qpll0clk_in(xcvr_qpll0clk_in),
        .xcvr_qpll0refclk_in(xcvr_qpll0refclk_in),
        .xcvr_qpll1lock_in(xcvr_qpll1lock_in),
        .xcvr_qpll1clk_in(xcvr_qpll1clk_in),
        .xcvr_qpll1refclk_in(xcvr_qpll1refclk_in),

        /*
         * Serial data
         */
        .xcvr_txp(xcvr_txp),
        .xcvr_txn(xcvr_txn),
        .xcvr_rxp(xcvr_rxp),
        .xcvr_rxn(xcvr_rxn),

        /*
         * GT user clocks
         */
        .rx_clk_out(rx_clk_out),
        .rx_clk_in(rx_clk_in),
        .rx_rst_in(rx_rst_in || rx_reset_req),
        .rx_rst_out(rx_rst_out),
        .tx_clk_out(tx_clk_out),
        .tx_clk_in(tx_clk_in),
        .tx_rst_in(tx_rst_in),
        .tx_rst_out(tx_rst_out),

        /*
         * Serdes interface
         */
        .serdes_txdata(gt_txdata),
        .serdes_txctrl0(gt_txctrl0),
        .serdes_txctrl1(gt_txctrl1),
        .serdes_rxdata(gt_rxdata),
        .serdes_rxctrl0(gt_rxctrl0),
        .serdes_rxctrl1(gt_rxctrl1)
    );

end else begin

    $fatal(0, "Error: invalid configuration (%m)");

end

endmodule

`resetall
