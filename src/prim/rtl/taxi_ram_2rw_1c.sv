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
 * True dual-port RAM
 */
module taxi_ram_2rw_1c #
(
    parameter ADDR_W = 16,
    parameter DATA_W = 16,
    parameter logic STRB_EN = 1'b1,
    parameter STRB_W = DATA_W/8
)
(
    input  wire logic               clk,

    input  wire logic               a_en,
    input  wire logic [ADDR_W-1:0]  a_addr,
    input  wire logic               a_wr_en,
    input  wire logic [DATA_W-1:0]  a_wr_data,
    input  wire logic [STRB_W-1:0]  a_wr_strb = '1,
    output wire logic [DATA_W-1:0]  a_rd_data,

    input  wire logic               b_en,
    input  wire logic [ADDR_W-1:0]  b_addr,
    input  wire logic               b_wr_en,
    input  wire logic [DATA_W-1:0]  b_wr_data,
    input  wire logic [STRB_W-1:0]  b_wr_strb = '1,
    output wire logic [DATA_W-1:0]  b_rd_data
);

localparam BYTE_LANES = STRB_W;
localparam BYTE_W = DATA_W/BYTE_LANES;

// check configuration
if (STRB_EN && BYTE_W * STRB_W != DATA_W)
    $fatal(0, "Error: Data width not evenly divisible (instance %m)");

reg [DATA_W-1:0] a_rd_data_reg = '0;
reg [DATA_W-1:0] b_rd_data_reg = '0;

assign a_rd_data = a_rd_data_reg;
assign b_rd_data = b_rd_data_reg;

// verilator lint_off MULTIDRIVEN
// (* RAM_STYLE="BLOCK" *)
logic [DATA_W-1:0] mem[2**ADDR_W] = '{default: '0};
// verilator lint_on MULTIDRIVEN

always_ff @(posedge clk) begin
    if (a_en) begin
        if (a_wr_en) begin
            if (STRB_EN) begin
                for (integer i = 0; i < BYTE_LANES; i = i + 1) begin
                    if (a_wr_strb[i]) begin
                        mem[a_addr][BYTE_W*i +: BYTE_W] <= a_wr_data[BYTE_W*i +: BYTE_W];
                    end
                end
            end else begin
                mem[a_addr] <= a_wr_data;
            end
        end else begin
            a_rd_data_reg <= mem[a_addr];
        end
    end

    if (b_en) begin
        if (b_wr_en) begin
            if (STRB_EN) begin
                for (integer i = 0; i < BYTE_LANES; i = i + 1) begin
                    if (b_wr_strb[i]) begin
                        mem[b_addr][BYTE_W*i +: BYTE_W] <= b_wr_data[BYTE_W*i +: BYTE_W];
                    end
                end
            end else begin
                mem[b_addr] <= b_wr_data;
            end
        end else begin
            b_rd_data_reg <= mem[b_addr];
        end
    end
end

endmodule

`resetall
