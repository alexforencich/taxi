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
 * GT TX reset controller for UltraScale/UltraScale+ GTH/GTY
 */
module taxi_gt_tx_reset #
(
    parameter GT_TX_PD = 1'b0,
    parameter GT_TX_QPLL_SEL = 1'b0,
    parameter CNT_W = 8
)
(
    input  wire logic  clk,
    input  wire logic  rst,

    /*
     * GT
     */
    input  wire logic  gt_txusrclk2,
    output wire logic  gt_tx_pd_out,
    output wire logic  gt_tx_reset_out,
    input  wire logic  gt_tx_reset_done_in,
    input  wire logic  gt_userclk_tx_active_in,
    output wire logic  gt_tx_pma_reset_out,
    output wire logic  gt_tx_pcs_reset_out,
    input  wire logic  gt_tx_pma_reset_done_in,
    output wire logic  gt_tx_prgdiv_reset_out,
    input  wire logic  gt_tx_prgdiv_reset_done_in,
    output wire logic  gt_tx_qpll_sel_out,
    output wire logic  gt_tx_userrdy_out,

    /*
     * Control/status
     */
    input  wire logic  qpll0_lock_in,
    input  wire logic  qpll1_lock_in,
    input  wire logic  tx_reset_in = 1'b0,
    output wire logic  tx_reset_done_out,
    input  wire logic  tx_pma_reset_in = 1'b0,
    output wire logic  tx_pma_reset_done_out,
    output wire logic  tx_prgdiv_reset_done_out,
    input  wire logic  tx_pcs_reset_in = 1'b0,
    input  wire logic  tx_pd_in = GT_TX_PD,
    input  wire logic  tx_qpll_sel_in = GT_TX_QPLL_SEL
);

logic gt_tx_reset_reg = 1'b1;
logic gt_tx_pma_reset_reg = 1'b0;
logic gt_tx_pcs_reset_reg = 1'b0;

logic gt_tx_prgdiv_reset_reg = 1'b0;
logic gt_tx_userrdy_reg = 1'b0;

logic gt_tx_pd_reg = GT_TX_PD;

logic gt_tx_qpll_sel_reg = GT_TX_QPLL_SEL;

wire gt_tx_reset_done_sync;
wire gt_tx_pma_reset_done_sync;
wire gt_tx_prgdiv_reset_done_sync;
wire gt_userclk_tx_active_sync;

taxi_sync_signal #(
    .WIDTH(4),
    .N(2)
)
gt_status_sync_inst (
    .clk(clk),
    .in({gt_tx_reset_done_in, gt_tx_pma_reset_done_in, gt_tx_prgdiv_reset_done_in, gt_userclk_tx_active_in}),
    .out({gt_tx_reset_done_sync, gt_tx_pma_reset_done_sync, gt_tx_prgdiv_reset_done_sync, gt_userclk_tx_active_sync})
);

taxi_sync_signal #(
    .WIDTH(1),
    .N(2)
)
gt_ctrl_sync_inst (
    .clk(gt_txusrclk2),
    .in({gt_tx_pd_reg}),
    .out({gt_tx_pd_out})
);

wire tx_reset_sync;

taxi_sync_reset #(
    .N(4)
)
reset_sync_inst (
    .clk(clk),
    .rst(tx_reset_in),
    .out(tx_reset_sync)
);

typedef enum logic [1:0] {
    STATE_RESET,
    STATE_WAIT_LOCK,
    STATE_WAIT_USRCLK,
    STATE_DONE
} state_t;

state_t state_reg = STATE_RESET, state_next;

logic [CNT_W-1:0] tx_reset_cnt_reg = '0;
logic tx_reset_done_reg = 1'b0;

assign gt_tx_reset_out = gt_tx_reset_reg;
assign gt_tx_pma_reset_out = gt_tx_pma_reset_reg;
assign gt_tx_pcs_reset_out = gt_tx_pcs_reset_reg;
assign gt_tx_prgdiv_reset_out = gt_tx_prgdiv_reset_reg;
assign gt_tx_qpll_sel_out = gt_tx_qpll_sel_reg;
assign gt_tx_userrdy_out = gt_tx_userrdy_reg;

assign tx_reset_done_out = tx_reset_done_reg;
assign tx_pma_reset_done_out = gt_tx_pma_reset_done_sync;
assign tx_prgdiv_reset_done_out = gt_tx_prgdiv_reset_done_sync;

wire tx_sel_pll_lock = gt_tx_qpll_sel_reg ? qpll1_lock_in : qpll0_lock_in;

always_ff @(posedge clk) begin
    gt_tx_reset_reg <= 1'b1;
    gt_tx_pma_reset_reg <= tx_pma_reset_in;
    gt_tx_pcs_reset_reg <= tx_pcs_reset_in;

    gt_tx_prgdiv_reset_reg <= 1'b1;
    gt_tx_userrdy_reg <= 1'b0;

    state_reg <= STATE_RESET;
    tx_reset_cnt_reg <= '0;
    tx_reset_done_reg <= 1'b0;

    case (state_reg)
        STATE_RESET: begin
            gt_tx_reset_reg <= 1'b1;
            gt_tx_prgdiv_reset_reg <= 1'b1;
            gt_tx_userrdy_reg <= 1'b0;

            gt_tx_pd_reg <= tx_pd_in;
            gt_tx_qpll_sel_reg <= tx_qpll_sel_in;

            state_reg <= STATE_WAIT_LOCK;
        end
        STATE_WAIT_LOCK: begin
            gt_tx_reset_reg <= 1'b1;
            gt_tx_prgdiv_reset_reg <= 1'b1;
            gt_tx_userrdy_reg <= 1'b0;

            state_reg <= STATE_WAIT_LOCK;
            if (tx_sel_pll_lock) begin
                // QPLL locked
                tx_reset_cnt_reg <= tx_reset_cnt_reg + 1;
                if (&tx_reset_cnt_reg) begin
                    state_reg <= STATE_WAIT_USRCLK;
                end
            end
        end
        STATE_WAIT_USRCLK: begin
            gt_tx_reset_reg <= 1'b0;
            gt_tx_prgdiv_reset_reg <= 1'b0;
            gt_tx_userrdy_reg <= 1'b0;

            state_reg <= STATE_WAIT_USRCLK;
            if (gt_userclk_tx_active_sync) begin
                // user clock running
                tx_reset_cnt_reg <= tx_reset_cnt_reg + 1;
                if (&tx_reset_cnt_reg) begin
                    state_reg <= STATE_DONE;
                end
            end
        end
        STATE_DONE: begin
            gt_tx_reset_reg <= 1'b0;
            gt_tx_prgdiv_reset_reg <= 1'b0;
            gt_tx_userrdy_reg <= 1'b1;

            tx_reset_done_reg <= gt_tx_reset_done_sync && gt_tx_prgdiv_reset_done_sync;

            state_reg <= STATE_DONE;
        end
        default: begin
            state_reg <= STATE_RESET;
        end
    endcase

    if (tx_reset_sync || tx_pd_in || !tx_sel_pll_lock || (gt_tx_qpll_sel_reg != tx_qpll_sel_in)) begin
        state_reg <= STATE_RESET;
    end

    if (rst) begin
        gt_tx_reset_reg <= 1'b1;
        gt_tx_pma_reset_reg <= 1'b0;
        gt_tx_pcs_reset_reg <= 1'b0;

        gt_tx_prgdiv_reset_reg <= 1'b1;
        gt_tx_userrdy_reg <= 1'b0;

        gt_tx_pd_reg <= GT_TX_PD;
        gt_tx_qpll_sel_reg <= GT_TX_QPLL_SEL;

        state_reg <= STATE_RESET;
        tx_reset_done_reg <= 1'b0;
    end
end

endmodule

`resetall
