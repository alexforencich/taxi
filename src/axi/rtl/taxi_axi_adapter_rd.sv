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
module taxi_axi_adapter_rd #
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
    taxi_axi_if.rd_slv  s_axi_rd,

    /*
     * AXI4 master interface
     */
    taxi_axi_if.rd_mst  m_axi_rd
);

// extract parameters
localparam S_DATA_W = s_axi_rd.DATA_W;
localparam ADDR_W = s_axi_rd.ADDR_W;
localparam CL_ADDR_W = $clog2(ADDR_W);
localparam S_STRB_W = s_axi_rd.STRB_W;
localparam ID_W = s_axi_rd.ID_W;
localparam logic ARUSER_EN = s_axi_rd.ARUSER_EN && m_axi_rd.ARUSER_EN;
localparam ARUSER_W = s_axi_rd.ARUSER_W;
localparam logic RUSER_EN = s_axi_rd.RUSER_EN && m_axi_rd.RUSER_EN;
localparam RUSER_W = s_axi_rd.RUSER_W;

localparam M_DATA_W = m_axi_rd.DATA_W;
localparam M_STRB_W = m_axi_rd.STRB_W;

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

    assign m_axi_rd.arid = s_axi_rd.arid;
    assign m_axi_rd.araddr = s_axi_rd.araddr;
    assign m_axi_rd.arlen = s_axi_rd.arlen;
    assign m_axi_rd.arsize = s_axi_rd.arsize;
    assign m_axi_rd.arburst = s_axi_rd.arburst;
    assign m_axi_rd.arlock = s_axi_rd.arlock;
    assign m_axi_rd.arcache = s_axi_rd.arcache;
    assign m_axi_rd.arprot = s_axi_rd.arprot;
    assign m_axi_rd.arqos = s_axi_rd.arqos;
    assign m_axi_rd.arregion = s_axi_rd.arregion;
    assign m_axi_rd.aruser = ARUSER_EN ? s_axi_rd.aruser : '0;
    assign m_axi_rd.arvalid = s_axi_rd.arvalid;
    assign s_axi_rd.arready = m_axi_rd.arready;

    assign s_axi_rd.rid = m_axi_rd.rid;
    assign s_axi_rd.rdata = m_axi_rd.rdata;
    assign s_axi_rd.rresp = m_axi_rd.rresp;
    assign s_axi_rd.rlast = m_axi_rd.rlast;
    assign s_axi_rd.ruser = RUSER_EN ? m_axi_rd.ruser : '0;
    assign s_axi_rd.rvalid = m_axi_rd.rvalid;
    assign m_axi_rd.rready = s_axi_rd.rready;

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
        STATE_DATA_READ,
        STATE_DATA_SPLIT
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic [ID_W-1:0] id_reg = '0, id_next;
    logic [ADDR_W-1:0] addr_reg = '0, addr_next;
    logic [DATA_W-1:0] data_reg = '0, data_next;
    logic [1:0] resp_reg = '0, resp_next;
    logic [RUSER_W-1:0] ruser_reg = '0, ruser_next;
    logic [7:0] burst_reg = '0, burst_next;
    logic [2:0] burst_size_reg = '0, burst_size_next;
    logic [7:0] master_burst_reg = '0, master_burst_next;
    logic [2:0] master_burst_size_reg = '0, master_burst_size_next;

    logic s_axi_arready_reg = 1'b0, s_axi_arready_next;

    logic [ID_W-1:0] m_axi_arid_reg = '0, m_axi_arid_next;
    logic [ADDR_W-1:0] m_axi_araddr_reg = '0, m_axi_araddr_next;
    logic [7:0] m_axi_arlen_reg = '0, m_axi_arlen_next;
    logic [2:0] m_axi_arsize_reg = '0, m_axi_arsize_next;
    logic [1:0] m_axi_arburst_reg = '0, m_axi_arburst_next;
    logic m_axi_arlock_reg = '0, m_axi_arlock_next;
    logic [3:0] m_axi_arcache_reg = '0, m_axi_arcache_next;
    logic [2:0] m_axi_arprot_reg = '0, m_axi_arprot_next;
    logic [3:0] m_axi_arqos_reg = '0, m_axi_arqos_next;
    logic [3:0] m_axi_arregion_reg = '0, m_axi_arregion_next;
    logic [ARUSER_W-1:0] m_axi_aruser_reg = '0, m_axi_aruser_next;
    logic m_axi_arvalid_reg = 1'b0, m_axi_arvalid_next;
    logic m_axi_rready_reg = 1'b0, m_axi_rready_next;

    // internal datapath
    logic  [ID_W-1:0]     s_axi_rid_int;
    logic  [S_DATA_W-1:0] s_axi_rdata_int;
    logic  [1:0]          s_axi_rresp_int;
    logic                 s_axi_rlast_int;
    logic  [RUSER_W-1:0]  s_axi_ruser_int;
    logic                 s_axi_rvalid_int;
    logic                 s_axi_rready_int_reg = 1'b0;
    wire                  s_axi_rready_int_early;

    assign s_axi_rd.arready = s_axi_arready_reg;

    assign m_axi_rd.arid = '0;
    assign m_axi_rd.araddr = m_axi_araddr_reg;
    assign m_axi_rd.arlen = m_axi_arlen_reg;
    assign m_axi_rd.arsize = m_axi_arsize_reg;
    assign m_axi_rd.arburst = m_axi_arburst_reg;
    assign m_axi_rd.arlock = m_axi_arlock_reg;
    assign m_axi_rd.arcache = m_axi_arcache_reg;
    assign m_axi_rd.arprot = m_axi_arprot_reg;
    assign m_axi_rd.arqos = m_axi_arqos_reg;
    assign m_axi_rd.arregion = m_axi_arregion_reg;
    assign m_axi_rd.aruser = ARUSER_EN ? m_axi_aruser_reg : '0;
    assign m_axi_rd.arvalid = m_axi_arvalid_reg;
    assign m_axi_rd.rready = m_axi_rready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        id_next = id_reg;
        addr_next = addr_reg;
        data_next = data_reg;
        resp_next = resp_reg;
        ruser_next = ruser_reg;
        burst_next = burst_reg;
        burst_size_next = burst_size_reg;
        master_burst_next = master_burst_reg;
        master_burst_size_next = master_burst_size_reg;

        s_axi_arready_next = 1'b0;
        m_axi_arid_next = m_axi_arid_reg;
        m_axi_araddr_next = m_axi_araddr_reg;
        m_axi_arlen_next = m_axi_arlen_reg;
        m_axi_arsize_next = m_axi_arsize_reg;
        m_axi_arburst_next = m_axi_arburst_reg;
        m_axi_arlock_next = m_axi_arlock_reg;
        m_axi_arcache_next = m_axi_arcache_reg;
        m_axi_arprot_next = m_axi_arprot_reg;
        m_axi_arqos_next = m_axi_arqos_reg;
        m_axi_arregion_next = m_axi_arregion_reg;
        m_axi_aruser_next = m_axi_aruser_reg;
        m_axi_arvalid_next = m_axi_arvalid_reg && !m_axi_rd.arready;
        m_axi_rready_next = 1'b0;

        s_axi_rid_int = id_reg;
        s_axi_rdata_int = m_axi_rd.rdata[addr_reg[M_ADDR_BIT_OFFSET-1:S_ADDR_BIT_OFFSET] * S_DATA_W +: S_DATA_W];
        s_axi_rresp_int = m_axi_rd.rresp;
        s_axi_rlast_int = m_axi_rd.rlast;
        s_axi_ruser_int = m_axi_rd.ruser;
        s_axi_rvalid_int = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                // idle state; wait for new burst
                s_axi_arready_next = !m_axi_rd.arvalid;

                if (s_axi_rd.arready && s_axi_rd.arvalid) begin
                    s_axi_arready_next = 1'b0;
                    id_next = s_axi_rd.arid;
                    m_axi_arid_next = s_axi_rd.arid;
                    m_axi_araddr_next = s_axi_rd.araddr;
                    addr_next = s_axi_rd.araddr;
                    burst_next = s_axi_rd.arlen;
                    burst_size_next = s_axi_rd.arsize;
                    if (CONVERT_BURST && s_axi_rd.arcache[1] && (CONVERT_NARROW_BURST || s_axi_rd.arsize == S_BURST_SIZE)) begin
                        // split reads
                        // require CONVERT_BURST and arcache[1] set
                        master_burst_size_next = M_BURST_SIZE;
                        if (CONVERT_NARROW_BURST) begin
                            m_axi_arlen_next = 8'((({8'd0, s_axi_rd.arlen} << s_axi_rd.arsize) + 16'(s_axi_rd.araddr[M_ADDR_BIT_OFFSET-1:0])) >> M_BURST_SIZE);
                        end else begin
                            m_axi_arlen_next = (s_axi_rd.arlen + 8'(s_axi_rd.araddr[M_ADDR_BIT_OFFSET-1:S_ADDR_BIT_OFFSET])) >> CL_SEG_COUNT;
                        end
                        m_axi_arsize_next = M_BURST_SIZE;
                        state_next = STATE_DATA_READ;
                    end else begin
                        // output narrow burst
                        master_burst_size_next = s_axi_rd.arsize;
                        m_axi_arlen_next = s_axi_rd.arlen;
                        m_axi_arsize_next = s_axi_rd.arsize;
                        state_next = STATE_DATA;
                    end
                    m_axi_arburst_next = s_axi_rd.arburst;
                    m_axi_arlock_next = s_axi_rd.arlock;
                    m_axi_arcache_next = s_axi_rd.arcache;
                    m_axi_arprot_next = s_axi_rd.arprot;
                    m_axi_arqos_next = s_axi_rd.arqos;
                    m_axi_arregion_next = s_axi_rd.arregion;
                    m_axi_aruser_next = s_axi_rd.aruser;
                    m_axi_arvalid_next = 1'b1;
                    m_axi_rready_next = s_axi_rready_int_early;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                m_axi_rready_next = s_axi_rready_int_early;

                if (m_axi_rd.rready && m_axi_rd.rvalid) begin
                    s_axi_rid_int = id_reg;
                    s_axi_rdata_int = m_axi_rd.rdata[addr_reg[M_ADDR_BIT_OFFSET-1:S_ADDR_BIT_OFFSET] * S_DATA_W +: S_DATA_W];
                    s_axi_rresp_int = m_axi_rd.rresp;
                    s_axi_rlast_int = m_axi_rd.rlast;
                    s_axi_ruser_int = m_axi_rd.ruser;
                    s_axi_rvalid_int = 1'b1;
                    addr_next = addr_reg + (1 << burst_size_reg);
                    if (m_axi_rd.rlast) begin
                        m_axi_rready_next = 1'b0;
                        s_axi_arready_next = !m_axi_rd.arvalid;
                        state_next = STATE_IDLE;
                    end else begin
                        state_next = STATE_DATA;
                    end
                end else begin
                    state_next = STATE_DATA;
                end
            end
            STATE_DATA_READ: begin
                m_axi_rready_next = s_axi_rready_int_early;

                if (m_axi_rd.rready && m_axi_rd.rvalid) begin
                    s_axi_rid_int = id_reg;
                    data_next = m_axi_rd.rdata;
                    resp_next = m_axi_rd.rresp;
                    ruser_next = m_axi_rd.ruser;
                    s_axi_rdata_int = m_axi_rd.rdata[addr_reg[M_ADDR_BIT_OFFSET-1:S_ADDR_BIT_OFFSET] * S_DATA_W +: S_DATA_W];
                    s_axi_rresp_int = m_axi_rd.rresp;
                    s_axi_rlast_int = 1'b0;
                    s_axi_ruser_int = m_axi_rd.ruser;
                    s_axi_rvalid_int = 1'b1;
                    burst_next = burst_reg - 1;
                    addr_next = addr_reg + (1 << burst_size_reg);
                    if (burst_reg == 0) begin
                        m_axi_rready_next = 1'b0;
                        s_axi_arready_next = !m_axi_rd.arvalid;
                        s_axi_rlast_int = 1'b1;
                        state_next = STATE_IDLE;
                    end else if (addr_next[CL_ADDR_W'(master_burst_size_reg)] != addr_reg[CL_ADDR_W'(master_burst_size_reg)]) begin
                        state_next = STATE_DATA_READ;
                    end else begin
                        m_axi_rready_next = 1'b0;
                        state_next = STATE_DATA_SPLIT;
                    end
                end else begin
                    state_next = STATE_DATA_READ;
                end
            end
            STATE_DATA_SPLIT: begin
                m_axi_rready_next = 1'b0;

                if (s_axi_rready_int_reg) begin
                    s_axi_rid_int = id_reg;
                    s_axi_rdata_int = data_reg[addr_reg[M_ADDR_BIT_OFFSET-1:S_ADDR_BIT_OFFSET] * S_DATA_W +: S_DATA_W];
                    s_axi_rresp_int = resp_reg;
                    s_axi_rlast_int = 1'b0;
                    s_axi_ruser_int = ruser_reg;
                    s_axi_rvalid_int = 1'b1;
                    burst_next = burst_reg - 1;
                    addr_next = addr_reg + (1 << burst_size_reg);
                    if (burst_reg == 0) begin
                        s_axi_arready_next = !m_axi_rd.arvalid;
                        s_axi_rlast_int = 1'b1;
                        state_next = STATE_IDLE;
                    end else if (addr_next[CL_ADDR_W'(master_burst_size_reg)] != addr_reg[CL_ADDR_W'(master_burst_size_reg)]) begin
                        m_axi_rready_next = s_axi_rready_int_early;
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
        ruser_reg <= ruser_next;
        burst_reg <= burst_next;
        burst_size_reg <= burst_size_next;
        master_burst_reg <= master_burst_next;
        master_burst_size_reg <= master_burst_size_next;

        s_axi_arready_reg <= s_axi_arready_next;

        m_axi_arid_reg <= m_axi_arid_next;
        m_axi_araddr_reg <= m_axi_araddr_next;
        m_axi_arlen_reg <= m_axi_arlen_next;
        m_axi_arsize_reg <= m_axi_arsize_next;
        m_axi_arburst_reg <= m_axi_arburst_next;
        m_axi_arlock_reg <= m_axi_arlock_next;
        m_axi_arcache_reg <= m_axi_arcache_next;
        m_axi_arprot_reg <= m_axi_arprot_next;
        m_axi_arqos_reg <= m_axi_arqos_next;
        m_axi_arregion_reg <= m_axi_arregion_next;
        m_axi_aruser_reg <= m_axi_aruser_next;
        m_axi_arvalid_reg <= m_axi_arvalid_next;
        m_axi_rready_reg <= m_axi_rready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axi_arready_reg <= 1'b0;

            m_axi_arvalid_reg <= 1'b0;
            m_axi_rready_reg <= 1'b0;
        end
    end

    // output datapath logic
    logic [ID_W-1:0]     s_axi_rid_reg    = '0;
    logic [S_DATA_W-1:0] s_axi_rdata_reg  = '0;
    logic [1:0]          s_axi_rresp_reg  = 2'd0;
    logic                s_axi_rlast_reg  = 1'b0;
    logic [RUSER_W-1:0]  s_axi_ruser_reg  = 1'b0;
    logic                s_axi_rvalid_reg = 1'b0, s_axi_rvalid_next;

    logic [ID_W-1:0]     temp_s_axi_rid_reg    = '0;
    logic [S_DATA_W-1:0] temp_s_axi_rdata_reg  = '0;
    logic [1:0]          temp_s_axi_rresp_reg  = 2'd0;
    logic                temp_s_axi_rlast_reg  = 1'b0;
    logic [RUSER_W-1:0]  temp_s_axi_ruser_reg  = 1'b0;
    logic                temp_s_axi_rvalid_reg = 1'b0, temp_s_axi_rvalid_next;

    // datapath control
    logic store_axi_r_int_to_output;
    logic store_axi_r_int_to_temp;
    logic store_axi_r_temp_to_output;

    assign s_axi_rd.rid    = s_axi_rid_reg;
    assign s_axi_rd.rdata  = s_axi_rdata_reg;
    assign s_axi_rd.rresp  = s_axi_rresp_reg;
    assign s_axi_rd.rlast  = s_axi_rlast_reg;
    assign s_axi_rd.ruser  = RUSER_EN ? s_axi_ruser_reg : '0;
    assign s_axi_rd.rvalid = s_axi_rvalid_reg;

    // enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
    assign s_axi_rready_int_early = s_axi_rd.rready | (~temp_s_axi_rvalid_reg & (~s_axi_rvalid_reg | ~s_axi_rvalid_int));

    always_comb begin
        // transfer sink ready state to source
        s_axi_rvalid_next = s_axi_rvalid_reg;
        temp_s_axi_rvalid_next = temp_s_axi_rvalid_reg;

        store_axi_r_int_to_output = 1'b0;
        store_axi_r_int_to_temp = 1'b0;
        store_axi_r_temp_to_output = 1'b0;

        if (s_axi_rready_int_reg) begin
            // input is ready
            if (s_axi_rd.rready | ~s_axi_rvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                s_axi_rvalid_next = s_axi_rvalid_int;
                store_axi_r_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_s_axi_rvalid_next = s_axi_rvalid_int;
                store_axi_r_int_to_temp = 1'b1;
            end
        end else if (s_axi_rd.rready) begin
            // input is not ready, but output is ready
            s_axi_rvalid_next = temp_s_axi_rvalid_reg;
            temp_s_axi_rvalid_next = 1'b0;
            store_axi_r_temp_to_output = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            s_axi_rvalid_reg <= 1'b0;
            s_axi_rready_int_reg <= 1'b0;
            temp_s_axi_rvalid_reg <= 1'b0;
        end else begin
            s_axi_rvalid_reg <= s_axi_rvalid_next;
            s_axi_rready_int_reg <= s_axi_rready_int_early;
            temp_s_axi_rvalid_reg <= temp_s_axi_rvalid_next;
        end

        // datapath
        if (store_axi_r_int_to_output) begin
            s_axi_rid_reg <= s_axi_rid_int;
            s_axi_rdata_reg <= s_axi_rdata_int;
            s_axi_rresp_reg <= s_axi_rresp_int;
            s_axi_rlast_reg <= s_axi_rlast_int;
            s_axi_ruser_reg <= s_axi_ruser_int;
        end else if (store_axi_r_temp_to_output) begin
            s_axi_rid_reg <= temp_s_axi_rid_reg;
            s_axi_rdata_reg <= temp_s_axi_rdata_reg;
            s_axi_rresp_reg <= temp_s_axi_rresp_reg;
            s_axi_rlast_reg <= temp_s_axi_rlast_reg;
            s_axi_ruser_reg <= temp_s_axi_ruser_reg;
        end

        if (store_axi_r_int_to_temp) begin
            temp_s_axi_rid_reg <= s_axi_rid_int;
            temp_s_axi_rdata_reg <= s_axi_rdata_int;
            temp_s_axi_rresp_reg <= s_axi_rresp_int;
            temp_s_axi_rlast_reg <= s_axi_rlast_int;
            temp_s_axi_ruser_reg <= s_axi_ruser_int;
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

    typedef enum logic [0:0] {
        STATE_IDLE,
        STATE_DATA
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic [ID_W-1:0] id_reg = '0, id_next;
    logic [ADDR_W-1:0] addr_reg = '0, addr_next;
    logic [DATA_W-1:0] data_reg = '0, data_next;
    logic [1:0] resp_reg = '0, resp_next;
    logic [RUSER_W-1:0] ruser_reg = '0, ruser_next;
    logic [7:0] burst_reg = '0, burst_next;
    logic [2:0] burst_size_reg = '0, burst_size_next;
    logic [7:0] master_burst_reg = '0, master_burst_next;
    logic [2:0] master_burst_size_reg = '0, master_burst_size_next;

    logic s_axi_arready_reg = 1'b0, s_axi_arready_next;

    logic [ID_W-1:0] m_axi_arid_reg = '0, m_axi_arid_next;
    logic [ADDR_W-1:0] m_axi_araddr_reg = '0, m_axi_araddr_next;
    logic [7:0] m_axi_arlen_reg = '0, m_axi_arlen_next;
    logic [2:0] m_axi_arsize_reg = '0, m_axi_arsize_next;
    logic [1:0] m_axi_arburst_reg = '0, m_axi_arburst_next;
    logic m_axi_arlock_reg = '0, m_axi_arlock_next;
    logic [3:0] m_axi_arcache_reg = '0, m_axi_arcache_next;
    logic [2:0] m_axi_arprot_reg = '0, m_axi_arprot_next;
    logic [3:0] m_axi_arqos_reg = '0, m_axi_arqos_next;
    logic [3:0] m_axi_arregion_reg = '0, m_axi_arregion_next;
    logic [ARUSER_W-1:0] m_axi_aruser_reg = '0, m_axi_aruser_next;
    logic m_axi_arvalid_reg = 1'b0, m_axi_arvalid_next;
    logic m_axi_rready_reg = 1'b0, m_axi_rready_next;

    // internal datapath
    logic  [ID_W-1:0]     s_axi_rid_int;
    logic  [S_DATA_W-1:0] s_axi_rdata_int;
    logic  [1:0]          s_axi_rresp_int;
    logic                 s_axi_rlast_int;
    logic  [RUSER_W-1:0]  s_axi_ruser_int;
    logic                 s_axi_rvalid_int;
    logic                 s_axi_rready_int_reg = 1'b0;
    wire                  s_axi_rready_int_early;

    assign s_axi_rd.arready = s_axi_arready_reg;

    assign m_axi_rd.arid = '0;
    assign m_axi_rd.araddr = m_axi_araddr_reg;
    assign m_axi_rd.arlen = m_axi_arlen_reg;
    assign m_axi_rd.arsize = m_axi_arsize_reg;
    assign m_axi_rd.arburst = m_axi_arburst_reg;
    assign m_axi_rd.arlock = m_axi_arlock_reg;
    assign m_axi_rd.arcache = m_axi_arcache_reg;
    assign m_axi_rd.arprot = m_axi_arprot_reg;
    assign m_axi_rd.arqos = m_axi_arqos_reg;
    assign m_axi_rd.arregion = m_axi_arregion_reg;
    assign m_axi_rd.aruser = ARUSER_EN ? m_axi_aruser_reg : '0;
    assign m_axi_rd.arvalid = m_axi_arvalid_reg;
    assign m_axi_rd.rready = m_axi_rready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        id_next = id_reg;
        addr_next = addr_reg;
        data_next = data_reg;
        resp_next = resp_reg;
        ruser_next = ruser_reg;
        burst_next = burst_reg;
        burst_size_next = burst_size_reg;
        master_burst_next = master_burst_reg;
        master_burst_size_next = master_burst_size_reg;

        s_axi_arready_next = 1'b0;
        m_axi_arid_next = m_axi_arid_reg;
        m_axi_araddr_next = m_axi_araddr_reg;
        m_axi_arlen_next = m_axi_arlen_reg;
        m_axi_arsize_next = m_axi_arsize_reg;
        m_axi_arburst_next = m_axi_arburst_reg;
        m_axi_arlock_next = m_axi_arlock_reg;
        m_axi_arcache_next = m_axi_arcache_reg;
        m_axi_arprot_next = m_axi_arprot_reg;
        m_axi_arqos_next = m_axi_arqos_reg;
        m_axi_arregion_next = m_axi_arregion_reg;
        m_axi_aruser_next = m_axi_aruser_reg;
        m_axi_arvalid_next = m_axi_arvalid_reg && !m_axi_rd.arready;
        m_axi_rready_next = 1'b0;

        // master output is narrower; merge reads and possibly split burst
        s_axi_rid_int = id_reg;
        s_axi_rdata_int = data_reg;
        s_axi_rresp_int = resp_reg;
        s_axi_rlast_int = 1'b0;
        s_axi_ruser_int = m_axi_rd.ruser;
        s_axi_rvalid_int = 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                // idle state; wait for new burst
                s_axi_arready_next = !m_axi_rd.arvalid;

                resp_next = 2'd0;

                if (s_axi_rd.arready && s_axi_rd.arvalid) begin
                    s_axi_arready_next = 1'b0;
                    id_next = s_axi_rd.arid;
                    m_axi_arid_next = s_axi_rd.arid;
                    m_axi_araddr_next = s_axi_rd.araddr;
                    addr_next = s_axi_rd.araddr;
                    burst_next = s_axi_rd.arlen;
                    burst_size_next = s_axi_rd.arsize;
                    if (s_axi_rd.arsize > M_BURST_SIZE) begin
                        // need to adjust burst size
                        if (s_axi_rd.arlen >> (8+M_BURST_SIZE-s_axi_rd.arsize) != 0) begin
                            // limit burst length to max
                            master_burst_next = 8'(8'd255 << 3'(s_axi_rd.arsize-M_BURST_SIZE)) | 8'((8'(~s_axi_rd.araddr) & 8'(8'hff >> (8-s_axi_rd.arsize))) >> M_BURST_SIZE);
                        end else begin
                            master_burst_next = 8'(s_axi_rd.arlen << 3'(s_axi_rd.arsize-M_BURST_SIZE)) | 8'((8'(~s_axi_rd.araddr) & 8'(8'hff >> (8-s_axi_rd.arsize))) >> M_BURST_SIZE);
                        end
                        master_burst_size_next = M_BURST_SIZE;
                        m_axi_arlen_next = master_burst_next;
                        m_axi_arsize_next = master_burst_size_next;
                    end else begin
                        // pass through narrow (enough) burst
                        master_burst_next = s_axi_rd.arlen;
                        master_burst_size_next = s_axi_rd.arsize;
                        m_axi_arlen_next = s_axi_rd.arlen;
                        m_axi_arsize_next = s_axi_rd.arsize;
                    end
                    m_axi_arburst_next = s_axi_rd.arburst;
                    m_axi_arlock_next = s_axi_rd.arlock;
                    m_axi_arcache_next = s_axi_rd.arcache;
                    m_axi_arprot_next = s_axi_rd.arprot;
                    m_axi_arqos_next = s_axi_rd.arqos;
                    m_axi_arregion_next = s_axi_rd.arregion;
                    m_axi_aruser_next = s_axi_rd.aruser;
                    m_axi_arvalid_next = 1'b1;
                    m_axi_rready_next = 1'b0;
                    state_next = STATE_DATA;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_DATA: begin
                m_axi_rready_next = s_axi_rready_int_early && !m_axi_rd.arvalid;

                if (m_axi_rd.rready && m_axi_rd.rvalid) begin
                    data_next[addr_reg[S_ADDR_BIT_OFFSET-1:M_ADDR_BIT_OFFSET]*SEG_DATA_W +: SEG_DATA_W] = m_axi_rd.rdata;
                    if (m_axi_rd.rresp != 0) begin
                        resp_next = m_axi_rd.rresp;
                    end
                    s_axi_rid_int = id_reg;
                    s_axi_rdata_int = data_next;
                    s_axi_rresp_int = resp_next;
                    s_axi_rlast_int = 1'b0;
                    s_axi_ruser_int = m_axi_rd.ruser;
                    s_axi_rvalid_int = 1'b0;
                    master_burst_next = master_burst_reg - 1;
                    addr_next = (addr_reg + (1 << master_burst_size_reg)) & ({ADDR_W{1'b1}} << master_burst_size_reg);
                    m_axi_araddr_next = addr_next;
                    if (addr_next[CL_ADDR_W'(burst_size_reg)] != addr_reg[CL_ADDR_W'(burst_size_reg)]) begin
                        data_next = '0;
                        burst_next = burst_reg - 1;
                        s_axi_rvalid_int = 1'b1;
                    end
                    if (master_burst_reg == 0) begin
                        if (burst_next >> (8+M_BURST_SIZE-burst_size_reg) != 0) begin
                            // limit burst length to max
                            master_burst_next = 8'd255;
                        end else begin
                            master_burst_next = (burst_next << (burst_size_reg-M_BURST_SIZE)) | (8'hff >> (8-burst_size_reg) >> M_BURST_SIZE);
                        end
                        m_axi_arlen_next = master_burst_next;

                        if (burst_reg == 0) begin
                            m_axi_rready_next = 1'b0;
                            s_axi_rlast_int = 1'b1;
                            s_axi_rvalid_int = 1'b1;
                            s_axi_arready_next = !m_axi_rd.arvalid;
                            state_next = STATE_IDLE;
                        end else begin
                            // start new burst
                            m_axi_arvalid_next = 1'b1;
                            m_axi_rready_next = 1'b0;
                            state_next = STATE_DATA;
                        end
                    end else begin
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
        ruser_reg <= ruser_next;
        burst_reg <= burst_next;
        burst_size_reg <= burst_size_next;
        master_burst_reg <= master_burst_next;
        master_burst_size_reg <= master_burst_size_next;

        s_axi_arready_reg <= s_axi_arready_next;

        m_axi_arid_reg <= m_axi_arid_next;
        m_axi_araddr_reg <= m_axi_araddr_next;
        m_axi_arlen_reg <= m_axi_arlen_next;
        m_axi_arsize_reg <= m_axi_arsize_next;
        m_axi_arburst_reg <= m_axi_arburst_next;
        m_axi_arlock_reg <= m_axi_arlock_next;
        m_axi_arcache_reg <= m_axi_arcache_next;
        m_axi_arprot_reg <= m_axi_arprot_next;
        m_axi_arqos_reg <= m_axi_arqos_next;
        m_axi_arregion_reg <= m_axi_arregion_next;
        m_axi_aruser_reg <= m_axi_aruser_next;
        m_axi_arvalid_reg <= m_axi_arvalid_next;
        m_axi_rready_reg <= m_axi_rready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;

            s_axi_arready_reg <= 1'b0;

            m_axi_arvalid_reg <= 1'b0;
            m_axi_rready_reg <= 1'b0;
        end
    end

    // output datapath logic
    logic [ID_W-1:0]     s_axi_rid_reg    = '0;
    logic [S_DATA_W-1:0] s_axi_rdata_reg  = '0;
    logic [1:0]          s_axi_rresp_reg  = 2'd0;
    logic                s_axi_rlast_reg  = 1'b0;
    logic [RUSER_W-1:0]  s_axi_ruser_reg  = 1'b0;
    logic                s_axi_rvalid_reg = 1'b0, s_axi_rvalid_next;

    logic [ID_W-1:0]     temp_s_axi_rid_reg    = '0;
    logic [S_DATA_W-1:0] temp_s_axi_rdata_reg  = '0;
    logic [1:0]          temp_s_axi_rresp_reg  = 2'd0;
    logic                temp_s_axi_rlast_reg  = 1'b0;
    logic [RUSER_W-1:0]  temp_s_axi_ruser_reg  = 1'b0;
    logic                temp_s_axi_rvalid_reg = 1'b0, temp_s_axi_rvalid_next;

    // datapath control
    logic store_axi_r_int_to_output;
    logic store_axi_r_int_to_temp;
    logic store_axi_r_temp_to_output;

    assign s_axi_rd.rid    = s_axi_rid_reg;
    assign s_axi_rd.rdata  = s_axi_rdata_reg;
    assign s_axi_rd.rresp  = s_axi_rresp_reg;
    assign s_axi_rd.rlast  = s_axi_rlast_reg;
    assign s_axi_rd.ruser  = RUSER_EN ? s_axi_ruser_reg : '0;
    assign s_axi_rd.rvalid = s_axi_rvalid_reg;

    // enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
    assign s_axi_rready_int_early = s_axi_rd.rready | (~temp_s_axi_rvalid_reg & (~s_axi_rvalid_reg | ~s_axi_rvalid_int));

    always_comb begin
        // transfer sink ready state to source
        s_axi_rvalid_next = s_axi_rvalid_reg;
        temp_s_axi_rvalid_next = temp_s_axi_rvalid_reg;

        store_axi_r_int_to_output = 1'b0;
        store_axi_r_int_to_temp = 1'b0;
        store_axi_r_temp_to_output = 1'b0;

        if (s_axi_rready_int_reg) begin
            // input is ready
            if (s_axi_rd.rready | ~s_axi_rvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                s_axi_rvalid_next = s_axi_rvalid_int;
                store_axi_r_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_s_axi_rvalid_next = s_axi_rvalid_int;
                store_axi_r_int_to_temp = 1'b1;
            end
        end else if (s_axi_rd.rready) begin
            // input is not ready, but output is ready
            s_axi_rvalid_next = temp_s_axi_rvalid_reg;
            temp_s_axi_rvalid_next = 1'b0;
            store_axi_r_temp_to_output = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            s_axi_rvalid_reg <= 1'b0;
            s_axi_rready_int_reg <= 1'b0;
            temp_s_axi_rvalid_reg <= 1'b0;
        end else begin
            s_axi_rvalid_reg <= s_axi_rvalid_next;
            s_axi_rready_int_reg <= s_axi_rready_int_early;
            temp_s_axi_rvalid_reg <= temp_s_axi_rvalid_next;
        end

        // datapath
        if (store_axi_r_int_to_output) begin
            s_axi_rid_reg <= s_axi_rid_int;
            s_axi_rdata_reg <= s_axi_rdata_int;
            s_axi_rresp_reg <= s_axi_rresp_int;
            s_axi_rlast_reg <= s_axi_rlast_int;
            s_axi_ruser_reg <= s_axi_ruser_int;
        end else if (store_axi_r_temp_to_output) begin
            s_axi_rid_reg <= temp_s_axi_rid_reg;
            s_axi_rdata_reg <= temp_s_axi_rdata_reg;
            s_axi_rresp_reg <= temp_s_axi_rresp_reg;
            s_axi_rlast_reg <= temp_s_axi_rlast_reg;
            s_axi_ruser_reg <= temp_s_axi_ruser_reg;
        end

        if (store_axi_r_int_to_temp) begin
            temp_s_axi_rid_reg <= s_axi_rid_int;
            temp_s_axi_rdata_reg <= s_axi_rdata_int;
            temp_s_axi_rresp_reg <= s_axi_rresp_int;
            temp_s_axi_rlast_reg <= s_axi_rlast_int;
            temp_s_axi_ruser_reg <= s_axi_ruser_int;
        end
    end

end

endmodule

`resetall
