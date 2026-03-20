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
 * AXI4 dual-port RAM testbench
 */
module test_taxi_axi_dp_ram #
(
    /* verilator lint_off WIDTHTRUNC */
    parameter DATA_W = 32,
    parameter ADDR_W = 16,
    parameter STRB_W = (DATA_W/8),
    parameter ID_W = 8,
    parameter logic A_PIPELINE_OUTPUT = 1'b0,
    parameter logic B_PIPELINE_OUTPUT = 1'b0,
    parameter logic A_INTERLEAVE = 1'b0,
    parameter logic B_INTERLEAVE = 1'b0
    /* verilator lint_on WIDTHTRUNC */
)
();

logic a_clk;
logic a_rst;
logic b_clk;
logic b_rst;

taxi_axi_if #(
    .DATA_W(DATA_W),
    .ADDR_W(ADDR_W+16),
    .STRB_W(STRB_W),
    .ID_W(ID_W)
) s_axi_a(), s_axi_b();

taxi_axi_dp_ram #(
    .ADDR_W(ADDR_W),
    .A_PIPELINE_OUTPUT(A_PIPELINE_OUTPUT),
    .B_PIPELINE_OUTPUT(B_PIPELINE_OUTPUT),
    .A_INTERLEAVE(A_INTERLEAVE),
    .B_INTERLEAVE(B_INTERLEAVE)
)
uut (
    /*
     * Port A
     */
    .a_clk(a_clk),
    .a_rst(a_rst),
    .s_axi_wr_a(s_axi_a),
    .s_axi_rd_a(s_axi_a),

    /*
     * Port B
     */
    .b_clk(b_clk),
    .b_rst(b_rst),
    .s_axi_wr_b(s_axi_b),
    .s_axi_rd_b(s_axi_b)
);

endmodule

`resetall
