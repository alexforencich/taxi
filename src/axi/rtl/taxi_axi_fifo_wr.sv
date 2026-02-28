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
 * AXI4 FIFO (write)
 */
module taxi_axi_fifo_wr #
(
    // Write data FIFO depth (cycles)
    parameter FIFO_DEPTH = 32,
    // Hold write address until write data in FIFO, if possible
    parameter logic FIFO_DELAY = 1'b0
)
(
    input  wire logic   clk,
    input  wire logic   rst,

    /*
     * AXI4 slave interface
     */
    taxi_axi_if.wr_slv  s_axi_wr,

    /*
     * AXI4 master interface
     */
    taxi_axi_if.wr_mst  m_axi_wr
);

// extract parameters
localparam DATA_W = s_axi_wr.DATA_W;
localparam ADDR_W = s_axi_wr.ADDR_W;
localparam STRB_W = s_axi_wr.STRB_W;
localparam ID_W = s_axi_wr.ID_W;
localparam logic AWUSER_EN = s_axi_wr.AWUSER_EN && m_axi_wr.AWUSER_EN;
localparam AWUSER_W = s_axi_wr.AWUSER_W;
localparam logic WUSER_EN = s_axi_wr.WUSER_EN && m_axi_wr.WUSER_EN;
localparam WUSER_W = s_axi_wr.WUSER_W;
localparam logic BUSER_EN = s_axi_wr.BUSER_EN && m_axi_wr.BUSER_EN;
localparam BUSER_W = s_axi_wr.BUSER_W;

localparam STRB_OFFSET  = DATA_W;
localparam LAST_OFFSET  = STRB_OFFSET + STRB_W;
localparam WUSER_OFFSET = LAST_OFFSET + 1;
localparam WWIDTH       = WUSER_OFFSET + (WUSER_EN ? WUSER_W : 0);

localparam FIFO_AW = $clog2(FIFO_DEPTH);

if (m_axi_wr.DATA_W != DATA_W)
    $fatal(0, "Error: Interface DATA_W parameter mismatch (instance %m)");

if (m_axi_wr.STRB_W != STRB_W)
    $fatal(0, "Error: Interface STRB_W parameter mismatch (instance %m)");

logic [FIFO_AW:0] wr_ptr_reg = '0, wr_ptr_next;
logic [FIFO_AW:0] wr_addr_reg = '0;
logic [FIFO_AW:0] rd_ptr_reg = '0, rd_ptr_next;
logic [FIFO_AW:0] rd_addr_reg = '0;

(* ramstyle = "no_rw_check" *)
logic [WWIDTH-1:0] mem[2**FIFO_AW];
logic [WWIDTH-1:0] mem_read_data_reg;
logic mem_read_data_valid_reg = 1'b0, mem_read_data_valid_next;

wire [WWIDTH-1:0] s_axi_w;

logic [WWIDTH-1:0] m_axi_w_reg;
logic m_axi_wvalid_reg = 1'b0, m_axi_wvalid_next;

// full when first MSB different but rest same
wire full = ((wr_ptr_reg[FIFO_AW] != rd_ptr_reg[FIFO_AW]) &&
             (wr_ptr_reg[FIFO_AW-1:0] == rd_ptr_reg[FIFO_AW-1:0]));
// empty when pointers match exactly
wire empty = wr_ptr_reg == rd_ptr_reg;

wire hold;

// control signals
logic write;
logic read;
logic store_output;

assign s_axi_wr.wready = !full && !hold;
assign s_axi_w[DATA_W-1:0] = s_axi_wr.wdata;
assign s_axi_w[STRB_OFFSET +: STRB_W] = s_axi_wr.wstrb;
assign s_axi_w[LAST_OFFSET] = s_axi_wr.wlast;
if (WUSER_EN) assign s_axi_w[WUSER_OFFSET +: WUSER_W] = s_axi_wr.wuser;

if (FIFO_DELAY) begin
    // store AW channel value until W channel burst is stored in FIFO or FIFO is full

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_TRANSFER_IN,
        STATE_TRANSFER_OUT
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic hold_reg = 1'b1, hold_next;
    logic [8:0] count_reg = 9'd0, count_next;

    logic [ID_W-1:0] m_axi_awid_reg = '0, m_axi_awid_next;
    logic [ADDR_W-1:0] m_axi_awaddr_reg = '0, m_axi_awaddr_next;
    logic [7:0] m_axi_awlen_reg = '0, m_axi_awlen_next;
    logic [2:0] m_axi_awsize_reg = '0, m_axi_awsize_next;
    logic [1:0] m_axi_awburst_reg = '0, m_axi_awburst_next;
    logic m_axi_awlock_reg = '0, m_axi_awlock_next;
    logic [3:0] m_axi_awcache_reg = '0, m_axi_awcache_next;
    logic [2:0] m_axi_awprot_reg = '0, m_axi_awprot_next;
    logic [3:0] m_axi_awqos_reg = '0, m_axi_awqos_next;
    logic [3:0] m_axi_awregion_reg = '0, m_axi_awregion_next;
    logic [AWUSER_W-1:0] m_axi_awuser_reg = '0, m_axi_awuser_next;
    logic m_axi_awvalid_reg = 1'b0, m_axi_awvalid_next;

    logic s_axi_awready_reg = 1'b0, s_axi_awready_next;

    assign m_axi_wr.awid = m_axi_awid_reg;
    assign m_axi_wr.awaddr = m_axi_awaddr_reg;
    assign m_axi_wr.awlen = m_axi_awlen_reg;
    assign m_axi_wr.awsize = m_axi_awsize_reg;
    assign m_axi_wr.awburst = m_axi_awburst_reg;
    assign m_axi_wr.awlock = m_axi_awlock_reg;
    assign m_axi_wr.awcache = m_axi_awcache_reg;
    assign m_axi_wr.awprot = m_axi_awprot_reg;
    assign m_axi_wr.awqos = m_axi_awqos_reg;
    assign m_axi_wr.awregion = m_axi_awregion_reg;
    assign m_axi_wr.awuser = AWUSER_EN ? m_axi_awuser_reg : '0;
    assign m_axi_wr.awvalid = m_axi_awvalid_reg;

    assign s_axi_wr.awready = s_axi_awready_reg;

    assign hold = hold_reg;

    always_comb begin
        state_next = STATE_IDLE;

        hold_next = hold_reg;
        count_next = count_reg;

        m_axi_awid_next = m_axi_awid_reg;
        m_axi_awaddr_next = m_axi_awaddr_reg;
        m_axi_awlen_next = m_axi_awlen_reg;
        m_axi_awsize_next = m_axi_awsize_reg;
        m_axi_awburst_next = m_axi_awburst_reg;
        m_axi_awlock_next = m_axi_awlock_reg;
        m_axi_awcache_next = m_axi_awcache_reg;
        m_axi_awprot_next = m_axi_awprot_reg;
        m_axi_awqos_next = m_axi_awqos_reg;
        m_axi_awregion_next = m_axi_awregion_reg;
        m_axi_awuser_next = m_axi_awuser_reg;
        m_axi_awvalid_next = m_axi_awvalid_reg && !m_axi_wr.awready;
        s_axi_awready_next = s_axi_awready_reg;

        case (state_reg)
            STATE_IDLE: begin
                s_axi_awready_next = !m_axi_wr.awvalid || m_axi_wr.awready;
                hold_next = 1'b1;

                if (s_axi_wr.awready && s_axi_wr.awvalid) begin
                    s_axi_awready_next = 1'b0;

                    m_axi_awid_next = s_axi_wr.awid;
                    m_axi_awaddr_next = s_axi_wr.awaddr;
                    m_axi_awlen_next = s_axi_wr.awlen;
                    m_axi_awsize_next = s_axi_wr.awsize;
                    m_axi_awburst_next = s_axi_wr.awburst;
                    m_axi_awlock_next = s_axi_wr.awlock;
                    m_axi_awcache_next = s_axi_wr.awcache;
                    m_axi_awprot_next = s_axi_wr.awprot;
                    m_axi_awqos_next = s_axi_wr.awqos;
                    m_axi_awregion_next = s_axi_wr.awregion;
                    m_axi_awuser_next = s_axi_wr.awuser;

                    hold_next = 1'b0;
                    count_next = 0;
                    state_next = STATE_TRANSFER_IN;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_TRANSFER_IN: begin
                s_axi_awready_next = 1'b0;
                hold_next = 1'b0;

                if (s_axi_wr.wready && s_axi_wr.wvalid) begin
                    count_next = count_reg + 1;
                    if (s_axi_wr.wlast) begin
                        m_axi_awvalid_next = 1'b1;
                        hold_next = 1'b1;
                        state_next = STATE_IDLE;
                    end else if (FIFO_AW < 8 && count_next == 2**FIFO_AW) begin
                        m_axi_awvalid_next = 1'b1;
                        state_next = STATE_TRANSFER_OUT;
                    end else begin
                        state_next = STATE_TRANSFER_IN;
                    end
                end else begin
                    state_next = STATE_TRANSFER_IN;
                end
            end
            STATE_TRANSFER_OUT: begin
                s_axi_awready_next = 1'b0;
                hold_next = 1'b0;

                if (s_axi.wready && s_axi.wvalid) begin
                    if (s_axi.wlast) begin
                        hold_next = 1'b1;
                        state_next = STATE_IDLE;
                    end else begin
                        state_next = STATE_TRANSFER_OUT;
                    end
                end else begin
                    state_next = STATE_TRANSFER_OUT;
                end
            end
            default: begin
                state_next = STATE_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        state_reg <= state_next;

        hold_reg <= hold_next;
        count_reg <= count_next;

        m_axi_awid_reg <= m_axi_awid_next;
        m_axi_awaddr_reg <= m_axi_awaddr_next;
        m_axi_awlen_reg <= m_axi_awlen_next;
        m_axi_awsize_reg <= m_axi_awsize_next;
        m_axi_awburst_reg <= m_axi_awburst_next;
        m_axi_awlock_reg <= m_axi_awlock_next;
        m_axi_awcache_reg <= m_axi_awcache_next;
        m_axi_awprot_reg <= m_axi_awprot_next;
        m_axi_awqos_reg <= m_axi_awqos_next;
        m_axi_awregion_reg <= m_axi_awregion_next;
        m_axi_awuser_reg <= m_axi_awuser_next;
        m_axi_awvalid_reg <= m_axi_awvalid_next;
        s_axi_awready_reg <= s_axi_awready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;
            hold_reg <= 1'b1;
            m_axi_awvalid_reg <= 1'b0;
            s_axi_awready_reg <= 1'b0;
        end
    end

end else begin

    // bypass AW channel
    assign m_axi_wr.awid = s_axi_wr.awid;
    assign m_axi_wr.awaddr = s_axi_wr.awaddr;
    assign m_axi_wr.awlen = s_axi_wr.awlen;
    assign m_axi_wr.awsize = s_axi_wr.awsize;
    assign m_axi_wr.awburst = s_axi_wr.awburst;
    assign m_axi_wr.awlock = s_axi_wr.awlock;
    assign m_axi_wr.awcache = s_axi_wr.awcache;
    assign m_axi_wr.awprot = s_axi_wr.awprot;
    assign m_axi_wr.awqos = s_axi_wr.awqos;
    assign m_axi_wr.awregion = s_axi_wr.awregion;
    assign m_axi_wr.awuser = AWUSER_EN ? s_axi_wr.awuser : '0;
    assign m_axi_wr.awvalid = s_axi_wr.awvalid;
    assign s_axi_wr.awready = m_axi_wr.awready;

    assign hold = 1'b0;

end

// bypass B channel
assign s_axi_wr.bid = m_axi_wr.bid;
assign s_axi_wr.bresp = m_axi_wr.bresp;
if (BUSER_EN) begin
    assign s_axi_wr.buser = m_axi_wr.buser;
end else begin
    assign s_axi_wr.buser = '0;
end
assign s_axi_wr.bvalid = m_axi_wr.bvalid;
assign m_axi_wr.bready = s_axi_wr.bready;

assign m_axi_wr.wvalid = m_axi_wvalid_reg;

assign m_axi_wr.wdata = m_axi_w_reg[DATA_W-1:0];
assign m_axi_wr.wstrb = m_axi_w_reg[STRB_OFFSET +: STRB_W];
assign m_axi_wr.wlast = m_axi_w_reg[LAST_OFFSET];
if (WUSER_EN) begin
    assign m_axi_wr.wuser = m_axi_w_reg[WUSER_OFFSET +: WUSER_W];
end else begin
    assign m_axi_wr.wuser = '0;
end

// Write logic
always_comb begin
    write = 1'b0;

    wr_ptr_next = wr_ptr_reg;

    if (s_axi_wr.wvalid) begin
        // input data valid
        if (!full && !hold) begin
            // not full, perform write
            write = 1'b1;
            wr_ptr_next = wr_ptr_reg + 1;
        end
    end
end

always_ff @(posedge clk) begin
    wr_ptr_reg <= wr_ptr_next;
    wr_addr_reg <= wr_ptr_next;

    if (write) begin
        mem[wr_addr_reg[FIFO_AW-1:0]] <= s_axi_w;
    end

    if (rst) begin
        wr_ptr_reg <= '0;
    end
end

// Read logic
always_comb begin
    read = 1'b0;

    rd_ptr_next = rd_ptr_reg;

    mem_read_data_valid_next = mem_read_data_valid_reg;

    if (store_output || !mem_read_data_valid_reg) begin
        // output data not valid OR currently being transferred
        if (!empty) begin
            // not empty, perform read
            read = 1'b1;
            mem_read_data_valid_next = 1'b1;
            rd_ptr_next = rd_ptr_reg + 1;
        end else begin
            // empty, invalidate
            mem_read_data_valid_next = 1'b0;
        end
    end
end

always_ff @(posedge clk) begin
    rd_ptr_reg <= rd_ptr_next;
    rd_addr_reg <= rd_ptr_next;

    mem_read_data_valid_reg <= mem_read_data_valid_next;

    if (read) begin
        mem_read_data_reg <= mem[rd_addr_reg[FIFO_AW-1:0]];
    end

    if (rst) begin
        rd_ptr_reg <= '0;
        mem_read_data_valid_reg <= 1'b0;
    end
end

// Output register
always_comb begin
    store_output = 1'b0;

    m_axi_wvalid_next = m_axi_wvalid_reg;

    if (m_axi_wr.wready || !m_axi_wr.wvalid) begin
        store_output = 1'b1;
        m_axi_wvalid_next = mem_read_data_valid_reg;
    end
end

always_ff @(posedge clk) begin
    m_axi_wvalid_reg <= m_axi_wvalid_next;

    if (store_output) begin
        m_axi_w_reg <= mem_read_data_reg;
    end

    if (rst) begin
        m_axi_wvalid_reg <= 1'b0;
    end
end

endmodule

`resetall
