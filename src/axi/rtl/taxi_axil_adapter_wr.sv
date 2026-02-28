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
 * AXI4 lite width adapter (write)
 */
module taxi_axil_adapter_wr
(
    input  wire logic    clk,
    input  wire logic    rst,

    /*
     * AXI4-Lite slave interface
     */
    taxi_axil_if.wr_slv  s_axil_wr,

    /*
     * AXI4-Lite master interface
     */
    taxi_axil_if.wr_mst  m_axil_wr
);

// extract parameters
localparam S_DATA_W = s_axil_wr.DATA_W;
localparam ADDR_W = s_axil_wr.ADDR_W;
localparam S_STRB_W = s_axil_wr.STRB_W;
localparam logic AWUSER_EN = s_axil_wr.AWUSER_EN && m_axil_wr.AWUSER_EN;
localparam AWUSER_W = s_axil_wr.AWUSER_W;
localparam logic WUSER_EN = s_axil_wr.WUSER_EN && m_axil_wr.WUSER_EN;
localparam WUSER_W = s_axil_wr.WUSER_W;
localparam logic BUSER_EN = s_axil_wr.BUSER_EN && m_axil_wr.BUSER_EN;
localparam BUSER_W = s_axil_wr.BUSER_W;

localparam M_DATA_W = m_axil_wr.DATA_W;
localparam M_STRB_W = m_axil_wr.STRB_W;

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

    assign m_axil_wr.awaddr = s_axil_wr.awaddr;
    assign m_axil_wr.awprot = s_axil_wr.awprot;
    assign m_axil_wr.awuser = AWUSER_EN ? s_axil_wr.awuser : '0;
    assign m_axil_wr.awvalid = s_axil_wr.awvalid;
    assign s_axil_wr.awready = m_axil_wr.awready;

    assign m_axil_wr.wdata = s_axil_wr.wdata;
    assign m_axil_wr.wstrb = s_axil_wr.wstrb;
    assign m_axil_wr.wuser = WUSER_EN ? s_axil_wr.wuser : '0;
    assign m_axil_wr.wvalid = s_axil_wr.wvalid;
    assign s_axil_wr.wready = m_axil_wr.wready;

    assign s_axil_wr.bresp = m_axil_wr.bresp;
    assign s_axil_wr.buser = BUSER_EN ? m_axil_wr.buser : '0;
    assign s_axil_wr.bvalid = m_axil_wr.bvalid;
    assign m_axil_wr.bready = s_axil_wr.bready;

end else if (M_BYTE_LANES > S_BYTE_LANES) begin : upsize
    // output is wider; upsize

    typedef enum logic [0:0] {
        STATE_IDLE,
        STATE_DATA
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic s_axil_awready_reg = 1'b0, s_axil_awready_next;
    logic s_axil_wready_reg = 1'b0, s_axil_wready_next;

    logic [ADDR_W-1:0] m_axil_awaddr_reg = '0, m_axil_awaddr_next;
    logic [2:0] m_axil_awprot_reg = '0, m_axil_awprot_next;
    logic [AWUSER_W-1:0] m_axil_awuser_reg = '0, m_axil_awuser_next;
    logic m_axil_awvalid_reg = 1'b0, m_axil_awvalid_next;
    logic [M_DATA_W-1:0] m_axil_wdata_reg = '0, m_axil_wdata_next;
    logic [M_STRB_W-1:0] m_axil_wstrb_reg = '0, m_axil_wstrb_next;
    logic [WUSER_W-1:0] m_axil_wuser_reg = '0, m_axil_wuser_next;
    logic m_axil_wvalid_reg = 1'b0, m_axil_wvalid_next;

    assign s_axil_wr.awready = s_axil_awready_reg;
    assign s_axil_wr.wready = s_axil_wready_reg;

    assign m_axil_wr.awaddr = m_axil_awaddr_reg;
    assign m_axil_wr.awprot = m_axil_awprot_reg;
    assign m_axil_wr.awuser = AWUSER_EN ? m_axil_awuser_reg : '0;
    assign m_axil_wr.awvalid = m_axil_awvalid_reg;
    assign m_axil_wr.wdata = m_axil_wdata_reg;
    assign m_axil_wr.wstrb = m_axil_wstrb_reg;
    assign m_axil_wr.wuser = WUSER_EN ? m_axil_wuser_reg : '0;
    assign m_axil_wr.wvalid = m_axil_wvalid_reg;

    // B channel passthrough
    assign s_axil_wr.bresp = m_axil_wr.bresp;
    assign s_axil_wr.buser = BUSER_EN ? m_axil_wr.buser : '0;
    assign s_axil_wr.bvalid = m_axil_wr.bvalid;
    assign m_axil_wr.bready = s_axil_wr.bready;

    always_comb begin
        state_next = STATE_IDLE;

        s_axil_awready_next = 1'b0;
        s_axil_wready_next = 1'b0;
        m_axil_awaddr_next = m_axil_awaddr_reg;
        m_axil_awprot_next = m_axil_awprot_reg;
        m_axil_awuser_next = m_axil_awuser_reg;
        m_axil_awvalid_next = m_axil_awvalid_reg && !m_axil_wr.awready;
        m_axil_wdata_next = m_axil_wdata_reg;
        m_axil_wstrb_next = m_axil_wstrb_reg;
        m_axil_wuser_next = m_axil_wuser_reg;
        m_axil_wvalid_next = m_axil_wvalid_reg && !m_axil_wr.wready;

        case (state_reg)
            STATE_IDLE: begin
                s_axil_awready_next = !m_axil_wr.awvalid;

                if (s_axil_wr.awready && s_axil_wr.awvalid) begin
                    s_axil_awready_next = 1'b0;
                    m_axil_awaddr_next = s_axil_wr.awaddr;
                    m_axil_awprot_next = s_axil_wr.awprot;
                    m_axil_awuser_next = s_axil_wr.awuser;
                    m_axil_awvalid_next = 1'b1;
                    s_axil_wready_next = !m_axil_wr.wvalid;
                    state_next = STATE_DATA;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                s_axil_wready_next = !m_axil_wr.wvalid;

                if (s_axil_wr.wready && s_axil_wr.wvalid) begin
                    s_axil_wready_next = 1'b0;
                    m_axil_wdata_next = {(M_BYTE_LANES/S_BYTE_LANES){s_axil_wr.wdata}};
                    m_axil_wstrb_next = '0;
                    m_axil_wstrb_next[m_axil_awaddr_reg[M_ADDR_BIT_OFFSET - 1:S_ADDR_BIT_OFFSET] * S_STRB_W +: S_STRB_W] = s_axil_wr.wstrb;
                    m_axil_wuser_next = s_axil_wr.wuser;
                    m_axil_wvalid_next = 1'b1;
                    s_axil_awready_next = !m_axil_wr.awvalid;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_DATA;
                end
            end
            default: begin
                state_next = STATE_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        state_reg <= state_next;

        s_axil_awready_reg <= s_axil_awready_next;
        s_axil_wready_reg <= s_axil_wready_next;

        m_axil_awaddr_reg <= m_axil_awaddr_next;
        m_axil_awprot_reg <= m_axil_awprot_next;
        m_axil_awuser_reg <= m_axil_awuser_next;
        m_axil_awvalid_reg <= m_axil_awvalid_next;
        m_axil_wdata_reg <= m_axil_wdata_next;
        m_axil_wstrb_reg <= m_axil_wstrb_next;
        m_axil_wuser_reg <= m_axil_wuser_next;
        m_axil_wvalid_reg <= m_axil_wvalid_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axil_awready_reg <= 1'b0;
            s_axil_wready_reg <= 1'b0;

            m_axil_awvalid_reg <= 1'b0;
            m_axil_wvalid_reg <= 1'b0;
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

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_DATA,
        STATE_RESP
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic [DATA_W-1:0] data_reg = '0, data_next;
    logic [STRB_W-1:0] strb_reg = '0, strb_next;

    logic [SEG_COUNT_W-1:0] current_seg_reg = 0, current_seg_next;

    logic s_axil_awready_reg = 1'b0, s_axil_awready_next;
    logic s_axil_wready_reg = 1'b0, s_axil_wready_next;
    logic [1:0] s_axil_bresp_reg = '0, s_axil_bresp_next;
    logic [BUSER_W-1:0] s_axil_buser_reg = '0, s_axil_buser_next;
    logic s_axil_bvalid_reg = 1'b0, s_axil_bvalid_next;

    logic [ADDR_W-1:0] m_axil_awaddr_reg = '0, m_axil_awaddr_next;
    logic [2:0] m_axil_awprot_reg = '0, m_axil_awprot_next;
    logic [AWUSER_W-1:0] m_axil_awuser_reg = '0, m_axil_awuser_next;
    logic m_axil_awvalid_reg = 1'b0, m_axil_awvalid_next;
    logic [M_DATA_W-1:0] m_axil_wdata_reg = '0, m_axil_wdata_next;
    logic [M_STRB_W-1:0] m_axil_wstrb_reg = '0, m_axil_wstrb_next;
    logic [WUSER_W-1:0] m_axil_wuser_reg = '0, m_axil_wuser_next;
    logic m_axil_wvalid_reg = 1'b0, m_axil_wvalid_next;
    logic m_axil_bready_reg = 1'b0, m_axil_bready_next;

    assign s_axil_wr.awready = s_axil_awready_reg;
    assign s_axil_wr.wready = s_axil_wready_reg;
    assign s_axil_wr.bresp = s_axil_bresp_reg;
    assign s_axil_wr.buser = BUSER_EN ? s_axil_buser_reg : '0;
    assign s_axil_wr.bvalid = s_axil_bvalid_reg;

    assign m_axil_wr.awaddr = m_axil_awaddr_reg;
    assign m_axil_wr.awprot = m_axil_awprot_reg;
    assign m_axil_wr.awuser = AWUSER_EN ? m_axil_awuser_reg : '0;
    assign m_axil_wr.awvalid = m_axil_awvalid_reg;
    assign m_axil_wr.wdata = m_axil_wdata_reg;
    assign m_axil_wr.wstrb = m_axil_wstrb_reg;
    assign m_axil_wr.wuser = WUSER_EN ? m_axil_wuser_reg : '0;
    assign m_axil_wr.wvalid = m_axil_wvalid_reg;
    assign m_axil_wr.bready = m_axil_bready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        data_next = data_reg;
        strb_next = strb_reg;

        current_seg_next = current_seg_reg;

        s_axil_awready_next = 1'b0;
        s_axil_wready_next = 1'b0;
        s_axil_bresp_next = s_axil_bresp_reg;
        s_axil_buser_next = s_axil_buser_reg;
        s_axil_bvalid_next = s_axil_bvalid_reg && !s_axil_wr.bready;
        m_axil_awaddr_next = m_axil_awaddr_reg;
        m_axil_awprot_next = m_axil_awprot_reg;
        m_axil_awuser_next = m_axil_awuser_reg;
        m_axil_awvalid_next = m_axil_awvalid_reg && !m_axil_wr.awready;
        m_axil_wdata_next = m_axil_wdata_reg;
        m_axil_wstrb_next = m_axil_wstrb_reg;
        m_axil_wuser_next = m_axil_wuser_reg;
        m_axil_wvalid_next = m_axil_wvalid_reg && !m_axil_wr.wready;
        m_axil_bready_next = 1'b0;

        // master output is narrower; may need several cycles
        case (state_reg)
            STATE_IDLE: begin
                s_axil_awready_next = !m_axil_wr.awvalid;

                current_seg_next = s_axil_wr.awaddr[M_ADDR_BIT_OFFSET +: SEG_COUNT_W];
                s_axil_bresp_next = 2'd0;

                if (s_axil_wr.awready && s_axil_wr.awvalid) begin
                    s_axil_awready_next = 1'b0;
                    m_axil_awaddr_next = s_axil_wr.awaddr;
                    m_axil_awprot_next = s_axil_wr.awprot;
                    m_axil_awuser_next = s_axil_wr.awuser;
                    m_axil_awvalid_next = 1'b1;
                    s_axil_wready_next = !m_axil_wr.wvalid;
                    state_next = STATE_DATA;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                s_axil_wready_next = !m_axil_wr.wvalid;

                if (s_axil_wr.wready && s_axil_wr.wvalid) begin
                    s_axil_wready_next = 1'b0;
                    data_next = s_axil_wr.wdata;
                    strb_next = s_axil_wr.wstrb;
                    m_axil_wdata_next = data_next[current_seg_reg*SEG_DATA_W +: SEG_DATA_W];
                    m_axil_wstrb_next = strb_next[current_seg_reg*SEG_STRB_W +: SEG_STRB_W];
                    m_axil_wuser_next = s_axil_wr.wuser;
                    m_axil_wvalid_next = 1'b1;
                    m_axil_bready_next = !s_axil_wr.bvalid;
                    current_seg_next = current_seg_reg + 1;
                    state_next = STATE_RESP;
                end else begin
                    state_next = STATE_DATA;
                end
            end
            STATE_RESP: begin
                m_axil_bready_next = !s_axil_wr.bvalid;

                if (m_axil_wr.bready && m_axil_wr.bvalid) begin
                    m_axil_bready_next = 1'b0;
                    m_axil_awaddr_next = (m_axil_awaddr_reg & M_ADDR_MASK) + SEG_STRB_W;
                    m_axil_wdata_next = data_next[current_seg_reg*SEG_DATA_W +: SEG_DATA_W];
                    m_axil_wstrb_next = strb_next[current_seg_reg*SEG_STRB_W +: SEG_STRB_W];
                    s_axil_buser_next = m_axil_wr.buser;
                    current_seg_next = current_seg_reg + 1;
                    if (m_axil.bresp != 0) begin
                        s_axil_bresp_next = m_axil_wr.bresp;
                    end
                    if (current_seg_reg == 0) begin
                        s_axil_bvalid_next = 1'b1;
                        s_axil_awready_next = !m_axil_wr.awvalid;
                        state_next = STATE_IDLE;
                    end else begin
                        m_axil_awvalid_next = 1'b1;
                        m_axil_wvalid_next = 1'b1;
                        state_next = STATE_RESP;
                    end
                end else begin
                    state_next = STATE_RESP;
                end
            end
            default: begin
                state_next = STATE_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        state_reg <= state_next;

        data_reg <= data_next;
        strb_reg <= strb_next;

        current_seg_reg <= current_seg_next;

        s_axil_awready_reg <= s_axil_awready_next;
        s_axil_wready_reg <= s_axil_wready_next;
        s_axil_bresp_reg <= s_axil_bresp_next;
        s_axil_buser_reg <= s_axil_buser_next;
        s_axil_bvalid_reg <= s_axil_bvalid_next;

        m_axil_awaddr_reg <= m_axil_awaddr_next;
        m_axil_awprot_reg <= m_axil_awprot_next;
        m_axil_awuser_reg <= m_axil_awuser_next;
        m_axil_awvalid_reg <= m_axil_awvalid_next;
        m_axil_wdata_reg <= m_axil_wdata_next;
        m_axil_wstrb_reg <= m_axil_wstrb_next;
        m_axil_wuser_reg <= m_axil_wuser_next;
        m_axil_wvalid_reg <= m_axil_wvalid_next;
        m_axil_bready_reg <= m_axil_bready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axil_awready_reg <= 1'b0;
            s_axil_wready_reg <= 1'b0;
            s_axil_bvalid_reg <= 1'b0;

            m_axil_awvalid_reg <= 1'b0;
            m_axil_wvalid_reg <= 1'b0;
            m_axil_bready_reg <= 1'b0;
        end
    end

end

endmodule

`resetall
