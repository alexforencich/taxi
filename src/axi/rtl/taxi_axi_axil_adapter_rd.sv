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
 * AXI4 to AXI4-Lite adapter (read)
 */
module taxi_axi_axil_adapter_rd #
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
    taxi_axi_if.rd_slv   s_axi_rd,

    /*
     * AXI4-Lite master interface
     */
    taxi_axil_if.rd_mst  m_axil_rd
);

// extract parameters
localparam AXI_DATA_W = s_axi_rd.DATA_W;
localparam ADDR_W = s_axi_rd.ADDR_W;
localparam CL_ADDR_W = $clog2(ADDR_W);
localparam AXI_STRB_W = s_axi_rd.STRB_W;
localparam AXI_ID_W = s_axi_rd.ID_W;
localparam logic ARUSER_EN = s_axi_rd.ARUSER_EN && m_axil_rd.ARUSER_EN;
localparam ARUSER_W = s_axi_rd.ARUSER_W;
localparam logic RUSER_EN = s_axi_rd.RUSER_EN && m_axil_rd.RUSER_EN;
localparam RUSER_W = s_axi_rd.RUSER_W;

localparam AXIL_DATA_W = m_axil_rd.DATA_W;
localparam AXIL_STRB_W = m_axil_rd.STRB_W;

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

    typedef enum logic [0:0] {
        STATE_IDLE,
        STATE_DATA
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic [AXI_ID_W-1:0] id_reg = '0, id_next;
    logic [ADDR_W-1:0] addr_reg = '0, addr_next;
    logic [DATA_W-1:0] data_reg = '0, data_next;
    logic [1:0] resp_reg = 2'd0, resp_next;
    logic [7:0] burst_reg = 8'd0, burst_next;
    logic [2:0] burst_size_reg = 3'd0, burst_size_next;
    logic [7:0] master_burst_reg = 8'd0, master_burst_next;
    logic [2:0] master_burst_size_reg = 3'd0, master_burst_size_next;

    logic s_axi_arready_reg = 1'b0, s_axi_arready_next;
    logic [AXI_ID_W-1:0] s_axi_rid_reg = '0, s_axi_rid_next;
    logic [AXI_DATA_W-1:0] s_axi_rdata_reg = '0, s_axi_rdata_next;
    logic [1:0] s_axi_rresp_reg = 2'd0, s_axi_rresp_next;
    logic s_axi_rlast_reg = 1'b0, s_axi_rlast_next;
    logic s_axi_rvalid_reg = 1'b0, s_axi_rvalid_next;

    logic [ADDR_W-1:0] m_axil_araddr_reg = '0, m_axil_araddr_next;
    logic [2:0] m_axil_arprot_reg = 3'd0, m_axil_arprot_next;
    logic m_axil_arvalid_reg = 1'b0, m_axil_arvalid_next;
    logic m_axil_rready_reg = 1'b0, m_axil_rready_next;

    assign s_axi_rd.arready = s_axi_arready_reg;
    assign s_axi_rd.rid = s_axi_rid_reg;
    assign s_axi_rd.rdata = s_axi_rdata_reg;
    assign s_axi_rd.rresp = s_axi_rresp_reg;
    assign s_axi_rd.rlast = s_axi_rlast_reg;
    assign s_axi_rd.rvalid = s_axi_rvalid_reg;

    assign m_axil_rd.araddr = m_axil_araddr_reg;
    assign m_axil_rd.arprot = m_axil_arprot_reg;
    assign m_axil_rd.arvalid = m_axil_arvalid_reg;
    assign m_axil_rd.rready = m_axil_rready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        id_next = id_reg;
        addr_next = addr_reg;
        data_next = data_reg;
        resp_next = resp_reg;
        burst_next = burst_reg;
        burst_size_next = burst_size_reg;
        master_burst_next = master_burst_reg;
        master_burst_size_next = master_burst_size_reg;

        s_axi_arready_next = 1'b0;
        s_axi_rid_next = s_axi_rid_reg;
        s_axi_rdata_next = s_axi_rdata_reg;
        s_axi_rresp_next = s_axi_rresp_reg;
        s_axi_rlast_next = s_axi_rlast_reg;
        s_axi_rvalid_next = s_axi_rvalid_reg && !s_axi_rd.rready;
        m_axil_araddr_next = m_axil_araddr_reg;
        m_axil_arprot_next = m_axil_arprot_reg;
        m_axil_arvalid_next = m_axil_arvalid_reg && !m_axil_rd.arready;
        m_axil_rready_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                // idle state; wait for new burst
                s_axi_arready_next = !m_axil_rd.arvalid;

                if (s_axi_rd.arready && s_axi_rd.arvalid) begin
                    s_axi_arready_next = 1'b0;
                    id_next = s_axi_rd.arid;
                    m_axil_araddr_next = s_axi_rd.araddr;
                    addr_next = s_axi_rd.araddr;
                    burst_next = s_axi_rd.arlen;
                    burst_size_next = s_axi_rd.arsize;
                    m_axil_arprot_next = s_axi_rd.arprot;
                    m_axil_arvalid_next = 1'b1;
                    m_axil_rready_next = 1'b0;
                    state_next = STATE_DATA;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                // data state; transfer read data
                m_axil_rready_next = !s_axi_rd.rvalid && !m_axil_rd.arvalid;

                if (m_axil_rd.rready && m_axil_rd.rvalid) begin
                    s_axi_rid_next = id_reg;
                    s_axi_rdata_next = m_axil_rd.rdata;
                    s_axi_rresp_next = m_axil_rd.rresp;
                    s_axi_rlast_next = 1'b0;
                    s_axi_rvalid_next = 1'b1;
                    burst_next = burst_reg - 1;
                    addr_next = addr_reg + (1 << burst_size_reg);
                    if (burst_reg == 0) begin
                        // last data word, return to idle
                        m_axil_rready_next = 1'b0;
                        s_axi_rlast_next = 1'b1;
                        s_axi_arready_next = !m_axil_rd.arvalid;
                        state_next = STATE_IDLE;
                    end else begin
                        // start new AXI lite read
                        m_axil_araddr_next = addr_next;
                        m_axil_arvalid_next = 1'b1;
                        m_axil_rready_next = 1'b0;
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

        id_reg <= id_next;
        addr_reg <= addr_next;
        data_reg <= data_next;
        resp_reg <= resp_next;
        burst_reg <= burst_next;
        burst_size_reg <= burst_size_next;
        master_burst_reg <= master_burst_next;
        master_burst_size_reg <= master_burst_size_next;

        s_axi_arready_reg <= s_axi_arready_next;
        s_axi_rid_reg <= s_axi_rid_next;
        s_axi_rdata_reg <= s_axi_rdata_next;
        s_axi_rresp_reg <= s_axi_rresp_next;
        s_axi_rlast_reg <= s_axi_rlast_next;
        s_axi_rvalid_reg <= s_axi_rvalid_next;

        m_axil_araddr_reg <= m_axil_araddr_next;
        m_axil_arprot_reg <= m_axil_arprot_next;
        m_axil_arvalid_reg <= m_axil_arvalid_next;
        m_axil_rready_reg <= m_axil_rready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axi_arready_reg <= 1'b0;
            s_axi_rvalid_reg <= 1'b0;

            m_axil_arvalid_reg <= 1'b0;
            m_axil_rready_reg <= 1'b0;
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
        STATE_DATA_READ,
        STATE_DATA_SPLIT
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic [AXI_ID_W-1:0] id_reg = '0, id_next;
    logic [ADDR_W-1:0] addr_reg = '0, addr_next;
    logic [DATA_W-1:0] data_reg = '0, data_next;
    logic [1:0] resp_reg = 2'd0, resp_next;
    logic [7:0] burst_reg = 8'd0, burst_next;
    logic [2:0] burst_size_reg = 3'd0, burst_size_next;
    logic [7:0] master_burst_reg = 8'd0, master_burst_next;
    logic [2:0] master_burst_size_reg = 3'd0, master_burst_size_next;

    logic s_axi_arready_reg = 1'b0, s_axi_arready_next;
    logic [AXI_ID_W-1:0] s_axi_rid_reg = '0, s_axi_rid_next;
    logic [AXI_DATA_W-1:0] s_axi_rdata_reg = '0, s_axi_rdata_next;
    logic [1:0] s_axi_rresp_reg = 2'd0, s_axi_rresp_next;
    logic s_axi_rlast_reg = 1'b0, s_axi_rlast_next;
    logic s_axi_rvalid_reg = 1'b0, s_axi_rvalid_next;

    logic [ADDR_W-1:0] m_axil_araddr_reg = '0, m_axil_araddr_next;
    logic [2:0] m_axil_arprot_reg = 3'd0, m_axil_arprot_next;
    logic m_axil_arvalid_reg = 1'b0, m_axil_arvalid_next;
    logic m_axil_rready_reg = 1'b0, m_axil_rready_next;

    assign s_axi_rd.arready = s_axi_arready_reg;
    assign s_axi_rd.rid = s_axi_rid_reg;
    assign s_axi_rd.rdata = s_axi_rdata_reg;
    assign s_axi_rd.rresp = s_axi_rresp_reg;
    assign s_axi_rd.rlast = s_axi_rlast_reg;
    assign s_axi_rd.rvalid = s_axi_rvalid_reg;

    assign m_axil_rd.araddr = m_axil_araddr_reg;
    assign m_axil_rd.arprot = m_axil_arprot_reg;
    assign m_axil_rd.arvalid = m_axil_arvalid_reg;
    assign m_axil_rd.rready = m_axil_rready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        id_next = id_reg;
        addr_next = addr_reg;
        data_next = data_reg;
        resp_next = resp_reg;
        burst_next = burst_reg;
        burst_size_next = burst_size_reg;
        master_burst_next = master_burst_reg;
        master_burst_size_next = master_burst_size_reg;

        s_axi_arready_next = 1'b0;
        s_axi_rid_next = s_axi_rid_reg;
        s_axi_rdata_next = s_axi_rdata_reg;
        s_axi_rresp_next = s_axi_rresp_reg;
        s_axi_rlast_next = s_axi_rlast_reg;
        s_axi_rvalid_next = s_axi_rvalid_reg && !s_axi_rd.rready;
        m_axil_araddr_next = m_axil_araddr_reg;
        m_axil_arprot_next = m_axil_arprot_reg;
        m_axil_arvalid_next = m_axil_arvalid_reg && !m_axil_rd.arready;
        m_axil_rready_next = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                // idle state; wait for new burst
                s_axi_arready_next = !m_axil_rd.arvalid;

                if (s_axi_rd.arready && s_axi_rd.arvalid) begin
                    s_axi_arready_next = 1'b0;
                    id_next = s_axi_rd.arid;
                    m_axil_araddr_next = s_axi_rd.araddr;
                    addr_next = s_axi_rd.araddr;
                    burst_next = s_axi_rd.arlen;
                    burst_size_next = s_axi_rd.arsize;
                    if (CONVERT_BURST && s_axi_rd.arcache[1] && (CONVERT_NARROW_BURST || s_axi_rd.arsize == AXI_BURST_SIZE)) begin
                        // split reads
                        // require CONVERT_BURST and arcache[1] set
                        master_burst_size_next = AXIL_BURST_SIZE;
                        state_next = STATE_DATA_READ;
                    end else begin
                        // output narrow burst
                        master_burst_size_next = s_axi_rd.arsize;
                        state_next = STATE_DATA;
                    end
                    m_axil_arprot_next = s_axi_rd.arprot;
                    m_axil_arvalid_next = 1'b1;
                    m_axil_rready_next = 1'b0;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                m_axil_rready_next = !s_axi_rd.rvalid && !m_axil_rd.arvalid;

                if (m_axil_rd.rready && m_axil_rd.rvalid) begin
                    s_axi_rid_next = id_reg;
                    s_axi_rdata_next = m_axil_rd.rdata[addr_reg[AXIL_ADDR_BIT_OFFSET-1:AXI_ADDR_BIT_OFFSET] * AXI_DATA_W +: AXI_DATA_W];
                    s_axi_rresp_next = m_axil_rd.rresp;
                    s_axi_rlast_next = 1'b0;
                    s_axi_rvalid_next = 1'b1;
                    burst_next = burst_reg - 1;
                    addr_next = addr_reg + (1 << burst_size_reg);
                    if (burst_reg == 0) begin
                        // last data word, return to idle
                        m_axil_rready_next = 1'b0;
                        s_axi_rlast_next = 1'b1;
                        s_axi_arready_next = !m_axil_rd.arvalid;
                        state_next = STATE_IDLE;
                    end else begin
                        // start new AXI lite read
                        m_axil_araddr_next = addr_next;
                        m_axil_arvalid_next = 1'b1;
                        m_axil_rready_next = 1'b0;
                        state_next = STATE_DATA;
                    end
                end else begin
                    state_next = STATE_DATA;
                end
            end
            STATE_DATA_READ: begin
                m_axil_rready_next = !s_axi_rd.rvalid && !m_axil_rd.arvalid;

                if (m_axil_rd.rready && m_axil_rd.rvalid) begin
                    s_axi_rid_next = id_reg;
                    data_next = m_axil_rd.rdata;
                    resp_next = m_axil_rd.rresp;
                    s_axi_rdata_next = m_axil_rd.rdata[addr_reg[AXIL_ADDR_BIT_OFFSET-1:AXI_ADDR_BIT_OFFSET] * AXI_DATA_W +: AXI_DATA_W];
                    s_axi_rresp_next = m_axil_rd.rresp;
                    s_axi_rlast_next = 1'b0;
                    s_axi_rvalid_next = 1'b1;
                    burst_next = burst_reg - 1;
                    addr_next = addr_reg + (1 << burst_size_reg);
                    if (burst_reg == 0) begin
                        m_axil_rready_next = 1'b0;
                        s_axi_arready_next = !m_axil_rd.arvalid;
                        s_axi_rlast_next = 1'b1;
                        state_next = STATE_IDLE;
                    end else if (addr_next[CL_ADDR_W'(master_burst_size_reg)] != addr_reg[CL_ADDR_W'(master_burst_size_reg)]) begin
                        // start new AXI lite read
                        m_axil_araddr_next = addr_next;
                        m_axil_arvalid_next = 1'b1;
                        m_axil_rready_next = 1'b0;
                        state_next = STATE_DATA_READ;
                    end else begin
                        m_axil_rready_next = 1'b0;
                        state_next = STATE_DATA_SPLIT;
                    end
                end else begin
                    state_next = STATE_DATA_READ;
                end
            end
            STATE_DATA_SPLIT: begin
                m_axil_rready_next = 1'b0;

                if (s_axi_rd.rready || !s_axi_rd.rvalid) begin
                    s_axi_rid_next = id_reg;
                    s_axi_rdata_next = data_reg[addr_reg[AXIL_ADDR_BIT_OFFSET-1:AXI_ADDR_BIT_OFFSET] * AXI_DATA_W +: AXI_DATA_W];
                    s_axi_rresp_next = resp_reg;
                    s_axi_rlast_next = 1'b0;
                    s_axi_rvalid_next = 1'b1;
                    burst_next = burst_reg - 1;
                    addr_next = addr_reg + (1 << burst_size_reg);
                    if (burst_reg == 0) begin
                        s_axi_arready_next = !m_axil_rd.arvalid;
                        s_axi_rlast_next = 1'b1;
                        state_next = STATE_IDLE;
                    end else if (addr_next[CL_ADDR_W'(master_burst_size_reg)] != addr_reg[CL_ADDR_W'(master_burst_size_reg)]) begin
                        // start new AXI lite read
                        m_axil_araddr_next = addr_next;
                        m_axil_arvalid_next = 1'b1;
                        m_axil_rready_next = 1'b0;
                        state_next = STATE_DATA_READ;
                    end else begin
                        state_next = STATE_DATA_SPLIT;
                    end
                end else begin
                    state_next = STATE_DATA_SPLIT;
                end
            end
        endcase
    end

    always_ff @(posedge clk) begin
        state_reg <= state_next;

        id_reg <= id_next;
        addr_reg <= addr_next;
        data_reg <= data_next;
        resp_reg <= resp_next;
        burst_reg <= burst_next;
        burst_size_reg <= burst_size_next;
        master_burst_reg <= master_burst_next;
        master_burst_size_reg <= master_burst_size_next;

        s_axi_arready_reg <= s_axi_arready_next;
        s_axi_rid_reg <= s_axi_rid_next;
        s_axi_rdata_reg <= s_axi_rdata_next;
        s_axi_rresp_reg <= s_axi_rresp_next;
        s_axi_rlast_reg <= s_axi_rlast_next;
        s_axi_rvalid_reg <= s_axi_rvalid_next;

        m_axil_araddr_reg <= m_axil_araddr_next;
        m_axil_arprot_reg <= m_axil_arprot_next;
        m_axil_arvalid_reg <= m_axil_arvalid_next;
        m_axil_rready_reg <= m_axil_rready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axi_arready_reg <= 1'b0;
            s_axi_rvalid_reg <= 1'b0;

            m_axil_arvalid_reg <= 1'b0;
            m_axil_rready_reg <= 1'b0;
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
        STATE_DATA
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic [AXI_ID_W-1:0] id_reg = '0, id_next;
    logic [ADDR_W-1:0] addr_reg = '0, addr_next;
    logic [DATA_W-1:0] data_reg = '0, data_next;
    logic [1:0] resp_reg = 2'd0, resp_next;
    logic [7:0] burst_reg = '0, burst_next;
    logic [2:0] burst_size_reg = '0, burst_size_next;
    logic [15:0] master_burst_reg = '0, master_burst_next;
    logic [2:0] master_burst_size_reg = '0, master_burst_size_next;

    logic s_axi_arready_reg = 1'b0, s_axi_arready_next;
    logic [AXI_ID_W-1:0] s_axi_rid_reg = '0, s_axi_rid_next;
    logic [AXI_DATA_W-1:0] s_axi_rdata_reg = '0, s_axi_rdata_next;
    logic [1:0] s_axi_rresp_reg = 2'd0, s_axi_rresp_next;
    logic s_axi_rlast_reg = 1'b0, s_axi_rlast_next;
    logic s_axi_rvalid_reg = 1'b0, s_axi_rvalid_next;

    logic [ADDR_W-1:0] m_axil_araddr_reg = '0, m_axil_araddr_next;
    logic [2:0] m_axil_arprot_reg = 3'd0, m_axil_arprot_next;
    logic m_axil_arvalid_reg = 1'b0, m_axil_arvalid_next;
    logic m_axil_rready_reg = 1'b0, m_axil_rready_next;

    assign s_axi_rd.arready = s_axi_arready_reg;
    assign s_axi_rd.rid = s_axi_rid_reg;
    assign s_axi_rd.rdata = s_axi_rdata_reg;
    assign s_axi_rd.rresp = s_axi_rresp_reg;
    assign s_axi_rd.rlast = s_axi_rlast_reg;
    assign s_axi_rd.rvalid = s_axi_rvalid_reg;

    assign m_axil_rd.araddr = m_axil_araddr_reg;
    assign m_axil_rd.arprot = m_axil_arprot_reg;
    assign m_axil_rd.arvalid = m_axil_arvalid_reg;
    assign m_axil_rd.rready = m_axil_rready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        id_next = id_reg;
        addr_next = addr_reg;
        data_next = data_reg;
        resp_next = resp_reg;
        burst_next = burst_reg;
        burst_size_next = burst_size_reg;
        master_burst_next = master_burst_reg;
        master_burst_size_next = master_burst_size_reg;

        s_axi_arready_next = 1'b0;
        s_axi_rid_next = s_axi_rid_reg;
        s_axi_rdata_next = s_axi_rdata_reg;
        s_axi_rresp_next = s_axi_rresp_reg;
        s_axi_rlast_next = s_axi_rlast_reg;
        s_axi_rvalid_next = s_axi_rvalid_reg && !s_axi_rd.rready;
        m_axil_araddr_next = m_axil_araddr_reg;
        m_axil_arprot_next = m_axil_arprot_reg;
        m_axil_arvalid_next = m_axil_arvalid_reg && !m_axil_rd.arready;
        m_axil_rready_next = 1'b0;

        // master output is narrower; merge reads and possibly split burst
        case (state_reg)
            STATE_IDLE: begin
                // idle state; wait for new burst
                s_axi_arready_next = !m_axil_rd.arvalid;

                resp_next = 2'd0;

                if (s_axi_rd.arready && s_axi_rd.arvalid) begin
                    s_axi_arready_next = 1'b0;
                    id_next = s_axi_rd.arid;
                    m_axil_araddr_next = s_axi_rd.araddr;
                    addr_next = s_axi_rd.araddr;
                    burst_next = s_axi_rd.arlen;
                    burst_size_next = s_axi_rd.arsize;
                    if (s_axi_rd.arsize > AXIL_BURST_SIZE) begin
                        // need to adjust burst size
                        master_burst_next = 16'({8'd0, s_axi_rd.arlen} << 3'(s_axi_rd.arsize-AXIL_BURST_SIZE)) | 16'(8'(8'(~s_axi_rd.araddr) & 8'(8'hff >> (8-s_axi_rd.arsize))) >> AXIL_BURST_SIZE);
                        master_burst_size_next = AXIL_BURST_SIZE;
                    end else begin
                        // pass through narrow (enough) burst
                        master_burst_next = 16'(s_axi_rd.arlen);
                        master_burst_size_next = s_axi_rd.arsize;
                    end
                    m_axil_arprot_next = s_axi_rd.arprot;
                    m_axil_arvalid_next = 1'b1;
                    m_axil_rready_next = 1'b0;
                    state_next = STATE_DATA;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                m_axil_rready_next = !s_axi_rd.rvalid && !m_axil_rd.arvalid;

                if (m_axil_rd.rready && m_axil_rd.rvalid) begin
                    data_next[addr_reg[AXI_ADDR_BIT_OFFSET-1:AXIL_ADDR_BIT_OFFSET]*SEG_DATA_W +: SEG_DATA_W] = m_axil_rd.rdata;
                    if (m_axil_rd.rresp != 0) begin
                        resp_next = m_axil_rd.rresp;
                    end
                    s_axi_rid_next = id_reg;
                    s_axi_rdata_next = data_next;
                    s_axi_rresp_next = resp_next;
                    s_axi_rlast_next = 1'b0;
                    s_axi_rvalid_next = 1'b0;
                    master_burst_next = master_burst_reg - 1;
                    addr_next = (addr_reg + (1 << master_burst_size_reg)) & ({ADDR_W{1'b1}} << master_burst_size_reg);
                    m_axil_araddr_next = addr_next;
                    if (addr_next[CL_ADDR_W'(burst_size_reg)] != addr_reg[CL_ADDR_W'(burst_size_reg)]) begin
                        burst_next = burst_reg - 1;
                        s_axi_rvalid_next = 1'b1;
                    end
                    if (master_burst_reg == 0) begin
                        if (burst_reg == 0) begin
                            m_axil_rready_next = 1'b0;
                            s_axi_rlast_next = 1'b1;
                            s_axi_rvalid_next = 1'b1;
                            s_axi_arready_next = !m_axil_rd.arvalid;
                            state_next = STATE_IDLE;
                        end else begin
                            m_axil_arvalid_next = 1'b1;
                            m_axil_rready_next = 1'b0;
                            state_next = STATE_DATA;
                        end
                    end else begin
                        m_axil_arvalid_next = 1'b1;
                        m_axil_rready_next = 1'b0;
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

        id_reg <= id_next;
        addr_reg <= addr_next;
        data_reg <= data_next;
        resp_reg <= resp_next;
        burst_reg <= burst_next;
        burst_size_reg <= burst_size_next;
        master_burst_reg <= master_burst_next;
        master_burst_size_reg <= master_burst_size_next;

        s_axi_arready_reg <= s_axi_arready_next;
        s_axi_rid_reg <= s_axi_rid_next;
        s_axi_rdata_reg <= s_axi_rdata_next;
        s_axi_rresp_reg <= s_axi_rresp_next;
        s_axi_rlast_reg <= s_axi_rlast_next;
        s_axi_rvalid_reg <= s_axi_rvalid_next;

        m_axil_araddr_reg <= m_axil_araddr_next;
        m_axil_arprot_reg <= m_axil_arprot_next;
        m_axil_arvalid_reg <= m_axil_arvalid_next;
        m_axil_rready_reg <= m_axil_rready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axi_arready_reg <= 1'b0;
            s_axi_rvalid_reg <= 1'b0;

            m_axil_arvalid_reg <= 1'b0;
            m_axil_rready_reg <= 1'b0;
        end
    end

end

endmodule

`resetall
