// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Transceiver wrapper for 7-series
 */
module taxi_eth_phy_10g_7_gt #
(
    parameter logic SIM = 1'b0,
    parameter string VENDOR = "XILINX",
    parameter string FAMILY = "virtex7",

    parameter logic HAS_COMMON = 1'b1,

    // GT type
    parameter string GT_TYPE = "GTH",

    // PLL parameters
    parameter logic QPLL_PD = 1'b0,
    parameter logic QPLL_EXT_CTRL = 1'b0,

    // GT parameters
    parameter logic GT_TX_PD = 1'b0,
    parameter logic GT_TX_POLARITY = 1'b0,
    parameter logic GT_TX_ELECIDLE = 1'b0,
    parameter logic GT_TX_INHIBIT = 1'b0,
    parameter logic [3:0] GT_TX_DIFFCTRL = 4'd8,
    parameter logic [6:0] GT_TX_MAINCURSOR = 7'd64,
    parameter logic [4:0] GT_TX_POSTCURSOR = 5'd0,
    parameter logic [4:0] GT_TX_PRECURSOR = 5'd0,
    parameter logic GT_RX_PD = 1'b0,
    parameter logic GT_RX_LPM_EN = 1'b0,
    parameter logic GT_RX_POLARITY = 1'b0,

    // MAC/PHY parameters
    parameter DATA_W = 32,
    parameter HDR_W = 2
)
(
    input  wire logic               xcvr_ctrl_clk,
    input  wire logic               xcvr_ctrl_rst,

    /*
     * Transceiver control
     */
    taxi_apb_if.slv                 s_apb_ctrl,

    /*
     * PLL out
     */
    input  wire logic               xcvr_gtrefclk0_in = 1'b0,
    input  wire logic               xcvr_qpllpd_in = 1'b0,
    input  wire logic               xcvr_qpllreset_in = 1'b0,
    input  wire logic [2:0]         xcvr_qpllpcierate_in = 3'd0,
    output wire logic               xcvr_qplllock_out,
    output wire logic               xcvr_qpllclk_out,
    output wire logic               xcvr_qpllrefclk_out,

    /*
     * PLL in
     */
    input  wire logic               xcvr_qplllock_in = 1'b0,
    input  wire logic               xcvr_qpllclk_in = 1'b0,
    input  wire logic               xcvr_qpllrefclk_in = 1'b0,

    /*
     * Serial data
     */
    output wire logic               xcvr_txp,
    output wire logic               xcvr_txn,
    input  wire logic               xcvr_rxp,
    input  wire logic               xcvr_rxn,

    /*
     * GT user clocks
     */
    output wire logic               rx_clk,
    input  wire logic               rx_rst_in = 1'b0,
    output wire logic               rx_rst_out,
    output wire logic               tx_clk,
    input  wire logic               tx_rst_in = 1'b0,
    output wire logic               tx_rst_out,

    /*
     * Serdes interface
     */
    input  wire logic [DATA_W-1:0]  serdes_tx_data,
    input  wire logic               serdes_tx_data_valid,
    input  wire logic [HDR_W-1:0]   serdes_tx_hdr,
    input  wire logic               serdes_tx_hdr_valid,
    output wire logic               serdes_tx_gbx_req_sync,
    output wire logic               serdes_tx_gbx_req_stall,
    input  wire logic               serdes_tx_gbx_sync,
    output wire logic [DATA_W-1:0]  serdes_rx_data,
    output wire logic               serdes_rx_data_valid,
    output wire logic [HDR_W-1:0]   serdes_rx_hdr,
    output wire logic               serdes_rx_hdr_valid,
    input  wire logic               serdes_rx_bitslip
);

// check configuration
if (DATA_W != 32)
    $fatal(0, "Error: Interface width must be 32");

if (HDR_W != 2)
    $fatal(0, "Error: HDR_W must be 2");

// status
wire qpll_lock;

wire tx_reset_done;
wire tx_pma_reset_done;
wire tx_prgdiv_reset_done;

wire rx_reset_done;
wire rx_pma_reset_done;
wire rx_prgdiv_reset_done;

// control registers
wire [10:0]  gt_drp_addr;
wire [15:0]  gt_drp_di;
wire         gt_drp_en;
wire         gt_drp_we;
wire [15:0]  gt_drp_do;
wire         gt_drp_rdy;

wire [10:0]  com_drp_addr;
wire [15:0]  com_drp_di;
wire         com_drp_en;
wire         com_drp_we;
wire [15:0]  com_drp_do;
wire         com_drp_rdy;

wire         ctrl_qpll_reset;
wire         ctrl_qpll_pd;

wire [2:0]   ctrl_loopback;

wire         ctrl_tx_reset;
wire         ctrl_tx_pma_reset;
wire         ctrl_tx_pcs_reset;
wire         ctrl_tx_pd;
wire         ctrl_tx_qpll_sel;
wire         ctrl_rx_reset;
wire         ctrl_rx_pma_reset;
wire         ctrl_rx_pcs_reset;
wire         ctrl_rx_dfe_lpm_reset;
wire         ctrl_eyescan_reset;
wire         ctrl_rx_pd;
wire         ctrl_rx_qpll_sel;

wire         ctrl_rxcdrhold;
wire         ctrl_rxlpmen;

wire [3:0]   ctrl_txprbssel;
wire         ctrl_txprbsforceerr;
wire         ctrl_txpolarity;
wire         ctrl_txelecidle;
wire         ctrl_txinhibit;
wire [4:0]   ctrl_txdiffctrl;
wire [6:0]   ctrl_txmaincursor;
wire [4:0]   ctrl_txpostcursor;
wire [4:0]   ctrl_txprecursor;

wire         ctrl_rxpolarity;
wire         ctrl_rxprbscntreset;
wire [3:0]   ctrl_rxprbssel;

wire         ctrl_rxprbserr;

wire [15:0]  ctrl_dmonitorout;

wire         ctrl_phy_rx_reset_req_en;

taxi_eth_phy_25g_us_gt_apb #(
    .HAS_COMMON(HAS_COMMON),

    // PLL parameters
    .QPLL0_PD(QPLL_PD),

    // GT parameters
    .GT_TX_PD(GT_TX_PD),
    .GT_TX_POLARITY(GT_TX_POLARITY),
    .GT_TX_ELECIDLE(GT_TX_ELECIDLE),
    .GT_TX_INHIBIT(GT_TX_INHIBIT),
    .GT_TX_DIFFCTRL(5'(GT_TX_DIFFCTRL)),
    .GT_TX_MAINCURSOR(GT_TX_MAINCURSOR),
    .GT_TX_POSTCURSOR(GT_TX_POSTCURSOR),
    .GT_TX_PRECURSOR(GT_TX_PRECURSOR),
    .GT_RX_PD(GT_RX_PD),
    .GT_RX_LPM_EN(GT_RX_LPM_EN),
    .GT_RX_POLARITY(GT_RX_POLARITY)
)
ctrl_regs_inst (
    .clk(xcvr_ctrl_clk),
    .rst(xcvr_ctrl_rst),

    /*
     * Transceiver clocks
     */
    .gt_txusrclk2(tx_clk),
    .gt_rxusrclk2(rx_clk),

    /*
     * Transceiver control
     */
    .s_apb_ctrl(s_apb_ctrl),

    /*
     * DRP (channel)
     */
    .gt_drp_addr(gt_drp_addr),
    .gt_drp_di(gt_drp_di),
    .gt_drp_en(gt_drp_en),
    .gt_drp_we(gt_drp_we),
    .gt_drp_do(gt_drp_do),
    .gt_drp_rdy(gt_drp_rdy),

    /*
     * DRP (common)
     */
    .com_drp_addr(com_drp_addr),
    .com_drp_di(com_drp_di),
    .com_drp_en(com_drp_en),
    .com_drp_we(com_drp_we),
    .com_drp_do(com_drp_do),
    .com_drp_rdy(com_drp_rdy),

    /*
     * Control and status signals
     */
    .qpll0_reset(ctrl_qpll_reset),
    .qpll0_pd(ctrl_qpll_pd),
    .qpll0_lock(qpll_lock),
    .qpll1_reset(),
    .qpll1_pd(),
    .qpll1_lock(1'b0),

    .gt_loopback(ctrl_loopback),

    .gt_tx_reset(ctrl_tx_reset),
    .gt_tx_pma_reset(ctrl_tx_pma_reset),
    .gt_tx_pcs_reset(ctrl_tx_pcs_reset),
    .gt_tx_reset_done(tx_reset_done),
    .gt_tx_pma_reset_done(tx_pma_reset_done),
    .gt_tx_prgdiv_reset_done(tx_prgdiv_reset_done),
    .gt_tx_pd(ctrl_tx_pd),
    .gt_tx_qpll_sel(ctrl_tx_qpll_sel),
    .gt_rx_reset(ctrl_rx_reset),
    .gt_rx_pma_reset(ctrl_rx_pma_reset),
    .gt_rx_pcs_reset(ctrl_rx_pcs_reset),
    .gt_rx_dfe_lpm_reset(ctrl_rx_dfe_lpm_reset),
    .gt_eyescan_reset(ctrl_eyescan_reset),
    .gt_rx_reset_done(rx_reset_done),
    .gt_rx_pma_reset_done(rx_pma_reset_done),
    .gt_rx_prgdiv_reset_done(rx_prgdiv_reset_done),
    .gt_rx_pd(ctrl_rx_pd),
    .gt_rx_qpll_sel(ctrl_rx_qpll_sel),

    .gt_rxcdrhold(ctrl_rxcdrhold),
    .gt_rxlpmen(ctrl_rxlpmen),

    .gt_txprbssel(ctrl_txprbssel),
    .gt_txprbsforceerr(ctrl_txprbsforceerr),
    .gt_txpolarity(ctrl_txpolarity),
    .gt_txelecidle(ctrl_txelecidle),
    .gt_txinhibit(ctrl_txinhibit),
    .gt_txdiffctrl(ctrl_txdiffctrl),
    .gt_txmaincursor(ctrl_txmaincursor),
    .gt_txpostcursor(ctrl_txpostcursor),
    .gt_txprecursor(ctrl_txprecursor),

    .gt_rxpolarity(ctrl_rxpolarity),
    .gt_rxprbscntreset(ctrl_rxprbscntreset),
    .gt_rxprbssel(ctrl_rxprbssel),

    .gt_rxprbserr(ctrl_rxprbserr),

    .gt_dmonitorout(ctrl_dmonitorout),

    .phy_rx_reset_req_en(ctrl_phy_rx_reset_req_en)
);

wire gt_qpll_pd;
wire gt_qpll_reset;

wire qpll_refclk_lost;

if (HAS_COMMON) begin : common_ctrl

    taxi_gt_qpll_reset #(
        .QPLL_PD(QPLL_PD),
        .CNT_W(8)
    )
    qpll_reset_inst (
        .clk(xcvr_ctrl_clk),
        .rst(xcvr_ctrl_rst),

        /*
         * GT
         */
        .gt_qpll_reset_out(gt_qpll_reset),
        .gt_qpll_pd_out(gt_qpll_pd),
        .gt_qpll_lock_in(xcvr_qplllock_out),

        /*
         * Control/status
         */
        .qpll_reset_in(ctrl_qpll_reset),
        .qpll_pd_in(ctrl_qpll_pd),
        .qpll_lock_out(qpll_lock)
    );

end else begin : common_ctrl

    assign gt_qpll_pd = 1'b1;
    assign gt_qpll_reset = 1'b1;

    taxi_sync_signal #(
        .WIDTH(1),
        .N(2)
    )
    qpll_lock_sync_inst (
        .clk(xcvr_ctrl_clk),
        .in(xcvr_qplllock_in),
        .out(qpll_lock)
    );

end

wire gt_txoutclk;
wire gt_txusrclk;
wire gt_txusrclk2;

assign gt_txusrclk2 = gt_txusrclk;

wire gt_rxoutclk;
wire gt_rxusrclk;
wire gt_rxusrclk2;

assign gt_rxusrclk2 = gt_rxusrclk;

if (SIM) begin : clkbuf

    assign gt_txusrclk = gt_txoutclk;
    assign gt_rxusrclk = gt_rxoutclk;

end else begin : clkbuf

    BUFG txoutclk_bufg_inst (
        .I(gt_txoutclk),
        .O(gt_txusrclk)
    );

    BUFG rxoutclk_bufg_inst (
        .I(gt_rxoutclk),
        .O(gt_rxusrclk)
    );

    assign tx_clk = gt_txusrclk2;
    assign rx_clk = gt_rxusrclk2;

end

wire gt_tx_pd;
wire gt_tx_reset;
wire gt_tx_reset_done;
wire gt_tx_pma_reset;
wire gt_tx_pcs_reset;
wire gt_tx_pma_reset_done;
wire gt_tx_userrdy;

taxi_sync_reset #(
    .N(4)
)
tx_reset_sync_inst (
    .clk(tx_clk),
    .rst(!tx_reset_done || tx_rst_in),
    .out(tx_rst_out)
);

taxi_gt_tx_reset #(
    .GT_TX_PD(GT_TX_PD),
    .CNT_W(8)
)
gt_tx_reset_inst (
    .clk(xcvr_ctrl_clk),
    .rst(xcvr_ctrl_rst),

    /*
     * GT
     */
    .gt_txusrclk2(tx_clk),
    .gt_tx_pd_out(gt_tx_pd),
    .gt_tx_reset_out(gt_tx_reset),
    .gt_tx_reset_done_in(gt_tx_reset_done),
    .gt_userclk_tx_active_out(),
    .gt_tx_pma_reset_out(gt_tx_pma_reset),
    .gt_tx_pcs_reset_out(gt_tx_pcs_reset),
    .gt_tx_pma_reset_done_in(gt_tx_pma_reset_done),
    .gt_tx_prgdiv_reset_out(),
    .gt_tx_prgdiv_reset_done_in(1'b1),
    .gt_tx_qpll_sel_out(),
    .gt_tx_userrdy_out(gt_tx_userrdy),

    /*
     * Control/status
     */
    .qpll0_lock_in(qpll_lock),
    .qpll1_lock_in(1'b1),
    .tx_reset_in(tx_rst_in || ctrl_tx_reset),
    .tx_reset_done_out(tx_reset_done),
    .tx_pma_reset_in(ctrl_tx_pma_reset),
    .tx_pma_reset_done_out(tx_pma_reset_done),
    .tx_prgdiv_reset_done_out(tx_prgdiv_reset_done),
    .tx_pcs_reset_in(ctrl_tx_pcs_reset),
    .tx_pd_in(ctrl_tx_pd),
    .tx_qpll_sel_in(1'b0)
);

wire gt_rx_pd;
wire gt_rx_reset;
wire gt_rx_reset_done;
wire gt_rx_pma_reset;
wire gt_rx_dfe_lpm_reset;
wire gt_rx_eyescan_reset;
wire gt_rx_pcs_reset;
wire gt_rx_pma_reset_done;
wire gt_rx_userrdy;
wire gt_rx_cdr_lock;
wire gt_rx_lpm_en;

taxi_sync_reset #(
    .N(4)
)
rx_reset_sync_inst (
    .clk(rx_clk),
    .rst(!rx_reset_done || rx_rst_in),
    .out(rx_rst_out)
);

taxi_gt_rx_reset #(
    .GT_RX_PD(GT_RX_PD),
    .GT_RX_LPM_EN(GT_RX_LPM_EN),
    .CNT_W(8),
    .CDR_CNT_W(20)
)
gt_rx_reset_inst (
    .clk(xcvr_ctrl_clk),
    .rst(xcvr_ctrl_rst),

    /*
     * GT
     */
    .gt_rxusrclk2(rx_clk),
    .gt_rx_pd_out(gt_rx_pd),
    .gt_rx_reset_out(gt_rx_reset),
    .gt_rx_reset_done_in(gt_rx_reset_done),
    .gt_userclk_rx_active_out(),
    .gt_rx_pma_reset_out(gt_rx_pma_reset),
    .gt_rx_dfe_lpm_reset_out(gt_rx_dfe_lpm_reset),
    .gt_rx_eyescan_reset_out(gt_rx_eyescan_reset),
    .gt_rx_pcs_reset_out(gt_rx_pcs_reset),
    .gt_rx_pma_reset_done_in(gt_rx_pma_reset_done),
    .gt_rx_prgdiv_reset_out(),
    .gt_rx_prgdiv_reset_done_in(1'b1),
    .gt_rx_qpll_sel_out(),
    .gt_rx_userrdy_out(gt_rx_userrdy),
    .gt_rx_cdr_lock_in(gt_rx_cdr_lock),
    .gt_rx_lpm_en_out(gt_rx_lpm_en),

    /*
     * Control/status
     */
    .qpll0_lock_in(qpll_lock),
    .qpll1_lock_in(1'b1),
    .rx_reset_in(rx_rst_in || ctrl_rx_reset),
    .rx_reset_done_out(rx_reset_done),
    .rx_pma_reset_in(ctrl_rx_pma_reset),
    .rx_pma_reset_done_out(rx_pma_reset_done),
    .rx_prgdiv_reset_done_out(rx_prgdiv_reset_done),
    .rx_pcs_reset_in(ctrl_rx_pcs_reset),
    .rx_dfe_lpm_reset_in(ctrl_rx_dfe_lpm_reset),
    .eyescan_reset_in(ctrl_eyescan_reset),
    .rx_pd_in(ctrl_rx_pd),
    .rx_qpll_sel_in(1'b0),
    .rx_lpm_en_in(ctrl_rxlpmen)
);

wire [6:0] gt_txsequence;
wire [2:0] gt_txheader;
wire [63:0] gt_txdata;
wire gt_rxgearboxslip;
wire [1:0] gt_rxstartofseq;
wire [5:0] gt_rxheader;
wire [1:0] gt_rxheadervalid;
wire [63:0] gt_rxdata;
wire [1:0] gt_rxdatavalid;

assign gt_txdata = {32'd0, serdes_tx_data};
assign gt_txheader = {1'b0, serdes_tx_hdr};
assign gt_rxgearboxslip = serdes_rx_bitslip;

if (!SIM) begin
    assign serdes_rx_data = gt_rxdata;
    assign serdes_rx_data_valid = gt_rxdatavalid;
    assign serdes_rx_hdr = gt_rxheader[1:0];
    assign serdes_rx_hdr_valid = gt_rxheadervalid[0];
end

// 66 clock cycle sequence, with two stalls on cycles 64 and 65
// 32-bit internal, 32-bit external datapath width

// Generate gearbox request signals
logic [6:0] tx_seq_gen_reg = '0;
logic tx_req_sync_reg = 1'b0;
logic tx_req_stall_reg = 1'b0;

assign serdes_tx_gbx_req_sync = tx_req_sync_reg;
assign serdes_tx_gbx_req_stall = tx_req_stall_reg;

always_ff @(posedge tx_clk) begin
    tx_req_sync_reg <= 1'b0;
    tx_req_stall_reg <= 1'b0;

    tx_seq_gen_reg <= tx_seq_gen_reg - 1;
    if (tx_seq_gen_reg == 0) begin
        tx_seq_gen_reg <= 65;
        tx_req_sync_reg <= 1'b1;
    end
    if (tx_seq_gen_reg == 2 || tx_seq_gen_reg == 1) begin
        tx_req_stall_reg <= 1'b1;
    end
end

// Generate TX sequence
logic [6:0] tx_seq_reg = '0;

assign gt_txsequence = {1'b0, tx_seq_reg[6:1]};

always_ff @(posedge tx_clk) begin
    tx_seq_reg <= tx_seq_reg + 1;
    if (tx_seq_reg == 65) begin
        tx_seq_reg <= '0;
    end
    if (serdes_tx_gbx_sync) begin
        tx_seq_reg <= 1;
    end
end

if (SIM) begin : xcvr
    // simulation (no GT core)

    assign xcvr_qplllock_out = !gt_qpll_reset && !gt_qpll_pd;
    assign xcvr_qpllclk_out = 1'b0;
    assign xcvr_qpllrefclk_out = xcvr_gtrefclk0_in;

    assign gt_tx_reset_done = !gt_tx_reset;
    assign gt_tx_pma_reset_done = gt_tx_reset_done;

    assign gt_rx_reset_done = !gt_rx_reset;
    assign gt_rx_pma_reset_done = gt_rx_reset_done;
    assign gt_rx_cdr_lock = gt_rx_reset_done;

    assign com_drp_do = 16'hCC00;
    assign com_drp_rdy = 1'b1;

    assign gt_drp_do = 16'hDA00;
    assign gt_drp_rdy = 1'b1;

end else if (GT_TYPE == "GTH") begin : xcvr
    // 7-series GTH

    if (HAS_COMMON) begin : common

        // 156.25      * 66 = 10.3125
        // 161.1328125 * 64 = 10.3125
        // 322.265625  * 32 = 10.3125
        localparam QPLL_FBDIV_TOP =  66;

        localparam QPLL_FBDIV_IN  =
            (QPLL_FBDIV_TOP == 16)  ? 10'b0000100000 :
            (QPLL_FBDIV_TOP == 20)  ? 10'b0000110000 :
            (QPLL_FBDIV_TOP == 32)  ? 10'b0001100000 :
            (QPLL_FBDIV_TOP == 40)  ? 10'b0010000000 :
            (QPLL_FBDIV_TOP == 64)  ? 10'b0011100000 :
            (QPLL_FBDIV_TOP == 66)  ? 10'b0101000000 :
            (QPLL_FBDIV_TOP == 80)  ? 10'b0100100000 :
            (QPLL_FBDIV_TOP == 100) ? 10'b0101110000 : 10'b0000000000;

       localparam QPLL_FBDIV_RATIO =
            (QPLL_FBDIV_TOP == 16)  ? 1'b1 :
            (QPLL_FBDIV_TOP == 20)  ? 1'b1 :
            (QPLL_FBDIV_TOP == 32)  ? 1'b1 :
            (QPLL_FBDIV_TOP == 40)  ? 1'b1 :
            (QPLL_FBDIV_TOP == 64)  ? 1'b1 :
            (QPLL_FBDIV_TOP == 66)  ? 1'b0 :
            (QPLL_FBDIV_TOP == 80)  ? 1'b1 :
            (QPLL_FBDIV_TOP == 100) ? 1'b1 : 1'b1;

        GTHE2_COMMON #
        (
            // Simulation attributes
            .SIM_RESET_SPEEDUP   (SIM ? "TRUE" : "FALSE"),
            .SIM_QPLLREFCLK_SEL  (3'b001),
            .SIM_VERSION         ("2.0"),

            //----------------COMMON BLOCK Attributes---------------
            .BIAS_CFG                   (64'h0000040000001050),
            .COMMON_CFG                 (32'h0000005C),
            .QPLL_CFG                   (27'h04801C7),
            .QPLL_CLKOUT_CFG            (4'b1111),
            .QPLL_COARSE_FREQ_OVRD      (6'b010000),
            .QPLL_COARSE_FREQ_OVRD_EN   (1'b0),
            .QPLL_CP                    (10'b0000011111),
            .QPLL_CP_MONITOR_EN         (1'b0),
            .QPLL_DMONITOR_SEL          (1'b0),
            .QPLL_FBDIV                 (QPLL_FBDIV_IN),
            .QPLL_FBDIV_MONITOR_EN      (1'b0),
            .QPLL_FBDIV_RATIO           (QPLL_FBDIV_RATIO),
            .QPLL_INIT_CFG              (24'h000006),
            .QPLL_LOCK_CFG              (16'h05E8),
            .QPLL_LPF                   (4'b1111),
            .QPLL_REFCLK_DIV            (1),
            .RSVD_ATTR0                 (16'h0000),
            .RSVD_ATTR1                 (16'h0000),
            .QPLL_RP_COMP               (1'b0),
            .QPLL_VTRL_RESET            (2'b00),
            .RCAL_CFG                   (2'b00)
        )
        gt_common_inst
        (
            //----------- Common Block  - Dynamic Reconfiguration Port (DRP) -----------
            .DRPADDR            (com_drp_addr),
            .DRPCLK             (xcvr_ctrl_clk),
            .DRPDI              (com_drp_di),
            .DRPDO              (com_drp_do),
            .DRPEN              (com_drp_en),
            .DRPRDY             (com_drp_rdy),
            .DRPWE              (com_drp_we),
            //-------------------- Common Block  - Ref Clock Ports ---------------------
            .GTGREFCLK          (1'b0),
            .GTNORTHREFCLK0     (1'b0),
            .GTNORTHREFCLK1     (1'b0),
            .GTREFCLK0          (xcvr_gtrefclk0_in),
            .GTREFCLK1          (1'b0),
            .GTSOUTHREFCLK0     (1'b0),
            .GTSOUTHREFCLK1     (1'b0),
            //----------------------- Common Block -  QPLL Ports -----------------------
            .QPLLDMONITOR       (),
            //--------------------- Common Block - Clocking Ports ----------------------
            .QPLLOUTCLK         (xcvr_qpllclk_out),
            .QPLLOUTREFCLK      (xcvr_qpllrefclk_out),
            .REFCLKOUTMONITOR   (),
            //----------------------- Common Block - QPLL Ports ------------------------
            .BGRCALOVRDENB      (1'b1),
            .PMARSVDOUT         (),
            .QPLLFBCLKLOST      (),
            .QPLLLOCK           (xcvr_qplllock_out),
            .QPLLLOCKDETCLK     (xcvr_ctrl_clk),
            .QPLLLOCKEN         (1'b1),
            .QPLLOUTRESET       (1'b0),
            .QPLLPD             (QPLL_EXT_CTRL ? xcvr_qpllpd_in : gt_qpll_pd),
            .QPLLREFCLKLOST     (qpll_refclk_lost),
            .QPLLREFCLKSEL      (3'b001),
            .QPLLRESET          (QPLL_EXT_CTRL ? xcvr_qpllreset_in : gt_qpll_reset),
            .QPLLRSVD1          (16'b0000000000000000),
            .QPLLRSVD2          (5'b11111),
            //------------------------------- QPLL Ports -------------------------------
            .BGBYPASSB          (1'b1),
            .BGMONITORENB       (1'b1),
            .BGPDB              (1'b1),
            .BGRCALOVRD         (5'b11111),
            .PMARSVD            (8'b00000000),
            .RCALENB            (1'b1)
        );

    end else begin

        assign xcvr_qplllock_out = 1'b0;
        assign xcvr_qpllclk_out = 1'b0;
        assign xcvr_qpllrefclk_out = 1'b0;

        assign com_drp_do = '0;
        assign com_drp_rdy = 1'b1;

    end

    GTHE2_CHANNEL #
    (
        //_______________________ Simulation-Only Attributes __________________
        .SIM_RECEIVER_DETECT_PASS   ("TRUE"),
        .SIM_TX_EIDLE_DRIVE_LEVEL   ("X"),
        .SIM_RESET_SPEEDUP          (SIM ? "TRUE" : "FALSE"),
        .SIM_CPLLREFCLK_SEL         (3'b001),
        .SIM_VERSION                ("2.0"),
        //----------------RX Byte and Word Alignment Attributes---------------
        .ALIGN_COMMA_DOUBLE                     ("FALSE"),
        .ALIGN_COMMA_ENABLE                     (10'b0001111111),
        .ALIGN_COMMA_WORD                       (1),
        .ALIGN_MCOMMA_DET                       ("FALSE"),
        .ALIGN_MCOMMA_VALUE                     (10'b1010000011),
        .ALIGN_PCOMMA_DET                       ("FALSE"),
        .ALIGN_PCOMMA_VALUE                     (10'b0101111100),
        .SHOW_REALIGN_COMMA                     ("FALSE"),
        .RXSLIDE_AUTO_WAIT                      (7),
        .RXSLIDE_MODE                           ("OFF"),
        .RX_SIG_VALID_DLY                       (10),
        //----------------RX 8B/10B Decoder Attributes---------------
        .RX_DISPERR_SEQ_MATCH                   ("FALSE"),
        .DEC_MCOMMA_DETECT                      ("FALSE"),
        .DEC_PCOMMA_DETECT                      ("FALSE"),
        .DEC_VALID_COMMA_ONLY                   ("FALSE"),
        //----------------------RX Clock Correction Attributes----------------------
        .CBCC_DATA_SOURCE_SEL                   ("ENCODED"),
        .CLK_COR_SEQ_2_USE                      ("FALSE"),
        .CLK_COR_KEEP_IDLE                      ("FALSE"),
        .CLK_COR_MAX_LAT                        (19),
        .CLK_COR_MIN_LAT                        (15),
        .CLK_COR_PRECEDENCE                     ("TRUE"),
        .CLK_COR_REPEAT_WAIT                    (0),
        .CLK_COR_SEQ_LEN                        (1),
        .CLK_COR_SEQ_1_ENABLE                   (4'b1111),
        .CLK_COR_SEQ_1_1                        (10'b0100000000),
        .CLK_COR_SEQ_1_2                        (10'b0000000000),
        .CLK_COR_SEQ_1_3                        (10'b0000000000),
        .CLK_COR_SEQ_1_4                        (10'b0000000000),
        .CLK_CORRECT_USE                        ("FALSE"),
        .CLK_COR_SEQ_2_ENABLE                   (4'b1111),
        .CLK_COR_SEQ_2_1                        (10'b0100000000),
        .CLK_COR_SEQ_2_2                        (10'b0000000000),
        .CLK_COR_SEQ_2_3                        (10'b0000000000),
        .CLK_COR_SEQ_2_4                        (10'b0000000000),
        //----------------------RX Channel Bonding Attributes----------------------
        .CHAN_BOND_KEEP_ALIGN                   ("FALSE"),
        .CHAN_BOND_MAX_SKEW                     (1),
        .CHAN_BOND_SEQ_LEN                      (1),
        .CHAN_BOND_SEQ_1_1                      (10'b0000000000),
        .CHAN_BOND_SEQ_1_2                      (10'b0000000000),
        .CHAN_BOND_SEQ_1_3                      (10'b0000000000),
        .CHAN_BOND_SEQ_1_4                      (10'b0000000000),
        .CHAN_BOND_SEQ_1_ENABLE                 (4'b1111),
        .CHAN_BOND_SEQ_2_1                      (10'b0000000000),
        .CHAN_BOND_SEQ_2_2                      (10'b0000000000),
        .CHAN_BOND_SEQ_2_3                      (10'b0000000000),
        .CHAN_BOND_SEQ_2_4                      (10'b0000000000),
        .CHAN_BOND_SEQ_2_ENABLE                 (4'b1111),
        .CHAN_BOND_SEQ_2_USE                    ("FALSE"),
        .FTS_DESKEW_SEQ_ENABLE                  (4'b1111),
        .FTS_LANE_DESKEW_CFG                    (4'b1111),
        .FTS_LANE_DESKEW_EN                     ("FALSE"),
        //-------------------------RX Margin Analysis Attributes----------------------------
        .ES_CONTROL                             (6'b000000),
        .ES_ERRDET_EN                           ("FALSE"),
        .ES_EYE_SCAN_EN                         ("TRUE"),
        .ES_HORZ_OFFSET                         (12'h000),
        .ES_PMA_CFG                             (10'b0000000000),
        .ES_PRESCALE                            (5'b00000),
        .ES_QUALIFIER                           (80'h00000000000000000000),
        .ES_QUAL_MASK                           (80'h00000000000000000000),
        .ES_SDATA_MASK                          (80'h00000000000000000000),
        .ES_VERT_OFFSET                         (9'b000000000),
        //-----------------------FPGA RX Interface Attributes-------------------------
        .RX_DATA_WIDTH                          (32),
        //-------------------------PMA Attributes----------------------------
        .OUTREFCLK_SEL_INV                      (2'b11),
        .PMA_RSV                                (32'b00000000000000000000000010000000),
        .PMA_RSV2                               (32'h1C00000A),
        .PMA_RSV3                               (2'b00),
        .PMA_RSV4                               (15'h0008),
        .RX_BIAS_CFG                            (24'b000011000000000000010000),
        .DMONITOR_CFG                           (24'h000A00),
        .RX_CM_SEL                              (2'b11),
        .RX_CM_TRIM                             (4'b1010),
        .RX_DEBUG_CFG                           (14'b00000000000000),
        .RX_OS_CFG                              (13'b0000010000000),
        .TERM_RCAL_CFG                          (15'b100001000010000),
        .TERM_RCAL_OVRD                         (3'b000),
        .TST_RSV                                (32'h00000000),
        .RX_CLK25_DIV                           (7),
        .TX_CLK25_DIV                           (7),
        .UCODEER_CLR                            (1'b0),
        //-------------------------PCI Express Attributes----------------------------
        .PCS_PCIE_EN                            ("FALSE"),
        //-------------------------PCS Attributes----------------------------
        .PCS_RSVD_ATTR                          (48'h000000000000),
        //-----------RX Buffer Attributes------------
        .RXBUF_ADDR_MODE                        ("FAST"),
        .RXBUF_EIDLE_HI_CNT                     (4'b1000),
        .RXBUF_EIDLE_LO_CNT                     (4'b0000),
        .RXBUF_EN                               ("TRUE"),
        .RX_BUFFER_CFG                          (6'b000000),
        .RXBUF_RESET_ON_CB_CHANGE               ("TRUE"),
        .RXBUF_RESET_ON_COMMAALIGN              ("FALSE"),
        .RXBUF_RESET_ON_EIDLE                   ("FALSE"),
        .RXBUF_RESET_ON_RATE_CHANGE             ("TRUE"),
        .RXBUFRESET_TIME                        (5'b00001),
        .RXBUF_THRESH_OVFLW                     (61),
        .RXBUF_THRESH_OVRD                      ("FALSE"),
        .RXBUF_THRESH_UNDFLW                    (4),
        .RXDLY_CFG                              (16'h001F),
        .RXDLY_LCFG                             (9'h030),
        .RXDLY_TAP_CFG                          (16'h0000),
        .RXPH_CFG                               (24'hC00002),
        .RXPHDLY_CFG                            (24'h084020),
        .RXPH_MONITOR_SEL                       (5'b00000),
        .RX_XCLK_SEL                            ("RXREC"),
        .RX_DDI_SEL                             (6'b000000),
        .RX_DEFER_RESET_BUF_EN                  ("TRUE"),
        //---------------------CDR Attributes-------------------------
        //For Display Port, HBR/RBR- set RXCDR_CFG=72'h0380008bff40200008
        //For Display Port, HBR2 -   set RXCDR_CFG=72'h038c008bff20200010
        //For SATA Gen1 GTX- set RXCDR_CFG=72'h03_8000_8BFF_4010_0008
        //For SATA Gen2 GTX- set RXCDR_CFG=72'h03_8800_8BFF_4020_0008
        //For SATA Gen3 GTX- set RXCDR_CFG=72'h03_8000_8BFF_1020_0010
        //For SATA Gen3 GTP- set RXCDR_CFG=83'h0_0000_87FE_2060_2444_1010
        //For SATA Gen2 GTP- set RXCDR_CFG=83'h0_0000_47FE_2060_2448_1010
        //For SATA Gen1 GTP- set RXCDR_CFG=83'h0_0000_47FE_1060_2448_1010
        .RXCDR_CFG                              (83'h0002007FE2000C208001A),
        .RXCDR_FR_RESET_ON_EIDLE                (1'b0),
        .RXCDR_HOLD_DURING_EIDLE                (1'b0),
        .RXCDR_PH_RESET_ON_EIDLE                (1'b0),
        .RXCDR_LOCK_CFG                         (6'b010101),
        //-----------------RX Initialization and Reset Attributes-------------------
        .RXCDRFREQRESET_TIME                    (5'b00001),
        .RXCDRPHRESET_TIME                      (5'b00001),
        .RXISCANRESET_TIME                      (5'b00001),
        .RXPCSRESET_TIME                        (5'b00001),
        .RXPMARESET_TIME                        (5'b00011),
        //-----------------RX OOB Signaling Attributes-------------------
        .RXOOB_CFG                              (7'b0000110),
        //-----------------------RX Gearbox Attributes---------------------------
        .RXGEARBOX_EN                           ("TRUE"),
        .GEARBOX_MODE                           (3'b001),
        //-----------------------PRBS Detection Attribute-----------------------
        .RXPRBS_ERR_LOOPBACK                    (1'b0),
        //-----------Power-Down Attributes----------
        .PD_TRANS_TIME_FROM_P2                  (12'h03c),
        .PD_TRANS_TIME_NONE_P2                  (8'h19),
        .PD_TRANS_TIME_TO_P2                    (8'h64),
        //-----------RX OOB Signaling Attributes----------
        .SAS_MAX_COM                            (64),
        .SAS_MIN_COM                            (36),
        .SATA_BURST_SEQ_LEN                     (4'b0101),
        .SATA_BURST_VAL                         (3'b100),
        .SATA_EIDLE_VAL                         (3'b100),
        .SATA_MAX_BURST                         (8),
        .SATA_MAX_INIT                          (21),
        .SATA_MAX_WAKE                          (7),
        .SATA_MIN_BURST                         (4),
        .SATA_MIN_INIT                          (12),
        .SATA_MIN_WAKE                          (4),
        //-----------RX Fabric Clock Output Control Attributes----------
        .TRANS_TIME_RATE                        (8'h0E),
        //------------TX Buffer Attributes----------------
        .TXBUF_EN                               ("TRUE"),
        .TXBUF_RESET_ON_RATE_CHANGE             ("TRUE"),
        .TXDLY_CFG                              (16'h001F),
        .TXDLY_LCFG                             (9'h030),
        .TXDLY_TAP_CFG                          (16'h0000),
        .TXPH_CFG                               (16'h0780),
        .TXPHDLY_CFG                            (24'h084020),
        .TXPH_MONITOR_SEL                       (5'b00000),
        .TX_XCLK_SEL                            ("TXOUT"),
        //-----------------------FPGA TX Interface Attributes-------------------------
        .TX_DATA_WIDTH                          (32),
        //-----------------------TX Configurable Driver Attributes-------------------------
        .TX_DEEMPH0                             (6'b000000),
        .TX_DEEMPH1                             (6'b000000),
        .TX_EIDLE_ASSERT_DELAY                  (3'b110),
        .TX_EIDLE_DEASSERT_DELAY                (3'b100),
        .TX_LOOPBACK_DRIVE_HIZ                  ("FALSE"),
        .TX_MAINCURSOR_SEL                      (1'b0),
        .TX_DRIVE_MODE                          ("DIRECT"),
        .TX_MARGIN_FULL_0                       (7'b1001110),
        .TX_MARGIN_FULL_1                       (7'b1001001),
        .TX_MARGIN_FULL_2                       (7'b1000101),
        .TX_MARGIN_FULL_3                       (7'b1000010),
        .TX_MARGIN_FULL_4                       (7'b1000000),
        .TX_MARGIN_LOW_0                        (7'b1000110),
        .TX_MARGIN_LOW_1                        (7'b1000100),
        .TX_MARGIN_LOW_2                        (7'b1000010),
        .TX_MARGIN_LOW_3                        (7'b1000000),
        .TX_MARGIN_LOW_4                        (7'b1000000),
        //-----------------------TX Gearbox Attributes--------------------------
        .TXGEARBOX_EN                           ("TRUE"),
        //-----------------------TX Initialization and Reset Attributes--------------------------
        .TXPCSRESET_TIME                        (5'b00001),
        .TXPMARESET_TIME                        (5'b00001),
        //-----------------------TX Receiver Detection Attributes--------------------------
        .TX_RXDETECT_CFG                        (14'h1832),
        .TX_RXDETECT_REF                        (3'b100),
        //--------------------------CPLL Attributes----------------------------
        .CPLL_CFG                               (29'h00BC07DC),
        .CPLL_FBDIV                             (4),
        .CPLL_FBDIV_45                          (5),
        .CPLL_INIT_CFG                          (24'h00001E),
        .CPLL_LOCK_CFG                          (16'h01E8),
        .CPLL_REFCLK_DIV                        (1),
        .RXOUT_DIV                              (1),
        .TXOUT_DIV                              (1),
        .SATA_CPLL_CFG                          ("VCO_3000MHZ"),
        //------------RX Initialization and Reset Attributes-------------
        .RXDFELPMRESET_TIME                     (7'b0001111),
        //------------RX Equalizer Attributes-------------
        .RXLPM_HF_CFG                           (14'b00001000000000),
        .RXLPM_LF_CFG                           (18'b001001000000000000),
        .RX_DFE_GAIN_CFG                        (23'h0020C0),
        .RX_DFE_H2_CFG                          (12'b000000000000),
        .RX_DFE_H3_CFG                          (12'b000001000000),
        .RX_DFE_H4_CFG                          (11'b00011100000),
        .RX_DFE_H5_CFG                          (11'b00011100000),
        .RX_DFE_KL_CFG                          (33'b001000001000000000000001100010000),
        .RX_DFE_LPM_CFG                         (16'h0080),
        .RX_DFE_LPM_HOLD_DURING_EIDLE           (1'b0),
        .RX_DFE_UT_CFG                          (17'b00011100000000000),
        .RX_DFE_VP_CFG                          (17'b00011101010100011),
        //-----------------------Power-Down Attributes-------------------------
        .RX_CLKMUX_PD                           (1'b1),
        .TX_CLKMUX_PD                           (1'b1),
        //-----------------------FPGA RX Interface Attribute-------------------------
        .RX_INT_DATAWIDTH                       (1),
        //-----------------------FPGA TX Interface Attribute-------------------------
        .TX_INT_DATAWIDTH                       (1),
        //----------------TX Configurable Driver Attributes---------------
        .TX_QPI_STATUS_EN                       (1'b0),
        //---------------- JTAG Attributes ---------------
        .ACJTAG_DEBUG_MODE                      (1'b0),
        .ACJTAG_MODE                            (1'b0),
        .ACJTAG_RESET                           (1'b0),
        .ADAPT_CFG0                             (20'h00C10),
        .CFOK_CFG                               (42'h24800040E80),
        .CFOK_CFG2                              (6'h20),
        .CFOK_CFG3                              (6'h20),
        .ES_CLK_PHASE_SEL                       (1'b0),
        .PMA_RSV5                               (4'h0),
        .RESET_POWERSAVE_DISABLE                (1'b0),
        .USE_PCS_CLK_PHASE_SEL                  (1'b0),
        .A_RXOSCALRESET                         (1'b0),
        //---------------- RX Phase Interpolator Attributes---------------
        .RXPI_CFG0                              (2'b00),
        .RXPI_CFG1                              (2'b11),
        .RXPI_CFG2                              (2'b11),
        .RXPI_CFG3                              (2'b11),
        .RXPI_CFG4                              (1'b0),
        .RXPI_CFG5                              (1'b0),
        .RXPI_CFG6                              (3'b100),
        //------------RX Decision Feedback Equalizer(DFE)-------------
        .RX_DFELPM_CFG0                         (4'b0110),
        .RX_DFELPM_CFG1                         (1'b0),
        .RX_DFELPM_KLKH_AGC_STUP_EN             (1'b1),
        .RX_DFE_AGC_CFG0                        (2'b00),
        .RX_DFE_AGC_CFG1                        (3'b100),
        .RX_DFE_AGC_CFG2                        (4'b0000),
        .RX_DFE_AGC_OVRDEN                      (1'b1),
        .RX_DFE_H6_CFG                          (11'h020),
        .RX_DFE_H7_CFG                          (11'h020),
        .RX_DFE_KL_LPM_KH_CFG0                  (2'b01),
        .RX_DFE_KL_LPM_KH_CFG1                  (3'b010),
        .RX_DFE_KL_LPM_KH_CFG2                  (4'b0010),
        .RX_DFE_KL_LPM_KH_OVRDEN                (1'b1),
        .RX_DFE_KL_LPM_KL_CFG0                  (2'b10),
        .RX_DFE_KL_LPM_KL_CFG1                  (3'b010),
        .RX_DFE_KL_LPM_KL_CFG2                  (4'b0010),
        .RX_DFE_KL_LPM_KL_OVRDEN                (1'b1),
        .RX_DFE_ST_CFG                          (54'h00E100000C003F),
        //---------------- TX Phase Interpolator Attributes---------------
        .TXPI_CFG0                              (2'b00),
        .TXPI_CFG1                              (2'b00),
        .TXPI_CFG2                              (2'b00),
        .TXPI_CFG3                              (1'b0),
        .TXPI_CFG4                              (1'b0),
        .TXPI_CFG5                              (3'b100),
        .TXPI_GREY_SEL                          (1'b0),
        .TXPI_INVSTROBE_SEL                     (1'b0),
        .TXPI_PPMCLK_SEL                        ("TXUSRCLK2"),
        .TXPI_PPM_CFG                           (8'h00),
        .TXPI_SYNFREQ_PPM                       (3'b001),
        .TX_RXDETECT_PRECHARGE_TIME             (17'h155CC),
        //---------------- LOOPBACK Attributes---------------
        .LOOPBACK_CFG                           (1'b0),
        //----------------RX OOB Signalling Attributes---------------
        .RXOOB_CLK_CFG                          ("PMA"),
        //---------------- CDR Attributes ---------------
        .RXOSCALRESET_TIME                      (5'b00011),
        .RXOSCALRESET_TIMEOUT                   (5'b00000),
        //----------------TX OOB Signalling Attributes---------------
        .TXOOB_CFG                              (1'b0),
        //----------------RX Buffer Attributes---------------
        .RXSYNC_MULTILANE                       (1'b0),
        .RXSYNC_OVRD                            (1'b0),
        .RXSYNC_SKIP_DA                         (1'b0),
        //----------------TX Buffer Attributes---------------
        .TXSYNC_MULTILANE                       (1'b0),
        .TXSYNC_OVRD                            (1'b0),
        .TXSYNC_SKIP_DA                         (1'b0)
    )
    gt_ch_inst
    (
        //------------------------------- CPLL Ports -------------------------------
        .CPLLFBCLKLOST                  (),
        .CPLLLOCK                       (),
        .CPLLLOCKDETCLK                 (1'b0),
        .CPLLLOCKEN                     (1'b1),
        .CPLLPD                         (1'b1),
        .CPLLREFCLKLOST                 (),
        .CPLLREFCLKSEL                  (3'b001),
        .CPLLRESET                      (1'b0),
        .GTRSVD                         (16'b0000000000000000),
        .PCSRSVDIN                      (16'b0000000000000000),
        .PCSRSVDIN2                     (5'b00000),
        .PMARSVDIN                      (5'b00000),
        .TSTIN                          (20'b11111111111111111111),
        //------------------------ Channel - Clocking Ports ------------------------
        .GTGREFCLK                      (1'b0),
        .GTNORTHREFCLK0                 (1'b0),
        .GTNORTHREFCLK1                 (1'b0),
        .GTREFCLK0                      (1'b0),
        .GTREFCLK1                      (1'b0),
        .GTSOUTHREFCLK0                 (1'b0),
        .GTSOUTHREFCLK1                 (1'b0),
        //-------------------------- Channel - DRP Ports  --------------------------
        .DRPADDR                        (gt_drp_addr),
        .DRPCLK                         (xcvr_ctrl_clk),
        .DRPDI                          (gt_drp_di),
        .DRPDO                          (gt_drp_do),
        .DRPEN                          (gt_drp_en),
        .DRPRDY                         (gt_drp_rdy),
        .DRPWE                          (gt_drp_we),
        //----------------------------- Clocking Ports -----------------------------
        .GTREFCLKMONITOR                (),
        .QPLLCLK                        (xcvr_qpllclk_in),
        .QPLLREFCLK                     (xcvr_qpllrefclk_in),
        .RXSYSCLKSEL                    (2'b11),
        .TXSYSCLKSEL                    (2'b11),
        //--------------- FPGA TX Interface Datapath Configuration  ----------------
        .TX8B10BEN                      (1'b0),
        //----------------------------- Loopback Ports -----------------------------
        .LOOPBACK                       (3'b000),
        //--------------------------- PCI Express Ports ----------------------------
        .PHYSTATUS                      (),
        .RXRATE                         (3'd0),
        .RXVALID                        (),
        //---------------------------- Power-Down Ports ----------------------------
        .RXPD                           (gt_rx_pd ? 2'b11 : 2'b00),
        .TXPD                           (gt_tx_pd ? 2'b11 : 2'b00),
        //------------------------ RX 8B/10B Decoder Ports -------------------------
        .SETERRSTATUS                   (1'b0),
        //------------------- RX Initialization and Reset Ports --------------------
        .EYESCANRESET                   (gt_rx_eyescan_reset),
        .RXUSERRDY                      (gt_rx_userrdy),
        //------------------------ RX Margin Analysis Ports ------------------------
        .EYESCANDATAERROR               (),
        .EYESCANMODE                    (1'b0),
        .EYESCANTRIGGER                 (1'b0),
        //----------------------------- Receive Ports ------------------------------
        .CLKRSVD0                       (1'b0),
        .CLKRSVD1                       (1'b0),
        .DMONFIFORESET                  (1'b0),
        .DMONITORCLK                    (1'b0),
        .RXRATEMODE                     (1'b0),
        .SIGVALIDCLK                    (1'b0),
        //------------ Receive Ports - 64b66b and 64b67b Gearbox Ports -------------
        .RXSTARTOFSEQ                   (gt_rxstartofseq),
        //----------------------- Receive Ports - CDR Ports ------------------------
        .RXCDRFREQRESET                 (1'b0),
        .RXCDRHOLD                      (1'b0),
        .RXCDRLOCK                      (gt_rx_cdr_lock),
        .RXCDROVRDEN                    (1'b0),
        .RXCDRRESET                     (1'b0),
        .RXCDRRESETRSV                  (1'b0),
        //----------------- Receive Ports - Clock Correction Ports -----------------
        .RXCLKCORCNT                    (),
        //------------- Receive Ports - Comma Detection and Alignment --------------
        .RXSLIDE                        (1'b0),
        //----------------- Receive Ports - Digital Monitor Ports ------------------
        .DMONITOROUT                    (),
        //-------- Receive Ports - FPGA RX Interface Datapath Configuration --------
        .RX8B10BEN                      (1'b0),
        //---------------- Receive Ports - FPGA RX Interface Ports -----------------
        .RXUSRCLK                       (gt_rxusrclk),
        .RXUSRCLK2                      (gt_rxusrclk2),
        //---------------- Receive Ports - FPGA RX interface Ports -----------------
        .RXDATA                         (gt_rxdata),
        //----------------- Receive Ports - Pattern Checker Ports ------------------
        .RXPRBSERR                      (),
        .RXPRBSSEL                      (3'd0),
        //----------------- Receive Ports - Pattern Checker ports ------------------
        .RXPRBSCNTRESET                 (1'b0),
        //---------------- Receive Ports - RX 8B/10B Decoder Ports -----------------
        .RXDISPERR                      (),
        .RXNOTINTABLE                   (),
        //----------------- Receive Ports - RX Buffer Bypass Ports -----------------
        .RXBUFRESET                     (1'b0),
        .RXBUFSTATUS                    (),
        .RXDDIEN                        (1'b0),
        .RXDLYBYPASS                    (1'b1),
        .RXDLYEN                        (1'b0),
        .RXDLYOVRDEN                    (1'b0),
        .RXDLYSRESET                    (1'b0),
        .RXDLYSRESETDONE                (),
        .RXPHALIGN                      (1'b0),
        .RXPHALIGNDONE                  (),
        .RXPHALIGNEN                    (1'b0),
        .RXPHDLYPD                      (1'b0),
        .RXPHDLYRESET                   (1'b0),
        .RXPHMONITOR                    (),
        .RXPHOVRDEN                     (1'b0),
        .RXPHSLIPMONITOR                (),
        .RXSTATUS                       (),
        .RXSYNCALLIN                    (1'b0),
        .RXSYNCDONE                     (),
        .RXSYNCIN                       (1'b0),
        .RXSYNCMODE                     (1'b0),
        .RXSYNCOUT                      (),
        //------------ Receive Ports - RX Byte and Word Alignment Ports ------------
        .RXBYTEISALIGNED                (),
        .RXBYTEREALIGN                  (),
        .RXCOMMADET                     (),
        .RXCOMMADETEN                   (1'b0),
        .RXMCOMMAALIGNEN                (1'b0),
        .RXPCOMMAALIGNEN                (1'b0),
        //---------------- Receive Ports - RX Channel Bonding Ports ----------------
        .RXCHANBONDSEQ                  (),
        .RXCHBONDEN                     (1'b0),
        .RXCHBONDLEVEL                  (3'd0),
        .RXCHBONDMASTER                 (1'b0),
        .RXCHBONDO                      (),
        .RXCHBONDSLAVE                  (1'b0),
        //--------------- Receive Ports - RX Channel Bonding Ports  ----------------
        .RXCHANISALIGNED                (),
        .RXCHANREALIGN                  (),
        //---------- Receive Ports - RX Decision Feedback Equalizer(DFE) -----------
        .RSOSINTDONE                    (),
        .RXDFESLIDETAPOVRDEN            (1'b0),
        .RXOSCALRESET                   (1'b0),
        //------------------ Receive Ports - RX Equailizer Ports -------------------
        .RXLPMHFHOLD                    (1'b0),
        .RXLPMHFOVRDEN                  (1'b0),
        .RXLPMLFHOLD                    (1'b0),
        //------------------- Receive Ports - RX Equalizar Ports -------------------
        .RXDFESLIDETAPSTARTED           (),
        .RXDFESLIDETAPSTROBEDONE        (),
        .RXDFESLIDETAPSTROBESTARTED     (),
        //------------------- Receive Ports - RX Equalizer Ports -------------------
        .RXADAPTSELTEST                 (14'd0),
        .RXDFEAGCHOLD                   (1'b0),
        .RXDFEAGCOVRDEN                 (1'b0),
        .RXDFEAGCTRL                    (5'b10000),
        .RXDFECM1EN                     (1'b0),
        .RXDFELFHOLD                    (1'b0),
        .RXDFELFOVRDEN                  (1'b0),
        .RXDFELPMRESET                  (gt_rx_dfe_lpm_reset),
        .RXDFESLIDETAP                  (5'd0),
        .RXDFESLIDETAPADAPTEN           (1'b0),
        .RXDFESLIDETAPHOLD              (1'b0),
        .RXDFESLIDETAPID                (6'd0),
        .RXDFESLIDETAPINITOVRDEN        (1'b0),
        .RXDFESLIDETAPONLYADAPTEN       (1'b0),
        .RXDFESLIDETAPSTROBE            (1'b0),
        .RXDFESTADAPTDONE               (),
        .RXDFETAP2HOLD                  (1'b0),
        .RXDFETAP2OVRDEN                (1'b0),
        .RXDFETAP3HOLD                  (1'b0),
        .RXDFETAP3OVRDEN                (1'b0),
        .RXDFETAP4HOLD                  (1'b0),
        .RXDFETAP4OVRDEN                (1'b0),
        .RXDFETAP5HOLD                  (1'b0),
        .RXDFETAP5OVRDEN                (1'b0),
        .RXDFETAP6HOLD                  (1'b0),
        .RXDFETAP6OVRDEN                (1'b0),
        .RXDFETAP7HOLD                  (1'b0),
        .RXDFETAP7OVRDEN                (1'b0),
        .RXDFEUTHOLD                    (1'b0),
        .RXDFEUTOVRDEN                  (1'b0),
        .RXDFEVPHOLD                    (1'b0),
        .RXDFEVPOVRDEN                  (1'b0),
        .RXDFEVSEN                      (1'b0),
        .RXDFEXYDEN                     (1'b1),
        .RXLPMLFKLOVRDEN                (1'b0),
        .RXMONITOROUT                   (),
        .RXMONITORSEL                   ('0),
        .RXOSHOLD                       (1'b0),
        .RXOSINTCFG                     (4'b0110),
        .RXOSINTEN                      (1'b1),
        .RXOSINTHOLD                    (1'b0),
        .RXOSINTID0                     (4'd0),
        .RXOSINTNTRLEN                  (1'b0),
        .RXOSINTOVRDEN                  (1'b0),
        .RXOSINTSTARTED                 (),
        .RXOSINTSTROBE                  (1'b0),
        .RXOSINTSTROBEDONE              (),
        .RXOSINTSTROBESTARTED           (),
        .RXOSINTTESTOVRDEN              (1'b0),
        .RXOSOVRDEN                     (1'b0),
        //---------- Receive Ports - RX Fabric ClocK Output Control Ports ----------
        .RXRATEDONE                     (),
        //------------- Receive Ports - RX Fabric Output Control Ports -------------
        .RXOUTCLK                       (gt_rxoutclk),
        .RXOUTCLKFABRIC                 (),
        .RXOUTCLKPCS                    (),
        .RXOUTCLKSEL                    (3'b010),
        //-------------------- Receive Ports - RX Gearbox Ports --------------------
        .RXDATAVALID                    (gt_rxdatavalid),
        .RXHEADER                       (gt_rxheader),
        .RXHEADERVALID                  (gt_rxheadervalid),
        //------------------- Receive Ports - RX Gearbox Ports  --------------------
        .RXGEARBOXSLIP                  (gt_rxgearboxslip),
        //----------- Receive Ports - RX Initialization and Reset Ports ------------
        .GTRXRESET                      (gt_rx_reset),
        .RXOOBRESET                     (1'b0),
        .RXPCSRESET                     (gt_rx_pcs_reset),
        .RXPMARESET                     (gt_rx_pma_reset),
        .RXPMARESETDONE                 (gt_rx_pma_reset_done),
        .RXRESETDONE                    (gt_rx_reset_done),
        //---------------- Receive Ports - RX Margin Analysis ports ----------------
        .RXLPMEN                        (gt_rx_lpm_en),
        //----------------- Receive Ports - RX OOB Signaling ports -----------------
        .RXCOMSASDET                    (),
        .RXCOMWAKEDET                   (),
        //---------------- Receive Ports - RX OOB Signaling ports  -----------------
        .RXCOMINITDET                   (),
        //---------------- Receive Ports - RX OOB signalling Ports -----------------
        .RXELECIDLE                     (),
        .RXELECIDLEMODE                 (2'b11),
        //--------------- Receive Ports - RX Polarity Control Ports ----------------
        .RXPOLARITY                     (ctrl_rxpolarity),
        //----------------- Receive Ports - RX8B/10B Decoder Ports -----------------
        .RXCHARISCOMMA                  (),
        .RXCHARISK                      (),
        //---------------- Receive Ports - Rx Channel Bonding Ports ----------------
        .RXCHBONDI                      (5'b00000),
        //---------------------- Receive Ports -RX AFE Ports -----------------------
        .GTHRXN                         (xcvr_rxn),
        .GTHRXP                         (xcvr_rxp),
        //------------------------------ Rx AFE Ports ------------------------------
        .RXQPIEN                        (1'b0),
        .RXQPISENN                      (),
        .RXQPISENP                      (),
        //------------------------- TX Buffer Bypass Ports -------------------------
        .TXPHDLYTSTCLK                  (1'b0),
        //--------------- TX Phase Interpolator PPM Controller Ports ---------------
        .TXPIPPMEN                      (1'b0),
        .TXPIPPMOVRDEN                  (1'b0),
        .TXPIPPMPD                      (1'b0),
        .TXPIPPMSEL                     (1'b1),
        .TXPIPPMSTEPSIZE                (5'd0),
        //-------------------- Transceiver Reset Mode Operation --------------------
        .GTRESETSEL                     (1'b0),
        .RESETOVRD                      (1'b0),
        //----------------------------- Transmit Ports -----------------------------
        .TXRATEMODE                     (1'b0),
        //------------ Transmit Ports - 64b66b and 64b67b Gearbox Ports ------------
        .TXHEADER                       (gt_txheader),
        //-------------- Transmit Ports - 8b10b Encoder Control Ports --------------
        .TXCHARDISPMODE                 (8'd0),
        .TXCHARDISPVAL                  (8'd0),
        //---------------- Transmit Ports - FPGA TX Interface Ports ----------------
        .TXUSRCLK                       (gt_txusrclk),
        .TXUSRCLK2                      (gt_txusrclk2),
        //------------------- Transmit Ports - PCI Express Ports -------------------
        .TXELECIDLE                     (ctrl_txelecidle),
        .TXMARGIN                       (3'd0),
        .TXRATE                         (3'd0),
        .TXSWING                        (1'b0),
        //---------------- Transmit Ports - Pattern Generator Ports ----------------
        .TXPRBSFORCEERR                 (1'b0),
        //---------------- Transmit Ports - TX Buffer Bypass Ports -----------------
        .TXDLYBYPASS                    (1'b1),
        .TXDLYEN                        (1'b0),
        .TXDLYHOLD                      (1'b0),
        .TXDLYOVRDEN                    (1'b0),
        .TXDLYSRESET                    (1'b0),
        .TXDLYSRESETDONE                (),
        .TXDLYUPDOWN                    (1'b0),
        .TXPHALIGN                      (1'b0),
        .TXPHALIGNDONE                  (),
        .TXPHALIGNEN                    (1'b0),
        .TXPHDLYPD                      (1'b0),
        .TXPHDLYRESET                   (1'b0),
        .TXPHINIT                       (1'b0),
        .TXPHINITDONE                   (),
        .TXPHOVRDEN                     (1'b0),
        .TXSYNCALLIN                    (1'b0),
        .TXSYNCDONE                     (),
        .TXSYNCIN                       (1'b0),
        .TXSYNCMODE                     (1'b0),
        .TXSYNCOUT                      (),
        //-------------------- Transmit Ports - TX Buffer Ports --------------------
        .TXBUFSTATUS                    (),
        //------------- Transmit Ports - TX Configurable Driver Ports --------------
        .TXBUFDIFFCTRL                  (3'b100),
        .TXDEEMPH                       (1'b0),
        .TXDIFFCTRL                     (ctrl_txdiffctrl[3:0]),
        .TXDIFFPD                       (1'b0),
        .TXINHIBIT                      (ctrl_txinhibit),
        .TXMAINCURSOR                   (ctrl_txmaincursor),
        .TXPISOPD                       (1'b0),
        .TXPOSTCURSOR                   (ctrl_txpostcursor),
        .TXPOSTCURSORINV                (1'b0),
        .TXPRECURSOR                    (ctrl_txprecursor),
        .TXPRECURSORINV                 (1'b0),
        .TXQPIBIASEN                    (1'b0),
        .TXQPISTRONGPDOWN               (1'b0),
        .TXQPIWEAKPUP                   (1'b0),
        //---------------- Transmit Ports - TX Data Path interface -----------------
        .TXDATA                         (gt_txdata),
        //-------------- Transmit Ports - TX Driver and OOB signaling --------------
        .GTHTXN                         (xcvr_txn),
        .GTHTXP                         (xcvr_txp),
        //--------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
        .TXOUTCLK                       (gt_txoutclk),
        .TXOUTCLKFABRIC                 (),
        .TXOUTCLKPCS                    (),
        .TXOUTCLKSEL                    (3'b010),
        .TXRATEDONE                     (),
        //------------------- Transmit Ports - TX Gearbox Ports --------------------
        .TXGEARBOXREADY                 (),
        .TXSEQUENCE                     (gt_txsequence),
        .TXSTARTSEQ                     (1'b0),
        //----------- Transmit Ports - TX Initialization and Reset Ports -----------
        .CFGRESET                       (1'b0),
        .GTTXRESET                      (gt_tx_reset),
        .PCSRSVDOUT                     (),
        .TXUSERRDY                      (gt_tx_userrdy),
        .TXPCSRESET                     (gt_tx_pcs_reset),
        .TXPMARESET                     (gt_tx_pma_reset),
        .TXPMARESETDONE                 (gt_tx_pma_reset_done),
        .TXRESETDONE                    (gt_tx_reset_done),
        //---------------- Transmit Ports - TX OOB signalling Ports ----------------
        .TXCOMFINISH                    (),
        .TXCOMINIT                      (1'b0),
        .TXCOMSAS                       (1'b0),
        .TXCOMWAKE                      (1'b0),
        .TXPDELECIDLEMODE               (1'b1),
        //--------------- Transmit Ports - TX Polarity Control Ports ---------------
        .TXPOLARITY                     (ctrl_txpolarity),
        //------------- Transmit Ports - TX Receiver Detection Ports  --------------
        .TXDETECTRX                     (1'b0),
        //---------------- Transmit Ports - TX8b/10b Encoder Ports -----------------
        .TX8B10BBYPASS                  (8'd0),
        //---------------- Transmit Ports - pattern Generator Ports ----------------
        .TXPRBSSEL                      (3'd0),
        //--------- Transmit Transmit Ports - 8b10b Encoder Control Ports ----------
        .TXCHARISK                      (8'd0),
        //--------------------- Tx Configurable Driver  Ports ----------------------
        .TXQPISENN                      (),
        .TXQPISENP                      ()
    );

end else if (GT_TYPE == "GTX") begin : xcvr
    // 7-series GTX

    if (HAS_COMMON) begin : common

        // 156.25      * 66 = 10.3125
        // 161.1328125 * 64 = 10.3125
        // 322.265625  * 32 = 10.3125
        localparam QPLL_FBDIV_TOP =  66;

        localparam QPLL_FBDIV_IN  =  (QPLL_FBDIV_TOP == 16)  ? 10'b0000100000 :
            (QPLL_FBDIV_TOP == 20)  ? 10'b0000110000 :
            (QPLL_FBDIV_TOP == 32)  ? 10'b0001100000 :
            (QPLL_FBDIV_TOP == 40)  ? 10'b0010000000 :
            (QPLL_FBDIV_TOP == 64)  ? 10'b0011100000 :
            (QPLL_FBDIV_TOP == 66)  ? 10'b0101000000 :
            (QPLL_FBDIV_TOP == 80)  ? 10'b0100100000 :
            (QPLL_FBDIV_TOP == 100) ? 10'b0101110000 : 10'b0000000000;

        localparam QPLL_FBDIV_RATIO = (QPLL_FBDIV_TOP == 16)  ? 1'b1 :
            (QPLL_FBDIV_TOP == 20)  ? 1'b1 :
            (QPLL_FBDIV_TOP == 32)  ? 1'b1 :
            (QPLL_FBDIV_TOP == 40)  ? 1'b1 :
            (QPLL_FBDIV_TOP == 64)  ? 1'b1 :
            (QPLL_FBDIV_TOP == 66)  ? 1'b0 :
            (QPLL_FBDIV_TOP == 80)  ? 1'b1 :
            (QPLL_FBDIV_TOP == 100) ? 1'b1 : 1'b1;

        GTXE2_COMMON #
        (
            // Simulation attributes
            .SIM_RESET_SPEEDUP   (SIM ? "TRUE" : "FALSE"),
            .SIM_QPLLREFCLK_SEL  (3'b001),
            .SIM_VERSION         ("4.0"),
            //----------------COMMON BLOCK Attributes---------------
            .BIAS_CFG                   (64'h0000040000001000),
            .COMMON_CFG                 (32'h00000000),
            .QPLL_CFG                   (27'h0680181),
            .QPLL_CLKOUT_CFG            (4'b0000),
            .QPLL_COARSE_FREQ_OVRD      (6'b010000),
            .QPLL_COARSE_FREQ_OVRD_EN   (1'b0),
            .QPLL_CP                    (10'b0000011111),
            .QPLL_CP_MONITOR_EN         (1'b0),
            .QPLL_DMONITOR_SEL          (1'b0),
            .QPLL_FBDIV                 (QPLL_FBDIV_IN),
            .QPLL_FBDIV_MONITOR_EN      (1'b0),
            .QPLL_FBDIV_RATIO           (QPLL_FBDIV_RATIO),
            .QPLL_INIT_CFG              (24'h000006),
            .QPLL_LOCK_CFG              (16'h21E8),
            .QPLL_LPF                   (4'b1111),
            .QPLL_REFCLK_DIV            (1)
        )
        gt_common_inst
        (
            //----------- Common Block  - Dynamic Reconfiguration Port (DRP) -----------
            .DRPADDR            (com_drp_addr),
            .DRPCLK             (xcvr_ctrl_clk),
            .DRPDI              (com_drp_di),
            .DRPDO              (com_drp_do),
            .DRPEN              (com_drp_en),
            .DRPRDY             (com_drp_rdy),
            .DRPWE              (com_drp_we),
            //-------------------- Common Block  - Ref Clock Ports ---------------------
            .GTGREFCLK          (1'b0),
            .GTNORTHREFCLK0     (1'b0),
            .GTNORTHREFCLK1     (1'b0),
            .GTREFCLK0          (xcvr_gtrefclk0_in),
            .GTREFCLK1          (1'b0),
            .GTSOUTHREFCLK0     (1'b0),
            .GTSOUTHREFCLK1     (1'b0),
            //----------------------- Common Block -  QPLL Ports -----------------------
            .QPLLDMONITOR       (),
            //--------------------- Common Block - Clocking Ports ----------------------
            .QPLLOUTCLK         (xcvr_qpllclk_out),
            .QPLLOUTREFCLK      (xcvr_qpllrefclk_out),
            .REFCLKOUTMONITOR   (),
            //----------------------- Common Block - QPLL Ports ------------------------
            .QPLLFBCLKLOST      (),
            .QPLLLOCK           (xcvr_qplllock_out),
            .QPLLLOCKDETCLK     (xcvr_ctrl_clk),
            .QPLLLOCKEN         (1'b1),
            .QPLLOUTRESET       (1'b0),
            .QPLLPD             (QPLL_EXT_CTRL ? xcvr_qpllpd_in : gt_qpll_pd),
            .QPLLREFCLKLOST     (qpll_refclk_lost),
            .QPLLREFCLKSEL      (3'b001),
            .QPLLRESET          (QPLL_EXT_CTRL ? xcvr_qpllreset_in : gt_qpll_reset),
            .QPLLRSVD1          (16'b0000000000000000),
            .QPLLRSVD2          (5'b11111),
            //------------------------------- QPLL Ports -------------------------------
            .BGBYPASSB          (1'b1),
            .BGMONITORENB       (1'b1),
            .BGPDB              (1'b1),
            .BGRCALOVRD         (5'b11111),
            .PMARSVD            (8'b00000000),
            .RCALENB            (1'b1)
        );

    end else begin

        assign xcvr_qplllock_out = 1'b0;
        assign xcvr_qpllclk_out = 1'b0;
        assign xcvr_qpllrefclk_out = 1'b0;

        assign com_drp_do = '0;
        assign com_drp_rdy = 1'b1;

    end

    GTXE2_CHANNEL #
    (
        //_______________________ Simulation-Only Attributes __________________
        .SIM_RECEIVER_DETECT_PASS   ("TRUE"),
        .SIM_TX_EIDLE_DRIVE_LEVEL   ("X"),
        .SIM_RESET_SPEEDUP          (SIM ? "TRUE" : "FALSE"),
        .SIM_CPLLREFCLK_SEL         (3'b001),
        .SIM_VERSION                ("4.0"),
        //----------------RX Byte and Word Alignment Attributes---------------
        .ALIGN_COMMA_DOUBLE                     ("FALSE"),
        .ALIGN_COMMA_ENABLE                     (10'b1111111111),
        .ALIGN_COMMA_WORD                       (1),
        .ALIGN_MCOMMA_DET                       ("FALSE"),
        .ALIGN_MCOMMA_VALUE                     (10'b1010000011),
        .ALIGN_PCOMMA_DET                       ("FALSE"),
        .ALIGN_PCOMMA_VALUE                     (10'b0101111100),
        .SHOW_REALIGN_COMMA                     ("FALSE"),
        .RXSLIDE_AUTO_WAIT                      (7),
        .RXSLIDE_MODE                           ("OFF"),
        .RX_SIG_VALID_DLY                       (10),
        //----------------RX 8B/10B Decoder Attributes---------------
        .RX_DISPERR_SEQ_MATCH                   ("FALSE"),
        .DEC_MCOMMA_DETECT                      ("FALSE"),
        .DEC_PCOMMA_DETECT                      ("FALSE"),
        .DEC_VALID_COMMA_ONLY                   ("FALSE"),
        //----------------------RX Clock Correction Attributes----------------------
        .CBCC_DATA_SOURCE_SEL                   ("ENCODED"),
        .CLK_COR_SEQ_2_USE                      ("FALSE"),
        .CLK_COR_KEEP_IDLE                      ("FALSE"),
        .CLK_COR_MAX_LAT                        (19),
        .CLK_COR_MIN_LAT                        (15),
        .CLK_COR_PRECEDENCE                     ("TRUE"),
        .CLK_COR_REPEAT_WAIT                    (0),
        .CLK_COR_SEQ_LEN                        (1),
        .CLK_COR_SEQ_1_ENABLE                   (4'b1111),
        .CLK_COR_SEQ_1_1                        (10'b0100000000),
        .CLK_COR_SEQ_1_2                        (10'b0000000000),
        .CLK_COR_SEQ_1_3                        (10'b0000000000),
        .CLK_COR_SEQ_1_4                        (10'b0000000000),
        .CLK_CORRECT_USE                        ("FALSE"),
        .CLK_COR_SEQ_2_ENABLE                   (4'b1111),
        .CLK_COR_SEQ_2_1                        (10'b0100000000),
        .CLK_COR_SEQ_2_2                        (10'b0000000000),
        .CLK_COR_SEQ_2_3                        (10'b0000000000),
        .CLK_COR_SEQ_2_4                        (10'b0000000000),
        //----------------------RX Channel Bonding Attributes----------------------
        .CHAN_BOND_KEEP_ALIGN                   ("FALSE"),
        .CHAN_BOND_MAX_SKEW                     (1),
        .CHAN_BOND_SEQ_LEN                      (1),
        .CHAN_BOND_SEQ_1_1                      (10'b0000000000),
        .CHAN_BOND_SEQ_1_2                      (10'b0000000000),
        .CHAN_BOND_SEQ_1_3                      (10'b0000000000),
        .CHAN_BOND_SEQ_1_4                      (10'b0000000000),
        .CHAN_BOND_SEQ_1_ENABLE                 (4'b1111),
        .CHAN_BOND_SEQ_2_1                      (10'b0000000000),
        .CHAN_BOND_SEQ_2_2                      (10'b0000000000),
        .CHAN_BOND_SEQ_2_3                      (10'b0000000000),
        .CHAN_BOND_SEQ_2_4                      (10'b0000000000),
        .CHAN_BOND_SEQ_2_ENABLE                 (4'b1111),
        .CHAN_BOND_SEQ_2_USE                    ("FALSE"),
        .FTS_DESKEW_SEQ_ENABLE                  (4'b1111),
        .FTS_LANE_DESKEW_CFG                    (4'b1111),
        .FTS_LANE_DESKEW_EN                     ("FALSE"),
        //-------------------------RX Margin Analysis Attributes----------------------------
        .ES_CONTROL                             (6'b000000),
        .ES_ERRDET_EN                           ("FALSE"),
        .ES_EYE_SCAN_EN                         ("TRUE"),
        .ES_HORZ_OFFSET                         (12'h000),
        .ES_PMA_CFG                             (10'b0000000000),
        .ES_PRESCALE                            (5'b00000),
        .ES_QUALIFIER                           (80'h00000000000000000000),
        .ES_QUAL_MASK                           (80'h00000000000000000000),
        .ES_SDATA_MASK                          (80'h00000000000000000000),
        .ES_VERT_OFFSET                         (9'b000000000),
        //-----------------------FPGA RX Interface Attributes-------------------------
        .RX_DATA_WIDTH                          (32),
        //-------------------------PMA Attributes----------------------------
        .OUTREFCLK_SEL_INV                      (2'b11),
        .PMA_RSV                                (32'h001E7080),
        .PMA_RSV2                               (16'h2050),
        .PMA_RSV3                               (2'b00),
        .PMA_RSV4                               (32'h00000000),
        .RX_BIAS_CFG                            (12'b000000000100),
        .DMONITOR_CFG                           (24'h000A00),
        .RX_CM_SEL                              (2'b11),
        .RX_CM_TRIM                             (3'b010),
        .RX_DEBUG_CFG                           (12'b000000000000),
        .RX_OS_CFG                              (13'b0000010000000),
        .TERM_RCAL_CFG                          (5'b10000),
        .TERM_RCAL_OVRD                         (1'b0),
        .TST_RSV                                (32'h00000000),
        .RX_CLK25_DIV                           (7),
        .TX_CLK25_DIV                           (7),
        .UCODEER_CLR                            (1'b0),
        //-------------------------PCI Express Attributes----------------------------
        .PCS_PCIE_EN                            ("FALSE"),
        //-------------------------PCS Attributes----------------------------
        .PCS_RSVD_ATTR                          (48'h000000000000),
        //-----------RX Buffer Attributes------------
        .RXBUF_ADDR_MODE                        ("FAST"),
        .RXBUF_EIDLE_HI_CNT                     (4'b1000),
        .RXBUF_EIDLE_LO_CNT                     (4'b0000),
        .RXBUF_EN                               ("TRUE"),
        .RX_BUFFER_CFG                          (6'b000000),
        .RXBUF_RESET_ON_CB_CHANGE               ("TRUE"),
        .RXBUF_RESET_ON_COMMAALIGN              ("FALSE"),
        .RXBUF_RESET_ON_EIDLE                   ("FALSE"),
        .RXBUF_RESET_ON_RATE_CHANGE             ("TRUE"),
        .RXBUFRESET_TIME                        (5'b00001),
        .RXBUF_THRESH_OVFLW                     (61),
        .RXBUF_THRESH_OVRD                      ("FALSE"),
        .RXBUF_THRESH_UNDFLW                    (4),
        .RXDLY_CFG                              (16'h001F),
        .RXDLY_LCFG                             (9'h030),
        .RXDLY_TAP_CFG                          (16'h0000),
        .RXPH_CFG                               (24'h000000),
        .RXPHDLY_CFG                            (24'h084020),
        .RXPH_MONITOR_SEL                       (5'b00000),
        .RX_XCLK_SEL                            ("RXREC"),
        .RX_DDI_SEL                             (6'b000000),
        .RX_DEFER_RESET_BUF_EN                  ("TRUE"),
        //---------------------CDR Attributes-------------------------
        //For Display Port, HBR/RBR- set RXCDR_CFG=72'h0380008bff40200008
        //For Display Port, HBR2 -   set RXCDR_CFG=72'h038c008bff20200010
        //For SATA Gen1 GTX- set RXCDR_CFG=72'h03_8000_8BFF_4010_0008
        //For SATA Gen2 GTX- set RXCDR_CFG=72'h03_8800_8BFF_4020_0008
        //For SATA Gen3 GTX- set RXCDR_CFG=72'h03_8000_8BFF_1020_0010
        //For SATA Gen3 GTP- set RXCDR_CFG=83'h0_0000_87FE_2060_2444_1010
        //For SATA Gen2 GTP- set RXCDR_CFG=83'h0_0000_47FE_2060_2448_1010
        //For SATA Gen1 GTP- set RXCDR_CFG=83'h0_0000_47FE_1060_2448_1010
        .RXCDR_CFG                              (72'h0b000023ff10400020),
        .RXCDR_FR_RESET_ON_EIDLE                (1'b0),
        .RXCDR_HOLD_DURING_EIDLE                (1'b0),
        .RXCDR_PH_RESET_ON_EIDLE                (1'b0),
        .RXCDR_LOCK_CFG                         (6'b010101),
        //-----------------RX Initialization and Reset Attributes-------------------
        .RXCDRFREQRESET_TIME                    (5'b00001),
        .RXCDRPHRESET_TIME                      (5'b00001),
        .RXISCANRESET_TIME                      (5'b00001),
        .RXPCSRESET_TIME                        (5'b00001),
        .RXPMARESET_TIME                        (5'b00011),
        //-----------------RX OOB Signaling Attributes-------------------
        .RXOOB_CFG                              (7'b0000110),
        //-----------------------RX Gearbox Attributes---------------------------
        .RXGEARBOX_EN                           ("TRUE"),
        .GEARBOX_MODE                           (3'b001),
        //-----------------------PRBS Detection Attribute-----------------------
        .RXPRBS_ERR_LOOPBACK                    (1'b0),
        //-----------Power-Down Attributes----------
        .PD_TRANS_TIME_FROM_P2                  (12'h03c),
        .PD_TRANS_TIME_NONE_P2                  (8'h19),
        .PD_TRANS_TIME_TO_P2                    (8'h64),
        //-----------RX OOB Signaling Attributes----------
        .SAS_MAX_COM                            (64),
        .SAS_MIN_COM                            (36),
        .SATA_BURST_SEQ_LEN                     (4'b0101),
        .SATA_BURST_VAL                         (3'b100),
        .SATA_EIDLE_VAL                         (3'b100),
        .SATA_MAX_BURST                         (8),
        .SATA_MAX_INIT                          (21),
        .SATA_MAX_WAKE                          (7),
        .SATA_MIN_BURST                         (4),
        .SATA_MIN_INIT                          (12),
        .SATA_MIN_WAKE                          (4),
        //-----------RX Fabric Clock Output Control Attributes----------
        .TRANS_TIME_RATE                        (8'h0E),
        //------------TX Buffer Attributes----------------
        .TXBUF_EN                               ("TRUE"),
        .TXBUF_RESET_ON_RATE_CHANGE             ("TRUE"),
        .TXDLY_CFG                              (16'h001F),
        .TXDLY_LCFG                             (9'h030),
        .TXDLY_TAP_CFG                          (16'h0000),
        .TXPH_CFG                               (16'h0780),
        .TXPHDLY_CFG                            (24'h084020),
        .TXPH_MONITOR_SEL                       (5'b00000),
        .TX_XCLK_SEL                            ("TXOUT"),
        //-----------------------FPGA TX Interface Attributes-------------------------
        .TX_DATA_WIDTH                          (32),
        //-----------------------TX Configurable Driver Attributes-------------------------
        .TX_DEEMPH0                             (5'b00000),
        .TX_DEEMPH1                             (5'b00000),
        .TX_EIDLE_ASSERT_DELAY                  (3'b110),
        .TX_EIDLE_DEASSERT_DELAY                (3'b100),
        .TX_LOOPBACK_DRIVE_HIZ                  ("FALSE"),
        .TX_MAINCURSOR_SEL                      (1'b0),
        .TX_DRIVE_MODE                          ("DIRECT"),
        .TX_MARGIN_FULL_0                       (7'b1001110),
        .TX_MARGIN_FULL_1                       (7'b1001001),
        .TX_MARGIN_FULL_2                       (7'b1000101),
        .TX_MARGIN_FULL_3                       (7'b1000010),
        .TX_MARGIN_FULL_4                       (7'b1000000),
        .TX_MARGIN_LOW_0                        (7'b1000110),
        .TX_MARGIN_LOW_1                        (7'b1000100),
        .TX_MARGIN_LOW_2                        (7'b1000010),
        .TX_MARGIN_LOW_3                        (7'b1000000),
        .TX_MARGIN_LOW_4                        (7'b1000000),
        //-----------------------TX Gearbox Attributes--------------------------
        .TXGEARBOX_EN                           ("TRUE"),
        //-----------------------TX Initialization and Reset Attributes--------------------------
        .TXPCSRESET_TIME                        (5'b00001),
        .TXPMARESET_TIME                        (5'b00001),
        //-----------------------TX Receiver Detection Attributes--------------------------
        .TX_RXDETECT_CFG                        (14'h1832),
        .TX_RXDETECT_REF                        (3'b100),
        //--------------------------CPLL Attributes----------------------------
        .CPLL_CFG                               (24'hBC07DC),
        .CPLL_FBDIV                             (4),
        .CPLL_FBDIV_45                          (5),
        .CPLL_INIT_CFG                          (24'h00001E),
        .CPLL_LOCK_CFG                          (16'h01E8),
        .CPLL_REFCLK_DIV                        (1),
        .RXOUT_DIV                              (1),
        .TXOUT_DIV                              (1),
        .SATA_CPLL_CFG                          ("VCO_3000MHZ"),
        //------------RX Initialization and Reset Attributes-------------
        .RXDFELPMRESET_TIME                     (7'b0001111),
        //------------RX Equalizer Attributes-------------
        .RXLPM_HF_CFG                           (14'b00000011110000),
        .RXLPM_LF_CFG                           (14'b00000011110000),
        .RX_DFE_GAIN_CFG                        (23'h020FEA),
        .RX_DFE_H2_CFG                          (12'b000000000000),
        .RX_DFE_H3_CFG                          (12'b000001000000),
        .RX_DFE_H4_CFG                          (11'b00011110000),
        .RX_DFE_H5_CFG                          (11'b00011100000),
        .RX_DFE_KL_CFG                          (13'b0000011111110),
        .RX_DFE_LPM_CFG                         (16'h0954),
        .RX_DFE_LPM_HOLD_DURING_EIDLE           (1'b0),
        .RX_DFE_UT_CFG                          (17'b10001111000000000),
        .RX_DFE_VP_CFG                          (17'b00011111100000011),
        //-----------------------Power-Down Attributes-------------------------
        .RX_CLKMUX_PD                           (1'b1),
        .TX_CLKMUX_PD                           (1'b1),
        //-----------------------FPGA RX Interface Attribute-------------------------
        .RX_INT_DATAWIDTH                       (1),
        //-----------------------FPGA TX Interface Attribute-------------------------
        .TX_INT_DATAWIDTH                       (1),
        //----------------TX Configurable Driver Attributes---------------
        .TX_QPI_STATUS_EN                       (1'b0),
        //-----------------------RX Equalizer Attributes--------------------------
        .RX_DFE_KL_CFG2                         (32'h301148AC),
        .RX_DFE_XYD_CFG                         (13'b0000000000000),
        //-----------------------TX Configurable Driver Attributes--------------------------
        .TX_PREDRIVER_MODE                      (1'b0)
    )
    gt_ch_inst
    (
        //------------------------------- CPLL Ports -------------------------------
        .CPLLFBCLKLOST                  (),
        .CPLLLOCK                       (),
        .CPLLLOCKDETCLK                 (1'b0),
        .CPLLLOCKEN                     (1'b1),
        .CPLLPD                         (1'b1),
        .CPLLREFCLKLOST                 (),
        .CPLLREFCLKSEL                  (3'b001),
        .CPLLRESET                      (1'b0),
        .GTRSVD                         (16'b0000000000000000),
        .PCSRSVDIN                      (16'b0000000000000000),
        .PCSRSVDIN2                     (5'b00000),
        .PMARSVDIN                      (5'b00000),
        .PMARSVDIN2                     (5'b00000),
        .TSTIN                          (20'b11111111111111111111),
        .TSTOUT                         (),
        //-------------------------------- Channel ---------------------------------
        .CLKRSVD                        (4'd0),
        //------------------------ Channel - Clocking Ports ------------------------
        .GTGREFCLK                      (1'b0),
        .GTNORTHREFCLK0                 (1'b0),
        .GTNORTHREFCLK1                 (1'b0),
        .GTREFCLK0                      (1'b0),
        .GTREFCLK1                      (1'b0),
        .GTSOUTHREFCLK0                 (1'b0),
        .GTSOUTHREFCLK1                 (1'b0),
        //-------------------------- Channel - DRP Ports  --------------------------
        .DRPADDR                        (gt_drp_addr),
        .DRPCLK                         (xcvr_ctrl_clk),
        .DRPDI                          (gt_drp_di),
        .DRPDO                          (gt_drp_do),
        .DRPEN                          (gt_drp_en),
        .DRPRDY                         (gt_drp_rdy),
        .DRPWE                          (gt_drp_we),
        //----------------------------- Clocking Ports -----------------------------
        .GTREFCLKMONITOR                (),
        .QPLLCLK                        (xcvr_qpllclk_in),
        .QPLLREFCLK                     (xcvr_qpllrefclk_in),
        .RXSYSCLKSEL                    (2'b11),
        .TXSYSCLKSEL                    (2'b11),
        //------------------------- Digital Monitor Ports --------------------------
        .DMONITOROUT                    (),
        //--------------- FPGA TX Interface Datapath Configuration  ----------------
        .TX8B10BEN                      (1'b0),
        //----------------------------- Loopback Ports -----------------------------
        .LOOPBACK                       (3'b000),
        //--------------------------- PCI Express Ports ----------------------------
        .PHYSTATUS                      (),
        .RXRATE                         (3'd0),
        .RXVALID                        (),
        //---------------------------- Power-Down Ports ----------------------------
        .RXPD                           (gt_rx_pd ? 2'b11 : 2'b00),
        .TXPD                           (gt_tx_pd ? 2'b11 : 2'b00),
        //------------------------ RX 8B/10B Decoder Ports -------------------------
        .SETERRSTATUS                   (1'b0),
        //------------------- RX Initialization and Reset Ports --------------------
        .EYESCANRESET                   (gt_rx_eyescan_reset),
        .RXUSERRDY                      (gt_rx_userrdy),
        //------------------------ RX Margin Analysis Ports ------------------------
        .EYESCANDATAERROR               (),
        .EYESCANMODE                    (1'b0),
        .EYESCANTRIGGER                 (1'b0),
        //----------------------- Receive Ports - CDR Ports ------------------------
        .RXCDRFREQRESET                 (1'b0),
        .RXCDRHOLD                      (1'b0),
        .RXCDRLOCK                      (gt_rx_cdr_lock),
        .RXCDROVRDEN                    (1'b0),
        .RXCDRRESET                     (1'b0),
        .RXCDRRESETRSV                  (1'b0),
        //----------------- Receive Ports - Clock Correction Ports -----------------
        .RXCLKCORCNT                    (),
        //-------- Receive Ports - FPGA RX Interface Datapath Configuration --------
        .RX8B10BEN                      (1'b0),
        //---------------- Receive Ports - FPGA RX Interface Ports -----------------
        .RXUSRCLK                       (gt_rxusrclk),
        .RXUSRCLK2                      (gt_rxusrclk2),
        //---------------- Receive Ports - FPGA RX interface Ports -----------------
        .RXDATA                         (gt_rxdata),
        //----------------- Receive Ports - Pattern Checker Ports ------------------
        .RXPRBSERR                      (),
        .RXPRBSSEL                      (3'd0),
        //----------------- Receive Ports - Pattern Checker ports ------------------
        .RXPRBSCNTRESET                 (1'b0),
        //------------------ Receive Ports - RX  Equalizer Ports -------------------
        .RXDFEXYDEN                     (1'b1),
        .RXDFEXYDHOLD                   (1'b0),
        .RXDFEXYDOVRDEN                 (1'b0),
        //---------------- Receive Ports - RX 8B/10B Decoder Ports -----------------
        .RXDISPERR                      (),
        .RXNOTINTABLE                   (),
        //---------------------- Receive Ports - RX AFE Ports ----------------------
        .GTXRXN                         (xcvr_rxn),
        .GTXRXP                         (xcvr_rxp),
        //----------------- Receive Ports - RX Buffer Bypass Ports -----------------
        .RXBUFRESET                     (1'b0),
        .RXBUFSTATUS                    (),
        .RXDDIEN                        (1'b0),
        .RXDLYBYPASS                    (1'b1),
        .RXDLYEN                        (1'b0),
        .RXDLYOVRDEN                    (1'b0),
        .RXDLYSRESET                    (1'b0),
        .RXDLYSRESETDONE                (),
        .RXPHALIGN                      (1'b0),
        .RXPHALIGNDONE                  (),
        .RXPHALIGNEN                    (1'b0),
        .RXPHDLYPD                      (1'b0),
        .RXPHDLYRESET                   (1'b0),
        .RXPHMONITOR                    (),
        .RXPHOVRDEN                     (1'b0),
        .RXPHSLIPMONITOR                (),
        .RXSTATUS                       (),
        //------------ Receive Ports - RX Byte and Word Alignment Ports ------------
        .RXBYTEISALIGNED                (),
        .RXBYTEREALIGN                  (),
        .RXCOMMADET                     (),
        .RXCOMMADETEN                   (1'b0),
        .RXMCOMMAALIGNEN                (1'b0),
        .RXPCOMMAALIGNEN                (1'b0),
        //---------------- Receive Ports - RX Channel Bonding Ports ----------------
        .RXCHANBONDSEQ                  (),
        .RXCHBONDEN                     (1'b0),
        .RXCHBONDLEVEL                  (3'd0),
        .RXCHBONDMASTER                 (1'b0),
        .RXCHBONDO                      (),
        .RXCHBONDSLAVE                  (1'b0),
        //--------------- Receive Ports - RX Channel Bonding Ports  ----------------
        .RXCHANISALIGNED                (),
        .RXCHANREALIGN                  (),
        //------------------ Receive Ports - RX Equailizer Ports -------------------
        .RXLPMHFHOLD                    (1'b0),
        .RXLPMHFOVRDEN                  (1'b0),
        .RXLPMLFHOLD                    (1'b0),
        //------------------- Receive Ports - RX Equalizer Ports -------------------
        .RXDFEAGCHOLD                   (1'b0),
        .RXDFEAGCOVRDEN                 (1'b0),
        .RXDFECM1EN                     (1'b0),
        .RXDFELFHOLD                    (1'b0),
        .RXDFELFOVRDEN                  (1'b1),
        .RXDFELPMRESET                  (gt_rx_dfe_lpm_reset),
        .RXDFETAP2HOLD                  (1'b0),
        .RXDFETAP2OVRDEN                (1'b0),
        .RXDFETAP3HOLD                  (1'b0),
        .RXDFETAP3OVRDEN                (1'b0),
        .RXDFETAP4HOLD                  (1'b0),
        .RXDFETAP4OVRDEN                (1'b0),
        .RXDFETAP5HOLD                  (1'b0),
        .RXDFETAP5OVRDEN                (1'b0),
        .RXDFEUTHOLD                    (1'b0),
        .RXDFEUTOVRDEN                  (1'b0),
        .RXDFEVPHOLD                    (1'b0),
        .RXDFEVPOVRDEN                  (1'b0),
        .RXDFEVSEN                      (1'b0),
        .RXLPMLFKLOVRDEN                (1'b0),
        .RXMONITOROUT                   (),
        .RXMONITORSEL                   ('0),
        .RXOSHOLD                       (1'b0),
        .RXOSOVRDEN                     (1'b0),
        //---------- Receive Ports - RX Fabric ClocK Output Control Ports ----------
        .RXRATEDONE                     (),
        //------------- Receive Ports - RX Fabric Output Control Ports -------------
        .RXOUTCLK                       (gt_rxoutclk),
        .RXOUTCLKFABRIC                 (),
        .RXOUTCLKPCS                    (),
        .RXOUTCLKSEL                    (3'b010),
        //-------------------- Receive Ports - RX Gearbox Ports --------------------
        .RXDATAVALID                    (gt_rxdatavalid),
        .RXHEADER                       (gt_rxheader),
        .RXHEADERVALID                  (gt_rxheadervalid),
        .RXSTARTOFSEQ                   (),
        //------------------- Receive Ports - RX Gearbox Ports  --------------------
        .RXGEARBOXSLIP                  (gt_rxgearboxslip),
        //----------- Receive Ports - RX Initialization and Reset Ports ------------
        .GTRXRESET                      (gt_rx_reset),
        .RXOOBRESET                     (1'b0),
        .RXPCSRESET                     (gt_rx_pcs_reset),
        .RXPMARESET                     (gt_rx_pma_reset),
        .RXRESETDONE                    (gt_rx_reset_done),
        //---------------- Receive Ports - RX Margin Analysis ports ----------------
        .RXLPMEN                        (gt_rx_lpm_en),
        //----------------- Receive Ports - RX OOB Signaling ports -----------------
        .RXCOMSASDET                    (),
        .RXCOMWAKEDET                   (),
        //---------------- Receive Ports - RX OOB Signaling ports  -----------------
        .RXCOMINITDET                   (),
        //---------------- Receive Ports - RX OOB signalling Ports -----------------
        .RXELECIDLE                     (),
        .RXELECIDLEMODE                 (2'b11),
        //--------------- Receive Ports - RX Polarity Control Ports ----------------
        .RXPOLARITY                     (ctrl_rxpolarity),
        //-------------------- Receive Ports - RX gearbox ports --------------------
        .RXSLIDE                        (1'b0),
        //----------------- Receive Ports - RX8B/10B Decoder Ports -----------------
        .RXCHARISCOMMA                  (),
        .RXCHARISK                      (),
        //---------------- Receive Ports - Rx Channel Bonding Ports ----------------
        .RXCHBONDI                      (5'b00000),
        //------------------------------ Rx AFE Ports ------------------------------
        .RXQPIEN                        (1'b0),
        .RXQPISENN                      (),
        .RXQPISENP                      (),
        //------------------------- TX Buffer Bypass Ports -------------------------
        .TXPHDLYTSTCLK                  (1'b0),
        //---------------------- TX Configurable Driver Ports ----------------------
        .TXPOSTCURSOR                   (ctrl_txpostcursor),
        .TXPOSTCURSORINV                (1'b0),
        .TXPRECURSOR                    (ctrl_txprecursor),
        .TXPRECURSORINV                 (1'b0),
        .TXQPIBIASEN                    (1'b0),
        .TXQPISTRONGPDOWN               (1'b0),
        .TXQPIWEAKPUP                   (1'b0),
        //------------------- TX Initialization and Reset Ports --------------------
        .CFGRESET                       (1'b0),
        .GTTXRESET                      (gt_tx_reset),
        .PCSRSVDOUT                     (),
        .TXUSERRDY                      (gt_tx_userrdy),
        //-------------------- Transceiver Reset Mode Operation --------------------
        .GTRESETSEL                     (1'b0),
        .RESETOVRD                      (1'b0),
        //-------------- Transmit Ports - 8b10b Encoder Control Ports --------------
        .TXCHARDISPMODE                 (8'd0),
        .TXCHARDISPVAL                  (8'd0),
        //---------------- Transmit Ports - FPGA TX Interface Ports ----------------
        .TXUSRCLK                       (gt_txusrclk),
        .TXUSRCLK2                      (gt_txusrclk2),
        //------------------- Transmit Ports - PCI Express Ports -------------------
        .TXELECIDLE                     (ctrl_txelecidle),
        .TXMARGIN                       (3'd0),
        .TXRATE                         (3'd0),
        .TXSWING                        (1'b0),
        //---------------- Transmit Ports - Pattern Generator Ports ----------------
        .TXPRBSFORCEERR                 (1'b0),
        //---------------- Transmit Ports - TX Buffer Bypass Ports -----------------
        .TXDLYBYPASS                    (1'b1),
        .TXDLYEN                        (1'b0),
        .TXDLYHOLD                      (1'b0),
        .TXDLYOVRDEN                    (1'b0),
        .TXDLYSRESET                    (1'b0),
        .TXDLYSRESETDONE                (),
        .TXDLYUPDOWN                    (1'b0),
        .TXPHALIGN                      (1'b0),
        .TXPHALIGNDONE                  (),
        .TXPHALIGNEN                    (1'b0),
        .TXPHDLYPD                      (1'b0),
        .TXPHDLYRESET                   (1'b0),
        .TXPHINIT                       (1'b0),
        .TXPHINITDONE                   (),
        .TXPHOVRDEN                     (1'b0),
        //-------------------- Transmit Ports - TX Buffer Ports --------------------
        .TXBUFSTATUS                    (),
        //------------- Transmit Ports - TX Configurable Driver Ports --------------
        .TXBUFDIFFCTRL                  (3'b100),
        .TXDEEMPH                       (1'b0),
        .TXDIFFCTRL                     (ctrl_txdiffctrl[3:0]),
        .TXDIFFPD                       (1'b0),
        .TXINHIBIT                      (ctrl_txinhibit),
        .TXMAINCURSOR                   (ctrl_txmaincursor),
        .TXPISOPD                       (1'b0),
        //---------------- Transmit Ports - TX Data Path interface -----------------
        .TXDATA                         (gt_txdata),
        //-------------- Transmit Ports - TX Driver and OOB signaling --------------
        .GTXTXN                         (xcvr_txn),
        .GTXTXP                         (xcvr_txp),
        //--------- Transmit Ports - TX Fabric Clock Output Control Ports ----------
        .TXOUTCLK                       (gt_txoutclk),
        .TXOUTCLKFABRIC                 (),
        .TXOUTCLKPCS                    (),
        .TXOUTCLKSEL                    (3'b010),
        .TXRATEDONE                     (),
        //------------------- Transmit Ports - TX Gearbox Ports --------------------
        .TXCHARISK                      (8'd0),
        .TXGEARBOXREADY                 (),
        .TXHEADER                       (gt_txheader),
        .TXSEQUENCE                     (gt_txsequence),
        .TXSTARTSEQ                     (1'b0),
        //----------- Transmit Ports - TX Initialization and Reset Ports -----------
        .TXPCSRESET                     (gt_tx_pcs_reset),
        .TXPMARESET                     (gt_tx_pma_reset),
        .TXRESETDONE                    (gt_tx_reset_done),
        //---------------- Transmit Ports - TX OOB signalling Ports ----------------
        .TXCOMFINISH                    (),
        .TXCOMINIT                      (1'b0),
        .TXCOMSAS                       (1'b0),
        .TXCOMWAKE                      (1'b0),
        .TXPDELECIDLEMODE               (1'b0),
        //--------------- Transmit Ports - TX Polarity Control Ports ---------------
        .TXPOLARITY                     (ctrl_txpolarity),
        //------------- Transmit Ports - TX Receiver Detection Ports  --------------
        .TXDETECTRX                     (1'b0),
        //---------------- Transmit Ports - TX8b/10b Encoder Ports -----------------
        .TX8B10BBYPASS                  (8'd0),
        //---------------- Transmit Ports - pattern Generator Ports ----------------
        .TXPRBSSEL                      (3'd0),
        //--------------------- Tx Configurable Driver  Ports ----------------------
        .TXQPISENN                      (),
        .TXQPISENP                      ()
    );

    assign gt_tx_pma_reset_done = 1'b1;
    assign gt_rx_pma_reset_done = 1'b1;

end else begin

    $fatal(0, "Error: invalid configuration (%m)");

end

endmodule

`resetall
