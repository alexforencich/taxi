// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2019-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4 to AXI4-Lite adapter (write)
 */
module taxi_axi_axil_adapter_wr #
(
    // When adapting to a wider bus, re-pack full-width burst instead of passing through narrow burst if possible
    parameter logic CONVERT_BURST = 1'b1,
    // When adapting to a wider bus, re-pack all bursts instead of passing through narrow burst if possible
    parameter logic CONVERT_NARROW_BURST = 1'b0
)
(
    input  wire logic    clk,
    input  wire logic    rst,

    /*
     * AXI4 slave interface
     */
    taxi_axi_if.wr_slv   s_axi_wr,

    /*
     * AXI4-Lite master interface
     */
    taxi_axil_if.wr_mst  m_axil_wr
);

// extract parameters
localparam AXI_DATA_W = s_axi_wr.DATA_W;
localparam ADDR_W = s_axi_wr.ADDR_W;
localparam CL_ADDR_W = $clog2(ADDR_W);
localparam AXI_STRB_W = s_axi_wr.STRB_W;
localparam AXI_ID_W = s_axi_wr.ID_W;
localparam logic AWUSER_EN = s_axi_wr.AWUSER_EN && m_axil_wr.AWUSER_EN;
localparam AWUSER_W = s_axi_wr.AWUSER_W;
localparam logic WUSER_EN = s_axi_wr.WUSER_EN && m_axil_wr.WUSER_EN;
localparam WUSER_W = s_axi_wr.WUSER_W;
localparam logic BUSER_EN = s_axi_wr.BUSER_EN && m_axil_wr.BUSER_EN;
localparam BUSER_W = s_axi_wr.BUSER_W;

localparam AXIL_DATA_W = m_axil_wr.DATA_W;
localparam AXIL_STRB_W = m_axil_wr.STRB_W;

localparam AXI_ADDR_BIT_OFFSET = $clog2(AXI_STRB_W);
localparam AXIL_ADDR_BIT_OFFSET = $clog2(AXIL_STRB_W);
localparam AXI_BYTE_LANES = AXI_STRB_W;
localparam AXIL_BYTE_LANES = AXIL_STRB_W;
localparam AXI_BYTE_SIZE = AXI_DATA_W/AXI_BYTE_LANES;
localparam AXIL_BYTE_SIZE = AXIL_DATA_W/AXIL_BYTE_LANES;
localparam logic [2:0] AXI_BURST_SIZE = 3'($clog2(AXI_BYTE_LANES));
localparam logic [2:0] AXIL_BURST_SIZE = 3'($clog2(AXIL_BYTE_LANES));

// check configuration
if (AXI_BYTE_SIZE * AXI_STRB_W != AXI_DATA_W)
    $fatal(0, "Error: AXI slave interface data width not evenly divisible (instance %m)");

if (AXIL_BYTE_SIZE * AXIL_STRB_W != AXIL_DATA_W)
    $fatal(0, "Error: AXI lite master interface data width not evenly divisible (instance %m)");

if (AXI_BYTE_SIZE != AXIL_BYTE_SIZE)
    $fatal(0, "Error: byte size mismatch (instance %m)");

if (2**$clog2(AXI_BYTE_LANES) != AXI_BYTE_LANES)
    $fatal(0, "Error: AXI slave interface byte lane count must be even power of two (instance %m)");

if (2**$clog2(AXIL_BYTE_LANES) != AXIL_BYTE_LANES)
    $fatal(0, "Error: AXI lite master interface byte lane count must be even power of two (instance %m)");

if (AXIL_BYTE_LANES == AXI_BYTE_LANES) begin : translate
    // same width; translate

    // output bus is wider
    localparam EXPAND = AXIL_BYTE_LANES > AXI_BYTE_LANES;
    localparam DATA_W = EXPAND ? AXIL_DATA_W : AXI_DATA_W;
    localparam STRB_W = EXPAND ? AXIL_STRB_W : AXI_STRB_W;
    // required number of segments in wider bus
    localparam SEG_COUNT = EXPAND ? (AXIL_BYTE_LANES / AXI_BYTE_LANES) : (AXI_BYTE_LANES / AXIL_BYTE_LANES);
    // data width and keep width per segment
    localparam SEG_DATA_W = DATA_W / SEG_COUNT;
    localparam SEG_STRB_W = STRB_W / SEG_COUNT;

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_DATA,
        STATE_RESP
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic [AXI_ID_W-1:0] id_reg = '0, id_next;
    logic [ADDR_W-1:0] addr_reg = '0, addr_next;
    logic [DATA_W-1:0] data_reg = '0, data_next;
    logic [STRB_W-1:0] strb_reg = '0, strb_next;
    logic [7:0] burst_reg = 8'd0, burst_next;
    logic [2:0] burst_size_reg = 3'd0, burst_size_next;
    logic [2:0] master_burst_size_reg = 3'd0, master_burst_size_next;
    logic burst_active_reg = 1'b0, burst_active_next;
    logic convert_burst_reg = 1'b0, convert_burst_next;
    logic first_transfer_reg = 1'b0, first_transfer_next;
    logic last_seg_reg = 1'b0, last_seg_next;

    logic s_axi_awready_reg = 1'b0, s_axi_awready_next;
    logic s_axi_wready_reg = 1'b0, s_axi_wready_next;
    logic [AXI_ID_W-1:0] s_axi_bid_reg = '0, s_axi_bid_next;
    logic [1:0] s_axi_bresp_reg = 2'd0, s_axi_bresp_next;
    logic s_axi_bvalid_reg = 1'b0, s_axi_bvalid_next;

    logic [ADDR_W-1:0] m_axil_awaddr_reg = '0, m_axil_awaddr_next;
    logic [2:0] m_axil_awprot_reg = 3'd0, m_axil_awprot_next;
    logic m_axil_awvalid_reg = 1'b0, m_axil_awvalid_next;
    logic [AXIL_DATA_W-1:0] m_axil_wdata_reg = '0, m_axil_wdata_next;
    logic [AXIL_STRB_W-1:0] m_axil_wstrb_reg = '0, m_axil_wstrb_next;
    logic m_axil_wvalid_reg = 1'b0, m_axil_wvalid_next;
    logic m_axil_bready_reg = 1'b0, m_axil_bready_next;

    assign s_axi_wr.awready = s_axi_awready_reg;
    assign s_axi_wr.wready = s_axi_wready_reg;
    assign s_axi_wr.bid = s_axi_bid_reg;
    assign s_axi_wr.bresp = s_axi_bresp_reg;
    assign s_axi_wr.bvalid = s_axi_bvalid_reg;

    assign m_axil_wr.awaddr = m_axil_awaddr_reg;
    assign m_axil_wr.awprot = m_axil_awprot_reg;
    assign m_axil_wr.awvalid = m_axil_awvalid_reg;
    assign m_axil_wr.wdata = m_axil_wdata_reg;
    assign m_axil_wr.wstrb = m_axil_wstrb_reg;
    assign m_axil_wr.wvalid = m_axil_wvalid_reg;
    assign m_axil_wr.bready = m_axil_bready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        id_next = id_reg;
        addr_next = addr_reg;
        data_next = data_reg;
        strb_next = strb_reg;
        burst_next = burst_reg;
        burst_size_next = burst_size_reg;
        master_burst_size_next = master_burst_size_reg;
        burst_active_next = burst_active_reg;
        convert_burst_next = convert_burst_reg;
        first_transfer_next = first_transfer_reg;
        last_seg_next = last_seg_reg;

        s_axi_awready_next = 1'b0;
        s_axi_wready_next = 1'b0;
        s_axi_bid_next = s_axi_bid_reg;
        s_axi_bresp_next = s_axi_bresp_reg;
        s_axi_bvalid_next = s_axi_bvalid_reg && !s_axi_wr.bready;
        m_axil_awaddr_next = m_axil_awaddr_reg;
        m_axil_awprot_next = m_axil_awprot_reg;
        m_axil_awvalid_next = m_axil_awvalid_reg && !m_axil_wr.awready;
        m_axil_wdata_next = m_axil_wdata_reg;
        m_axil_wstrb_next = m_axil_wstrb_reg;
        m_axil_wvalid_next = m_axil_wvalid_reg && !m_axil_wr.wready;
        m_axil_bready_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                // idle state; wait for new burst
                s_axi_awready_next = !m_axil_wr.awvalid;
                first_transfer_next = 1'b1;

                if (s_axi_wr.awready && s_axi_wr.awvalid) begin
                    s_axi_awready_next = 1'b0;
                    id_next = s_axi_wr.awid;
                    m_axil_awaddr_next = s_axi_wr.awaddr;
                    addr_next = s_axi_wr.awaddr;
                    burst_next = s_axi_wr.awlen;
                    burst_size_next = s_axi_wr.awsize;
                    burst_active_next = 1'b1;
                    m_axil_awprot_next = s_axi_wr.awprot;
                    m_axil_awvalid_next = 1'b1;
                    s_axi_wready_next = !m_axil_wr.wvalid;
                    state_next = STATE_DATA;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                // data state; transfer write data
                s_axi_wready_next = !m_axil_wr.wvalid;

                if (s_axi_wr.wready && s_axi_wr.wvalid) begin
                    m_axil_wdata_next = s_axi_wr.wdata;
                    m_axil_wstrb_next = s_axi_wr.wstrb;
                    m_axil_wvalid_next = 1'b1;
                    burst_next = burst_reg - 1;
                    burst_active_next = burst_reg != 0;
                    addr_next = addr_reg + (1 << burst_size_reg);
                    s_axi_wready_next = 1'b0;
                    m_axil_bready_next = !s_axi_wr.bvalid && !m_axil_wr.awvalid;
                    state_next = STATE_RESP;
                end else begin
                    state_next = STATE_DATA;
                end
            end
            STATE_RESP: begin
                // resp state; transfer write response
                m_axil_bready_next = !s_axi_wr.bvalid && !m_axil_wr.awvalid;

                if (m_axil_wr.bready && m_axil_wr.bvalid) begin
                    m_axil_bready_next = 1'b0;
                    s_axi_bid_next = id_reg;
                    first_transfer_next = 1'b0;
                    if (first_transfer_reg || m_axil_wr.bresp != 0) begin
                        s_axi_bresp_next = m_axil_wr.bresp;
                    end
                    if (burst_active_reg) begin
                        // burst on slave interface still active; start new AXI lite write
                        m_axil_awaddr_next = addr_reg;
                        m_axil_awvalid_next = 1'b1;
                        s_axi_wready_next = !m_axil_wr.wvalid;
                        state_next = STATE_DATA;
                    end else begin
                        // burst on slave interface finished; return to idle
                        s_axi_bvalid_next = 1'b1;
                        s_axi_awready_next = !m_axil_wr.awvalid;
                        state_next = STATE_IDLE;
                    end
                end else begin
                    state_next = STATE_RESP;
                end
            end
            default: begin
                // invalid state
                state_next = STATE_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        state_reg <= state_next;

        id_reg <= id_next;
        addr_reg <= addr_next;
        data_reg <= data_next;
        strb_reg <= strb_next;
        burst_reg <= burst_next;
        burst_size_reg <= burst_size_next;
        master_burst_size_reg <= master_burst_size_next;
        burst_active_reg <= burst_active_next;
        convert_burst_reg <= convert_burst_next;
        first_transfer_reg <= first_transfer_next;
        last_seg_reg <= last_seg_next;

        s_axi_awready_reg <= s_axi_awready_next;
        s_axi_wready_reg <= s_axi_wready_next;
        s_axi_bid_reg <= s_axi_bid_next;
        s_axi_bresp_reg <= s_axi_bresp_next;
        s_axi_bvalid_reg <= s_axi_bvalid_next;

        m_axil_awaddr_reg <= m_axil_awaddr_next;
        m_axil_awprot_reg <= m_axil_awprot_next;
        m_axil_awvalid_reg <= m_axil_awvalid_next;
        m_axil_wdata_reg <= m_axil_wdata_next;
        m_axil_wstrb_reg <= m_axil_wstrb_next;
        m_axil_wvalid_reg <= m_axil_wvalid_next;
        m_axil_bready_reg <= m_axil_bready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axi_awready_reg <= 1'b0;
            s_axi_wready_reg <= 1'b0;
            s_axi_bvalid_reg <= 1'b0;

            m_axil_awvalid_reg <= 1'b0;
            m_axil_wvalid_reg <= 1'b0;
            m_axil_bready_reg <= 1'b0;
        end
    end

end else if (AXIL_BYTE_LANES > AXI_BYTE_LANES) begin : upsize
    // output is wider; upsize

    // output bus is wider
    localparam EXPAND = AXIL_BYTE_LANES > AXI_BYTE_LANES;
    localparam DATA_W = EXPAND ? AXIL_DATA_W : AXI_DATA_W;
    localparam STRB_W = EXPAND ? AXIL_STRB_W : AXI_STRB_W;
    // required number of segments in wider bus
    localparam SEG_COUNT = EXPAND ? (AXIL_BYTE_LANES / AXI_BYTE_LANES) : (AXI_BYTE_LANES / AXIL_BYTE_LANES);
    // data width and keep width per segment
    localparam SEG_DATA_W = DATA_W / SEG_COUNT;
    localparam SEG_STRB_W = STRB_W / SEG_COUNT;

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_DATA,
        STATE_DATA_2,
        STATE_RESP
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic [AXI_ID_W-1:0] id_reg = '0, id_next;
    logic [ADDR_W-1:0] addr_reg = '0, addr_next;
    logic [DATA_W-1:0] data_reg = '0, data_next;
    logic [STRB_W-1:0] strb_reg = '0, strb_next;
    logic [7:0] burst_reg = 8'd0, burst_next;
    logic [2:0] burst_size_reg = 3'd0, burst_size_next;
    logic [2:0] master_burst_size_reg = 3'd0, master_burst_size_next;
    logic burst_active_reg = 1'b0, burst_active_next;
    logic convert_burst_reg = 1'b0, convert_burst_next;
    logic first_transfer_reg = 1'b0, first_transfer_next;
    logic last_seg_reg = 1'b0, last_seg_next;

    logic s_axi_awready_reg = 1'b0, s_axi_awready_next;
    logic s_axi_wready_reg = 1'b0, s_axi_wready_next;
    logic [AXI_ID_W-1:0] s_axi_bid_reg = '0, s_axi_bid_next;
    logic [1:0] s_axi_bresp_reg = 2'd0, s_axi_bresp_next;
    logic s_axi_bvalid_reg = 1'b0, s_axi_bvalid_next;

    logic [ADDR_W-1:0] m_axil_awaddr_reg = '0, m_axil_awaddr_next;
    logic [2:0] m_axil_awprot_reg = 3'd0, m_axil_awprot_next;
    logic m_axil_awvalid_reg = 1'b0, m_axil_awvalid_next;
    logic [AXIL_DATA_W-1:0] m_axil_wdata_reg = '0, m_axil_wdata_next;
    logic [AXIL_STRB_W-1:0] m_axil_wstrb_reg = '0, m_axil_wstrb_next;
    logic m_axil_wvalid_reg = 1'b0, m_axil_wvalid_next;
    logic m_axil_bready_reg = 1'b0, m_axil_bready_next;

    assign s_axi_wr.awready = s_axi_awready_reg;
    assign s_axi_wr.wready = s_axi_wready_reg;
    assign s_axi_wr.bid = s_axi_bid_reg;
    assign s_axi_wr.bresp = s_axi_bresp_reg;
    assign s_axi_wr.bvalid = s_axi_bvalid_reg;

    assign m_axil_wr.awaddr = m_axil_awaddr_reg;
    assign m_axil_wr.awprot = m_axil_awprot_reg;
    assign m_axil_wr.awvalid = m_axil_awvalid_reg;
    assign m_axil_wr.wdata = m_axil_wdata_reg;
    assign m_axil_wr.wstrb = m_axil_wstrb_reg;
    assign m_axil_wr.wvalid = m_axil_wvalid_reg;
    assign m_axil_wr.bready = m_axil_bready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        id_next = id_reg;
        addr_next = addr_reg;
        data_next = data_reg;
        strb_next = strb_reg;
        burst_next = burst_reg;
        burst_size_next = burst_size_reg;
        master_burst_size_next = master_burst_size_reg;
        burst_active_next = burst_active_reg;
        convert_burst_next = convert_burst_reg;
        first_transfer_next = first_transfer_reg;
        last_seg_next = last_seg_reg;

        s_axi_awready_next = 1'b0;
        s_axi_wready_next = 1'b0;
        s_axi_bid_next = s_axi_bid_reg;
        s_axi_bresp_next = s_axi_bresp_reg;
        s_axi_bvalid_next = s_axi_bvalid_reg && !s_axi_wr.bready;
        m_axil_awaddr_next = m_axil_awaddr_reg;
        m_axil_awprot_next = m_axil_awprot_reg;
        m_axil_awvalid_next = m_axil_awvalid_reg && !m_axil_wr.awready;
        m_axil_wdata_next = m_axil_wdata_reg;
        m_axil_wstrb_next = m_axil_wstrb_reg;
        m_axil_wvalid_next = m_axil_wvalid_reg && !m_axil_wr.wready;
        m_axil_bready_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                // idle state; wait for new burst
                s_axi_awready_next = !m_axil_wr.awvalid;

                first_transfer_next = 1'b1;

                strb_next = '0;

                if (s_axi_wr.awready && s_axi_wr.awvalid) begin
                    s_axi_awready_next = 1'b0;
                    id_next = s_axi_wr.awid;
                    m_axil_awaddr_next = s_axi_wr.awaddr;
                    addr_next = s_axi_wr.awaddr;
                    burst_next = s_axi_wr.awlen;
                    burst_size_next = s_axi_wr.awsize;
                    if (CONVERT_BURST && s_axi_wr.awcache[1] && (CONVERT_NARROW_BURST || s_axi_wr.awsize == AXI_BURST_SIZE)) begin
                        // merge writes
                        // require CONVERT_BURST and awcache[1] set
                        convert_burst_next = 1'b1;
                        master_burst_size_next = AXIL_BURST_SIZE;
                        state_next = STATE_DATA_2;
                    end else begin
                        // output narrow burst
                        convert_burst_next = 1'b0;
                        master_burst_size_next = s_axi_wr.awsize;
                        state_next = STATE_DATA;
                    end
                    m_axil_awprot_next = s_axi_wr.awprot;
                    m_axil_awvalid_next = 1'b1;
                    s_axi_wready_next = !m_axil_wr.wvalid;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                // data state; transfer write data
                s_axi_wready_next = !m_axil_wr.wvalid || m_axil_wr.wready;

                if (s_axi_wr.wready && s_axi_wr.wvalid) begin
                    m_axil_wdata_next = {(AXIL_BYTE_LANES/AXI_BYTE_LANES){s_axi_wr.wdata}};
                    m_axil_wstrb_next = '0;
                    m_axil_wstrb_next[addr_reg[AXIL_ADDR_BIT_OFFSET-1:AXI_ADDR_BIT_OFFSET] * AXI_STRB_W +: AXI_STRB_W] = s_axi_wr.wstrb;
                    m_axil_wvalid_next = 1'b1;
                    burst_next = burst_reg - 1;
                    burst_active_next = burst_reg != 0;
                    addr_next = addr_reg + (1 << burst_size_reg);
                    s_axi_wready_next = 1'b0;
                    m_axil_bready_next = !s_axi_wr.bvalid && !m_axil_wr.awvalid;
                    state_next = STATE_RESP;
                end else begin
                    state_next = STATE_DATA;
                end
            end
            STATE_DATA_2: begin
                s_axi_wready_next = !m_axil_wr.wvalid;

                if (s_axi_wr.wready && s_axi_wr.wvalid) begin
                    if (CONVERT_NARROW_BURST) begin
                        for (integer i = 0; i < AXI_BYTE_LANES; i = i + 1) begin
                            if (s_axi_wr.wstrb[i]) begin
                                data_next[addr_reg[AXIL_ADDR_BIT_OFFSET-1:AXI_ADDR_BIT_OFFSET]*SEG_DATA_W+i*AXIL_BYTE_SIZE +: AXIL_BYTE_SIZE] = s_axi_wr.wdata[i*AXIL_BYTE_SIZE +: AXIL_BYTE_SIZE];
                                strb_next[addr_reg[AXIL_ADDR_BIT_OFFSET-1:AXI_ADDR_BIT_OFFSET]*SEG_STRB_W+i] = 1'b1;
                            end
                        end
                    end else begin
                        data_next[addr_reg[AXIL_ADDR_BIT_OFFSET-1:AXI_ADDR_BIT_OFFSET]*SEG_DATA_W +: SEG_DATA_W] = s_axi_wr.wdata;
                        strb_next[addr_reg[AXIL_ADDR_BIT_OFFSET-1:AXI_ADDR_BIT_OFFSET]*SEG_STRB_W +: SEG_STRB_W] = s_axi_wr.wstrb;
                    end
                    m_axil_wdata_next = data_next;
                    m_axil_wstrb_next = strb_next;
                    burst_next = burst_reg - 1;
                    burst_active_next = burst_reg != 0;
                    addr_next = addr_reg + (1 << burst_size_reg);
                    if (burst_reg == 0 || addr_next[CL_ADDR_W'(master_burst_size_reg)] != addr_reg[CL_ADDR_W'(master_burst_size_reg)]) begin
                        strb_next = '0;
                        m_axil_wvalid_next = 1'b1;
                        s_axi_wready_next = 1'b0;
                        m_axil_bready_next = !s_axi_wr.bvalid && !m_axil_wr.awvalid;
                        state_next = STATE_RESP;
                    end else begin
                        state_next = STATE_DATA_2;
                    end
                end else begin
                    state_next = STATE_DATA_2;
                end
            end
            STATE_RESP: begin
                // resp state; transfer write response
                m_axil_bready_next = !s_axi_wr.bvalid && !m_axil_wr.awvalid;

                if (m_axil_wr.bready && m_axil_wr.bvalid) begin
                    m_axil_bready_next = 1'b0;
                    s_axi_bid_next = id_reg;
                    first_transfer_next = 1'b0;
                    if (first_transfer_reg || m_axil_wr.bresp != 0) begin
                        s_axi_bresp_next = m_axil_wr.bresp;
                    end
                    if (burst_active_reg) begin
                        // burst on slave interface still active; start new AXI lite write
                        m_axil_awaddr_next = addr_reg;
                        m_axil_awvalid_next = 1'b1;
                        s_axi_wready_next = !m_axil_wr.wvalid || m_axil_wr.wready;
                        if (convert_burst_reg) begin
                            state_next = STATE_DATA_2;
                        end else begin
                            state_next = STATE_DATA;
                        end
                    end else begin
                        // burst on slave interface finished; return to idle
                        s_axi_bvalid_next = 1'b1;
                        s_axi_awready_next = !m_axil_wr.awvalid;
                        state_next = STATE_IDLE;
                    end
                end else begin
                    state_next = STATE_RESP;
                end
            end
        endcase
    end

    always_ff @(posedge clk) begin
        state_reg <= state_next;

        id_reg <= id_next;
        addr_reg <= addr_next;
        data_reg <= data_next;
        strb_reg <= strb_next;
        burst_reg <= burst_next;
        burst_size_reg <= burst_size_next;
        master_burst_size_reg <= master_burst_size_next;
        burst_active_reg <= burst_active_next;
        convert_burst_reg <= convert_burst_next;
        first_transfer_reg <= first_transfer_next;
        last_seg_reg <= last_seg_next;

        s_axi_awready_reg <= s_axi_awready_next;
        s_axi_wready_reg <= s_axi_wready_next;
        s_axi_bid_reg <= s_axi_bid_next;
        s_axi_bresp_reg <= s_axi_bresp_next;
        s_axi_bvalid_reg <= s_axi_bvalid_next;

        m_axil_awaddr_reg <= m_axil_awaddr_next;
        m_axil_awprot_reg <= m_axil_awprot_next;
        m_axil_awvalid_reg <= m_axil_awvalid_next;
        m_axil_wdata_reg <= m_axil_wdata_next;
        m_axil_wstrb_reg <= m_axil_wstrb_next;
        m_axil_wvalid_reg <= m_axil_wvalid_next;
        m_axil_bready_reg <= m_axil_bready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axi_awready_reg <= 1'b0;
            s_axi_wready_reg <= 1'b0;
            s_axi_bvalid_reg <= 1'b0;

            m_axil_awvalid_reg <= 1'b0;
            m_axil_wvalid_reg <= 1'b0;
            m_axil_bready_reg <= 1'b0;
        end
    end

end else begin : downsize
    // output is narrower; downsize

    // output bus is wider
    localparam EXPAND = AXIL_BYTE_LANES > AXI_BYTE_LANES;
    localparam DATA_W = EXPAND ? AXIL_DATA_W : AXI_DATA_W;
    localparam STRB_W = EXPAND ? AXIL_STRB_W : AXI_STRB_W;
    // required number of segments in wider bus
    localparam SEG_COUNT = EXPAND ? (AXIL_BYTE_LANES / AXI_BYTE_LANES) : (AXI_BYTE_LANES / AXIL_BYTE_LANES);
    // data width and keep width per segment
    localparam SEG_DATA_W = DATA_W / SEG_COUNT;
    localparam SEG_STRB_W = STRB_W / SEG_COUNT;

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_DATA,
        STATE_DATA_2,
        STATE_RESP
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic [AXI_ID_W-1:0] id_reg = '0, id_next;
    logic [ADDR_W-1:0] addr_reg = '0, addr_next;
    logic [DATA_W-1:0] data_reg = '0, data_next;
    logic [STRB_W-1:0] strb_reg = '0, strb_next;
    logic [7:0] burst_reg = 8'd0, burst_next;
    logic [2:0] burst_size_reg = 3'd0, burst_size_next;
    logic [2:0] master_burst_size_reg = 3'd0, master_burst_size_next;
    logic burst_active_reg = 1'b0, burst_active_next;
    logic convert_burst_reg = 1'b0, convert_burst_next;
    logic first_transfer_reg = 1'b0, first_transfer_next;
    logic last_seg_reg = 1'b0, last_seg_next;

    logic s_axi_awready_reg = 1'b0, s_axi_awready_next;
    logic s_axi_wready_reg = 1'b0, s_axi_wready_next;
    logic [AXI_ID_W-1:0] s_axi_bid_reg = '0, s_axi_bid_next;
    logic [1:0] s_axi_bresp_reg = 2'd0, s_axi_bresp_next;
    logic s_axi_bvalid_reg = 1'b0, s_axi_bvalid_next;

    logic [ADDR_W-1:0] m_axil_awaddr_reg = '0, m_axil_awaddr_next;
    logic [2:0] m_axil_awprot_reg = 3'd0, m_axil_awprot_next;
    logic m_axil_awvalid_reg = 1'b0, m_axil_awvalid_next;
    logic [AXIL_DATA_W-1:0] m_axil_wdata_reg = '0, m_axil_wdata_next;
    logic [AXIL_STRB_W-1:0] m_axil_wstrb_reg = '0, m_axil_wstrb_next;
    logic m_axil_wvalid_reg = 1'b0, m_axil_wvalid_next;
    logic m_axil_bready_reg = 1'b0, m_axil_bready_next;

    assign s_axi_wr.awready = s_axi_awready_reg;
    assign s_axi_wr.wready = s_axi_wready_reg;
    assign s_axi_wr.bid = s_axi_bid_reg;
    assign s_axi_wr.bresp = s_axi_bresp_reg;
    assign s_axi_wr.bvalid = s_axi_bvalid_reg;

    assign m_axil_wr.awaddr = m_axil_awaddr_reg;
    assign m_axil_wr.awprot = m_axil_awprot_reg;
    assign m_axil_wr.awvalid = m_axil_awvalid_reg;
    assign m_axil_wr.wdata = m_axil_wdata_reg;
    assign m_axil_wr.wstrb = m_axil_wstrb_reg;
    assign m_axil_wr.wvalid = m_axil_wvalid_reg;
    assign m_axil_wr.bready = m_axil_bready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        id_next = id_reg;
        addr_next = addr_reg;
        data_next = data_reg;
        strb_next = strb_reg;
        burst_next = burst_reg;
        burst_size_next = burst_size_reg;
        master_burst_size_next = master_burst_size_reg;
        burst_active_next = burst_active_reg;
        convert_burst_next = convert_burst_reg;
        first_transfer_next = first_transfer_reg;
        last_seg_next = last_seg_reg;

        s_axi_awready_next = 1'b0;
        s_axi_wready_next = 1'b0;
        s_axi_bid_next = s_axi_bid_reg;
        s_axi_bresp_next = s_axi_bresp_reg;
        s_axi_bvalid_next = s_axi_bvalid_reg && !s_axi_wr.bready;
        m_axil_awaddr_next = m_axil_awaddr_reg;
        m_axil_awprot_next = m_axil_awprot_reg;
        m_axil_awvalid_next = m_axil_awvalid_reg && !m_axil_wr.awready;
        m_axil_wdata_next = m_axil_wdata_reg;
        m_axil_wstrb_next = m_axil_wstrb_reg;
        m_axil_wvalid_next = m_axil_wvalid_reg && !m_axil_wr.wready;
        m_axil_bready_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                // idle state; wait for new burst
                s_axi_awready_next = !m_axil_wr.awvalid;

                first_transfer_next = 1'b1;

                if (s_axi_wr.awready && s_axi_wr.awvalid) begin
                    s_axi_awready_next = 1'b0;
                    id_next = s_axi_wr.awid;
                    m_axil_awaddr_next = s_axi_wr.awaddr;
                    addr_next = s_axi_wr.awaddr;
                    burst_next = s_axi_wr.awlen;
                    burst_size_next = s_axi_wr.awsize;
                    burst_active_next = 1'b1;
                    if (s_axi_wr.awsize > AXIL_BURST_SIZE) begin
                        // need to adjust burst size
                        master_burst_size_next = AXIL_BURST_SIZE;
                    end else begin
                        // pass through narrow (enough) burst
                        master_burst_size_next = s_axi_wr.awsize;
                    end
                    m_axil_awprot_next = s_axi_wr.awprot;
                    m_axil_awvalid_next = 1'b1;
                    s_axi_wready_next = !m_axil_wr.wvalid;
                    state_next = STATE_DATA;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                s_axi_wready_next = !m_axil_wr.wvalid;

                if (s_axi_wr.wready && s_axi_wr.wvalid) begin
                    data_next = s_axi_wr.wdata;
                    strb_next = s_axi_wr.wstrb;
                    m_axil_wdata_next = s_axi_wr.wdata[addr_reg[AXI_ADDR_BIT_OFFSET-1:AXIL_ADDR_BIT_OFFSET] * AXIL_DATA_W +: AXIL_DATA_W];
                    m_axil_wstrb_next = s_axi_wr.wstrb[addr_reg[AXI_ADDR_BIT_OFFSET-1:AXIL_ADDR_BIT_OFFSET] * AXIL_STRB_W +: AXIL_STRB_W];
                    m_axil_wvalid_next = 1'b1;
                    burst_next = burst_reg - 1;
                    burst_active_next = burst_reg != 0;
                    addr_next = (addr_reg + (1 << master_burst_size_reg)) & ({ADDR_W{1'b1}} << master_burst_size_reg);
                    last_seg_next = addr_next[CL_ADDR_W'(burst_size_reg)] != addr_reg[CL_ADDR_W'(burst_size_reg)];
                    s_axi_wready_next = 1'b0;
                    m_axil_bready_next = !s_axi_wr.bvalid && !m_axil_wr.awvalid;
                    state_next = STATE_RESP;
                end else begin
                    state_next = STATE_DATA;
                end
            end
            STATE_DATA_2: begin
                s_axi_wready_next = 1'b0;

                if (!m_axil_wr.wvalid || m_axil_wr.wready) begin
                    m_axil_wdata_next = data_reg[addr_reg[AXI_ADDR_BIT_OFFSET-1:AXIL_ADDR_BIT_OFFSET] * AXIL_DATA_W +: AXIL_DATA_W];
                    m_axil_wstrb_next = strb_reg[addr_reg[AXI_ADDR_BIT_OFFSET-1:AXIL_ADDR_BIT_OFFSET] * AXIL_STRB_W +: AXIL_STRB_W];
                    m_axil_wvalid_next = 1'b1;
                    addr_next = (addr_reg + (1 << master_burst_size_reg)) & ({ADDR_W{1'b1}} << master_burst_size_reg);
                    last_seg_next = addr_next[CL_ADDR_W'(burst_size_reg)] != addr_reg[CL_ADDR_W'(burst_size_reg)];
                    s_axi_wready_next = 1'b0;
                    m_axil_bready_next = !s_axi_wr.bvalid && !m_axil_wr.awvalid;
                    state_next = STATE_RESP;
                end else begin
                    state_next = STATE_DATA_2;
                end
            end
            STATE_RESP: begin
                // resp state; transfer write response
                m_axil_bready_next = !s_axi_wr.bvalid && !m_axil_wr.awvalid;

                if (m_axil_wr.bready && m_axil_wr.bvalid) begin
                    first_transfer_next = 1'b0;
                    m_axil_awaddr_next = addr_reg;
                    m_axil_bready_next = 1'b0;
                    s_axi_bid_next = id_reg;
                    if (first_transfer_reg || m_axil_wr.bresp != 0) begin
                        s_axi_bresp_next = m_axil_wr.bresp;
                    end
                    if (burst_active_reg || !last_seg_reg) begin
                        // burst on slave interface still active; start new burst
                        m_axil_awvalid_next = 1'b1;
                        if (last_seg_reg) begin
                            s_axi_wready_next = !m_axil_wr.wvalid;
                            state_next = STATE_DATA;
                        end else begin
                            s_axi_wready_next = 1'b0;
                            state_next = STATE_DATA_2;
                        end
                    end else begin
                        // burst on slave interface finished; return to idle
                        s_axi_bvalid_next = 1'b1;
                        s_axi_awready_next = !m_axil_wr.awvalid;
                        state_next = STATE_IDLE;
                    end
                end else begin
                    state_next = STATE_RESP;
                end
            end
        endcase
    end

    always_ff @(posedge clk) begin
        state_reg <= state_next;

        id_reg <= id_next;
        addr_reg <= addr_next;
        data_reg <= data_next;
        strb_reg <= strb_next;
        burst_reg <= burst_next;
        burst_size_reg <= burst_size_next;
        master_burst_size_reg <= master_burst_size_next;
        burst_active_reg <= burst_active_next;
        convert_burst_reg <= convert_burst_next;
        first_transfer_reg <= first_transfer_next;
        last_seg_reg <= last_seg_next;

        s_axi_awready_reg <= s_axi_awready_next;
        s_axi_wready_reg <= s_axi_wready_next;
        s_axi_bid_reg <= s_axi_bid_next;
        s_axi_bresp_reg <= s_axi_bresp_next;
        s_axi_bvalid_reg <= s_axi_bvalid_next;

        m_axil_awaddr_reg <= m_axil_awaddr_next;
        m_axil_awprot_reg <= m_axil_awprot_next;
        m_axil_awvalid_reg <= m_axil_awvalid_next;
        m_axil_wdata_reg <= m_axil_wdata_next;
        m_axil_wstrb_reg <= m_axil_wstrb_next;
        m_axil_wvalid_reg <= m_axil_wvalid_next;
        m_axil_bready_reg <= m_axil_bready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axi_awready_reg <= 1'b0;
            s_axi_wready_reg <= 1'b0;
            s_axi_bvalid_reg <= 1'b0;

            m_axil_awvalid_reg <= 1'b0;
            m_axil_wvalid_reg <= 1'b0;
            m_axil_bready_reg <= 1'b0;
        end
    end

end

endmodule

`resetall
