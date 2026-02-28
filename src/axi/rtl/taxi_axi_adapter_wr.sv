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
 * AXI4 width adapter
 */
module taxi_axi_adapter_wr #
(
    // When adapting to a wider bus, re-pack full-width burst instead of passing through narrow burst if possible
    parameter logic CONVERT_BURST = 1'b1,
    // When adapting to a wider bus, re-pack all bursts instead of passing through narrow burst if possible
    parameter logic CONVERT_NARROW_BURST = 1'b0
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
localparam S_DATA_W = s_axi_wr.DATA_W;
localparam ADDR_W = s_axi_wr.ADDR_W;
localparam CL_ADDR_W = $clog2(ADDR_W);
localparam S_STRB_W = s_axi_wr.STRB_W;
localparam ID_W = s_axi_wr.ID_W;
localparam logic AWUSER_EN = s_axi_wr.AWUSER_EN && m_axi_wr.AWUSER_EN;
localparam AWUSER_W = s_axi_wr.AWUSER_W;
localparam logic WUSER_EN = s_axi_wr.WUSER_EN && m_axi_wr.WUSER_EN;
localparam WUSER_W = s_axi_wr.WUSER_W;
localparam logic BUSER_EN = s_axi_wr.BUSER_EN && m_axi_wr.BUSER_EN;
localparam BUSER_W = s_axi_wr.BUSER_W;

localparam M_DATA_W = m_axi_wr.DATA_W;
localparam M_STRB_W = m_axi_wr.STRB_W;

localparam S_ADDR_BIT_OFFSET = $clog2(S_STRB_W);
localparam M_ADDR_BIT_OFFSET = $clog2(M_STRB_W);
localparam S_BYTE_LANES = S_STRB_W;
localparam M_BYTE_LANES = M_STRB_W;
localparam S_BYTE_SIZE = S_DATA_W/S_BYTE_LANES;
localparam M_BYTE_SIZE = M_DATA_W/M_BYTE_LANES;
localparam logic [2:0] S_BURST_SIZE = 3'($clog2(S_STRB_W));
localparam logic [2:0] M_BURST_SIZE = 3'($clog2(M_STRB_W));

// check configuration
if (S_BYTE_SIZE * S_STRB_W != S_DATA_W)
    $fatal(0, "Error: AXI slave interface data width not evenly divisible (instance %m)");

if (M_BYTE_SIZE * M_STRB_W != M_DATA_W)
    $fatal(0, "Error: AXI master interface data width not evenly divisible (instance %m)");

if (S_BYTE_SIZE != M_BYTE_SIZE)
    $fatal(0, "Error: byte size mismatch (instance %m)");

if (2**$clog2(S_BYTE_LANES) != S_BYTE_LANES)
    $fatal(0, "Error: AXI slave interface byte lane count must be even power of two (instance %m)");

if (2**$clog2(M_BYTE_LANES) != M_BYTE_LANES)
    $fatal(0, "Error: AXI master interface byte lane count must be even power of two (instance %m)");

if (M_BYTE_LANES == S_BYTE_LANES) begin : bypass
    // same width; bypass

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

    assign m_axi_wr.wdata = s_axi_wr.wdata;
    assign m_axi_wr.wstrb = s_axi_wr.wstrb;
    assign m_axi_wr.wlast = s_axi_wr.wlast;
    assign m_axi_wr.wuser = WUSER_EN ? s_axi_wr.wuser : '0;
    assign m_axi_wr.wvalid = s_axi_wr.wvalid;
    assign s_axi_wr.wready = m_axi_wr.wready;

    assign s_axi_wr.bid = m_axi_wr.bid;
    assign s_axi_wr.bresp = m_axi_wr.bresp;
    assign s_axi_wr.buser = BUSER_EN ? m_axi_wr.buser : '0;
    assign s_axi_wr.bvalid = m_axi_wr.bvalid;
    assign m_axi_wr.bready = s_axi_wr.bready;

end else if (M_BYTE_LANES > S_BYTE_LANES) begin : upsize
    // output is wider; upsize

    // output bus is wider
    localparam EXPAND = M_BYTE_LANES > S_BYTE_LANES;
    localparam DATA_W = EXPAND ? M_DATA_W : S_DATA_W;
    localparam STRB_W = EXPAND ? M_STRB_W : S_STRB_W;
    // required number of segments in wider bus
    localparam SEG_COUNT = EXPAND ? (M_BYTE_LANES / S_BYTE_LANES) : (S_BYTE_LANES / M_BYTE_LANES);
    localparam CL_SEG_COUNT = $clog2(SEG_COUNT);
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

    logic [ID_W-1:0] id_reg = '0, id_next;
    logic [ADDR_W-1:0] addr_reg = '0, addr_next;
    logic [DATA_W-1:0] data_reg = '0, data_next;
    logic [STRB_W-1:0] strb_reg = '0, strb_next;
    logic [WUSER_W-1:0] wuser_reg = '0, wuser_next;
    logic [7:0] burst_reg = '0, burst_next;
    logic [2:0] burst_size_reg = '0, burst_size_next;
    logic [2:0] master_burst_size_reg = '0, master_burst_size_next;
    logic burst_active_reg = 1'b0, burst_active_next;
    logic first_transfer_reg = 1'b0, first_transfer_next;

    logic s_axi_awready_reg = 1'b0, s_axi_awready_next;
    logic s_axi_wready_reg = 1'b0, s_axi_wready_next;
    logic [ID_W-1:0] s_axi_bid_reg = '0, s_axi_bid_next;
    logic [1:0] s_axi_bresp_reg = '0, s_axi_bresp_next;
    logic [BUSER_W-1:0] s_axi_buser_reg = '0, s_axi_buser_next;
    logic s_axi_bvalid_reg = 1'b0, s_axi_bvalid_next;

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
    logic m_axi_bready_reg = 1'b0, m_axi_bready_next;

    // internal datapath
    logic  [M_DATA_W-1:0] m_axi_wdata_int;
    logic  [M_STRB_W-1:0] m_axi_wstrb_int;
    logic                 m_axi_wlast_int;
    logic  [WUSER_W-1:0]  m_axi_wuser_int;
    logic                 m_axi_wvalid_int;
    logic                 m_axi_wready_int_reg = 1'b0;
    wire                  m_axi_wready_int_early;

    assign s_axi_wr.awready = s_axi_awready_reg;
    assign s_axi_wr.wready = s_axi_wready_reg;
    assign s_axi_wr.bid = s_axi_bid_reg;
    assign s_axi_wr.bresp = s_axi_bresp_reg;
    assign s_axi_wr.buser = BUSER_EN ? s_axi_buser_reg : '0;
    assign s_axi_wr.bvalid = s_axi_bvalid_reg;

    assign m_axi_wr.awid = '0;
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
    assign m_axi_wr.bready = m_axi_bready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        id_next = id_reg;
        addr_next = addr_reg;
        data_next = data_reg;
        strb_next = strb_reg;
        wuser_next = wuser_reg;
        burst_next = burst_reg;
        burst_size_next = burst_size_reg;
        master_burst_size_next = master_burst_size_reg;
        burst_active_next = burst_active_reg;
        first_transfer_next = first_transfer_reg;

        s_axi_awready_next = 1'b0;
        s_axi_wready_next = 1'b0;
        s_axi_bid_next = s_axi_bid_reg;
        s_axi_bresp_next = s_axi_bresp_reg;
        s_axi_buser_next = s_axi_buser_reg;
        s_axi_bvalid_next = s_axi_bvalid_reg && !s_axi_wr.bready;
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
        m_axi_bready_next = 1'b0;

        m_axi_wdata_int = {(M_BYTE_LANES/S_BYTE_LANES){s_axi_wr.wdata}};
        m_axi_wstrb_int = 0;
        m_axi_wstrb_int[addr_reg[M_ADDR_BIT_OFFSET-1:S_ADDR_BIT_OFFSET] * S_STRB_W +: S_STRB_W] = s_axi_wr.wstrb;
        m_axi_wlast_int = s_axi_wr.wlast;
        m_axi_wuser_int = s_axi_wr.wuser;
        m_axi_wvalid_int = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                // idle state; wait for new burst
                s_axi_awready_next = !m_axi_wr.awvalid;

                strb_next = '0;

                if (s_axi_wr.awready && s_axi_wr.awvalid) begin
                    s_axi_awready_next = 1'b0;
                    id_next = s_axi_wr.awid;
                    m_axi_awid_next = s_axi_wr.awid;
                    m_axi_awaddr_next = s_axi_wr.awaddr;
                    addr_next = s_axi_wr.awaddr;
                    burst_next = s_axi_wr.awlen;
                    burst_size_next = s_axi_wr.awsize;
                    if (CONVERT_BURST && s_axi_wr.awcache[1] && (CONVERT_NARROW_BURST || s_axi_wr.awsize == S_BURST_SIZE)) begin
                        // merge writes
                        // require CONVERT_BURST and awcache[1] set
                        master_burst_size_next = M_BURST_SIZE;
                        if (CONVERT_NARROW_BURST) begin
                            m_axi_awlen_next = 8'((({8'd0, s_axi_wr.awlen} << s_axi_wr.awsize) + 16'(s_axi_wr.awaddr[M_ADDR_BIT_OFFSET-1:0])) >> M_BURST_SIZE);
                        end else begin
                            m_axi_awlen_next = (s_axi_wr.awlen + 8'(s_axi_wr.awaddr[M_ADDR_BIT_OFFSET-1:S_ADDR_BIT_OFFSET])) >> CL_SEG_COUNT;
                        end
                        m_axi_awsize_next = M_BURST_SIZE;
                        state_next = STATE_DATA_2;
                    end else begin
                        // output narrow burst
                        master_burst_size_next = s_axi_wr.awsize;
                        m_axi_awlen_next = s_axi_wr.awlen;
                        m_axi_awsize_next = s_axi_wr.awsize;
                        state_next = STATE_DATA;
                    end
                    m_axi_awburst_next = s_axi_wr.awburst;
                    m_axi_awlock_next = s_axi_wr.awlock;
                    m_axi_awcache_next = s_axi_wr.awcache;
                    m_axi_awprot_next = s_axi_wr.awprot;
                    m_axi_awqos_next = s_axi_wr.awqos;
                    m_axi_awregion_next = s_axi_wr.awregion;
                    m_axi_awuser_next = s_axi_wr.awuser;
                    m_axi_awvalid_next = 1'b1;
                    s_axi_wready_next = m_axi_wready_int_early;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                // data state; transfer write data
                s_axi_wready_next = m_axi_wready_int_early;

                if (s_axi_wr.wready && s_axi_wr.wvalid) begin
                    m_axi_wdata_int = {(M_BYTE_LANES/S_BYTE_LANES){s_axi_wr.wdata}};
                    m_axi_wstrb_int = 0;
                    m_axi_wstrb_int[addr_reg[M_ADDR_BIT_OFFSET-1:S_ADDR_BIT_OFFSET] * S_STRB_W +: S_STRB_W] = s_axi_wr.wstrb;
                    m_axi_wlast_int = s_axi_wr.wlast;
                    m_axi_wuser_int = s_axi_wr.wuser;
                    m_axi_wvalid_int = 1'b1;
                    addr_next = addr_reg + (1 << burst_size_reg);
                    if (s_axi_wr.wlast) begin
                        s_axi_wready_next = 1'b0;
                        m_axi_bready_next = !s_axi_wr.bvalid;
                        state_next = STATE_RESP;
                    end else begin
                        state_next = STATE_DATA;
                    end
                end else begin
                    state_next = STATE_DATA;
                end
            end
            STATE_DATA_2: begin
                s_axi_wready_next = m_axi_wready_int_early;

                if (s_axi_wr.wready && s_axi_wr.wvalid) begin
                    if (CONVERT_NARROW_BURST) begin
                        for (integer i = 0; i < S_BYTE_LANES; i = i + 1) begin
                            if (s_axi_wr.wstrb[i]) begin
                                data_next[addr_reg[M_ADDR_BIT_OFFSET-1:S_ADDR_BIT_OFFSET]*SEG_DATA_W+i*M_BYTE_SIZE +: M_BYTE_SIZE] = s_axi_wr.wdata[i*M_BYTE_SIZE +: M_BYTE_SIZE];
                                strb_next[addr_reg[M_ADDR_BIT_OFFSET-1:S_ADDR_BIT_OFFSET]*SEG_STRB_W+i] = 1'b1;
                            end
                        end
                    end else begin
                        data_next[addr_reg[M_ADDR_BIT_OFFSET-1:S_ADDR_BIT_OFFSET]*SEG_DATA_W +: SEG_DATA_W] = s_axi_wr.wdata;
                        strb_next[addr_reg[M_ADDR_BIT_OFFSET-1:S_ADDR_BIT_OFFSET]*SEG_STRB_W +: SEG_STRB_W] = s_axi_wr.wstrb;
                    end
                    m_axi_wdata_int = data_next;
                    m_axi_wstrb_int = strb_next;
                    m_axi_wlast_int = s_axi_wr.wlast;
                    m_axi_wuser_int = s_axi_wr.wuser;
                    burst_next = burst_reg - 1;
                    addr_next = addr_reg + (1 << burst_size_reg);
                    if (addr_next[CL_ADDR_W'(master_burst_size_reg)] != addr_reg[CL_ADDR_W'(master_burst_size_reg)]) begin
                        strb_next = '0;
                        m_axi_wvalid_int = 1'b1;
                    end
                    if (burst_reg == 0) begin
                        m_axi_wvalid_int = 1'b1;
                        s_axi_wready_next = 1'b0;
                        m_axi_bready_next = !s_axi_wr.bvalid;
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
                m_axi_bready_next = !s_axi_wr.bvalid;

                if (m_axi_wr.bready && m_axi_wr.bvalid) begin
                    m_axi_bready_next = 1'b0;
                    s_axi_bid_next = id_reg;
                    s_axi_bresp_next = m_axi_wr.bresp;
                    s_axi_buser_next = m_axi_wr.buser;
                    s_axi_bvalid_next = 1'b1;
                    s_axi_awready_next = !m_axi_wr.awvalid;
                    state_next = STATE_IDLE;
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
        wuser_reg <= wuser_next;
        burst_reg <= burst_next;
        burst_size_reg <= burst_size_next;
        master_burst_size_reg <= master_burst_size_next;
        burst_active_reg <= burst_active_next;
        first_transfer_reg <= first_transfer_next;

        s_axi_awready_reg <= s_axi_awready_next;
        s_axi_wready_reg <= s_axi_wready_next;
        s_axi_bid_reg <= s_axi_bid_next;
        s_axi_bresp_reg <= s_axi_bresp_next;
        s_axi_buser_reg <= s_axi_buser_next;
        s_axi_bvalid_reg <= s_axi_bvalid_next;

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
        m_axi_bready_reg <= m_axi_bready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axi_awready_reg <= 1'b0;
            s_axi_wready_reg <= 1'b0;
            s_axi_bvalid_reg <= 1'b0;

            m_axi_awvalid_reg <= 1'b0;
            m_axi_bready_reg <= 1'b0;
        end
    end

    // output datapath logic
    logic [M_DATA_W-1:0] m_axi_wdata_reg  = '0;
    logic [M_STRB_W-1:0] m_axi_wstrb_reg  = '0;
    logic                m_axi_wlast_reg  = 1'b0;
    logic [WUSER_W-1:0]  m_axi_wuser_reg  = 1'b0;
    logic                m_axi_wvalid_reg = 1'b0, m_axi_wvalid_next;

    logic [M_DATA_W-1:0] temp_m_axi_wdata_reg  = '0;
    logic [M_STRB_W-1:0] temp_m_axi_wstrb_reg  = '0;
    logic                temp_m_axi_wlast_reg  = 1'b0;
    logic [WUSER_W-1:0]  temp_m_axi_wuser_reg  = 1'b0;
    logic                temp_m_axi_wvalid_reg = 1'b0, temp_m_axi_wvalid_next;

    // datapath control
    logic store_axi_w_int_to_output;
    logic store_axi_w_int_to_temp;
    logic store_axi_w_temp_to_output;

    assign m_axi_wr.wdata  = m_axi_wdata_reg;
    assign m_axi_wr.wstrb  = m_axi_wstrb_reg;
    assign m_axi_wr.wlast  = m_axi_wlast_reg;
    assign m_axi_wr.wuser  = WUSER_EN ? m_axi_wuser_reg : '0;
    assign m_axi_wr.wvalid = m_axi_wvalid_reg;

    // enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
    assign m_axi_wready_int_early = m_axi_wr.wready | (~temp_m_axi_wvalid_reg & (~m_axi_wvalid_reg | ~m_axi_wvalid_int));

    always_comb begin
        // transfer sink ready state to source
        m_axi_wvalid_next = m_axi_wvalid_reg;
        temp_m_axi_wvalid_next = temp_m_axi_wvalid_reg;

        store_axi_w_int_to_output = 1'b0;
        store_axi_w_int_to_temp = 1'b0;
        store_axi_w_temp_to_output = 1'b0;

        if (m_axi_wready_int_reg) begin
            // input is ready
            if (m_axi_wr.wready | ~m_axi_wvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_axi_wvalid_next = m_axi_wvalid_int;
                store_axi_w_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_axi_wvalid_next = m_axi_wvalid_int;
                store_axi_w_int_to_temp = 1'b1;
            end
        end else if (m_axi_wr.wready) begin
            // input is not ready, but output is ready
            m_axi_wvalid_next = temp_m_axi_wvalid_reg;
            temp_m_axi_wvalid_next = 1'b0;
            store_axi_w_temp_to_output = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            m_axi_wvalid_reg <= 1'b0;
            m_axi_wready_int_reg <= 1'b0;
            temp_m_axi_wvalid_reg <= 1'b0;
        end else begin
            m_axi_wvalid_reg <= m_axi_wvalid_next;
            m_axi_wready_int_reg <= m_axi_wready_int_early;
            temp_m_axi_wvalid_reg <= temp_m_axi_wvalid_next;
        end

        // datapath
        if (store_axi_w_int_to_output) begin
            m_axi_wdata_reg <= m_axi_wdata_int;
            m_axi_wstrb_reg <= m_axi_wstrb_int;
            m_axi_wlast_reg <= m_axi_wlast_int;
            m_axi_wuser_reg <= m_axi_wuser_int;
        end else if (store_axi_w_temp_to_output) begin
            m_axi_wdata_reg <= temp_m_axi_wdata_reg;
            m_axi_wstrb_reg <= temp_m_axi_wstrb_reg;
            m_axi_wlast_reg <= temp_m_axi_wlast_reg;
            m_axi_wuser_reg <= temp_m_axi_wuser_reg;
        end

        if (store_axi_w_int_to_temp) begin
            temp_m_axi_wdata_reg <= m_axi_wdata_int;
            temp_m_axi_wstrb_reg <= m_axi_wstrb_int;
            temp_m_axi_wlast_reg <= m_axi_wlast_int;
            temp_m_axi_wuser_reg <= m_axi_wuser_int;
        end
    end

end else begin : downsize
    // output is narrower; downsize

    // output bus is wider
    localparam EXPAND = M_BYTE_LANES > S_BYTE_LANES;
    localparam DATA_W = EXPAND ? M_DATA_W : S_DATA_W;
    localparam STRB_W = EXPAND ? M_STRB_W : S_STRB_W;
    // required number of segments in wider bus
    localparam SEG_COUNT = EXPAND ? (M_BYTE_LANES / S_BYTE_LANES) : (S_BYTE_LANES / M_BYTE_LANES);
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

    logic [ID_W-1:0] id_reg = '0, id_next;
    logic [ADDR_W-1:0] addr_reg = '0, addr_next;
    logic [DATA_W-1:0] data_reg = '0, data_next;
    logic [STRB_W-1:0] strb_reg = '0, strb_next;
    logic [WUSER_W-1:0] wuser_reg = '0, wuser_next;
    logic [7:0] burst_reg = '0, burst_next;
    logic [2:0] burst_size_reg = '0, burst_size_next;
    logic [7:0] master_burst_reg = '0, master_burst_next;
    logic [2:0] master_burst_size_reg = '0, master_burst_size_next;
    logic burst_active_reg = 1'b0, burst_active_next;
    logic first_transfer_reg = 1'b0, first_transfer_next;

    logic s_axi_awready_reg = 1'b0, s_axi_awready_next;
    logic s_axi_wready_reg = 1'b0, s_axi_wready_next;
    logic [ID_W-1:0] s_axi_bid_reg = '0, s_axi_bid_next;
    logic [1:0] s_axi_bresp_reg = '0, s_axi_bresp_next;
    logic [BUSER_W-1:0] s_axi_buser_reg = '0, s_axi_buser_next;
    logic s_axi_bvalid_reg = 1'b0, s_axi_bvalid_next;

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
    logic m_axi_bready_reg = 1'b0, m_axi_bready_next;

    // internal datapath
    logic  [M_DATA_W-1:0] m_axi_wdata_int;
    logic  [M_STRB_W-1:0] m_axi_wstrb_int;
    logic                 m_axi_wlast_int;
    logic  [WUSER_W-1:0]  m_axi_wuser_int;
    logic                 m_axi_wvalid_int;
    logic                 m_axi_wready_int_reg = 1'b0;
    wire                  m_axi_wready_int_early;

    assign s_axi_wr.awready = s_axi_awready_reg;
    assign s_axi_wr.wready = s_axi_wready_reg;
    assign s_axi_wr.bid = s_axi_bid_reg;
    assign s_axi_wr.bresp = s_axi_bresp_reg;
    assign s_axi_wr.buser = BUSER_EN ? s_axi_buser_reg : '0;
    assign s_axi_wr.bvalid = s_axi_bvalid_reg;

    assign m_axi_wr.awid = '0;
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
    assign m_axi_wr.bready = m_axi_bready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        id_next = id_reg;
        addr_next = addr_reg;
        data_next = data_reg;
        strb_next = strb_reg;
        wuser_next = wuser_reg;
        burst_next = burst_reg;
        burst_size_next = burst_size_reg;
        master_burst_next = master_burst_reg;
        master_burst_size_next = master_burst_size_reg;
        burst_active_next = burst_active_reg;
        first_transfer_next = first_transfer_reg;

        s_axi_awready_next = 1'b0;
        s_axi_wready_next = 1'b0;
        s_axi_bid_next = s_axi_bid_reg;
        s_axi_bresp_next = s_axi_bresp_reg;
        s_axi_buser_next = s_axi_buser_reg;
        s_axi_bvalid_next = s_axi_bvalid_reg && !s_axi_wr.bready;
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
        m_axi_bready_next = 1'b0;

        m_axi_wdata_int = data_reg[addr_reg[S_ADDR_BIT_OFFSET-1:M_ADDR_BIT_OFFSET] * M_DATA_W +: M_DATA_W];
        m_axi_wstrb_int = strb_reg[addr_reg[S_ADDR_BIT_OFFSET-1:M_ADDR_BIT_OFFSET] * M_STRB_W +: M_STRB_W];
        m_axi_wlast_int = 1'b0;
        m_axi_wuser_int = wuser_reg;
        m_axi_wvalid_int = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                // idle state; wait for new burst
                s_axi_awready_next = !m_axi_wr.awvalid;

                first_transfer_next = 1'b1;

                if (s_axi_wr.awready && s_axi_wr.awvalid) begin
                    s_axi_awready_next = 1'b0;
                    id_next = s_axi_wr.awid;
                    m_axi_awid_next = s_axi_wr.awid;
                    m_axi_awaddr_next = s_axi_wr.awaddr;
                    addr_next = s_axi_wr.awaddr;
                    burst_next = s_axi_wr.awlen;
                    burst_size_next = s_axi_wr.awsize;
                    burst_active_next = 1'b1;
                    if (s_axi_wr.awsize > M_BURST_SIZE) begin
                        // need to adjust burst size
                        if (s_axi_wr.awlen >> (8+M_BURST_SIZE-s_axi_wr.awsize) != 0) begin
                            // limit burst length to max
                            master_burst_next = 8'(32'hff << 3'(s_axi_wr.awsize-M_BURST_SIZE)) | 8'((8'(~s_axi_wr.awaddr) & 8'(8'hff >> (8-s_axi_wr.awsize))) >> M_BURST_SIZE);
                        end else begin
                            master_burst_next = 8'(s_axi_wr.awlen << 3'(s_axi_wr.awsize-M_BURST_SIZE)) | 8'((8'(~s_axi_wr.awaddr) & 8'(8'hff >> (8-s_axi_wr.awsize))) >> M_BURST_SIZE);
                        end
                        master_burst_size_next = M_BURST_SIZE;
                        m_axi_awlen_next = master_burst_next;
                        m_axi_awsize_next = master_burst_size_next;
                    end else begin
                        // pass through narrow (enough) burst
                        master_burst_next = s_axi_wr.awlen;
                        master_burst_size_next = s_axi_wr.awsize;
                        m_axi_awlen_next = s_axi_wr.awlen;
                        m_axi_awsize_next = s_axi_wr.awsize;
                    end
                    m_axi_awburst_next = s_axi_wr.awburst;
                    m_axi_awlock_next = s_axi_wr.awlock;
                    m_axi_awcache_next = s_axi_wr.awcache;
                    m_axi_awprot_next = s_axi_wr.awprot;
                    m_axi_awqos_next = s_axi_wr.awqos;
                    m_axi_awregion_next = s_axi_wr.awregion;
                    m_axi_awuser_next = s_axi_wr.awuser;
                    m_axi_awvalid_next = 1'b1;
                    s_axi_wready_next = m_axi_wready_int_early;
                    state_next = STATE_DATA;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                s_axi_wready_next = m_axi_wready_int_early;

                if (s_axi_wr.wready && s_axi_wr.wvalid) begin
                    data_next = s_axi_wr.wdata;
                    strb_next = s_axi_wr.wstrb;
                    wuser_next = s_axi_wr.wuser;
                    m_axi_wdata_int = s_axi_wr.wdata[addr_reg[S_ADDR_BIT_OFFSET-1:M_ADDR_BIT_OFFSET] * M_DATA_W +: M_DATA_W];
                    m_axi_wstrb_int = s_axi_wr.wstrb[addr_reg[S_ADDR_BIT_OFFSET-1:M_ADDR_BIT_OFFSET] * M_STRB_W +: M_STRB_W];
                    m_axi_wlast_int = 1'b0;
                    m_axi_wuser_int = s_axi_wr.wuser;
                    m_axi_wvalid_int = 1'b1;
                    burst_next = burst_reg - 1;
                    burst_active_next = burst_reg != 0;
                    master_burst_next = master_burst_reg - 1;
                    addr_next = (addr_reg + (1 << master_burst_size_reg)) & ({ADDR_W{1'b1}} << master_burst_size_reg);
                    if (master_burst_reg == 0) begin
                        s_axi_wready_next = 1'b0;
                        m_axi_bready_next = !s_axi_wr.bvalid && !s_axi_wr.awvalid;
                        m_axi_wlast_int = 1'b1;
                        state_next = STATE_RESP;
                    end else if (addr_next[CL_ADDR_W'(burst_size_reg)] != addr_reg[CL_ADDR_W'(burst_size_reg)]) begin
                        state_next = STATE_DATA;
                    end else begin
                        s_axi_wready_next = 1'b0;
                        state_next = STATE_DATA_2;
                    end
                end else begin
                    state_next = STATE_DATA;
                end
            end
            STATE_DATA_2: begin
                s_axi_wready_next = 1'b0;

                if (m_axi_wready_int_reg) begin
                    m_axi_wdata_int = data_reg[addr_reg[S_ADDR_BIT_OFFSET-1:M_ADDR_BIT_OFFSET] * M_DATA_W +: M_DATA_W];
                    m_axi_wstrb_int = strb_reg[addr_reg[S_ADDR_BIT_OFFSET-1:M_ADDR_BIT_OFFSET] * M_STRB_W +: M_STRB_W];
                    m_axi_wlast_int = 1'b0;
                    m_axi_wuser_int = wuser_reg;
                    m_axi_wvalid_int = 1'b1;
                    master_burst_next = master_burst_reg - 1;
                    addr_next = (addr_reg + (1 << master_burst_size_reg)) & ({ADDR_W{1'b1}} << master_burst_size_reg);
                    if (master_burst_reg == 0) begin
                        // burst on master interface finished; transfer response
                        s_axi_wready_next = 1'b0;
                        m_axi_bready_next = !s_axi_wr.bvalid && !m_axi_wr.awvalid;
                        m_axi_wlast_int = 1'b1;
                        state_next = STATE_RESP;
                    end else if (addr_next[CL_ADDR_W'(burst_size_reg)] != addr_reg[CL_ADDR_W'(burst_size_reg)]) begin
                        state_next = STATE_DATA;
                    end else begin
                        s_axi_wready_next = 1'b0;
                        state_next = STATE_DATA_2;
                    end
                end else begin
                    state_next = STATE_DATA_2;
                end
            end
            STATE_RESP: begin
                // resp state; transfer write response
                m_axi_bready_next = !s_axi.bvalid && !m_axi.awvalid;

                if (m_axi.bready && m_axi.bvalid) begin
                    first_transfer_next = 1'b0;
                    m_axi_bready_next = 1'b0;
                    s_axi_bid_next = id_reg;
                    if (first_transfer_reg || m_axi.bresp != 0) begin
                        s_axi_bresp_next = m_axi.bresp;
                    end

                    if (burst_reg >> (8+M_BURST_SIZE-burst_size_reg) != 0) begin
                        // limit burst length to max
                        master_burst_next = 8'd255;
                    end else begin
                        master_burst_next = (burst_reg << (burst_size_reg-M_BURST_SIZE)) | (8'hff >> (8-burst_size_reg) >> M_BURST_SIZE);
                    end
                    master_burst_size_next = M_BURST_SIZE;
                    m_axi_awaddr_next = addr_reg;
                    m_axi_awlen_next = master_burst_next;
                    m_axi_awsize_next = master_burst_size_next;
                    if (burst_active_reg) begin
                        // burst on slave interface still active; start new burst
                        m_axi_awvalid_next = 1'b1;
                        state_next = STATE_DATA;
                    end else begin
                        // burst on slave interface finished; return to idle
                        s_axi_bvalid_next = 1'b1;
                        s_axi_awready_next = !m_axi.awvalid;
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
        wuser_reg <= wuser_next;
        burst_reg <= burst_next;
        burst_size_reg <= burst_size_next;
        master_burst_reg <= master_burst_next;
        master_burst_size_reg <= master_burst_size_next;
        burst_active_reg <= burst_active_next;
        first_transfer_reg <= first_transfer_next;

        s_axi_awready_reg <= s_axi_awready_next;
        s_axi_wready_reg <= s_axi_wready_next;
        s_axi_bid_reg <= s_axi_bid_next;
        s_axi_bresp_reg <= s_axi_bresp_next;
        s_axi_buser_reg <= s_axi_buser_next;
        s_axi_bvalid_reg <= s_axi_bvalid_next;

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
        m_axi_bready_reg <= m_axi_bready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axi_awready_reg <= 1'b0;
            s_axi_wready_reg <= 1'b0;
            s_axi_bvalid_reg <= 1'b0;

            m_axi_awvalid_reg <= 1'b0;
            m_axi_bready_reg <= 1'b0;
        end
    end

    // output datapath logic
    logic [M_DATA_W-1:0] m_axi_wdata_reg  = '0;
    logic [M_STRB_W-1:0] m_axi_wstrb_reg  = '0;
    logic                m_axi_wlast_reg  = 1'b0;
    logic [WUSER_W-1:0]  m_axi_wuser_reg  = 1'b0;
    logic                m_axi_wvalid_reg = 1'b0, m_axi_wvalid_next;

    logic [M_DATA_W-1:0] temp_m_axi_wdata_reg  = '0;
    logic [M_STRB_W-1:0] temp_m_axi_wstrb_reg  = '0;
    logic                temp_m_axi_wlast_reg  = 1'b0;
    logic [WUSER_W-1:0]  temp_m_axi_wuser_reg  = 1'b0;
    logic                temp_m_axi_wvalid_reg = 1'b0, temp_m_axi_wvalid_next;

    // datapath control
    logic store_axi_w_int_to_output;
    logic store_axi_w_int_to_temp;
    logic store_axi_w_temp_to_output;

    assign m_axi_wr.wdata  = m_axi_wdata_reg;
    assign m_axi_wr.wstrb  = m_axi_wstrb_reg;
    assign m_axi_wr.wlast  = m_axi_wlast_reg;
    assign m_axi_wr.wuser  = WUSER_EN ? m_axi_wuser_reg : '0;
    assign m_axi_wr.wvalid = m_axi_wvalid_reg;

    // enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
    assign m_axi_wready_int_early = m_axi_wr.wready | (~temp_m_axi_wvalid_reg & (~m_axi_wvalid_reg | ~m_axi_wvalid_int));

    always_comb begin
        // transfer sink ready state to source
        m_axi_wvalid_next = m_axi_wvalid_reg;
        temp_m_axi_wvalid_next = temp_m_axi_wvalid_reg;

        store_axi_w_int_to_output = 1'b0;
        store_axi_w_int_to_temp = 1'b0;
        store_axi_w_temp_to_output = 1'b0;

        if (m_axi_wready_int_reg) begin
            // input is ready
            if (m_axi_wr.wready | ~m_axi_wvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_axi_wvalid_next = m_axi_wvalid_int;
                store_axi_w_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_axi_wvalid_next = m_axi_wvalid_int;
                store_axi_w_int_to_temp = 1'b1;
            end
        end else if (m_axi_wr.wready) begin
            // input is not ready, but output is ready
            m_axi_wvalid_next = temp_m_axi_wvalid_reg;
            temp_m_axi_wvalid_next = 1'b0;
            store_axi_w_temp_to_output = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            m_axi_wvalid_reg <= 1'b0;
            m_axi_wready_int_reg <= 1'b0;
            temp_m_axi_wvalid_reg <= 1'b0;
        end else begin
            m_axi_wvalid_reg <= m_axi_wvalid_next;
            m_axi_wready_int_reg <= m_axi_wready_int_early;
            temp_m_axi_wvalid_reg <= temp_m_axi_wvalid_next;
        end

        // datapath
        if (store_axi_w_int_to_output) begin
            m_axi_wdata_reg <= m_axi_wdata_int;
            m_axi_wstrb_reg <= m_axi_wstrb_int;
            m_axi_wlast_reg <= m_axi_wlast_int;
            m_axi_wuser_reg <= m_axi_wuser_int;
        end else if (store_axi_w_temp_to_output) begin
            m_axi_wdata_reg <= temp_m_axi_wdata_reg;
            m_axi_wstrb_reg <= temp_m_axi_wstrb_reg;
            m_axi_wlast_reg <= temp_m_axi_wlast_reg;
            m_axi_wuser_reg <= temp_m_axi_wuser_reg;
        end

        if (store_axi_w_int_to_temp) begin
            temp_m_axi_wdata_reg <= m_axi_wdata_int;
            temp_m_axi_wstrb_reg <= m_axi_wstrb_int;
            temp_m_axi_wlast_reg <= m_axi_wlast_int;
            temp_m_axi_wuser_reg <= m_axi_wuser_int;
        end
    end

end

endmodule

`resetall
