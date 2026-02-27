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
 * GT RX reset controller for UltraScale/UltraScale+ GTH/GTY
 */
module taxi_gt_rx_reset #
(
    parameter GT_RX_PD = 1'b0,
    parameter GT_RX_QPLL_SEL = 1'b0,
    parameter GT_RX_LPM_EN = 1'b0,
    parameter CNT_W = 8,
    parameter CDR_CNT_W = 20
)
(
    input  wire logic  clk,
    input  wire logic  rst,

    /*
     * GT
     */
    input  wire logic  gt_rxusrclk2,
    output wire logic  gt_rx_pd_out,
    output wire logic  gt_rx_reset_out,
    input  wire logic  gt_rx_reset_done_in,
    input  wire logic  gt_userclk_rx_active_in,
    output wire logic  gt_rx_pma_reset_out,
    output wire logic  gt_rx_dfe_lpm_reset_out,
    output wire logic  gt_rx_eyescan_reset_out,
    output wire logic  gt_rx_pcs_reset_out,
    input  wire logic  gt_rx_pma_reset_done_in,
    output wire logic  gt_rx_prgdiv_reset_out,
    input  wire logic  gt_rx_prgdiv_reset_done_in,
    output wire logic  gt_rx_qpll_sel_out,
    output wire logic  gt_rx_userrdy_out,
    input  wire logic  gt_rx_cdr_lock_in,
    output wire logic  gt_rx_lpm_en_out,

    /*
     * Control/status
     */
    input  wire logic  qpll0_lock_in,
    input  wire logic  qpll1_lock_in,
    input  wire logic  rx_reset_in = 1'b0,
    output wire logic  rx_reset_done_out,
    input  wire logic  rx_pma_reset_in = 1'b0,
    output wire logic  rx_pma_reset_done_out,
    output wire logic  rx_prgdiv_reset_done_out,
    input  wire logic  rx_pcs_reset_in = 1'b0,
    input  wire logic  rx_dfe_lpm_reset_in = 1'b0,
    input  wire logic  eyescan_reset_in = 1'b0,
    input  wire logic  rx_pd_in = GT_RX_PD,
    input  wire logic  rx_qpll_sel_in = GT_RX_QPLL_SEL,
    input  wire logic  rx_lpm_en_in = GT_RX_LPM_EN
);

logic gt_rx_reset_reg = 1'b1;
logic gt_rx_pma_reset_reg = 1'b0;
logic gt_rx_pcs_reset_reg = 1'b0;
logic gt_rx_dfe_lpm_reset_reg = 1'b0;
logic gt_eyescan_reset_reg = 1'b0;

logic gt_rx_prgdiv_reset_reg = 1'b0;
logic gt_rx_userrdy_reg = 1'b0;

logic gt_rx_pd_reg = GT_RX_PD;

logic gt_rx_qpll_sel_reg = GT_RX_QPLL_SEL;
logic gt_rx_lpm_en_reg = GT_RX_LPM_EN;

wire gt_rx_reset_done_sync;
wire gt_rx_pma_reset_done_sync;
wire gt_rx_prgdiv_reset_done_sync;
wire gt_userclk_rx_active_sync;
wire gt_rx_cdr_lock_sync;

taxi_sync_signal #(
    .WIDTH(5),
    .N(2)
)
gt_status_sync_inst (
    .clk(clk),
    .in({gt_rx_reset_done_in, gt_rx_pma_reset_done_in, gt_rx_prgdiv_reset_done_in, gt_userclk_rx_active_in, gt_rx_cdr_lock_in}),
    .out({gt_rx_reset_done_sync, gt_rx_pma_reset_done_sync, gt_rx_prgdiv_reset_done_sync, gt_userclk_rx_active_sync, gt_rx_cdr_lock_sync})
);

taxi_sync_signal #(
    .WIDTH(1),
    .N(2)
)
gt_ctrl_sync_inst (
    .clk(gt_rxusrclk2),
    .in({gt_rx_pd_reg}),
    .out({gt_rx_pd_out})
);

wire rx_reset_sync;

taxi_sync_reset #(
    .N(4)
)
reset_sync_inst (
    .clk(clk),
    .rst(rx_reset_in),
    .out(rx_reset_sync)
);

typedef enum logic [2:0] {
    STATE_RESET,
    STATE_WAIT_LOCK,
    STATE_WAIT_CDR,
    STATE_WAIT_USRCLK,
    STATE_DONE
} state_t;

state_t state_reg = STATE_RESET, state_next;

logic [CNT_W-1:0] rx_reset_cnt_reg = '0;
logic [CDR_CNT_W-1:0] rx_reset_cdr_cnt_reg = '0;
logic rx_reset_done_reg = 1'b0;

assign rx_reset_done_out = rx_reset_done_reg;

assign gt_rx_reset_out = gt_rx_reset_reg;
assign gt_rx_pma_reset_out = gt_rx_pma_reset_reg;
assign gt_rx_dfe_lpm_reset_out = gt_rx_dfe_lpm_reset_reg;
assign gt_rx_eyescan_reset_out = gt_eyescan_reset_reg;
assign gt_rx_pcs_reset_out = gt_rx_pcs_reset_reg;
assign gt_rx_prgdiv_reset_out = gt_rx_prgdiv_reset_reg;
assign gt_rx_qpll_sel_out = gt_rx_qpll_sel_reg;
assign gt_rx_userrdy_out = gt_rx_userrdy_reg;
assign gt_rx_lpm_en_out = gt_rx_lpm_en_reg;

assign rx_reset_done_out = rx_reset_done_reg;
assign rx_pma_reset_done_out = gt_rx_pma_reset_done_sync;
assign rx_prgdiv_reset_done_out = gt_rx_prgdiv_reset_done_sync;

wire rx_sel_pll_lock = gt_rx_qpll_sel_reg ? qpll1_lock_in : qpll0_lock_in;

always_ff @(posedge clk) begin
    gt_rx_reset_reg <= 1'b1;
    gt_rx_pma_reset_reg <= rx_pma_reset_in;
    gt_rx_pcs_reset_reg <= rx_pcs_reset_in;
    gt_rx_dfe_lpm_reset_reg <= rx_dfe_lpm_reset_in;
    gt_eyescan_reset_reg <= eyescan_reset_in;

    gt_rx_prgdiv_reset_reg <= 1'b1;
    gt_rx_userrdy_reg <= 1'b0;

    state_reg <= STATE_RESET;
    rx_reset_cnt_reg <= '0;
    rx_reset_cdr_cnt_reg <= '0;
    rx_reset_done_reg <= 1'b0;

    case (state_reg)
        STATE_RESET: begin
            gt_rx_reset_reg <= 1'b1;
            gt_rx_prgdiv_reset_reg <= 1'b1;
            gt_rx_userrdy_reg <= 1'b0;

            gt_rx_pd_reg <= rx_pd_in;
            gt_rx_qpll_sel_reg <= rx_qpll_sel_in;

            gt_rx_lpm_en_reg <= rx_lpm_en_in;

            state_reg <= STATE_WAIT_LOCK;
        end
        STATE_WAIT_LOCK: begin
            gt_rx_reset_reg <= 1'b1;
            gt_rx_prgdiv_reset_reg <= 1'b1;
            gt_rx_userrdy_reg <= 1'b0;

            state_reg <= STATE_WAIT_LOCK;
            if (rx_sel_pll_lock) begin
                // QPLL locked
                rx_reset_cnt_reg <= rx_reset_cnt_reg + 1;
                if (&rx_reset_cnt_reg) begin
                    state_reg <= STATE_WAIT_CDR;
                end
            end
        end
        STATE_WAIT_CDR: begin
            gt_rx_reset_reg <= 1'b0;
            gt_rx_prgdiv_reset_reg <= 1'b1;
            gt_rx_userrdy_reg <= 1'b0;

            state_reg <= STATE_WAIT_CDR;

            rx_reset_cdr_cnt_reg <= rx_reset_cdr_cnt_reg + 1;
            if (&rx_reset_cdr_cnt_reg) begin
                state_reg <= STATE_WAIT_USRCLK;
            end

            if (gt_rx_cdr_lock_sync) begin
                // CDR locked
                rx_reset_cnt_reg <= rx_reset_cnt_reg + 1;
                if (&rx_reset_cnt_reg) begin
                    state_reg <= STATE_WAIT_USRCLK;
                end
            end
        end
        STATE_WAIT_USRCLK: begin
            gt_rx_reset_reg <= 1'b0;
            gt_rx_prgdiv_reset_reg <= 1'b0;
            gt_rx_userrdy_reg <= 1'b0;

            state_reg <= STATE_WAIT_USRCLK;
            if (gt_userclk_rx_active_sync) begin
                // user clock running
                rx_reset_cnt_reg <= rx_reset_cnt_reg + 1;
                if (&rx_reset_cnt_reg) begin
                    state_reg <= STATE_DONE;
                end
            end
        end
        STATE_DONE: begin
            gt_rx_reset_reg <= 1'b0;
            gt_rx_prgdiv_reset_reg <= 1'b0;
            gt_rx_userrdy_reg <= 1'b1;

            rx_reset_done_reg <= gt_rx_reset_done_sync && gt_rx_prgdiv_reset_done_sync;

            state_reg <= STATE_DONE;
        end
        default: begin
            state_reg <= STATE_RESET;
        end
    endcase

    if (rx_reset_sync || rx_pd_in || !rx_sel_pll_lock || (gt_rx_qpll_sel_reg != rx_qpll_sel_in) || (gt_rx_lpm_en_reg != rx_lpm_en_in)) begin
        state_reg <= STATE_RESET;
    end

    if (rst) begin
        gt_rx_reset_reg <= 1'b1;
        gt_rx_pma_reset_reg <= 1'b0;
        gt_rx_pcs_reset_reg <= 1'b0;
        gt_rx_dfe_lpm_reset_reg <= 1'b0;
        gt_eyescan_reset_reg <= 1'b0;

        gt_rx_prgdiv_reset_reg <= 1'b1;
        gt_rx_userrdy_reg <= 1'b0;

        gt_rx_pd_reg <= GT_RX_PD;
        gt_rx_qpll_sel_reg <= GT_RX_QPLL_SEL;

        state_reg <= STATE_RESET;
        rx_reset_done_reg <= 1'b0;
    end
end

endmodule

`resetall
