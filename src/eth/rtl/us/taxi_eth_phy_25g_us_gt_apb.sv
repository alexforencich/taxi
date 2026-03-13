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
 * Transceiver wrapper APB interface for UltraScale/UltraScale+
 */
module taxi_eth_phy_25g_us_gt_apb #
(
    // parameter logic SIM = 1'b0,
    // parameter string VENDOR = "XILINX",
    // parameter string FAMILY = "virtexuplus",

    parameter logic HAS_COMMON = 1'b1,

    // // GT type
    // parameter string GT_TYPE = "GTY",

    // PLL parameters
    parameter logic QPLL0_PD = 1'b0,
    parameter logic QPLL1_PD = 1'b1,
    // parameter logic QPLL0_EXT_CTRL = 1'b0,
    // parameter logic QPLL1_EXT_CTRL = 1'b0,

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
    parameter logic GT_RX_LPM_EN = 1'b0,
    parameter logic GT_RX_POLARITY = 1'b0

    // // MAC/PHY parameters
    // parameter DATA_W = 64
)
(
    input  wire logic               clk,
    input  wire logic               rst,

    /*
     * Transceiver clocks
     */
    input  wire logic               gt_txusrclk2,
    input  wire logic               gt_rxusrclk2,

    /*
     * Transceiver control
     */
    taxi_apb_if.slv                 s_apb_ctrl,

    /*
     * DRP (channel)
     */
    output wire logic [10:0]        gt_drp_addr,
    output wire logic [15:0]        gt_drp_di,
    output wire logic               gt_drp_en,
    output wire logic               gt_drp_we,
    input  wire logic [15:0]        gt_drp_do = '0,
    input  wire logic               gt_drp_rdy = 1'b1,

    /*
     * DRP (common)
     */
    output wire logic [10:0]        com_drp_addr,
    output wire logic [15:0]        com_drp_di,
    output wire logic               com_drp_en,
    output wire logic               com_drp_we,
    input  wire logic [15:0]        com_drp_do = '0,
    input  wire logic               com_drp_rdy = 1'b1,

    /*
     * Control and status signals
     */
    output wire logic               qpll0_reset,
    output wire logic               qpll0_pd,
    input  wire logic               qpll0_lock,
    output wire logic               qpll1_reset,
    output wire logic               qpll1_pd,
    input  wire logic               qpll1_lock,

    output wire logic [2:0]         gt_loopback,

    output wire logic               gt_tx_reset,
    output wire logic               gt_tx_pma_reset,
    output wire logic               gt_tx_pcs_reset,
    input  wire logic               gt_tx_reset_done,
    input  wire logic               gt_tx_pma_reset_done,
    input  wire logic               gt_tx_prgdiv_reset_done,
    output wire logic               gt_tx_pd,
    output wire logic               gt_tx_qpll_sel,
    output wire logic               gt_rx_reset,
    output wire logic               gt_rx_pma_reset,
    output wire logic               gt_rx_pcs_reset,
    output wire logic               gt_rx_dfe_lpm_reset,
    output wire logic               gt_eyescan_reset,
    input  wire logic               gt_rx_reset_done,
    input  wire logic               gt_rx_pma_reset_done,
    input  wire logic               gt_rx_prgdiv_reset_done,
    output wire logic               gt_rx_pd,
    output wire logic               gt_rx_qpll_sel,

    output wire logic               gt_rxcdrhold,
    output wire logic               gt_rxlpmen,

    output wire logic [3:0]         gt_txprbssel,
    output wire logic               gt_txprbsforceerr,
    output wire logic               gt_txpolarity,
    output wire logic               gt_txelecidle,
    output wire logic               gt_txinhibit,
    output wire logic [4:0]         gt_txdiffctrl,
    output wire logic [6:0]         gt_txmaincursor,
    output wire logic [4:0]         gt_txpostcursor,
    output wire logic [4:0]         gt_txprecursor,

    output wire logic               gt_rxpolarity,
    output wire logic               gt_rxprbscntreset,
    output wire logic [3:0]         gt_rxprbssel,

    input  wire logic               gt_rxprbserr,

    input  wire logic [15:0]        gt_dmonitorout,

    output wire logic               phy_rx_reset_req_en
);

// check configuration
if (s_apb_ctrl.DATA_W != 16)
    $fatal(0, "Error: APB interface DATA_W must be 16 (instance %m)");

if (s_apb_ctrl.ADDR_W < 16)
    $fatal(0, "Error: APB interface ADDR_W must be at least 16 (instance %m)");

logic act_reg = 1'b0;

logic s_apb_ctrl_pready_reg = 1'b0;
logic [15:0] s_apb_ctrl_prdata_reg = '0;
logic s_apb_ctrl_pslverr_reg = 1'b0;

logic [10:0] drp_addr_reg = '0;
logic [15:0] drp_di_reg = '0;
logic gt_drp_en_reg = 1'b0;
logic gt_drp_we_reg = 1'b0;
logic com_drp_en_reg = 1'b0;
logic com_drp_we_reg = 1'b0;

logic qpll0_reset_reg = 1'b0;
logic qpll0_pd_reg = QPLL0_PD;
logic qpll1_reset_reg = 1'b0;
logic qpll1_pd_reg = QPLL1_PD;

logic [2:0] gt_loopback_reg = 3'b000;

logic gt_tx_reset_reg = 1'b0;
logic gt_tx_pma_reset_reg = 1'b0;
logic gt_tx_pcs_reset_reg = 1'b0;
logic gt_tx_pd_reg = GT_TX_PD;
logic gt_tx_qpll_sel_reg = GT_TX_QPLL_SEL;
logic gt_rx_reset_reg = 1'b0;
logic gt_rx_pma_reset_reg = 1'b0;
logic gt_rx_pcs_reset_reg = 1'b0;
logic gt_rx_dfe_lpm_reset_reg = 1'b0;
logic gt_eyescan_reset_reg = 1'b0;
logic gt_rx_pd_reg = GT_RX_PD;
logic gt_rx_qpll_sel_reg = GT_RX_QPLL_SEL;

logic gt_rxcdrhold_reg = 1'b0;
logic gt_rxlpmen_reg = GT_RX_LPM_EN;

logic [3:0] gt_txprbssel_reg = 4'd0;
logic gt_txprbsforceerr_reg = 1'b0;
logic gt_txpolarity_reg = GT_TX_POLARITY;
logic gt_txelecidle_reg = GT_TX_ELECIDLE;
logic gt_txinhibit_reg = GT_TX_INHIBIT;
logic [4:0] gt_txdiffctrl_reg = GT_TX_DIFFCTRL;
logic [6:0] gt_txmaincursor_reg = GT_TX_MAINCURSOR;
logic [4:0] gt_txpostcursor_reg = GT_TX_POSTCURSOR;
logic [4:0] gt_txprecursor_reg = GT_TX_PRECURSOR;

logic gt_rxpolarity_reg = GT_RX_POLARITY;
logic gt_rxprbscntreset_reg = 1'b0;
logic [3:0] gt_rxprbssel_reg = 4'd0;

logic gt_rxprbserr_reg = 1'b0;

logic phy_rx_reset_req_en_reg = 1'b1;

assign s_apb_ctrl.pready = s_apb_ctrl_pready_reg;
assign s_apb_ctrl.prdata = s_apb_ctrl_prdata_reg;
assign s_apb_ctrl.pslverr = s_apb_ctrl_pslverr_reg;
assign s_apb_ctrl.pruser = '0;
assign s_apb_ctrl.pbuser = '0;

assign gt_drp_addr = drp_addr_reg;
assign gt_drp_di = drp_di_reg;
assign gt_drp_en = gt_drp_en_reg;
assign gt_drp_we = gt_drp_we_reg;

assign com_drp_addr = drp_addr_reg;
assign com_drp_di = drp_di_reg;
assign com_drp_en = com_drp_en_reg;
assign com_drp_we = com_drp_we_reg;

assign qpll0_reset = qpll0_reset_reg;
assign qpll0_pd = qpll0_pd_reg;
assign qpll1_reset = qpll1_reset_reg;
assign qpll1_pd = qpll1_pd_reg;

assign gt_loopback = gt_loopback_reg;

assign gt_tx_reset = gt_tx_reset_reg;
assign gt_tx_pma_reset = gt_tx_pma_reset_reg;
assign gt_tx_pcs_reset = gt_tx_pcs_reset_reg;
assign gt_tx_pd = gt_tx_pd_reg;
assign gt_tx_qpll_sel = gt_tx_qpll_sel_reg;
assign gt_rx_reset = gt_rx_reset_reg;
assign gt_rx_pma_reset = gt_rx_pma_reset_reg;
assign gt_rx_pcs_reset = gt_rx_pcs_reset_reg;
assign gt_rx_dfe_lpm_reset = gt_rx_dfe_lpm_reset_reg;
assign gt_eyescan_reset = gt_eyescan_reset_reg;
assign gt_rx_pd = gt_rx_pd_reg;
assign gt_rx_qpll_sel = gt_rx_qpll_sel_reg;

assign gt_rxcdrhold = gt_rxcdrhold_reg;
assign gt_rxlpmen = gt_rxlpmen_reg;

assign gt_txprbsforceerr = gt_txprbsforceerr_reg;
assign gt_txdiffctrl = gt_txdiffctrl_reg;
assign gt_txmaincursor = gt_txmaincursor_reg;
assign gt_txpostcursor = gt_txpostcursor_reg;
assign gt_txprecursor = gt_txprecursor_reg;

taxi_sync_signal #(
    .WIDTH(3+4),
    .N(2)
)
tx_ctrl_sync_inst (
    .clk(gt_txusrclk2),
    .in({gt_txpolarity_reg, gt_txelecidle_reg, gt_txinhibit_reg, gt_txprbssel_reg}),
    .out({gt_txpolarity, gt_txelecidle, gt_txinhibit, gt_txprbssel})
);

taxi_sync_signal #(
    .WIDTH(1+4),
    .N(2)
)
rx_ctrl_sync_inst (
    .clk(gt_rxusrclk2),
    .in({gt_rxpolarity_reg, gt_rxprbssel_reg}),
    .out({gt_rxpolarity, gt_rxprbssel})
);

assign gt_rxprbscntreset = gt_rxprbscntreset_reg;

assign phy_rx_reset_req_en = phy_rx_reset_req_en_reg;

always_ff @(posedge clk) begin
    act_reg <= 1'b0;

    s_apb_ctrl_pready_reg <= 1'b0;
    s_apb_ctrl_prdata_reg <= '0;
    s_apb_ctrl_pslverr_reg <= 1'b0;

    drp_addr_reg <= s_apb_ctrl.paddr[1 +: 11];
    drp_di_reg <= s_apb_ctrl.pwdata;

    gt_drp_en_reg <= 1'b0;
    gt_drp_we_reg <= 1'b0;
    com_drp_en_reg <= 1'b0;
    com_drp_we_reg <= 1'b0;

    if (s_apb_ctrl.psel && !s_apb_ctrl_pready_reg) begin
        act_reg <= 1'b1;

        case (s_apb_ctrl.paddr[15:14])
        2'b00: begin
            // registers
            s_apb_ctrl_pready_reg <= 1'b1;

            if (HAS_COMMON) begin
                case ({s_apb_ctrl.paddr[13:1], 1'b0})
                14'd3000: begin
                    // QPLL0
                    s_apb_ctrl_prdata_reg[0] <= qpll0_pd_reg;
                    s_apb_ctrl_prdata_reg[1] <= qpll0_reset_reg;
                    s_apb_ctrl_prdata_reg[8] <= qpll0_lock;
                    if (s_apb_ctrl.pwrite) begin
                        qpll0_pd_reg <= s_apb_ctrl.pwdata[0];
                        qpll0_reset_reg <= s_apb_ctrl.pwdata[1];
                    end
                end
                14'd3100: begin
                    // QPLL1
                    s_apb_ctrl_prdata_reg[0] <= qpll1_pd_reg;
                    s_apb_ctrl_prdata_reg[1] <= qpll1_reset_reg;
                    s_apb_ctrl_prdata_reg[8] <= qpll1_lock;
                    if (s_apb_ctrl.pwrite) begin
                        qpll1_pd_reg <= s_apb_ctrl.pwdata[0];
                        qpll1_reset_reg <= s_apb_ctrl.pwdata[1];
                    end
                end
                default: begin
                    // no op
                end
                endcase
            end

            case ({s_apb_ctrl.paddr[13:1], 1'b0})
            14'h1000: begin
                s_apb_ctrl_prdata_reg[0] <= gt_tx_reset_reg;
                s_apb_ctrl_prdata_reg[1] <= gt_tx_pma_reset_reg;
                s_apb_ctrl_prdata_reg[2] <= gt_tx_pcs_reset_reg;
                // s_apb_ctrl_prdata_reg[8] <= tx_reset_done_reg;
                s_apb_ctrl_prdata_reg[9] <= gt_tx_reset_done;
                s_apb_ctrl_prdata_reg[10] <= gt_tx_pma_reset_done;
                s_apb_ctrl_prdata_reg[11] <= gt_tx_prgdiv_reset_done;
                // s_apb_ctrl_prdata_reg[12] <= gt_userclk_tx_active;
                if (s_apb_ctrl.pwrite) begin
                    gt_tx_reset_reg <= s_apb_ctrl.pwdata[0];
                    gt_tx_pma_reset_reg <= s_apb_ctrl.pwdata[1];
                    gt_tx_pcs_reset_reg <= s_apb_ctrl.pwdata[2];
                end
            end
            14'h1002: begin
                s_apb_ctrl_prdata_reg[0] <= gt_tx_pd_reg;
                s_apb_ctrl_prdata_reg[1] <= gt_tx_qpll_sel_reg;
                if (s_apb_ctrl.pwrite) begin
                    gt_tx_pd_reg <= s_apb_ctrl.pwdata[0];
                    gt_tx_qpll_sel_reg <= s_apb_ctrl.pwdata[1];
                end
            end
            14'h1010: begin
                s_apb_ctrl_prdata_reg[0] <= gt_txpolarity_reg;
                s_apb_ctrl_prdata_reg[1] <= gt_txelecidle_reg;
                s_apb_ctrl_prdata_reg[2] <= gt_txinhibit_reg;
                if (s_apb_ctrl.pwrite) begin
                    gt_txpolarity_reg <= s_apb_ctrl.pwdata[0];
                    gt_txelecidle_reg <= s_apb_ctrl.pwdata[1];
                    gt_txinhibit_reg <= s_apb_ctrl.pwdata[2];
                end
            end
            14'h1012: begin
                s_apb_ctrl_prdata_reg[4:0] <= gt_txdiffctrl_reg;
                if (s_apb_ctrl.pwrite) begin
                    gt_txdiffctrl_reg <= s_apb_ctrl.pwdata[4:0];
                end
            end
            14'h1014: begin
                s_apb_ctrl_prdata_reg[6:0] <= gt_txmaincursor_reg;
                if (s_apb_ctrl.pwrite) begin
                    gt_txmaincursor_reg <= s_apb_ctrl.pwdata[6:0];
                end
            end
            14'h1016: begin
                s_apb_ctrl_prdata_reg[4:0] <= gt_txprecursor_reg;
                if (s_apb_ctrl.pwrite) begin
                    gt_txprecursor_reg <= s_apb_ctrl.pwdata[4:0];
                end
            end
            14'h1018: begin
                s_apb_ctrl_prdata_reg[4:0] <= gt_txpostcursor_reg;
                if (s_apb_ctrl.pwrite) begin
                    gt_txpostcursor_reg <= s_apb_ctrl.pwdata[4:0];
                end
            end
            14'h1040: begin
                s_apb_ctrl_prdata_reg[3:0] <= gt_txprbssel_reg;
                if (s_apb_ctrl.pwrite) begin
                    gt_txprbssel_reg <= s_apb_ctrl.pwdata[3:0];
                end
            end
            14'h1042: begin
                if (s_apb_ctrl.pwrite) begin
                    // gt_txprbsforceerr_reg <= gt_txprbsforceerr_reg ^ s_apb_ctrl.pwdata[0];
                end
            end
            // RX
            14'h2000: begin
                s_apb_ctrl_prdata_reg[0] <= gt_rx_reset_reg;
                s_apb_ctrl_prdata_reg[1] <= gt_rx_pma_reset_reg;
                s_apb_ctrl_prdata_reg[2] <= gt_rx_pcs_reset_reg;
                s_apb_ctrl_prdata_reg[3] <= gt_rx_dfe_lpm_reset_reg;
                s_apb_ctrl_prdata_reg[4] <= gt_eyescan_reset_reg;
                // s_apb_ctrl_prdata_reg[8] <= rx_reset_done_reg;
                s_apb_ctrl_prdata_reg[9] <= gt_rx_reset_done;
                s_apb_ctrl_prdata_reg[10] <= gt_rx_pma_reset_done;
                s_apb_ctrl_prdata_reg[11] <= gt_rx_prgdiv_reset_done;
                // s_apb_ctrl_prdata_reg[12] <= gt_userclk_rx_active;
                if (s_apb_ctrl.pwrite) begin
                    gt_rx_reset_reg <= s_apb_ctrl.pwdata[0];
                    gt_rx_pma_reset_reg <= s_apb_ctrl.pwdata[1];
                    gt_rx_pcs_reset_reg <= s_apb_ctrl.pwdata[2];
                    gt_rx_dfe_lpm_reset_reg <= s_apb_ctrl.pwdata[3];
                    gt_eyescan_reset_reg <= s_apb_ctrl.pwdata[4];
                end
            end
            14'h2002: begin
                s_apb_ctrl_prdata_reg[0] <= gt_rx_pd_reg;
                s_apb_ctrl_prdata_reg[1] <= gt_rx_qpll_sel_reg;
                if (s_apb_ctrl.pwrite) begin
                    gt_rx_pd_reg <= s_apb_ctrl.pwdata[0];
                    gt_rx_qpll_sel_reg <= s_apb_ctrl.pwdata[1];
                end
            end
            14'h2004: begin
                s_apb_ctrl_prdata_reg[2:0] <= gt_loopback_reg;
                if (s_apb_ctrl.pwrite) begin
                    gt_loopback_reg <= s_apb_ctrl.pwdata[2:0];
                end
            end
            14'h2010: begin
                s_apb_ctrl_prdata_reg[0] <= gt_rxpolarity_reg;
                if (s_apb_ctrl.pwrite) begin
                    gt_rxpolarity_reg <= s_apb_ctrl.pwdata[0];
                end
            end
            14'h2020: begin
                s_apb_ctrl_prdata_reg[0] <= gt_rxcdrhold_reg;
                // s_apb_ctrl_prdata_reg[8] <= gt_rxcdrlock;
                if (s_apb_ctrl.pwrite) begin
                    gt_rxcdrhold_reg <= s_apb_ctrl.pwdata[0];
                end
            end
            14'h2024: begin
                s_apb_ctrl_prdata_reg[0] <= gt_rxlpmen_reg;
                if (s_apb_ctrl.pwrite) begin
                    gt_rxlpmen_reg <= s_apb_ctrl.pwdata[0];
                end
            end
            // 14'h2028: s_apb_ctrl_prdata_reg <= gt_dmonitorout_reg;
            14'h2040: begin
                s_apb_ctrl_prdata_reg[3:0] <= gt_rxprbssel_reg;
                if (s_apb_ctrl.pwrite) begin
                    gt_rxprbssel_reg <= s_apb_ctrl.pwdata[3:0];
                end
            end
            14'h2042: begin
                // s_apb_ctrl_prdata_reg[8] <= gt_rxprbslocked;
                s_apb_ctrl_prdata_reg[9] <= gt_rxprbserr_reg;

                if (s_apb_ctrl.pwrite) begin
                    // gt_rxprbscntreset_reg <= gt_rxprbscntreset_reg ^ s_apb_ctrl.pwdata[0];
                end else begin
                    // gt_rxprbserr_reg <= gt_rxprbserr;
                end
            end
            default: begin
                // no op
            end
            endcase

//             // PHY
//             16'h8000: begin
//                 drp_do_reg[0] <= tx_reset_done_reg;
//             end
//             16'h8100: begin
//                 drp_do_reg[0] <= rx_reset_done_reg;
//                 drp_do_reg[8] <= phy_rx_block_lock_sync_2_reg;
//                 drp_do_reg[9] <= phy_rx_high_ber_sync_2_reg;
//                 drp_do_reg[10] <= phy_rx_status_sync_2_reg;
//             end
//             16'h8101: begin
//                 drp_do_reg[0] <= phy_rx_reset_req_en_drp_reg;
//                 drp_do_reg[8] <= phy_rx_reset_req_drp_reg;

//                 phy_rx_reset_req_drp_reg <= phy_rx_reset_req_sync_3_reg ^ phy_rx_reset_req_sync_4_reg;
//             end
        end
        2'b01: begin
            // reserved
            s_apb_ctrl_pready_reg <= 1'b1;
        end
        2'b10: begin
            // GT DRP
            gt_drp_en_reg <= !act_reg;
            gt_drp_we_reg <= s_apb_ctrl.pwrite && !act_reg;

            if (gt_drp_rdy) begin
                s_apb_ctrl_prdata_reg <= gt_drp_do;
                s_apb_ctrl_pready_reg <= 1'b1;
            end
        end
        2'b11: begin
            // common DRP
            com_drp_en_reg <= !act_reg;
            com_drp_we_reg <= s_apb_ctrl.pwrite && !act_reg;

            if (com_drp_rdy) begin
                s_apb_ctrl_prdata_reg <= com_drp_do;
                s_apb_ctrl_pready_reg <= 1'b1;
            end
        end
        endcase
    end

    if (rst) begin
        act_reg <= 1'b0;

        s_apb_ctrl_pready_reg <= 1'b0;

        gt_drp_en_reg <= 1'b0;
        gt_drp_we_reg <= 1'b0;
        com_drp_en_reg <= 1'b0;
        com_drp_we_reg <= 1'b0;

        qpll0_reset_reg <= 1'b0;
        qpll0_pd_reg <= QPLL0_PD;
        qpll1_reset_reg <= 1'b0;
        qpll1_pd_reg <= QPLL1_PD;

        gt_loopback_reg <= 3'b000;

        gt_tx_reset_reg <= 1'b0;
        gt_tx_pma_reset_reg <= 1'b0;
        gt_tx_pcs_reset_reg <= 1'b0;
        gt_tx_pd_reg <= GT_TX_PD;
        gt_tx_qpll_sel_reg <= GT_TX_QPLL_SEL;
        gt_rx_reset_reg <= 1'b0;
        gt_rx_pma_reset_reg <= 1'b0;
        gt_rx_pcs_reset_reg <= 1'b0;
        gt_rx_dfe_lpm_reset_reg <= 1'b0;
        gt_eyescan_reset_reg <= 1'b0;
        gt_rx_pd_reg <= GT_RX_PD;
        gt_rx_qpll_sel_reg <= GT_RX_QPLL_SEL;

        gt_rxcdrhold_reg <= 1'b0;
        gt_rxlpmen_reg <= GT_RX_LPM_EN;

        gt_txprbssel_reg <= 4'd0;
        gt_txprbsforceerr_reg <= 1'b0;
        gt_txpolarity_reg <= GT_TX_POLARITY;
        gt_txelecidle_reg <= GT_TX_ELECIDLE;
        gt_txinhibit_reg <= GT_TX_INHIBIT;
        gt_txdiffctrl_reg <= GT_TX_DIFFCTRL;
        gt_txmaincursor_reg <= GT_TX_MAINCURSOR;
        gt_txpostcursor_reg <= GT_TX_POSTCURSOR;
        gt_txprecursor_reg <= GT_TX_PRECURSOR;

        gt_rxpolarity_reg <= GT_RX_POLARITY;
        gt_rxprbscntreset_reg <= 1'b0;
        gt_rxprbssel_reg <= 4'd0;

        gt_rxprbserr_reg <= 1'b0;

        phy_rx_reset_req_en_reg <= 1'b1;
    end
end

endmodule

`resetall
