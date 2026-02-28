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
 * AXI4 interconnect
 */
module taxi_axi_interconnect_wr #
(
    // Number of AXI inputs (slave interfaces)
    parameter S_COUNT = 4,
    // Number of AXI outputs (master interfaces)
    parameter M_COUNT = 4,
    // Address width in bits for address decoding
    parameter ADDR_W = 32,
    // Number of regions per master interface
    parameter M_REGIONS = 1,
    // TODO fix parametrization once verilator issue 5890 is fixed
    // Master interface base addresses
    // M_COUNT concatenated fields of M_REGIONS concatenated fields of ADDR_W bits
    // set to zero for default addressing based on M_ADDR_W
    parameter M_BASE_ADDR = 0,
    // Master interface address widths
    // M_COUNT concatenated fields of M_REGIONS concatenated fields of 32 bits
    parameter M_ADDR_W = {M_COUNT{{M_REGIONS{32'd24}}}},
    // Write connections between interfaces
    // M_COUNT concatenated fields of S_COUNT bits
    parameter M_CONNECT = {M_COUNT{{S_COUNT{1'b1}}}},
    // Secure master (fail operations based on awprot/arprot)
    // M_COUNT bits
    parameter M_SECURE = {M_COUNT{1'b0}}
)
(
    input  wire logic   clk,
    input  wire logic   rst,

    /*
     * AXI4 slave interfaces
     */
    taxi_axi_if.wr_slv  s_axi_wr[S_COUNT],

    /*
     * AXI4 master interfaces
     */
    taxi_axi_if.wr_mst  m_axi_wr[M_COUNT]
);

// extract parameters
localparam DATA_W = s_axi_wr[0].DATA_W;
localparam S_ADDR_W = s_axi_wr[0].ADDR_W;
localparam STRB_W = s_axi_wr[0].STRB_W;
localparam S_ID_W = s_axi_wr[0].ID_W;
localparam M_ID_W = m_axi_wr[0].ID_W;
localparam logic AWUSER_EN = s_axi_wr[0].AWUSER_EN && m_axi_wr[0].AWUSER_EN;
localparam AWUSER_W = s_axi_wr[0].AWUSER_W;
localparam logic WUSER_EN = s_axi_wr[0].WUSER_EN && m_axi_wr[0].WUSER_EN;
localparam WUSER_W = s_axi_wr[0].WUSER_W;
localparam logic BUSER_EN = s_axi_wr[0].BUSER_EN && m_axi_wr[0].BUSER_EN;
localparam BUSER_W = s_axi_wr[0].BUSER_W;

localparam AXI_M_ADDR_W = m_axi_wr[0].ADDR_W;

localparam CL_S_COUNT = $clog2(S_COUNT);
localparam CL_M_COUNT = $clog2(M_COUNT);
localparam CL_S_COUNT_INT = CL_S_COUNT > 0 ? CL_S_COUNT : 1;
localparam CL_M_COUNT_INT = CL_M_COUNT > 0 ? CL_M_COUNT : 1;

localparam [M_COUNT*M_REGIONS-1:0][31:0] M_ADDR_W_INT = M_ADDR_W;
localparam [M_COUNT-1:0][S_COUNT-1:0] M_CONNECT_INT = M_CONNECT;
localparam [M_COUNT-1:0] M_SECURE_INT = M_SECURE;

// default address computation
function [M_COUNT*M_REGIONS-1:0][ADDR_W-1:0] calcBaseAddrs(input [31:0] dummy);
    logic [ADDR_W-1:0] base;
    integer width;
    logic [ADDR_W-1:0] size;
    logic [ADDR_W-1:0] mask;
    begin
        calcBaseAddrs = '0;
        base = '0;
        for (integer i = 0; i < M_COUNT*M_REGIONS; i = i + 1) begin
            width = M_ADDR_W_INT[i];
            mask = {ADDR_W{1'b1}} >> (ADDR_W - width);
            size = mask + 1;
            if (width > 0) begin
                if ((base & mask) != 0) begin
                    base = base + size - (base & mask); // align
                end
                calcBaseAddrs[i] = base;
                base = base + size; // increment
            end
        end
    end
endfunction

localparam [M_COUNT*M_REGIONS-1:0][ADDR_W-1:0] M_BASE_ADDR_INT = M_BASE_ADDR != 0 ? (M_COUNT*M_REGIONS*ADDR_W)'(M_BASE_ADDR) : calcBaseAddrs(0);

// check configuration
if (s_axi_wr[0].ADDR_W != ADDR_W)
    $fatal(0, "Error: Interface ADDR_W parameter mismatch (instance %m)");

if (m_axi_wr[0].DATA_W != DATA_W)
    $fatal(0, "Error: Interface DATA_W parameter mismatch (instance %m)");

if (m_axi_wr[0].STRB_W != STRB_W)
    $fatal(0, "Error: Interface STRB_W parameter mismatch (instance %m)");

initial begin
    if (M_REGIONS < 1 || M_REGIONS > 16) begin
        $error("Error: M_REGIONS must be between 1 and 16 (instance %m)");
        $finish;
    end

    for (integer i = 0; i < M_COUNT*M_REGIONS; i = i + 1) begin
        /* verilator lint_off UNSIGNED */
        if (M_ADDR_W_INT[i] != 0 && (M_ADDR_W_INT[i] < $clog2(STRB_W) || M_ADDR_W_INT[i] > ADDR_W)) begin
            $error("Error: address width out of range (instance %m)");
            $finish;
        end
        /* verilator lint_on UNSIGNED */
    end

    $display("Addressing configuration for axi_interconnect instance %m");
    for (integer i = 0; i < M_COUNT*M_REGIONS; i = i + 1) begin
        if (M_ADDR_W_INT[i] != 0) begin
            $display("%2d (%2d): %x / %02d -- %x-%x",
                i/M_REGIONS, i%M_REGIONS,
                M_BASE_ADDR_INT[i],
                M_ADDR_W_INT[i],
                M_BASE_ADDR_INT[i] & ({ADDR_W{1'b1}} << M_ADDR_W_INT[i]),
                M_BASE_ADDR_INT[i] | ({ADDR_W{1'b1}} >> (ADDR_W - M_ADDR_W_INT[i]))
            );
        end
    end

    for (integer i = 0; i < M_COUNT*M_REGIONS; i = i + 1) begin
        if ((M_BASE_ADDR_INT[i] & (2**M_ADDR_W_INT[i]-1)) != 0) begin
            $display("Region not aligned:");
            $display("%2d (%2d): %x / %2d -- %x-%x",
                i/M_REGIONS, i%M_REGIONS,
                M_BASE_ADDR_INT[i],
                M_ADDR_W_INT[i],
                M_BASE_ADDR_INT[i] & ({ADDR_W{1'b1}} << M_ADDR_W_INT[i]),
                M_BASE_ADDR_INT[i] | ({ADDR_W{1'b1}} >> (ADDR_W - M_ADDR_W_INT[i]))
            );
            $error("Error: address range not aligned (instance %m)");
            $finish;
        end
    end

    for (integer i = 0; i < M_COUNT*M_REGIONS; i = i + 1) begin
        for (integer j = i+1; j < M_COUNT*M_REGIONS; j = j + 1) begin
            if (M_ADDR_W_INT[i] != 0 && M_ADDR_W_INT[j] != 0) begin
                if (((M_BASE_ADDR_INT[i] & ({ADDR_W{1'b1}} << M_ADDR_W_INT[i])) <= (M_BASE_ADDR_INT[j] | ({ADDR_W{1'b1}} >> (ADDR_W - M_ADDR_W_INT[j]))))
                        && ((M_BASE_ADDR_INT[j] & ({ADDR_W{1'b1}} << M_ADDR_W_INT[j])) <= (M_BASE_ADDR_INT[i] | ({ADDR_W{1'b1}} >> (ADDR_W - M_ADDR_W_INT[i]))))) begin
                    $display("Overlapping regions:");
                    $display("%2d (%2d): %x / %2d -- %x-%x",
                        i/M_REGIONS, i%M_REGIONS,
                        M_BASE_ADDR_INT[i],
                        M_ADDR_W_INT[i],
                        M_BASE_ADDR_INT[i] & ({ADDR_W{1'b1}} << M_ADDR_W_INT[i]),
                        M_BASE_ADDR_INT[i] | ({ADDR_W{1'b1}} >> (ADDR_W - M_ADDR_W_INT[i]))
                    );
                    $display("%2d (%2d): %x / %2d -- %x-%x",
                        j/M_REGIONS, j%M_REGIONS,
                        M_BASE_ADDR_INT[j],
                        M_ADDR_W_INT[j],
                        M_BASE_ADDR_INT[j] & ({ADDR_W{1'b1}} << M_ADDR_W_INT[j]),
                        M_BASE_ADDR_INT[j] | ({ADDR_W{1'b1}} >> (ADDR_W - M_ADDR_W_INT[j]))
                    );
                    $error("Error: address ranges overlap (instance %m)");
                    $finish;
                end
            end
        end
    end
end

typedef enum logic [2:0] {
    STATE_IDLE,
    STATE_DECODE,
    STATE_WRITE,
    STATE_WRITE_RESP,
    STATE_WRITE_DROP,
    STATE_WAIT_IDLE
} state_t;

state_t state_reg = STATE_IDLE, state_next;

logic match;

logic [CL_M_COUNT_INT-1:0] m_select_reg = '0, m_select_next;
logic [S_ID_W-1:0] axi_id_reg = '0, axi_id_next;
logic [ADDR_W-1:0] axi_addr_reg = '0, axi_addr_next;
logic axi_addr_valid_reg = 1'b0, axi_addr_valid_next;
logic [7:0] axi_len_reg = 8'd0, axi_len_next;
logic [2:0] axi_size_reg = 3'd0, axi_size_next;
logic [1:0] axi_burst_reg = 2'd0, axi_burst_next;
logic axi_lock_reg = 1'b0, axi_lock_next;
logic [3:0] axi_cache_reg = 4'd0, axi_cache_next;
logic [2:0] axi_prot_reg = 3'b000, axi_prot_next;
logic [3:0] axi_qos_reg = 4'd0, axi_qos_next;
logic [3:0] axi_region_reg = 4'd0, axi_region_next;
logic [AWUSER_W-1:0] axi_awuser_reg = '0, axi_awuser_next;
logic [1:0] axi_bresp_reg = 2'b00, axi_bresp_next;
logic [BUSER_W-1:0] axi_buser_reg = '0, axi_buser_next;

logic [S_COUNT-1:0] s_axi_awready_reg = '0, s_axi_awready_next;
logic [S_COUNT-1:0] s_axi_wready_reg = '0, s_axi_wready_next;
logic [S_COUNT-1:0] s_axi_bvalid_reg = '0, s_axi_bvalid_next;

logic [M_COUNT-1:0] m_axi_awvalid_reg = '0, m_axi_awvalid_next;
logic [M_COUNT-1:0] m_axi_bready_reg = '0, m_axi_bready_next;

// internal datapath
logic  [DATA_W-1:0]   m_axi_wdata_int;
logic  [STRB_W-1:0]   m_axi_wstrb_int;
logic                 m_axi_wlast_int;
logic  [WUSER_W-1:0]  m_axi_wuser_int;
logic  [M_COUNT-1:0]  m_axi_wvalid_int;
logic                 m_axi_wready_int_reg = 1'b0;
wire                  m_axi_wready_int_early;

// unpack interface array
wire [S_ID_W-1:0]    s_axi_awid[S_COUNT];
wire [ADDR_W-1:0]    s_axi_addr[S_COUNT];
wire [7:0]           s_axi_awlen[S_COUNT];
wire [2:0]           s_axi_awsize[S_COUNT];
wire [1:0]           s_axi_awburst[S_COUNT];
wire                 s_axi_awlock[S_COUNT];
wire [3:0]           s_axi_awcache[S_COUNT];
wire [2:0]           s_axi_awprot[S_COUNT];
wire [3:0]           s_axi_awqos[S_COUNT];
wire [AWUSER_W-1:0]  s_axi_awuser[S_COUNT];
wire [S_COUNT-1:0]   s_axi_awvalid;
wire [DATA_W-1:0]    s_axi_wdata[S_COUNT];
wire [STRB_W-1:0]    s_axi_wstrb[S_COUNT];
wire                 s_axi_wlast[S_COUNT];
wire [WUSER_W-1:0]   s_axi_wuser[S_COUNT];
wire [S_COUNT-1:0]   s_axi_wvalid;
wire [S_COUNT-1:0]   s_axi_bready;

wire [M_COUNT-1:0]   m_axi_awready;
wire [M_ID_W-1:0]    m_axi_bid[M_COUNT];
wire [1:0]           m_axi_bresp[M_COUNT];
wire [BUSER_W-1:0]   m_axi_buser[M_COUNT];
wire [M_COUNT-1:0]   m_axi_bvalid;

for (genvar n = 0; n < S_COUNT; n = n + 1) begin
    assign s_axi_awid[n] = s_axi_wr[n].awid;
    assign s_axi_addr[n] = s_axi_wr[n].awaddr;
    assign s_axi_awlen[n] = s_axi_wr[n].awlen;
    assign s_axi_awsize[n] = s_axi_wr[n].awsize;
    assign s_axi_awburst[n] = s_axi_wr[n].awburst;
    assign s_axi_awlock[n] = s_axi_wr[n].awlock;
    assign s_axi_awcache[n] = s_axi_wr[n].awcache;
    assign s_axi_awprot[n] = s_axi_wr[n].awprot;
    assign s_axi_awqos[n] = s_axi_wr[n].awqos;
    assign s_axi_awuser[n] = s_axi_wr[n].awuser;
    assign s_axi_awvalid[n] = s_axi_wr[n].awvalid;
    assign s_axi_wr[n].awready = s_axi_awready_reg[n];
    assign s_axi_wdata[n] = s_axi_wr[n].wdata;
    assign s_axi_wstrb[n] = s_axi_wr[n].wstrb;
    assign s_axi_wlast[n] = s_axi_wr[n].wlast;
    assign s_axi_wuser[n] = s_axi_wr[n].wuser;
    assign s_axi_wvalid[n] = s_axi_wr[n].wvalid;
    assign s_axi_wr[n].wready = s_axi_wready_reg[n];
    assign s_axi_wr[n].bid = axi_id_reg;
    assign s_axi_wr[n].bresp = axi_bresp_reg;
    assign s_axi_wr[n].buser = BUSER_EN ? axi_buser_reg : '0;
    assign s_axi_wr[n].bvalid = s_axi_bvalid_reg[n];
    assign s_axi_bready[n] = s_axi_wr[n].bready;
end

for (genvar n = 0; n < M_COUNT; n = n + 1) begin
    assign m_axi_wr[n].awid = axi_id_reg;
    assign m_axi_wr[n].awaddr = AXI_M_ADDR_W'(axi_addr_reg);
    assign m_axi_wr[n].awlen = axi_len_reg;
    assign m_axi_wr[n].awsize = axi_size_reg;
    assign m_axi_wr[n].awburst = axi_burst_reg;
    assign m_axi_wr[n].awlock = axi_lock_reg;
    assign m_axi_wr[n].awcache = axi_cache_reg;
    assign m_axi_wr[n].awprot = axi_prot_reg;
    assign m_axi_wr[n].awqos = axi_qos_reg;
    assign m_axi_wr[n].awuser = AWUSER_EN ? axi_awuser_reg : '0;
    assign m_axi_wr[n].awvalid = m_axi_awvalid_reg[n];
    assign m_axi_awready[n] = m_axi_wr[n].awready;
    assign m_axi_bid[n] = m_axi_wr[n].bid;
    assign m_axi_bresp[n] = m_axi_wr[n].bresp;
    assign m_axi_buser[n] = m_axi_wr[n].buser;
    assign m_axi_bvalid[n] = m_axi_wr[n].bvalid;
    assign m_axi_wr[n].bready = m_axi_bready_reg[n];
end

// slave side mux
wire [CL_S_COUNT_INT-1:0] s_select;

wire [S_ID_W-1:0]    current_s_axi_awid    = s_axi_awid[s_select];
wire [ADDR_W-1:0]    current_s_axi_addr    = s_axi_addr[s_select];
wire [7:0]           current_s_axi_awlen   = s_axi_awlen[s_select];
wire [2:0]           current_s_axi_awsize  = s_axi_awsize[s_select];
wire [1:0]           current_s_axi_awburst = s_axi_awburst[s_select];
wire                 current_s_axi_awlock  = s_axi_awlock[s_select];
wire [3:0]           current_s_axi_awcache = s_axi_awcache[s_select];
wire [2:0]           current_s_axi_awprot  = s_axi_awprot[s_select];
wire [3:0]           current_s_axi_awqos   = s_axi_awqos[s_select];
wire [AWUSER_W-1:0]  current_s_axi_awuser  = s_axi_awuser[s_select];
wire                 current_s_axi_awvalid = s_axi_awvalid[s_select];
wire [DATA_W-1:0]    current_s_axi_wdata   = s_axi_wdata[s_select];
wire [STRB_W-1:0]    current_s_axi_wstrb   = s_axi_wstrb[s_select];
wire                 current_s_axi_wlast   = s_axi_wlast[s_select];
wire [WUSER_W-1:0]   current_s_axi_wuser   = s_axi_wuser[s_select];
wire                 current_s_axi_wvalid  = s_axi_wvalid[s_select];
wire                 current_s_axi_bready  = s_axi_bready[s_select];

// master side mux
wire                 current_m_axi_awready = m_axi_awready[m_select_reg];
wire                 current_m_axi_wready  = m_axi_wready[m_select_reg];
wire [M_ID_W-1:0]    current_m_axi_bid     = m_axi_bid[m_select_reg];
wire [1:0]           current_m_axi_bresp   = m_axi_bresp[m_select_reg];
wire [BUSER_W-1:0]   current_m_axi_buser   = m_axi_buser[m_select_reg];
wire                 current_m_axi_bvalid  = m_axi_bvalid[m_select_reg];

// arbiter instance
wire [S_COUNT-1:0] req;
wire [S_COUNT-1:0] ack;
wire [S_COUNT-1:0] grant;
wire grant_valid;
wire [CL_S_COUNT_INT-1:0] grant_index;

assign s_select = grant_index;

if (S_COUNT > 1) begin : arb

    taxi_arbiter #(
        .PORTS(S_COUNT),
        .ARB_ROUND_ROBIN(1),
        .ARB_BLOCK(1),
        .ARB_BLOCK_ACK(1),
        .LSB_HIGH_PRIO(1)
    )
    arb_inst (
        .clk(clk),
        .rst(rst),
        .req(req),
        .ack(ack),
        .grant(grant),
        .grant_valid(grant_valid),
        .grant_index(grant_index)
    );

end else begin

    logic grant_valid_reg = 1'b0;

    always @(posedge clk) begin
        if (req) begin
            grant_valid_reg <= 1'b1;
        end

        if (ack || rst) begin
            grant_valid_reg <= 1'b0;
        end
    end

    assign grant_valid = grant_valid_reg;
    assign grant = '1;
    assign grant_index = '0;

end

assign req = s_axi_awvalid;
assign ack = state_reg == STATE_WAIT_IDLE ? '1 : '0;

always_comb begin
    state_next = STATE_IDLE;

    match = 1'b0;

    m_select_next = m_select_reg;
    axi_id_next = axi_id_reg;
    axi_addr_next = axi_addr_reg;
    axi_addr_valid_next = axi_addr_valid_reg;
    axi_len_next = axi_len_reg;
    axi_size_next = axi_size_reg;
    axi_burst_next = axi_burst_reg;
    axi_lock_next = axi_lock_reg;
    axi_cache_next = axi_cache_reg;
    axi_prot_next = axi_prot_reg;
    axi_qos_next = axi_qos_reg;
    axi_region_next = axi_region_reg;
    axi_awuser_next = axi_awuser_reg;
    axi_bresp_next = axi_bresp_reg;
    axi_buser_next = axi_buser_reg;

    s_axi_awready_next = '0;
    s_axi_wready_next = '0;
    s_axi_bvalid_next = s_axi_bvalid_reg & ~s_axi_bready;

    m_axi_awvalid_next = m_axi_awvalid_reg & ~m_axi_awready;
    m_axi_bready_next = '0;

    m_axi_wdata_int = current_s_axi_wdata;
    m_axi_wstrb_int = current_s_axi_wstrb;
    m_axi_wlast_int = current_s_axi_wlast;
    m_axi_wuser_int = current_s_axi_wuser;
    m_axi_wvalid_int = '0;

    case (state_reg)
        STATE_IDLE: begin
            // idle state; wait for arbitration

            axi_addr_valid_next = 1'b1;
            axi_id_next = current_s_axi_awid;
            axi_addr_next = current_s_axi_addr;
            axi_len_next = current_s_axi_awlen;
            axi_size_next = current_s_axi_awsize;
            axi_burst_next = current_s_axi_awburst;
            axi_lock_next = current_s_axi_awlock;
            axi_cache_next = current_s_axi_awcache;
            axi_prot_next = current_s_axi_awprot;
            axi_qos_next = current_s_axi_awqos;
            axi_awuser_next = current_s_axi_awuser;

            if (grant_valid) begin
                s_axi_awready_next[s_select] = 1'b1;
                state_next = STATE_DECODE;
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_DECODE: begin
            // decode state; determine master interface

            match = 1'b0;
            for (integer i = 0; i < M_COUNT; i = i + 1) begin
                for (integer j = 0; j < M_REGIONS; j = j + 1) begin
                    if (M_ADDR_W_INT[i*M_REGIONS+j] != 0 && (!M_SECURE_INT[i] || !axi_prot_reg[1]) && M_CONNECT_INT[i][s_select] && (axi_addr_reg >> M_ADDR_W_INT[i*M_REGIONS+j]) == (M_BASE_ADDR_INT[i*M_REGIONS+j] >> M_ADDR_W_INT[i*M_REGIONS+j])) begin
                        m_select_next = CL_M_COUNT_INT'(i);
                        match = 1'b1;
                    end
                end
            end

            axi_bresp_next = 2'b11;

            if (match) begin
                s_axi_wready_next[s_select] = m_axi_wready_int_early;
                state_next = STATE_WRITE;
            end else begin
                // no match; return decode error
                s_axi_wready_next[s_select] = 1'b1;
                state_next = STATE_WRITE_DROP;
            end
        end
        STATE_WRITE: begin
            // write state; store and forward write data
            s_axi_wready_next[s_select] = m_axi_wready_int_early;

            if (axi_addr_valid_reg) begin
                m_axi_awvalid_next[m_select_reg] = 1'b1;
            end
            axi_addr_valid_next = 1'b0;

            m_axi_wdata_int = current_s_axi_wdata;
            m_axi_wstrb_int = current_s_axi_wstrb;
            m_axi_wlast_int = current_s_axi_wlast;
            m_axi_wuser_int = current_s_axi_wuser;

            if (s_axi_wready_reg != 0 && current_s_axi_wvalid) begin
                m_axi_wvalid_int[m_select_reg] = 1'b1;

                if (current_s_axi_wlast) begin
                    s_axi_wready_next[s_select] = 1'b0;
                    m_axi_bready_next[m_select_reg] = s_axi_bvalid_reg == 0;
                    state_next = STATE_WRITE_RESP;
                end else begin
                    state_next = STATE_WRITE;
                end
            end else begin
                state_next = STATE_WRITE;
            end
        end
        STATE_WRITE_RESP: begin
            // write response state; store and forward write response
            m_axi_bready_next[m_select_reg] = s_axi_bvalid_reg == 0;

            if (m_axi_bready_reg != 0 && current_m_axi_bvalid) begin
                m_axi_bready_next[m_select_reg] = 1'b0;
                axi_bresp_next = current_m_axi_bresp;
                s_axi_bvalid_next[s_select] = 1'b1;
                state_next = STATE_WAIT_IDLE;
            end else begin
                state_next = STATE_WRITE_RESP;
            end
        end
        STATE_WRITE_DROP: begin
            // write drop state; drop write data
            s_axi_wready_next[s_select] = 1'b1;

            axi_addr_valid_next = 1'b0;

            if (s_axi_wready_reg != 0 && current_s_axi_wvalid && current_s_axi_wlast) begin
                s_axi_wready_next[s_select] = 1'b0;
                s_axi_bvalid_next[s_select] = 1'b1;
                state_next = STATE_WAIT_IDLE;
            end else begin
                state_next = STATE_WRITE_DROP;
            end
        end
        STATE_WAIT_IDLE: begin
            // wait for idle state; wait untl grant valid is deasserted

            if (grant_valid == 0 || ack != 0) begin
                state_next = STATE_IDLE;
            end else begin
                state_next = STATE_WAIT_IDLE;
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

    s_axi_awready_reg <= s_axi_awready_next;
    s_axi_wready_reg <= s_axi_wready_next;
    s_axi_bvalid_reg <= s_axi_bvalid_next;

    m_axi_awvalid_reg <= m_axi_awvalid_next;
    m_axi_bready_reg <= m_axi_bready_next;

    m_select_reg <= m_select_next;
    axi_id_reg <= axi_id_next;
    axi_addr_reg <= axi_addr_next;
    axi_addr_valid_reg <= axi_addr_valid_next;
    axi_len_reg <= axi_len_next;
    axi_size_reg <= axi_size_next;
    axi_burst_reg <= axi_burst_next;
    axi_lock_reg <= axi_lock_next;
    axi_cache_reg <= axi_cache_next;
    axi_prot_reg <= axi_prot_next;
    axi_qos_reg <= axi_qos_next;
    axi_region_reg <= axi_region_next;
    axi_awuser_reg <= axi_awuser_next;
    axi_bresp_reg <= axi_bresp_next;
    axi_buser_reg <= axi_buser_next;

    if (rst) begin
        state_reg <= STATE_IDLE;

        s_axi_awready_reg <= '0;
        s_axi_wready_reg <= '0;
        s_axi_bvalid_reg <= '0;

        m_axi_awvalid_reg <= '0;
        m_axi_bready_reg <= '0;
    end
end

// output datapath logic (W channel)
logic [DATA_W-1:0]  m_axi_wdata_reg  = '0;
logic [STRB_W-1:0]  m_axi_wstrb_reg  = '0;
logic               m_axi_wlast_reg  = 1'b0;
logic [WUSER_W-1:0] m_axi_wuser_reg  = 1'b0;
logic [M_COUNT-1:0] m_axi_wvalid_reg = '0, m_axi_wvalid_next;

logic [DATA_W-1:0]  temp_m_axi_wdata_reg  = '0;
logic [STRB_W-1:0]  temp_m_axi_wstrb_reg  = '0;
logic               temp_m_axi_wlast_reg  = 1'b0;
logic [WUSER_W-1:0] temp_m_axi_wuser_reg  = 1'b0;
logic [M_COUNT-1:0] temp_m_axi_wvalid_reg = '0, temp_m_axi_wvalid_next;

// datapath control
logic store_axi_w_int_to_output;
logic store_axi_w_int_to_temp;
logic store_axi_w_temp_to_output;

wire [M_COUNT-1:0] m_axi_wready;

for (genvar n = 0; n < M_COUNT; n = n + 1) begin
    assign m_axi_wr[n].wdata = m_axi_wdata_reg;
    assign m_axi_wr[n].wstrb = m_axi_wstrb_reg;
    assign m_axi_wr[n].wlast = m_axi_wlast_reg;
    assign m_axi_wr[n].wuser = WUSER_EN ? m_axi_wuser_reg : '0;
    assign m_axi_wr[n].wvalid = m_axi_wvalid_reg[n];
    assign m_axi_wready[n] = m_axi_wr[n].wready;
end

// enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
assign m_axi_wready_int_early = (m_axi_wready & m_axi_wvalid_reg) != 0 || (temp_m_axi_wvalid_reg == 0 && (m_axi_wvalid_reg == 0 || m_axi_wvalid_int == 0));

always_comb begin
    // transfer sink ready state to source
    m_axi_wvalid_next = m_axi_wvalid_reg;
    temp_m_axi_wvalid_next = temp_m_axi_wvalid_reg;

    store_axi_w_int_to_output = 1'b0;
    store_axi_w_int_to_temp = 1'b0;
    store_axi_w_temp_to_output = 1'b0;

    if (m_axi_wready_int_reg) begin
        // input is ready
        if ((m_axi_wready & m_axi_wvalid_reg) != 0 || m_axi_wvalid_reg == 0) begin
            // output is ready or currently not valid, transfer data to output
            m_axi_wvalid_next = m_axi_wvalid_int;
            store_axi_w_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_axi_wvalid_next = m_axi_wvalid_int;
            store_axi_w_int_to_temp = 1'b1;
        end
    end else if ((m_axi_wready & m_axi_wvalid_reg) != 0) begin
        // input is not ready, but output is ready
        m_axi_wvalid_next = temp_m_axi_wvalid_reg;
        temp_m_axi_wvalid_next = '0;
        store_axi_w_temp_to_output = 1'b1;
    end
end

always_ff @(posedge clk) begin
    m_axi_wvalid_reg <= m_axi_wvalid_next;
    m_axi_wready_int_reg <= m_axi_wready_int_early;
    temp_m_axi_wvalid_reg <= temp_m_axi_wvalid_next;

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

    if (rst) begin
        m_axi_wvalid_reg <= '0;
        m_axi_wready_int_reg <= 1'b0;
        temp_m_axi_wvalid_reg <= '0;
    end
end

endmodule

`resetall
