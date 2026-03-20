// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2019-2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4 dual-port RAM
 */
module taxi_axi_dp_ram #
(
    // Width of address bus in bits
    parameter ADDR_W = 16,
    // Extra pipeline register on output port A
    parameter logic A_PIPELINE_OUTPUT = 1'b0,
    // Extra pipeline register on output port B
    parameter logic B_PIPELINE_OUTPUT = 1'b0,
    // Interleave read and write burst cycles on port A
    parameter logic A_INTERLEAVE = 1'b0,
    // Interleave read and write burst cycles on port B
    parameter logic B_INTERLEAVE = 1'b0
)
(
    /*
     * Port A
     */
    input  wire logic   a_clk,
    input  wire logic   a_rst,
    taxi_axi_if.wr_slv  s_axi_wr_a,
    taxi_axi_if.rd_slv  s_axi_rd_a,

    /*
     * Port B
     */
    input  wire logic   b_clk,
    input  wire logic   b_rst,
    taxi_axi_if.wr_slv  s_axi_wr_b,
    taxi_axi_if.rd_slv  s_axi_rd_b
);

// extract parameters
localparam DATA_W = s_axi_wr_a.DATA_W;
localparam STRB_W = s_axi_wr_a.STRB_W;
localparam A_ID_W = s_axi_wr_a.ID_W;
localparam B_ID_W = s_axi_wr_b.ID_W;

localparam VALID_ADDR_W = ADDR_W - $clog2(STRB_W);
localparam BYTE_LANES = STRB_W;
localparam BYTE_W = DATA_W/BYTE_LANES;

// check configuration
if (BYTE_W * STRB_W != DATA_W)
    $fatal(0, "Error: AXI data width not evenly divisible (instance %m)");

if (2**$clog2(BYTE_LANES) != BYTE_LANES)
    $fatal(0, "Error: AXI word width must be even power of two (instance %m)");

wire  [A_ID_W-1:0]  ram_a_cmd_id;
wire  [ADDR_W-1:0]  ram_a_cmd_addr;
wire  [DATA_W-1:0]  ram_a_cmd_wr_data;
wire  [STRB_W-1:0]  ram_a_cmd_wr_strb;
wire                ram_a_cmd_wr_en;
wire                ram_a_cmd_rd_en;
wire                ram_a_cmd_last;
wire                ram_a_cmd_ready;
logic [A_ID_W-1:0]  ram_a_rd_resp_id_reg = 'd0;
logic [DATA_W-1:0]  ram_a_rd_resp_data_reg = 'd0;
logic               ram_a_rd_resp_last_reg = 1'b0;
logic               ram_a_rd_resp_valid_reg = 1'b0;
wire                ram_a_rd_resp_ready;

wire  [B_ID_W-1:0]  ram_b_cmd_id;
wire  [ADDR_W-1:0]  ram_b_cmd_addr;
wire  [DATA_W-1:0]  ram_b_cmd_wr_data;
wire  [STRB_W-1:0]  ram_b_cmd_wr_strb;
wire                ram_b_cmd_wr_en;
wire                ram_b_cmd_rd_en;
wire                ram_b_cmd_last;
wire                ram_b_cmd_ready;
logic [B_ID_W-1:0]  ram_b_rd_resp_id_reg = 'd0;
logic [DATA_W-1:0]  ram_b_rd_resp_data_reg = 'd0;
logic               ram_b_rd_resp_last_reg = 1'b0;
logic               ram_b_rd_resp_valid_reg = 1'b0;
wire                ram_b_rd_resp_ready;

taxi_axi_ram_if_rdwr #(
    .DATA_W(DATA_W),
    .ADDR_W(ADDR_W),
    .STRB_W(STRB_W),
    .ID_W(A_ID_W),
    .AUSER_W(s_axi_wr_a.AWUSER_W > s_axi_rd_a.ARUSER_W ? s_axi_wr_a.AWUSER_W : s_axi_rd_a.ARUSER_W),
    .WUSER_W(s_axi_wr_a.WUSER_W),
    .RUSER_W(s_axi_rd_a.RUSER_W),
    .PIPELINE_OUTPUT(A_PIPELINE_OUTPUT),
    .INTERLEAVE(A_INTERLEAVE)
)
a_if (
    .clk(a_clk),
    .rst(a_rst),

    /*
     * AXI4 slave interface
     */
    .s_axi_wr(s_axi_wr_a),
    .s_axi_rd(s_axi_rd_a),

    /*
     * RAM interface
     */
    .ram_cmd_id(ram_a_cmd_id),
    .ram_cmd_addr(ram_a_cmd_addr),
    .ram_cmd_lock(),
    .ram_cmd_cache(),
    .ram_cmd_prot(),
    .ram_cmd_qos(),
    .ram_cmd_region(),
    .ram_cmd_auser(),
    .ram_cmd_wr_data(ram_a_cmd_wr_data),
    .ram_cmd_wr_strb(ram_a_cmd_wr_strb),
    .ram_cmd_wr_user(),
    .ram_cmd_wr_en(ram_a_cmd_wr_en),
    .ram_cmd_rd_en(ram_a_cmd_rd_en),
    .ram_cmd_last(ram_a_cmd_last),
    .ram_cmd_ready(ram_a_cmd_ready),
    .ram_rd_resp_id(ram_a_rd_resp_id_reg),
    .ram_rd_resp_data(ram_a_rd_resp_data_reg),
    .ram_rd_resp_last(ram_a_rd_resp_last_reg),
    .ram_rd_resp_user('0),
    .ram_rd_resp_valid(ram_a_rd_resp_valid_reg),
    .ram_rd_resp_ready(ram_a_rd_resp_ready)
);

taxi_axi_ram_if_rdwr #(
    .DATA_W(DATA_W),
    .ADDR_W(ADDR_W),
    .STRB_W(STRB_W),
    .ID_W(B_ID_W),
    .AUSER_W(s_axi_wr_b.AWUSER_W > s_axi_rd_b.ARUSER_W ? s_axi_wr_b.AWUSER_W : s_axi_rd_b.ARUSER_W),
    .WUSER_W(s_axi_wr_b.WUSER_W),
    .RUSER_W(s_axi_rd_b.RUSER_W),
    .PIPELINE_OUTPUT(B_PIPELINE_OUTPUT),
    .INTERLEAVE(B_INTERLEAVE)
)
b_if (
    .clk(b_clk),
    .rst(b_rst),

    /*
     * AXI4 slave interface
     */
    .s_axi_wr(s_axi_wr_b),
    .s_axi_rd(s_axi_rd_b),

    /*
     * RAM interface
     */
    .ram_cmd_id(ram_b_cmd_id),
    .ram_cmd_addr(ram_b_cmd_addr),
    .ram_cmd_lock(),
    .ram_cmd_cache(),
    .ram_cmd_prot(),
    .ram_cmd_qos(),
    .ram_cmd_region(),
    .ram_cmd_auser(),
    .ram_cmd_wr_data(ram_b_cmd_wr_data),
    .ram_cmd_wr_strb(ram_b_cmd_wr_strb),
    .ram_cmd_wr_user(),
    .ram_cmd_wr_en(ram_b_cmd_wr_en),
    .ram_cmd_rd_en(ram_b_cmd_rd_en),
    .ram_cmd_last(ram_b_cmd_last),
    .ram_cmd_ready(ram_b_cmd_ready),
    .ram_rd_resp_id(ram_b_rd_resp_id_reg),
    .ram_rd_resp_data(ram_b_rd_resp_data_reg),
    .ram_rd_resp_last(ram_b_rd_resp_last_reg),
    .ram_rd_resp_user('0),
    .ram_rd_resp_valid(ram_b_rd_resp_valid_reg),
    .ram_rd_resp_ready(ram_b_rd_resp_ready)
);

// verilator lint_off MULTIDRIVEN
// (* RAM_STYLE="BLOCK" *)
logic [DATA_W-1:0] mem[2**VALID_ADDR_W] = '{default: '0};
// verilator lint_on MULTIDRIVEN

wire [VALID_ADDR_W-1:0] addr_a_valid = VALID_ADDR_W'(ram_a_cmd_addr >> (ADDR_W - VALID_ADDR_W));
wire [VALID_ADDR_W-1:0] addr_b_valid = VALID_ADDR_W'(ram_b_cmd_addr >> (ADDR_W - VALID_ADDR_W));

assign ram_a_cmd_ready = !ram_a_rd_resp_valid_reg || ram_a_rd_resp_ready;

always_ff @(posedge a_clk) begin
    ram_a_rd_resp_valid_reg <= ram_a_rd_resp_valid_reg && !ram_a_rd_resp_ready;

    if (ram_a_cmd_rd_en && ram_a_cmd_ready) begin
        ram_a_rd_resp_id_reg <= ram_a_cmd_id;
        ram_a_rd_resp_data_reg <= mem[addr_a_valid];
        ram_a_rd_resp_last_reg <= ram_a_cmd_last;
        ram_a_rd_resp_valid_reg <= 1'b1;
    end else if (ram_a_cmd_wr_en && ram_a_cmd_ready) begin
        for (integer i = 0; i < BYTE_LANES; i = i + 1) begin
            if (ram_a_cmd_wr_strb[i]) begin
                mem[addr_a_valid][BYTE_W*i +: BYTE_W] <= ram_a_cmd_wr_data[BYTE_W*i +: BYTE_W];
            end
        end
    end

    if (a_rst) begin
        ram_a_rd_resp_valid_reg <= 1'b0;
    end
end

assign ram_b_cmd_ready = !ram_b_rd_resp_valid_reg || ram_b_rd_resp_ready;

always_ff @(posedge b_clk) begin
    ram_b_rd_resp_valid_reg <= ram_b_rd_resp_valid_reg && !ram_b_rd_resp_ready;

    if (ram_b_cmd_rd_en && ram_b_cmd_ready) begin
        ram_b_rd_resp_id_reg <= ram_b_cmd_id;
        ram_b_rd_resp_data_reg <= mem[addr_b_valid];
        ram_b_rd_resp_last_reg <= ram_b_cmd_last;
        ram_b_rd_resp_valid_reg <= 1'b1;
    end else if (ram_b_cmd_wr_en && ram_b_cmd_ready) begin
        for (integer i = 0; i < BYTE_LANES; i = i + 1) begin
            if (ram_b_cmd_wr_strb[i]) begin
                mem[addr_b_valid][BYTE_W*i +: BYTE_W] <= ram_b_cmd_wr_data[BYTE_W*i +: BYTE_W];
            end
        end
    end

    if (b_rst) begin
        ram_b_rd_resp_valid_reg <= 1'b0;
    end
end

endmodule

`resetall
