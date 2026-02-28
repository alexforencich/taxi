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
 * AXI4 lite to AXI4 adapter (read)
 */
module taxi_axil_axi_adapter_rd
(
    input  wire logic    clk,
    input  wire logic    rst,

    /*
     * AXI4-Lite slave interface
     */
    taxi_axil_if.rd_slv  s_axil_rd,

    /*
     * AXI4 master interface
     */
    taxi_axi_if.rd_mst   m_axi_rd
);

// extract parameters
localparam AXIL_DATA_W = s_axil_rd.DATA_W;
localparam ADDR_W = s_axil_rd.ADDR_W;
localparam AXIL_STRB_W = s_axil_rd.STRB_W;
localparam logic ARUSER_EN = s_axil_rd.ARUSER_EN && m_axi_rd.ARUSER_EN;
localparam ARUSER_W = s_axil_rd.ARUSER_W;
localparam logic RUSER_EN = s_axil_rd.RUSER_EN && m_axi_rd.RUSER_EN;
localparam RUSER_W = s_axil_rd.RUSER_W;

localparam AXI_DATA_W = m_axi_rd.DATA_W;
localparam AXI_STRB_W = m_axi_rd.STRB_W;
localparam AXI_BURST_SIZE = $clog2(AXI_STRB_W);

localparam AXIL_ADDR_BIT_OFFSET = $clog2(AXIL_STRB_W);
localparam AXI_ADDR_BIT_OFFSET = $clog2(AXI_STRB_W);
localparam AXIL_BYTE_LANES = AXIL_STRB_W;
localparam AXI_BYTE_LANES = AXI_STRB_W;
localparam AXIL_BYTE_W = AXIL_DATA_W/AXIL_BYTE_LANES;
localparam AXI_BYTE_W = AXI_DATA_W/AXI_BYTE_LANES;
localparam AXIL_ADDR_MASK = {ADDR_W{1'b1}} << AXIL_ADDR_BIT_OFFSET;
localparam AXI_ADDR_MASK = {ADDR_W{1'b1}} << AXI_ADDR_BIT_OFFSET;

// check configuration
if (AXIL_BYTE_W * AXIL_STRB_W != AXIL_DATA_W)
    $fatal(0, "Error: AXI slave interface data width not evenly divisible (instance %m)");

if (AXI_BYTE_W * AXI_STRB_W != AXI_DATA_W)
    $fatal(0, "Error: AXI master interface data width not evenly divisible (instance %m)");

if (AXIL_BYTE_W != AXI_BYTE_W)
    $fatal(0, "Error: byte size mismatch (instance %m)");

if (2**$clog2(AXIL_BYTE_LANES) != AXIL_BYTE_LANES)
    $fatal(0, "Error: AXI slave interface byte lane count must be even power of two (instance %m)");

if (2**$clog2(AXI_BYTE_LANES) != AXI_BYTE_LANES)
    $fatal(0, "Error: AXI master interface byte lane count must be even power of two (instance %m)");

if (AXI_BYTE_LANES == AXIL_BYTE_LANES) begin : bypass
    // same width; bypass

    assign m_axi_rd.arid = '0;
    assign m_axi_rd.araddr = s_axil_rd.araddr;
    assign m_axi_rd.arlen = '0;
    assign m_axi_rd.arsize = 3'(AXI_BURST_SIZE);
    assign m_axi_rd.arburst = 2'b01;
    assign m_axi_rd.arlock = 1'b0;
    assign m_axi_rd.arcache = 4'b0011;
    assign m_axi_rd.arprot = s_axil_rd.arprot;
    assign m_axi_rd.arqos = '0;
    assign m_axi_rd.arregion = '0;
    assign m_axi_rd.aruser = ARUSER_EN ? s_axil_rd.aruser : '0;
    assign m_axi_rd.arvalid = s_axil_rd.arvalid;
    assign s_axil_rd.arready = m_axi_rd.arready;

    assign s_axil_rd.rdata = m_axi_rd.rdata;
    assign s_axil_rd.rresp = m_axi_rd.rresp;
    assign s_axil_rd.ruser = RUSER_EN ? m_axi_rd.ruser : '0;
    assign s_axil_rd.rvalid = m_axi_rd.rvalid;
    assign m_axi_rd.rready = s_axil_rd.rready;

end else if (AXI_BYTE_LANES > AXIL_BYTE_LANES) begin : upsize
    // output is wider; upsize

    typedef enum logic [0:0] {
        STATE_IDLE,
        STATE_DATA
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic s_axil_arready_reg = 1'b0, s_axil_arready_next;
    logic [AXIL_DATA_W-1:0] s_axil_rdata_reg = '0, s_axil_rdata_next;
    logic [1:0] s_axil_rresp_reg = '0, s_axil_rresp_next;
    logic [RUSER_W-1:0] s_axil_ruser_reg = '0, s_axil_ruser_next;
    logic s_axil_rvalid_reg = 1'b0, s_axil_rvalid_next;

    logic [ADDR_W-1:0] m_axi_araddr_reg = '0, m_axi_araddr_next;
    logic [2:0] m_axi_arprot_reg = '0, m_axi_arprot_next;
    logic [ARUSER_W-1:0] m_axi_aruser_reg = '0, m_axi_aruser_next;
    logic m_axi_arvalid_reg = 1'b0, m_axi_arvalid_next;
    logic m_axi_rready_reg = 1'b0, m_axi_rready_next;

    assign s_axil_rd.arready = s_axil_arready_reg;
    assign s_axil_rd.rdata = s_axil_rdata_reg;
    assign s_axil_rd.rresp = s_axil_rresp_reg;
    assign s_axil_rd.ruser = RUSER_EN ? s_axil_ruser_reg : '0;
    assign s_axil_rd.rvalid = s_axil_rvalid_reg;

    assign m_axi_rd.arid = '0;
    assign m_axi_rd.araddr = m_axi_araddr_reg;
    assign m_axi_rd.arlen = '0;
    assign m_axi_rd.arsize = 3'(AXI_BURST_SIZE);
    assign m_axi_rd.arburst = 2'b01;
    assign m_axi_rd.arlock = 1'b0;
    assign m_axi_rd.arcache = 4'b0011;
    assign m_axi_rd.arprot = m_axi_arprot_reg;
    assign m_axi_rd.arqos = '0;
    assign m_axi_rd.arregion = '0;
    assign m_axi_rd.aruser = ARUSER_EN ? m_axi_aruser_reg : '0;
    assign m_axi_rd.arvalid = m_axi_arvalid_reg;
    assign m_axi_rd.rready = m_axi_rready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        s_axil_arready_next = 1'b0;
        s_axil_rdata_next = s_axil_rdata_reg;
        s_axil_rresp_next = s_axil_rresp_reg;
        s_axil_ruser_next = s_axil_ruser_reg;
        s_axil_rvalid_next = s_axil_rvalid_reg && !s_axil_rd.rready;
        m_axi_araddr_next = m_axi_araddr_reg;
        m_axi_arprot_next = m_axi_arprot_reg;
        m_axi_aruser_next = m_axi_aruser_reg;
        m_axi_arvalid_next = m_axi_arvalid_reg && !m_axi_rd.arready;
        m_axi_rready_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                s_axil_arready_next = !m_axi_rd.arvalid;

                if (s_axil_rd.arready && s_axil_rd.arvalid) begin
                    s_axil_arready_next = 1'b0;
                    m_axi_araddr_next = s_axil_rd.araddr;
                    m_axi_arprot_next = s_axil_rd.arprot;
                    m_axi_aruser_next = s_axil_rd.aruser;
                    m_axi_arvalid_next = 1'b1;
                    m_axi_rready_next = !m_axi_rd.rvalid;
                    state_next = STATE_DATA;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                m_axi_rready_next = !s_axil_rd.rvalid;

                if (m_axi_rd.rready && m_axi_rd.rvalid) begin
                    m_axi_rready_next = 1'b0;
                    s_axil_rdata_next = m_axi_rd.rdata[m_axi_araddr_reg[AXI_ADDR_BIT_OFFSET - 1:AXIL_ADDR_BIT_OFFSET] * AXIL_DATA_W +: AXIL_DATA_W];
                    s_axil_rresp_next = m_axi_rd.rresp;
                    s_axil_ruser_next = m_axi_rd.ruser;
                    s_axil_rvalid_next = 1'b1;
                    s_axil_arready_next = !m_axi_rd.arvalid;
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

        m_axi_araddr_reg <= m_axi_araddr_next;
        m_axi_arprot_reg <= m_axi_arprot_next;
        m_axi_aruser_reg <= m_axi_aruser_next;
        m_axi_arvalid_reg <= m_axi_arvalid_next;
        m_axi_rready_reg <= m_axi_rready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axil_arready_reg <= 1'b0;
            s_axil_rvalid_reg <= 1'b0;

            m_axi_arvalid_reg <= 1'b0;
            m_axi_rready_reg <= 1'b0;
        end
    end

end else begin : downsize
    // output is narrower; downsize

    // output bus is wider
    localparam DATA_W = AXIL_DATA_W;
    localparam STRB_W = AXIL_STRB_W;
    // required number of segments in wider bus
    localparam SEG_COUNT = AXIL_BYTE_LANES / AXI_BYTE_LANES;
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
    logic [AXIL_DATA_W-1:0] s_axil_rdata_reg = '0, s_axil_rdata_next;
    logic [1:0] s_axil_rresp_reg = '0, s_axil_rresp_next;
    logic [RUSER_W-1:0] s_axil_ruser_reg = '0, s_axil_ruser_next;
    logic s_axil_rvalid_reg = 1'b0, s_axil_rvalid_next;

    logic [ADDR_W-1:0] m_axi_araddr_reg = '0, m_axi_araddr_next;
    logic [2:0] m_axi_arprot_reg = '0, m_axi_arprot_next;
    logic [ARUSER_W-1:0] m_axi_aruser_reg = '0, m_axi_aruser_next;
    logic m_axi_arvalid_reg = 1'b0, m_axi_arvalid_next;
    logic m_axi_rready_reg = 1'b0, m_axi_rready_next;

    assign s_axil_rd.arready = s_axil_arready_reg;
    assign s_axil_rd.rdata = s_axil_rdata_reg;
    assign s_axil_rd.rresp = s_axil_rresp_reg;
    assign s_axil_rd.ruser = RUSER_EN ? s_axil_ruser_reg : '0;
    assign s_axil_rd.rvalid = s_axil_rvalid_reg;

    assign m_axi_rd.arid = '0;
    assign m_axi_rd.araddr = m_axi_araddr_reg;
    assign m_axi_rd.arlen = '0;
    assign m_axi_rd.arsize = 3'(AXI_BURST_SIZE);
    assign m_axi_rd.arburst = 2'b01;
    assign m_axi_rd.arlock = 1'b0;
    assign m_axi_rd.arcache = 4'b0011;
    assign m_axi_rd.arprot = m_axi_arprot_reg;
    assign m_axi_rd.arqos = '0;
    assign m_axi_rd.arregion = '0;
    assign m_axi_rd.aruser = ARUSER_EN ? m_axi_aruser_reg : '0;
    assign m_axi_rd.arvalid = m_axi_arvalid_reg;
    assign m_axi_rd.rready = m_axi_rready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        current_seg_next = current_seg_reg;

        s_axil_arready_next = 1'b0;
        s_axil_rdata_next = s_axil_rdata_reg;
        s_axil_rresp_next = s_axil_rresp_reg;
        s_axil_ruser_next = s_axil_ruser_reg;
        s_axil_rvalid_next = s_axil_rvalid_reg && !s_axil_rd.rready;
        m_axi_araddr_next = m_axi_araddr_reg;
        m_axi_arprot_next = m_axi_arprot_reg;
        m_axi_aruser_next = m_axi_aruser_reg;
        m_axi_arvalid_next = m_axi_arvalid_reg && !m_axi_rd.arready;
        m_axi_rready_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                s_axil_arready_next = !m_axi_rd.arvalid;

                current_seg_next = s_axil_rd.araddr[AXI_ADDR_BIT_OFFSET +: SEG_COUNT_W];
                s_axil_rresp_next = 2'd0;

                if (s_axil_rd.arready && s_axil_rd.arvalid) begin
                    s_axil_arready_next = 1'b0;
                    m_axi_araddr_next = s_axil_rd.araddr;
                    m_axi_arprot_next = s_axil_rd.arprot;
                    m_axi_aruser_next = s_axil_rd.aruser;
                    m_axi_arvalid_next = 1'b1;
                    m_axi_rready_next = !m_axi_rd.rvalid;
                    state_next = STATE_DATA;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                m_axi_rready_next = !s_axil_rd.rvalid;

                if (m_axi_rd.rready && m_axi_rd.rvalid) begin
                    m_axi_rready_next = 1'b0;
                    m_axi_araddr_next = (m_axi_araddr_reg & AXI_ADDR_MASK) + SEG_STRB_W;
                    s_axil_rdata_next[current_seg_reg*SEG_DATA_W +: SEG_DATA_W] = m_axi_rd.rdata;
                    s_axil_ruser_next = m_axi_rd.ruser;
                    current_seg_next = current_seg_reg + 1;
                    if (m_axi.rresp != 0) begin
                        s_axil_rresp_next = m_axi_rd.rresp;
                    end
                    if (current_seg_reg == SEG_COUNT_W'(SEG_COUNT-1)) begin
                        s_axil_rvalid_next = 1'b1;
                        s_axil_arready_next = !m_axi_rd.arvalid;
                        state_next = STATE_IDLE;
                    end else begin
                        m_axi_arvalid_next = 1'b1;
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

        m_axi_araddr_reg <= m_axi_araddr_next;
        m_axi_arprot_reg <= m_axi_arprot_next;
        m_axi_aruser_reg <= m_axi_aruser_next;
        m_axi_arvalid_reg <= m_axi_arvalid_next;
        m_axi_rready_reg <= m_axi_rready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axil_arready_reg <= 1'b0;
            s_axil_rvalid_reg <= 1'b0;

            m_axi_arvalid_reg <= 1'b0;
            m_axi_rready_reg <= 1'b0;
        end
    end

end

endmodule

`resetall
