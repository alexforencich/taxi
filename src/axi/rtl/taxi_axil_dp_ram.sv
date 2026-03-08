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
 * AXI4-Lite dual-port RAM
 */
module taxi_axil_dp_ram #
(
    // Width of address bus in bits
    parameter ADDR_W = 16,
    // Extra pipeline register on output
    parameter logic PIPELINE_OUTPUT = 1'b0
)
(
    /*
     * Port A
     */
    input  wire logic    a_clk,
    input  wire logic    a_rst,
    taxi_axil_if.wr_slv  s_axil_wr_a,
    taxi_axil_if.rd_slv  s_axil_rd_a,

    /*
     * Port B
     */
    input  wire logic    b_clk,
    input  wire logic    b_rst,
    taxi_axil_if.wr_slv  s_axil_wr_b,
    taxi_axil_if.rd_slv  s_axil_rd_b
);

// extract parameters
localparam DATA_W = s_axil_wr_a.DATA_W;
localparam STRB_W = s_axil_wr_a.STRB_W;

localparam VALID_ADDR_W = ADDR_W - $clog2(STRB_W);
localparam BYTE_LANES = STRB_W;
localparam BYTE_W = DATA_W/BYTE_LANES;

// check configuration
if (BYTE_W * STRB_W != DATA_W)
    $fatal(0, "Error: AXI data width not evenly divisible (instance %m)");

if (2**$clog2(BYTE_LANES) != BYTE_LANES)
    $fatal(0, "Error: AXI word width must be even power of two (instance %m)");

if (s_axil_wr_a.DATA_W != s_axil_rd_a.DATA_W || s_axil_wr_b.DATA_W != s_axil_rd_b.DATA_W || s_axil_wr_a.DATA_W != s_axil_wr_b.DATA_W)
    $fatal(0, "Error: AXI interface configuration mismatch (instance %m)");

if (s_axil_wr_a.ADDR_W < ADDR_W || s_axil_wr_a.ADDR_W < ADDR_W || s_axil_rd_b.ADDR_W < ADDR_W || s_axil_rd_b.ADDR_W < ADDR_W)
    $fatal(0, "Error: AXI address width is insufficient (instance %m)");

logic read_eligible_a;
logic write_eligible_a;

logic read_eligible_b;
logic write_eligible_b;

logic mem_wr_en_a;
logic mem_rd_en_a;

logic mem_wr_en_b;
logic mem_rd_en_b;

logic last_read_a_reg = 1'b0, last_read_a_next;
logic last_read_b_reg = 1'b0, last_read_b_next;

logic s_axil_a_awready_reg = 1'b0, s_axil_a_awready_next;
logic s_axil_a_wready_reg = 1'b0, s_axil_a_wready_next;
logic s_axil_a_bvalid_reg = 1'b0, s_axil_a_bvalid_next;
logic s_axil_a_arready_reg = 1'b0, s_axil_a_arready_next;
logic [DATA_W-1:0] s_axil_a_rdata_reg = '0, s_axil_a_rdata_next;
logic s_axil_a_rvalid_reg = 1'b0, s_axil_a_rvalid_next;
logic [DATA_W-1:0] s_axil_a_rdata_pipe_reg = '0;
logic s_axil_a_rvalid_pipe_reg = 1'b0;

logic s_axil_b_awready_reg = 1'b0, s_axil_b_awready_next;
logic s_axil_b_wready_reg = 1'b0, s_axil_b_wready_next;
logic s_axil_b_bvalid_reg = 1'b0, s_axil_b_bvalid_next;
logic s_axil_b_arready_reg = 1'b0, s_axil_b_arready_next;
logic [DATA_W-1:0] s_axil_b_rdata_reg = '0, s_axil_b_rdata_next;
logic s_axil_b_rvalid_reg = 1'b0, s_axil_b_rvalid_next;
logic [DATA_W-1:0] s_axil_b_rdata_pipe_reg = '0;
logic s_axil_b_rvalid_pipe_reg = 1'b0;

// verilator lint_off MULTIDRIVEN
// (* RAM_STYLE="BLOCK" *)
logic [DATA_W-1:0] mem[2**VALID_ADDR_W] = '{default: '0};
// verilator lint_on MULTIDRIVEN

wire [VALID_ADDR_W-1:0] s_axil_a_awaddr_valid = VALID_ADDR_W'(s_axil_wr_a.awaddr >> (ADDR_W - VALID_ADDR_W));
wire [VALID_ADDR_W-1:0] s_axil_a_araddr_valid = VALID_ADDR_W'(s_axil_rd_a.araddr >> (ADDR_W - VALID_ADDR_W));

wire [VALID_ADDR_W-1:0] s_axil_b_awaddr_valid = VALID_ADDR_W'(s_axil_wr_b.awaddr >> (ADDR_W - VALID_ADDR_W));
wire [VALID_ADDR_W-1:0] s_axil_b_araddr_valid = VALID_ADDR_W'(s_axil_rd_b.araddr >> (ADDR_W - VALID_ADDR_W));

assign s_axil_wr_a.awready = s_axil_a_awready_reg;
assign s_axil_wr_a.wready = s_axil_a_wready_reg;
assign s_axil_wr_a.bresp = 2'b00;
assign s_axil_wr_a.buser = '0;
assign s_axil_wr_a.bvalid = s_axil_a_bvalid_reg;

assign s_axil_rd_a.arready = s_axil_a_arready_reg;
assign s_axil_rd_a.rdata = PIPELINE_OUTPUT ? s_axil_a_rdata_pipe_reg : s_axil_a_rdata_reg;
assign s_axil_rd_a.rresp = 2'b00;
assign s_axil_rd_a.ruser = '0;
assign s_axil_rd_a.rvalid = PIPELINE_OUTPUT ? s_axil_a_rvalid_pipe_reg : s_axil_a_rvalid_reg;

assign s_axil_wr_b.awready = s_axil_b_awready_reg;
assign s_axil_wr_b.wready = s_axil_b_wready_reg;
assign s_axil_wr_b.bresp = 2'b00;
assign s_axil_wr_b.buser = '0;
assign s_axil_wr_b.bvalid = s_axil_b_bvalid_reg;

assign s_axil_rd_b.arready = s_axil_b_arready_reg;
assign s_axil_rd_b.rdata = PIPELINE_OUTPUT ? s_axil_b_rdata_pipe_reg : s_axil_b_rdata_reg;
assign s_axil_rd_b.rresp = 2'b00;
assign s_axil_rd_b.ruser = '0;
assign s_axil_rd_b.rvalid = PIPELINE_OUTPUT ? s_axil_b_rvalid_pipe_reg : s_axil_b_rvalid_reg;

always_comb begin
    mem_wr_en_a = 1'b0;
    mem_rd_en_a = 1'b0;

    last_read_a_next = last_read_a_reg;

    s_axil_a_awready_next = 1'b0;
    s_axil_a_wready_next = 1'b0;
    s_axil_a_bvalid_next = s_axil_a_bvalid_reg && !s_axil_wr_a.bready;

    s_axil_a_arready_next = 1'b0;
    s_axil_a_rvalid_next = s_axil_a_rvalid_reg && !(s_axil_rd_a.rready || (PIPELINE_OUTPUT && !s_axil_a_rvalid_pipe_reg));

    write_eligible_a = s_axil_wr_a.awvalid && s_axil_wr_a.wvalid && (!s_axil_wr_a.bvalid || s_axil_wr_a.bready) && (!s_axil_wr_a.awready && !s_axil_wr_a.wready);
    read_eligible_a = s_axil_rd_a.arvalid && (!s_axil_rd_a.rvalid || s_axil_rd_a.rready || (PIPELINE_OUTPUT && !s_axil_a_rvalid_pipe_reg)) && (!s_axil_rd_a.arready);

    if (write_eligible_a && (!read_eligible_a || last_read_a_reg)) begin
        last_read_a_next = 1'b0;

        s_axil_a_awready_next = 1'b1;
        s_axil_a_wready_next = 1'b1;
        s_axil_a_bvalid_next = 1'b1;

        mem_wr_en_a = 1'b1;
    end else if (read_eligible_a) begin
        last_read_a_next = 1'b1;

        s_axil_a_arready_next = 1'b1;
        s_axil_a_rvalid_next = 1'b1;

        mem_rd_en_a = 1'b1;
    end
end

always_ff @(posedge a_clk) begin
    last_read_a_reg <= last_read_a_next;

    s_axil_a_awready_reg <= s_axil_a_awready_next;
    s_axil_a_wready_reg <= s_axil_a_wready_next;
    s_axil_a_bvalid_reg <= s_axil_a_bvalid_next;

    s_axil_a_arready_reg <= s_axil_a_arready_next;
    s_axil_a_rvalid_reg <= s_axil_a_rvalid_next;

    if (mem_rd_en_a) begin
        s_axil_a_rdata_reg <= mem[s_axil_a_araddr_valid];
    end else begin
        for (integer i = 0; i < BYTE_LANES; i = i + 1) begin
            if (mem_wr_en_a && s_axil_wr_a.wstrb[i]) begin
                mem[s_axil_a_awaddr_valid][BYTE_W*i +: BYTE_W] <= s_axil_wr_a.wdata[BYTE_W*i +: BYTE_W];
            end
        end
    end

    if (!s_axil_a_rvalid_pipe_reg || s_axil_rd_a.rready) begin
        s_axil_a_rdata_pipe_reg <= s_axil_a_rdata_reg;
        s_axil_a_rvalid_pipe_reg <= s_axil_a_rvalid_reg;
    end

    if (a_rst) begin
        last_read_a_reg <= 1'b0;

        s_axil_a_awready_reg <= 1'b0;
        s_axil_a_wready_reg <= 1'b0;
        s_axil_a_bvalid_reg <= 1'b0;

        s_axil_a_arready_reg <= 1'b0;
        s_axil_a_rvalid_reg <= 1'b0;
        s_axil_a_rvalid_pipe_reg <= 1'b0;
    end
end

always_comb begin
    mem_wr_en_b = 1'b0;
    mem_rd_en_b = 1'b0;

    last_read_b_next = last_read_b_reg;

    s_axil_b_awready_next = 1'b0;
    s_axil_b_wready_next = 1'b0;
    s_axil_b_bvalid_next = s_axil_b_bvalid_reg && !s_axil_wr_b.bready;

    s_axil_b_arready_next = 1'b0;
    s_axil_b_rvalid_next = s_axil_b_rvalid_reg && !(s_axil_rd_b.rready || (PIPELINE_OUTPUT && !s_axil_b_rvalid_pipe_reg));

    write_eligible_b = s_axil_wr_b.awvalid && s_axil_wr_b.wvalid && (!s_axil_wr_b.bvalid || s_axil_wr_b.bready) && (!s_axil_wr_b.awready && !s_axil_wr_b.wready);
    read_eligible_b = s_axil_rd_b.arvalid && (!s_axil_rd_b.rvalid || s_axil_rd_b.rready || (PIPELINE_OUTPUT && !s_axil_b_rvalid_pipe_reg)) && (!s_axil_rd_b.arready);

    if (write_eligible_b && (!read_eligible_b || last_read_b_reg)) begin
        last_read_b_next = 1'b0;

        s_axil_b_awready_next = 1'b1;
        s_axil_b_wready_next = 1'b1;
        s_axil_b_bvalid_next = 1'b1;

        mem_wr_en_b = 1'b1;
    end else if (read_eligible_b) begin
        last_read_b_next = 1'b1;

        s_axil_b_arready_next = 1'b1;
        s_axil_b_rvalid_next = 1'b1;

        mem_rd_en_b = 1'b1;
    end
end

always_ff @(posedge b_clk) begin
    last_read_b_reg <= last_read_b_next;

    s_axil_b_awready_reg <= s_axil_b_awready_next;
    s_axil_b_wready_reg <= s_axil_b_wready_next;
    s_axil_b_bvalid_reg <= s_axil_b_bvalid_next;

    s_axil_b_arready_reg <= s_axil_b_arready_next;
    s_axil_b_rvalid_reg <= s_axil_b_rvalid_next;

    if (mem_rd_en_b) begin
        s_axil_b_rdata_reg <= mem[s_axil_b_araddr_valid];
    end else begin
        for (integer i = 0; i < BYTE_LANES; i = i + 1) begin
            if (mem_wr_en_b && s_axil_wr_b.wstrb[i]) begin
                mem[s_axil_b_awaddr_valid][BYTE_W*i +: BYTE_W] <= s_axil_wr_b.wdata[BYTE_W*i +: BYTE_W];
            end
        end
    end

    if (!s_axil_b_rvalid_pipe_reg || s_axil_rd_b.rready) begin
        s_axil_b_rdata_pipe_reg <= s_axil_b_rdata_reg;
        s_axil_b_rvalid_pipe_reg <= s_axil_b_rvalid_reg;
    end

    if (b_rst) begin
        last_read_b_reg <= 1'b0;

        s_axil_b_awready_reg <= 1'b0;
        s_axil_b_wready_reg <= 1'b0;
        s_axil_b_bvalid_reg <= 1'b0;

        s_axil_b_arready_reg <= 1'b0;
        s_axil_b_rvalid_reg <= 1'b0;
        s_axil_b_rvalid_pipe_reg <= 1'b0;
    end
end

endmodule

`resetall
