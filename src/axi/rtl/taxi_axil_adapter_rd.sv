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
 * AXI4 lite width adapter (read)
 */
module taxi_axil_adapter_rd
(
    input  wire logic    clk,
    input  wire logic    rst,

    /*
     * AXI4-Lite slave interface
     */
    taxi_axil_if.rd_slv  s_axil_rd,

    /*
     * AXI4-Lite master interface
     */
    taxi_axil_if.rd_mst  m_axil_rd
);

// extract parameters
localparam S_DATA_W = s_axil_rd.DATA_W;
localparam ADDR_W = s_axil_rd.ADDR_W;
localparam S_STRB_W = s_axil_rd.STRB_W;
localparam logic ARUSER_EN = s_axil_rd.ARUSER_EN && m_axil_rd.ARUSER_EN;
localparam ARUSER_W = s_axil_rd.ARUSER_W;
localparam logic RUSER_EN = s_axil_rd.RUSER_EN && m_axil_rd.RUSER_EN;
localparam RUSER_W = s_axil_rd.RUSER_W;

localparam M_DATA_W = m_axil_rd.DATA_W;
localparam M_STRB_W = m_axil_rd.STRB_W;

localparam S_ADDR_BIT_OFFSET = $clog2(S_STRB_W);
localparam M_ADDR_BIT_OFFSET = $clog2(M_STRB_W);
localparam S_BYTE_LANES = S_STRB_W;
localparam M_BYTE_LANES = M_STRB_W;
localparam S_BYTE_W = S_DATA_W/S_BYTE_LANES;
localparam M_BYTE_W = M_DATA_W/M_BYTE_LANES;
localparam S_ADDR_MASK = {ADDR_W{1'b1}} << S_ADDR_BIT_OFFSET;
localparam M_ADDR_MASK = {ADDR_W{1'b1}} << M_ADDR_BIT_OFFSET;

// check configuration
if (S_BYTE_W * S_STRB_W != S_DATA_W)
    $fatal(0, "Error: AXI slave interface data width not evenly divisible (instance %m)");

if (M_BYTE_W * M_STRB_W != M_DATA_W)
    $fatal(0, "Error: AXI master interface data width not evenly divisible (instance %m)");

if (S_BYTE_W != M_BYTE_W)
    $fatal(0, "Error: byte size mismatch (instance %m)");

if (2**$clog2(S_BYTE_LANES) != S_BYTE_LANES)
    $fatal(0, "Error: AXI slave interface byte lane count must be even power of two (instance %m)");

if (2**$clog2(M_BYTE_LANES) != M_BYTE_LANES)
    $fatal(0, "Error: AXI master interface byte lane count must be even power of two (instance %m)");

if (M_BYTE_LANES == S_BYTE_LANES) begin : bypass
    // same width; bypass

    assign m_axil_rd.araddr = s_axil_rd.araddr;
    assign m_axil_rd.arprot = s_axil_rd.arprot;
    assign m_axil_rd.aruser = ARUSER_EN ? s_axil_rd.aruser : '0;
    assign m_axil_rd.arvalid = s_axil_rd.arvalid;
    assign s_axil_rd.arready = m_axil_rd.arready;

    assign s_axil_rd.rdata = m_axil_rd.rdata;
    assign s_axil_rd.rresp = m_axil_rd.rresp;
    assign s_axil_rd.ruser = RUSER_EN ? m_axil_rd.ruser : '0;
    assign s_axil_rd.rvalid = m_axil_rd.rvalid;
    assign m_axil_rd.rready = s_axil_rd.rready;

end else if (M_BYTE_LANES > S_BYTE_LANES) begin : upsize
    // output is wider; upsize

    typedef enum logic [0:0] {
        STATE_IDLE,
        STATE_DATA
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic s_axil_arready_reg = 1'b0, s_axil_arready_next;
    logic [S_DATA_W-1:0] s_axil_rdata_reg = '0, s_axil_rdata_next;
    logic [1:0] s_axil_rresp_reg = '0, s_axil_rresp_next;
    logic [RUSER_W-1:0] s_axil_ruser_reg = '0, s_axil_ruser_next;
    logic s_axil_rvalid_reg = 1'b0, s_axil_rvalid_next;

    logic [ADDR_W-1:0] m_axil_araddr_reg = '0, m_axil_araddr_next;
    logic [2:0] m_axil_arprot_reg = '0, m_axil_arprot_next;
    logic [ARUSER_W-1:0] m_axil_aruser_reg = '0, m_axil_aruser_next;
    logic m_axil_arvalid_reg = 1'b0, m_axil_arvalid_next;
    logic m_axil_rready_reg = 1'b0, m_axil_rready_next;

    assign s_axil_rd.arready = s_axil_arready_reg;
    assign s_axil_rd.rdata = s_axil_rdata_reg;
    assign s_axil_rd.rresp = s_axil_rresp_reg;
    assign s_axil_rd.ruser = RUSER_EN ? s_axil_ruser_reg : '0;
    assign s_axil_rd.rvalid = s_axil_rvalid_reg;

    assign m_axil_rd.araddr = m_axil_araddr_reg;
    assign m_axil_rd.arprot = m_axil_arprot_reg;
    assign m_axil_rd.aruser = ARUSER_EN ? m_axil_aruser_reg : '0;
    assign m_axil_rd.arvalid = m_axil_arvalid_reg;
    assign m_axil_rd.rready = m_axil_rready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        s_axil_arready_next = 1'b0;
        s_axil_rdata_next = s_axil_rdata_reg;
        s_axil_rresp_next = s_axil_rresp_reg;
        s_axil_ruser_next = s_axil_ruser_reg;
        s_axil_rvalid_next = s_axil_rvalid_reg && !s_axil_rd.rready;
        m_axil_araddr_next = m_axil_araddr_reg;
        m_axil_arprot_next = m_axil_arprot_reg;
        m_axil_aruser_next = m_axil_aruser_reg;
        m_axil_arvalid_next = m_axil_arvalid_reg && !m_axil_rd.arready;
        m_axil_rready_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                s_axil_arready_next = !m_axil_rd.arvalid;

                if (s_axil_rd.arready && s_axil_rd.arvalid) begin
                    s_axil_arready_next = 1'b0;
                    m_axil_araddr_next = s_axil_rd.araddr;
                    m_axil_arprot_next = s_axil_rd.arprot;
                    m_axil_aruser_next = s_axil_rd.aruser;
                    m_axil_arvalid_next = 1'b1;
                    m_axil_rready_next = !m_axil_rd.rvalid;
                    state_next = STATE_DATA;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                m_axil_rready_next = !s_axil_rd.rvalid;

                if (m_axil_rd.rready && m_axil_rd.rvalid) begin
                    m_axil_rready_next = 1'b0;
                    s_axil_rdata_next = m_axil_rd.rdata[m_axil_araddr_reg[M_ADDR_BIT_OFFSET - 1:S_ADDR_BIT_OFFSET] * S_DATA_W +: S_DATA_W];
                    s_axil_rresp_next = m_axil_rd.rresp;
                    s_axil_ruser_next = m_axil_rd.ruser;
                    s_axil_rvalid_next = 1'b1;
                    s_axil_arready_next = !m_axil_rd.arvalid;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_DATA;
                end
            end
        endcase
    end

    always_ff @(posedge clk) begin
        state_reg <= state_next;

        s_axil_arready_reg <= s_axil_arready_next;
        s_axil_rdata_reg <= s_axil_rdata_next;
        s_axil_rresp_reg <= s_axil_rresp_next;
        s_axil_ruser_reg <= s_axil_ruser_next;
        s_axil_rvalid_reg <= s_axil_rvalid_next;

        m_axil_araddr_reg <= m_axil_araddr_next;
        m_axil_arprot_reg <= m_axil_arprot_next;
        m_axil_aruser_reg <= m_axil_aruser_next;
        m_axil_arvalid_reg <= m_axil_arvalid_next;
        m_axil_rready_reg <= m_axil_rready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axil_arready_reg <= 1'b0;
            s_axil_rvalid_reg <= 1'b0;

            m_axil_arvalid_reg <= 1'b0;
            m_axil_rready_reg <= 1'b0;
        end
    end

end else begin : downsize
    // output is narrower; downsize

    // output bus is wider
    localparam DATA_W = S_DATA_W;
    localparam STRB_W = S_STRB_W;
    // required number of segments in wider bus
    localparam SEG_COUNT = S_BYTE_LANES / M_BYTE_LANES;
    localparam SEG_COUNT_W = $clog2(SEG_COUNT);
    // data width and keep width per segment
    localparam SEG_DATA_W = DATA_W / SEG_COUNT;
    localparam SEG_STRB_W = STRB_W / SEG_COUNT;

    typedef enum logic [0:0] {
        STATE_IDLE,
        STATE_DATA
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic [SEG_COUNT_W-1:0] current_seg_reg = '0, current_seg_next;

    logic s_axil_arready_reg = 1'b0, s_axil_arready_next;
    logic [S_DATA_W-1:0] s_axil_rdata_reg = '0, s_axil_rdata_next;
    logic [1:0] s_axil_rresp_reg = '0, s_axil_rresp_next;
    logic [RUSER_W-1:0] s_axil_ruser_reg = '0, s_axil_ruser_next;
    logic s_axil_rvalid_reg = 1'b0, s_axil_rvalid_next;

    logic [ADDR_W-1:0] m_axil_araddr_reg = '0, m_axil_araddr_next;
    logic [2:0] m_axil_arprot_reg = '0, m_axil_arprot_next;
    logic [ARUSER_W-1:0] m_axil_aruser_reg = '0, m_axil_aruser_next;
    logic m_axil_arvalid_reg = 1'b0, m_axil_arvalid_next;
    logic m_axil_rready_reg = 1'b0, m_axil_rready_next;

    assign s_axil_rd.arready = s_axil_arready_reg;
    assign s_axil_rd.rdata = s_axil_rdata_reg;
    assign s_axil_rd.rresp = s_axil_rresp_reg;
    assign s_axil_rd.ruser = RUSER_EN ? s_axil_ruser_reg : '0;
    assign s_axil_rd.rvalid = s_axil_rvalid_reg;

    assign m_axil_rd.araddr = m_axil_araddr_reg;
    assign m_axil_rd.arprot = m_axil_arprot_reg;
    assign m_axil_rd.aruser = ARUSER_EN ? m_axil_aruser_reg : '0;
    assign m_axil_rd.arvalid = m_axil_arvalid_reg;
    assign m_axil_rd.rready = m_axil_rready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        current_seg_next = current_seg_reg;

        s_axil_arready_next = 1'b0;
        s_axil_rdata_next = s_axil_rdata_reg;
        s_axil_rresp_next = s_axil_rresp_reg;
        s_axil_ruser_next = s_axil_ruser_reg;
        s_axil_rvalid_next = s_axil_rvalid_reg && !s_axil_rd.rready;
        m_axil_araddr_next = m_axil_araddr_reg;
        m_axil_arprot_next = m_axil_arprot_reg;
        m_axil_aruser_next = m_axil_aruser_reg;
        m_axil_arvalid_next = m_axil_arvalid_reg && !m_axil_rd.arready;
        m_axil_rready_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                s_axil_arready_next = !m_axil_rd.arvalid;

                current_seg_next = s_axil_rd.araddr[M_ADDR_BIT_OFFSET +: SEG_COUNT_W];
                s_axil_rresp_next = 2'd0;

                if (s_axil_rd.arready && s_axil_rd.arvalid) begin
                    s_axil_arready_next = 1'b0;
                    m_axil_araddr_next = s_axil_rd.araddr;
                    m_axil_arprot_next = s_axil_rd.arprot;
                    m_axil_aruser_next = s_axil_rd.aruser;
                    m_axil_arvalid_next = 1'b1;
                    m_axil_rready_next = !m_axil_rd.rvalid;
                    state_next = STATE_DATA;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                m_axil_rready_next = !s_axil_rd.rvalid;

                if (m_axil_rd.rready && m_axil_rd.rvalid) begin
                    m_axil_rready_next = 1'b0;
                    m_axil_araddr_next = (m_axil_araddr_reg & M_ADDR_MASK) + SEG_STRB_W;
                    s_axil_rdata_next[current_seg_reg*SEG_DATA_W +: SEG_DATA_W] = m_axil_rd.rdata;
                    s_axil_ruser_next = m_axil_rd.ruser;
                    current_seg_next = current_seg_reg + 1;
                    if (m_axil.rresp != 0) begin
                        s_axil_rresp_next = m_axil_rd.rresp;
                    end
                    if (current_seg_reg == SEG_COUNT_W'(SEG_COUNT-1)) begin
                        s_axil_rvalid_next = 1'b1;
                        s_axil_arready_next = !m_axil_rd.arvalid;
                        state_next = STATE_IDLE;
                    end else begin
                        m_axil_arvalid_next = 1'b1;
                        state_next = STATE_DATA;
                    end
                end else begin
                    state_next = STATE_DATA;
                end
            end
        endcase
    end

    always_ff @(posedge clk) begin
        state_reg <= state_next;

        current_seg_reg <= current_seg_next;

        s_axil_arready_reg <= s_axil_arready_next;
        s_axil_rdata_reg <= s_axil_rdata_next;
        s_axil_rresp_reg <= s_axil_rresp_next;
        s_axil_ruser_reg <= s_axil_ruser_next;
        s_axil_rvalid_reg <= s_axil_rvalid_next;

        m_axil_araddr_reg <= m_axil_araddr_next;
        m_axil_arprot_reg <= m_axil_arprot_next;
        m_axil_aruser_reg <= m_axil_aruser_next;
        m_axil_arvalid_reg <= m_axil_arvalid_next;
        m_axil_rready_reg <= m_axil_rready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axil_arready_reg <= 1'b0;
            s_axil_rvalid_reg <= 1'b0;

            m_axil_arvalid_reg <= 1'b0;
            m_axil_rready_reg <= 1'b0;
        end
    end

end

endmodule

`resetall
