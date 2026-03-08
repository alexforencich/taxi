// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2018-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Lite RAM
 */
module taxi_axil_ram #
(
    // Width of address bus in bits
    parameter ADDR_W = 16,
    // Extra pipeline register on output
    parameter logic PIPELINE_OUTPUT = 1'b0
)
(
    input  wire logic    clk,
    input  wire logic    rst,

    /*
     * AXI4-Lite slave interface
     */
    taxi_axil_if.wr_slv  s_axil_wr,
    taxi_axil_if.rd_slv  s_axil_rd
);

// extract parameters
localparam DATA_W = s_axil_wr.DATA_W;
localparam STRB_W = s_axil_wr.STRB_W;

localparam VALID_ADDR_W = ADDR_W - $clog2(STRB_W);
localparam BYTE_LANES = STRB_W;
localparam BYTE_W = DATA_W/BYTE_LANES;

// check configuration
if (BYTE_W * STRB_W != DATA_W)
    $fatal(0, "Error: AXI data width not evenly divisible (instance %m)");

if (2**$clog2(BYTE_LANES) != BYTE_LANES)
    $fatal(0, "Error: AXI byte lane count must be even power of two (instance %m)");

if (s_axil_wr.DATA_W != s_axil_rd.DATA_W)
    $fatal(0, "Error: AXI interface configuration mismatch (instance %m)");

if (s_axil_wr.ADDR_W < ADDR_W || s_axil_rd.ADDR_W < ADDR_W)
    $fatal(0, "Error: AXI address width is insufficient (instance %m)");

logic mem_wr_en;
logic mem_rd_en;

logic s_axil_awready_reg = 1'b0, s_axil_awready_next;
logic s_axil_wready_reg = 1'b0, s_axil_wready_next;
logic s_axil_bvalid_reg = 1'b0, s_axil_bvalid_next;
logic s_axil_arready_reg = 1'b0, s_axil_arready_next;
logic [DATA_W-1:0] s_axil_rdata_reg = '0, s_axil_rdata_next;
logic s_axil_rvalid_reg = 1'b0, s_axil_rvalid_next;
logic [DATA_W-1:0] s_axil_rdata_pipe_reg = '0;
logic s_axil_rvalid_pipe_reg = 1'b0;

// (* RAM_STYLE="BLOCK" *)
logic [DATA_W-1:0] mem[2**VALID_ADDR_W] = '{default: '0};

wire [VALID_ADDR_W-1:0] s_axil_awaddr_valid = VALID_ADDR_W'(s_axil_wr.awaddr >> (ADDR_W - VALID_ADDR_W));
wire [VALID_ADDR_W-1:0] s_axil_araddr_valid = VALID_ADDR_W'(s_axil_rd.araddr >> (ADDR_W - VALID_ADDR_W));

assign s_axil_wr.awready = s_axil_awready_reg;
assign s_axil_wr.wready = s_axil_wready_reg;
assign s_axil_wr.bresp = 2'b00;
assign s_axil_wr.buser = '0;
assign s_axil_wr.bvalid = s_axil_bvalid_reg;

assign s_axil_rd.arready = s_axil_arready_reg;
assign s_axil_rd.rdata = PIPELINE_OUTPUT ? s_axil_rdata_pipe_reg : s_axil_rdata_reg;
assign s_axil_rd.rresp = 2'b00;
assign s_axil_rd.ruser = '0;
assign s_axil_rd.rvalid = PIPELINE_OUTPUT ? s_axil_rvalid_pipe_reg : s_axil_rvalid_reg;

always_comb begin
    mem_wr_en = 1'b0;

    s_axil_awready_next = 1'b0;
    s_axil_wready_next = 1'b0;
    s_axil_bvalid_next = s_axil_bvalid_reg && !s_axil_wr.bready;

    if (s_axil_wr.awvalid && s_axil_wr.wvalid && (!s_axil_wr.bvalid || s_axil_wr.bready) && (!s_axil_wr.awready && !s_axil_wr.wready)) begin
        s_axil_awready_next = 1'b1;
        s_axil_wready_next = 1'b1;
        s_axil_bvalid_next = 1'b1;

        mem_wr_en = 1'b1;
    end
end

always_ff @(posedge clk) begin
    s_axil_awready_reg <= s_axil_awready_next;
    s_axil_wready_reg <= s_axil_wready_next;
    s_axil_bvalid_reg <= s_axil_bvalid_next;

    for (integer i = 0; i < BYTE_LANES; i = i + 1) begin
        if (mem_wr_en && s_axil_wr.wstrb[i]) begin
            mem[s_axil_awaddr_valid][BYTE_W*i +: BYTE_W] <= s_axil_wr.wdata[BYTE_W*i +: BYTE_W];
        end
    end

    if (rst) begin
        s_axil_awready_reg <= 1'b0;
        s_axil_wready_reg <= 1'b0;
        s_axil_bvalid_reg <= 1'b0;
    end
end

always_comb begin
    mem_rd_en = 1'b0;

    s_axil_arready_next = 1'b0;
    s_axil_rvalid_next = s_axil_rvalid_reg && !(s_axil_rd.rready || (PIPELINE_OUTPUT && !s_axil_rvalid_pipe_reg));

    if (s_axil_rd.arvalid && (!s_axil_rd.rvalid || s_axil_rd.rready || (PIPELINE_OUTPUT && !s_axil_rvalid_pipe_reg)) && (!s_axil_rd.arready)) begin
        s_axil_arready_next = 1'b1;
        s_axil_rvalid_next = 1'b1;

        mem_rd_en = 1'b1;
    end
end

always_ff @(posedge clk) begin
    s_axil_arready_reg <= s_axil_arready_next;
    s_axil_rvalid_reg <= s_axil_rvalid_next;

    if (mem_rd_en) begin
        s_axil_rdata_reg <= mem[s_axil_araddr_valid];
    end

    if (!s_axil_rvalid_pipe_reg || s_axil_rd.rready) begin
        s_axil_rdata_pipe_reg <= s_axil_rdata_reg;
        s_axil_rvalid_pipe_reg <= s_axil_rvalid_reg;
    end

    if (rst) begin
        s_axil_arready_reg <= 1'b0;
        s_axil_rvalid_reg <= 1'b0;
        s_axil_rvalid_pipe_reg <= 1'b0;
    end
end

endmodule

`resetall
