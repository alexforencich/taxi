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
 * Simple dual-port RAM
 */
module taxi_ram_1r1w_1c #
(
    parameter ADDR_W = 16,
    parameter DATA_W = 16,
    parameter logic STRB_EN = 1'b1,
    parameter STRB_W = DATA_W/8
)
(
    input  wire logic               clk,

    input  wire logic               wr_en,
    input  wire logic [ADDR_W-1:0]  wr_addr,
    input  wire logic [DATA_W-1:0]  wr_data,
    input  wire logic [STRB_W-1:0]  wr_strb = '1,

    input  wire logic               rd_en,
    input  wire logic [ADDR_W-1:0]  rd_addr,
    output wire logic [DATA_W-1:0]  rd_data
);

localparam BYTE_LANES = STRB_W;
localparam BYTE_W = DATA_W/BYTE_LANES;

// check configuration
if (STRB_EN && BYTE_W * STRB_W != DATA_W)
    $fatal(0, "Error: Data width not evenly divisible (instance %m)");

reg [DATA_W-1:0] rd_data_reg = '0;

assign rd_data = rd_data_reg;

// (* RAM_STYLE="BLOCK" *)
logic [DATA_W-1:0] mem[2**ADDR_W] = '{default: '0};

always_ff @(posedge clk) begin
    if (wr_en) begin
        if (STRB_EN) begin
            for (integer i = 0; i < BYTE_LANES; i = i + 1) begin
                if (wr_strb[i]) begin
                    mem[wr_addr][BYTE_W*i +: BYTE_W] <= wr_data[BYTE_W*i +: BYTE_W];
                end
            end
        end else begin
            mem[wr_addr] <= wr_data;
        end
    end

    if (rd_en) begin
        rd_data_reg <= mem[rd_addr];
    end
end

endmodule

`resetall
