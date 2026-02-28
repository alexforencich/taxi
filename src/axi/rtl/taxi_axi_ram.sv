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
 * AXI4 RAM
 */
module taxi_axi_ram #
(
    // Width of address bus in bits
    parameter ADDR_W = 16,
    // Extra pipeline register on output
    parameter logic PIPELINE_OUTPUT = 1'b0
)
(
    input  wire logic   clk,
    input  wire logic   rst,

    /*
     * AXI4 slave interface
     */
    taxi_axi_if.wr_slv  s_axi_wr,
    taxi_axi_if.rd_slv  s_axi_rd
);

// extract parameters
localparam DATA_W = s_axi_wr.DATA_W;
localparam STRB_W = s_axi_wr.STRB_W;
localparam WR_ID_W = s_axi_wr.ID_W;
localparam RD_ID_W = s_axi_rd.ID_W;

localparam VALID_ADDR_W = ADDR_W - $clog2(STRB_W);
localparam BYTE_LANES = STRB_W;
localparam BYTE_W = DATA_W/BYTE_LANES;

// check configuration
if (BYTE_W * STRB_W != DATA_W)
    $fatal(0, "Error: AXI data width not evenly divisible (instance %m)");

if (2**$clog2(BYTE_LANES) != BYTE_LANES)
    $fatal(0, "Error: AXI byte lane count must be even power of two (instance %m)");

if (s_axi_wr.DATA_W != s_axi_rd.DATA_W)
    $fatal(0, "Error: AXI interface configuration mismatch (instance %m)");

if (s_axi_wr.ADDR_W < ADDR_W || s_axi_rd.ADDR_W < ADDR_W)
    $fatal(0, "Error: AXI address width is insufficient (instance %m)");

typedef enum logic [0:0] {
    READ_STATE_IDLE,
    READ_STATE_BURST
} read_state_t;

read_state_t read_state_reg = READ_STATE_IDLE, read_state_next;

typedef enum logic [1:0] {
    WRITE_STATE_IDLE,
    WRITE_STATE_BURST,
    WRITE_STATE_RESP
} write_state_t;

write_state_t write_state_reg = WRITE_STATE_IDLE, write_state_next;

logic mem_wr_en;
logic mem_rd_en;

logic [WR_ID_W-1:0] write_id_reg = '0, write_id_next;
logic [ADDR_W-1:0] write_addr_reg = '0, write_addr_next;
logic [7:0] write_count_reg = 8'd0, write_count_next;
logic [2:0] write_size_reg = 3'd0, write_size_next;
logic [1:0] write_burst_reg = 2'd0, write_burst_next;
logic [RD_ID_W-1:0] read_id_reg = '0, read_id_next;
logic [ADDR_W-1:0] read_addr_reg = '0, read_addr_next;
logic [7:0] read_count_reg = 8'd0, read_count_next;
logic [2:0] read_size_reg = 3'd0, read_size_next;
logic [1:0] read_burst_reg = 2'd0, read_burst_next;

logic s_axi_awready_reg = 1'b0, s_axi_awready_next;
logic s_axi_wready_reg = 1'b0, s_axi_wready_next;
logic [WR_ID_W-1:0] s_axi_bid_reg = '0, s_axi_bid_next;
logic s_axi_bvalid_reg = 1'b0, s_axi_bvalid_next;
logic s_axi_arready_reg = 1'b0, s_axi_arready_next;
logic [RD_ID_W-1:0] s_axi_rid_reg = '0, s_axi_rid_next;
logic [DATA_W-1:0] s_axi_rdata_reg = '0, s_axi_rdata_next;
logic s_axi_rlast_reg = 1'b0, s_axi_rlast_next;
logic s_axi_rvalid_reg = 1'b0, s_axi_rvalid_next;
logic [RD_ID_W-1:0] s_axi_rid_pipe_reg = '0;
logic [DATA_W-1:0] s_axi_rdata_pipe_reg = '0;
logic s_axi_rlast_pipe_reg = 1'b0;
logic s_axi_rvalid_pipe_reg = 1'b0;

// (* RAM_STYLE="BLOCK" *)
logic [DATA_W-1:0] mem[2**VALID_ADDR_W];

wire [VALID_ADDR_W-1:0] read_addr_valid = VALID_ADDR_W'(read_addr_reg >> (ADDR_W - VALID_ADDR_W));
wire [VALID_ADDR_W-1:0] write_addr_valid = VALID_ADDR_W'(write_addr_reg >> (ADDR_W - VALID_ADDR_W));

assign s_axi_wr.awready = s_axi_awready_reg;
assign s_axi_wr.wready = s_axi_wready_reg;
assign s_axi_wr.bid = s_axi_bid_reg;
assign s_axi_wr.bresp = 2'b00;
assign s_axi_wr.buser = '0;
assign s_axi_wr.bvalid = s_axi_bvalid_reg;

assign s_axi_rd.arready = s_axi_arready_reg;
assign s_axi_rd.rid = PIPELINE_OUTPUT ? s_axi_rid_pipe_reg : s_axi_rid_reg;
assign s_axi_rd.rdata = PIPELINE_OUTPUT ? s_axi_rdata_pipe_reg : s_axi_rdata_reg;
assign s_axi_rd.rresp = 2'b00;
assign s_axi_rd.rlast = PIPELINE_OUTPUT ? s_axi_rlast_pipe_reg : s_axi_rlast_reg;
assign s_axi_rd.ruser = '0;
assign s_axi_rd.rvalid = PIPELINE_OUTPUT ? s_axi_rvalid_pipe_reg : s_axi_rvalid_reg;

initial begin
    // two nested loops for smaller number of iterations per loop
    // workaround for synthesizer complaints about large loop counts
    for (integer i = 0; i < 2**VALID_ADDR_W; i = i + 2**(VALID_ADDR_W/2)) begin
        for (integer j = i; j < i + 2**(VALID_ADDR_W/2); j = j + 1) begin
            mem[j] = '0;
        end
    end
end

always_comb begin
    write_state_next = WRITE_STATE_IDLE;

    mem_wr_en = 1'b0;

    write_id_next = write_id_reg;
    write_addr_next = write_addr_reg;
    write_count_next = write_count_reg;
    write_size_next = write_size_reg;
    write_burst_next = write_burst_reg;

    s_axi_awready_next = 1'b0;
    s_axi_wready_next = 1'b0;
    s_axi_bid_next = s_axi_bid_reg;
    s_axi_bvalid_next = s_axi_bvalid_reg && !s_axi_wr.bready;

    case (write_state_reg)
        WRITE_STATE_IDLE: begin
            s_axi_awready_next = 1'b1;

            if (s_axi_wr.awready && s_axi_wr.awvalid) begin
                write_id_next = s_axi_wr.awid;
                write_addr_next = ADDR_W'(s_axi_wr.awaddr);
                write_count_next = s_axi_wr.awlen;
                write_size_next = s_axi_wr.awsize <= 3'($clog2(STRB_W)) ? s_axi_wr.awsize : 3'($clog2(STRB_W));
                write_burst_next = s_axi_wr.awburst;

                s_axi_awready_next = 1'b0;
                s_axi_wready_next = 1'b1;
                write_state_next = WRITE_STATE_BURST;
            end else begin
                write_state_next = WRITE_STATE_IDLE;
            end
        end
        WRITE_STATE_BURST: begin
            s_axi_wready_next = 1'b1;

            if (s_axi_wr.wready && s_axi_wr.wvalid) begin
                mem_wr_en = 1'b1;
                if (write_burst_reg != 2'b00) begin
                    write_addr_next = write_addr_reg + (1 << write_size_reg);
                end
                write_count_next = write_count_reg - 1;
                if (write_count_reg > 0) begin
                    write_state_next = WRITE_STATE_BURST;
                end else begin
                    s_axi_wready_next = 1'b0;
                    if (s_axi_wr.bready || !s_axi_wr.bvalid) begin
                        s_axi_bid_next = write_id_reg;
                        s_axi_bvalid_next = 1'b1;
                        s_axi_awready_next = 1'b1;
                        write_state_next = WRITE_STATE_IDLE;
                    end else begin
                        write_state_next = WRITE_STATE_RESP;
                    end
                end
            end else begin
                write_state_next = WRITE_STATE_BURST;
            end
        end
        WRITE_STATE_RESP: begin
            if (s_axi_wr.bready || !s_axi_wr.bvalid) begin
                s_axi_bid_next = write_id_reg;
                s_axi_bvalid_next = 1'b1;
                s_axi_awready_next = 1'b1;
                write_state_next = WRITE_STATE_IDLE;
            end else begin
                write_state_next = WRITE_STATE_RESP;
            end
        end
        default: begin
            write_state_next = WRITE_STATE_IDLE;
        end
    endcase
end

always_ff @(posedge clk) begin
    write_state_reg <= write_state_next;

    write_id_reg <= write_id_next;
    write_addr_reg <= write_addr_next;
    write_count_reg <= write_count_next;
    write_size_reg <= write_size_next;
    write_burst_reg <= write_burst_next;

    s_axi_awready_reg <= s_axi_awready_next;
    s_axi_wready_reg <= s_axi_wready_next;
    s_axi_bid_reg <= s_axi_bid_next;
    s_axi_bvalid_reg <= s_axi_bvalid_next;

    for (integer i = 0; i < BYTE_LANES; i = i + 1) begin
        if (mem_wr_en & s_axi_wr.wstrb[i]) begin
            mem[write_addr_valid][BYTE_W*i +: BYTE_W] <= s_axi_wr.wdata[BYTE_W*i +: BYTE_W];
        end
    end

    if (rst) begin
        write_state_reg <= WRITE_STATE_IDLE;

        s_axi_awready_reg <= 1'b0;
        s_axi_wready_reg <= 1'b0;
        s_axi_bvalid_reg <= 1'b0;
    end
end

always_comb begin
    read_state_next = READ_STATE_IDLE;

    mem_rd_en = 1'b0;

    s_axi_rid_next = s_axi_rid_reg;
    s_axi_rlast_next = s_axi_rlast_reg;
    s_axi_rvalid_next = s_axi_rvalid_reg && !(s_axi_rd.rready || (PIPELINE_OUTPUT && !s_axi_rvalid_pipe_reg));

    read_id_next = read_id_reg;
    read_addr_next = read_addr_reg;
    read_count_next = read_count_reg;
    read_size_next = read_size_reg;
    read_burst_next = read_burst_reg;

    s_axi_arready_next = 1'b0;

    case (read_state_reg)
        READ_STATE_IDLE: begin
            s_axi_arready_next = 1'b1;

            if (s_axi_rd.arready && s_axi_rd.arvalid) begin
                read_id_next = s_axi_rd.arid;
                read_addr_next = ADDR_W'(s_axi_rd.araddr);
                read_count_next = s_axi_rd.arlen;
                read_size_next = s_axi_rd.arsize <= 3'($clog2(STRB_W)) ? s_axi_rd.arsize : 3'($clog2(STRB_W));
                read_burst_next = s_axi_rd.arburst;

                s_axi_arready_next = 1'b0;
                read_state_next = READ_STATE_BURST;
            end else begin
                read_state_next = READ_STATE_IDLE;
            end
        end
        READ_STATE_BURST: begin
            if (s_axi_rd.rready || (PIPELINE_OUTPUT && !s_axi_rvalid_pipe_reg) || !s_axi_rvalid_reg) begin
                mem_rd_en = 1'b1;
                s_axi_rvalid_next = 1'b1;
                s_axi_rid_next = read_id_reg;
                s_axi_rlast_next = read_count_reg == 0;
                if (read_burst_reg != 2'b00) begin
                    read_addr_next = read_addr_reg + (1 << read_size_reg);
                end
                read_count_next = read_count_reg - 1;
                if (read_count_reg > 0) begin
                    read_state_next = READ_STATE_BURST;
                end else begin
                    s_axi_arready_next = 1'b1;
                    read_state_next = READ_STATE_IDLE;
                end
            end else begin
                read_state_next = READ_STATE_BURST;
            end
        end
    endcase
end

always_ff @(posedge clk) begin
    read_state_reg <= read_state_next;

    read_id_reg <= read_id_next;
    read_addr_reg <= read_addr_next;
    read_count_reg <= read_count_next;
    read_size_reg <= read_size_next;
    read_burst_reg <= read_burst_next;

    s_axi_arready_reg <= s_axi_arready_next;
    s_axi_rid_reg <= s_axi_rid_next;
    s_axi_rlast_reg <= s_axi_rlast_next;
    s_axi_rvalid_reg <= s_axi_rvalid_next;

    if (mem_rd_en) begin
        s_axi_rdata_reg <= mem[read_addr_valid];
    end

    if (!s_axi_rvalid_pipe_reg || s_axi_rd.rready) begin
        s_axi_rid_pipe_reg <= s_axi_rid_reg;
        s_axi_rdata_pipe_reg <= s_axi_rdata_reg;
        s_axi_rlast_pipe_reg <= s_axi_rlast_reg;
        s_axi_rvalid_pipe_reg <= s_axi_rvalid_reg;
    end

    if (rst) begin
        read_state_reg <= READ_STATE_IDLE;

        s_axi_arready_reg <= 1'b0;
        s_axi_rvalid_reg <= 1'b0;
        s_axi_rvalid_pipe_reg <= 1'b0;
    end
end

endmodule

`resetall
