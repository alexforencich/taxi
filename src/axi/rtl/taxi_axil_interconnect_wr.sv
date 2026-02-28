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
 * AXI4 lite interconnect (write)
 */
module taxi_axil_interconnect_wr #
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
    parameter M_BASE_ADDR = '0,
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
    input  wire logic    clk,
    input  wire logic    rst,

    /*
     * AXI4-lite slave interfaces
     */
    taxi_axil_if.wr_slv  s_axil_wr[S_COUNT],

    /*
     * AXI4-lite master interfaces
     */
    taxi_axil_if.wr_mst  m_axil_wr[M_COUNT]
);

// extract parameters
localparam DATA_W = s_axil_wr[0].DATA_W;
localparam S_ADDR_W = s_axil_wr[0].ADDR_W;
localparam STRB_W = s_axil_wr[0].STRB_W;
localparam logic AWUSER_EN = s_axil_wr[0].AWUSER_EN && m_axil_wr[0].AWUSER_EN;
localparam AWUSER_W = s_axil_wr[0].AWUSER_W;
localparam logic WUSER_EN = s_axil_wr[0].WUSER_EN && m_axil_wr[0].WUSER_EN;
localparam WUSER_W = s_axil_wr[0].WUSER_W;
localparam logic BUSER_EN = s_axil_wr[0].BUSER_EN && m_axil_wr[0].BUSER_EN;
localparam BUSER_W = s_axil_wr[0].BUSER_W;

localparam AXIL_M_ADDR_W = m_axil_wr[0].ADDR_W;

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
if (s_axil_wr[0].ADDR_W != ADDR_W)
    $fatal(0, "Error: Interface ADDR_W parameter mismatch (instance %m)");

if (m_axil_wr[0].DATA_W != DATA_W)
    $fatal(0, "Error: Interface DATA_W parameter mismatch (instance %m)");

if (m_axil_wr[0].STRB_W != STRB_W)
    $fatal(0, "Error: Interface STRB_W parameter mismatch (instance %m)");

initial begin
    for (integer i = 0; i < M_COUNT*M_REGIONS; i = i + 1) begin
        /* verilator lint_off UNSIGNED */
        if (M_ADDR_W_INT[i] != 0 && (M_ADDR_W_INT[i] < $clog2(STRB_W) || M_ADDR_W_INT[i] > ADDR_W)) begin
            $error("Error: address width out of range (instance %m)");
            $finish;
        end
        /* verilator lint_on UNSIGNED */
    end

    $display("Addressing configuration for axil_interconnect instance %m");
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
logic [ADDR_W-1:0] axil_awaddr_reg = '0, axil_awaddr_next;
logic axil_awaddr_valid_reg = 1'b0, axil_awaddr_valid_next;
logic [2:0] axil_awprot_reg = 3'b000, axil_awprot_next;
logic [AWUSER_W-1:0] axil_awuser_reg = '0, axil_awuser_next;
logic [DATA_W-1:0] axil_wdata_reg = '0, axil_wdata_next;
logic [STRB_W-1:0] axil_wstrb_reg = '0, axil_wstrb_next;
logic [WUSER_W-1:0] axil_wuser_reg = '0, axil_wuser_next;
logic [1:0] axil_bresp_reg = 2'b00, axil_bresp_next;
logic [BUSER_W-1:0] axil_buser_reg = '0, axil_buser_next;

logic [S_COUNT-1:0] s_axil_awready_reg = '0, s_axil_awready_next;
logic [S_COUNT-1:0] s_axil_wready_reg = '0, s_axil_wready_next;
logic [S_COUNT-1:0] s_axil_bvalid_reg = '0, s_axil_bvalid_next;

logic [M_COUNT-1:0] m_axil_awvalid_reg = '0, m_axil_awvalid_next;
logic [M_COUNT-1:0] m_axil_wvalid_reg = '0, m_axil_wvalid_next;
logic [M_COUNT-1:0] m_axil_bready_reg = '0, m_axil_bready_next;

// unpack interface array
wire [ADDR_W-1:0]    s_axil_awaddr[S_COUNT];
wire [2:0]           s_axil_awprot[S_COUNT];
wire [AWUSER_W-1:0]  s_axil_awuser[S_COUNT];
wire [S_COUNT-1:0]   s_axil_awvalid;
wire [DATA_W-1:0]    s_axil_wdata[S_COUNT];
wire [STRB_W-1:0]    s_axil_wstrb[S_COUNT];
wire [WUSER_W-1:0]   s_axil_wuser[S_COUNT];
wire [S_COUNT-1:0]   s_axil_wvalid;
wire [S_COUNT-1:0]   s_axil_bready;

wire [M_COUNT-1:0]   m_axil_awready;
wire [M_COUNT-1:0]   m_axil_wready;
wire [1:0]           m_axil_bresp[M_COUNT];
wire [BUSER_W-1:0]   m_axil_buser[M_COUNT];
wire [M_COUNT-1:0]   m_axil_bvalid;

for (genvar n = 0; n < S_COUNT; n = n + 1) begin
    assign s_axil_awaddr[n] = s_axil_wr[n].awaddr;
    assign s_axil_awprot[n] = s_axil_wr[n].awprot;
    assign s_axil_awuser[n] = s_axil_wr[n].awuser;
    assign s_axil_awvalid[n] = s_axil_wr[n].awvalid;
    assign s_axil_wr[n].awready = s_axil_awready_reg[n];
    assign s_axil_wdata[n] = s_axil_wr[n].wdata;
    assign s_axil_wstrb[n] = s_axil_wr[n].wstrb;
    assign s_axil_wuser[n] = s_axil_wr[n].wuser;
    assign s_axil_wvalid[n] = s_axil_wr[n].wvalid;
    assign s_axil_wr[n].wready = s_axil_wready_reg[n];
    assign s_axil_wr[n].bresp = axil_bresp_reg;
    assign s_axil_wr[n].buser = BUSER_EN ? axil_buser_reg : '0;
    assign s_axil_wr[n].bvalid = s_axil_bvalid_reg[n];
    assign s_axil_bready[n] = s_axil_wr[n].bready;
end

for (genvar n = 0; n < M_COUNT; n = n + 1) begin
    assign m_axil_wr[n].awaddr = AXIL_M_ADDR_W'(axil_awaddr_reg);
    assign m_axil_wr[n].awprot = axil_awprot_reg;
    assign m_axil_wr[n].awuser = AWUSER_EN ? axil_awuser_reg : '0;
    assign m_axil_wr[n].awvalid = m_axil_awvalid_reg[n];
    assign m_axil_awready[n] = m_axil_wr[n].awready;
    assign m_axil_wr[n].wdata = axil_wdata_reg;
    assign m_axil_wr[n].wstrb = axil_wstrb_reg;
    assign m_axil_wr[n].wuser = AWUSER_EN ? axil_wuser_reg : '0;
    assign m_axil_wr[n].wvalid = m_axil_wvalid_reg[n];
    assign m_axil_wready[n] = m_axil_wr[n].wready;
    assign m_axil_bresp[n] = m_axil_wr[n].bresp;
    assign m_axil_buser[n] = m_axil_wr[n].buser;
    assign m_axil_bvalid[n] = m_axil_wr[n].bvalid;
    assign m_axil_wr[n].bready = m_axil_bready_reg[n];
end

// slave side mux
wire [CL_S_COUNT_INT-1:0] s_select;

wire [ADDR_W-1:0]    current_s_axil_awaddr  = s_axil_awaddr[s_select];
wire [2:0]           current_s_axil_awprot  = s_axil_awprot[s_select];
wire [AWUSER_W-1:0]  current_s_axil_awuser  = s_axil_awuser[s_select];
wire                 current_s_axil_awvalid = s_axil_awvalid[s_select];
wire [DATA_W-1:0]    current_s_axil_wdata   = s_axil_wdata[s_select];
wire [STRB_W-1:0]    current_s_axil_wstrb   = s_axil_wstrb[s_select];
wire [WUSER_W-1:0]   current_s_axil_wuser   = s_axil_wuser[s_select];
wire                 current_s_axil_wvalid  = s_axil_wvalid[s_select];
wire                 current_s_axil_bready  = s_axil_bready[s_select];

// master side mux
wire                 current_m_axil_awready = m_axil_awready[m_select_reg];
wire                 current_m_axil_wready  = m_axil_wready[m_select_reg];
wire [1:0]           current_m_axil_bresp   = m_axil_bresp[m_select_reg];
wire [BUSER_W-1:0]   current_m_axil_buser   = m_axil_buser[m_select_reg];
wire                 current_m_axil_bvalid  = m_axil_bvalid[m_select_reg];

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

assign req = s_axil_awvalid;
assign ack = grant & s_axil_bvalid_reg & s_axil_bready;

always_comb begin
    state_next = STATE_IDLE;

    match = 1'b0;

    m_select_next = m_select_reg;
    axil_awaddr_next = axil_awaddr_reg;
    axil_awaddr_valid_next = axil_awaddr_valid_reg;
    axil_awprot_next = axil_awprot_reg;
    axil_awuser_next = axil_awuser_reg;
    axil_wdata_next = axil_wdata_reg;
    axil_wstrb_next = axil_wstrb_reg;
    axil_wuser_next = axil_wuser_reg;
    axil_bresp_next = axil_bresp_reg;
    axil_buser_next = axil_buser_reg;

    s_axil_awready_next = '0;
    s_axil_wready_next = '0;
    s_axil_bvalid_next = s_axil_bvalid_reg & ~s_axil_bready;

    m_axil_awvalid_next = m_axil_awvalid_reg & ~m_axil_awready;
    m_axil_wvalid_next = m_axil_wvalid_reg & ~m_axil_wready;
    m_axil_bready_next = '0;

    case (state_reg)
        STATE_IDLE: begin
            // idle state; wait for arbitration
            axil_awaddr_valid_next = 1'b1;
            axil_awaddr_next = current_s_axil_awaddr;
            axil_awprot_next = current_s_axil_awprot;
            axil_awuser_next = current_s_axil_awuser;

            if (grant_valid) begin
                s_axil_awready_next[grant_index] = 1'b1;
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
                    if (M_ADDR_W_INT[i*M_REGIONS+j] != 0 && (!M_SECURE_INT[i] || !axil_awprot_reg[1]) && M_CONNECT_INT[i][s_select] && (axil_awaddr_reg >> M_ADDR_W_INT[i*M_REGIONS+j]) == (M_BASE_ADDR_INT[i*M_REGIONS+j] >> M_ADDR_W_INT[i*M_REGIONS+j])) begin
                        m_select_next = CL_M_COUNT_INT'(i);
                        match = 1'b1;
                    end
                end
            end

            s_axil_wready_next[s_select] = 1'b1;

            if (match) begin
                state_next = STATE_WRITE;
            end else begin
                // no match; return decode error
                state_next = STATE_WRITE_DROP;
            end
        end
        STATE_WRITE: begin
            // write state; store and forward write data
            s_axil_wready_next[s_select] = 1'b1;

            if (axil_awaddr_valid_reg) begin
                m_axil_awvalid_next[m_select_reg] = 1'b1;
            end
            axil_awaddr_valid_next = 1'b0;

            axil_wdata_next = current_s_axil_wdata;
            axil_wstrb_next = current_s_axil_wstrb;
            axil_wuser_next = current_s_axil_wuser;

            if (s_axil_wready_reg != 0 && current_s_axil_wvalid) begin
                s_axil_wready_next[s_select] = 1'b0;
                m_axil_wvalid_next[m_select_reg] = 1'b1;
                m_axil_bready_next[m_select_reg] = 1'b1;
                state_next = STATE_WRITE_RESP;
            end else begin
                state_next = STATE_WRITE;
            end
        end
        STATE_WRITE_RESP: begin
            // write response state; store and forward write response
            m_axil_bready_next[m_select_reg] = 1'b1;

            axil_bresp_next = current_m_axil_bresp;
            axil_buser_next = current_m_axil_buser;

            if (m_axil_bready_reg != 0 && current_m_axil_bvalid) begin
                m_axil_bready_next[m_select_reg] = 1'b0;
                s_axil_bvalid_next[s_select] = 1'b1;
                state_next = STATE_WAIT_IDLE;
            end else begin
                state_next = STATE_WRITE_RESP;
            end
        end
        STATE_WRITE_DROP: begin
            // write drop state; drop write data
            s_axil_wready_next[s_select] = 1'b1;

            axil_awaddr_valid_next = 1'b0;

            axil_bresp_next = 2'b11;
            axil_buser_next = '0;

            if (s_axil_wready_reg != 0 && current_s_axil_wvalid) begin
                s_axil_wready_next[s_select] = 1'b0;
                s_axil_bvalid_next[s_select] = 1'b1;
                state_next = STATE_WAIT_IDLE;
            end else begin
                state_next = STATE_WRITE_DROP;
            end
        end
        STATE_WAIT_IDLE: begin
            // wait for idle state; wait until grant valid is deasserted

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

    m_select_reg <= m_select_next;

    axil_awaddr_reg <= axil_awaddr_next;
    axil_awaddr_valid_reg <= axil_awaddr_valid_next;
    axil_awprot_reg <= axil_awprot_next;
    axil_awuser_reg <= axil_awuser_next;
    axil_wdata_reg <= axil_wdata_next;
    axil_wstrb_reg <= axil_wstrb_next;
    axil_wuser_reg <= axil_wuser_next;
    axil_bresp_reg <= axil_bresp_next;
    axil_buser_reg <= axil_buser_next;

    s_axil_awready_reg <= s_axil_awready_next;
    s_axil_wready_reg <= s_axil_wready_next;
    s_axil_bvalid_reg <= s_axil_bvalid_next;

    m_axil_awvalid_reg <= m_axil_awvalid_next;
    m_axil_wvalid_reg <= m_axil_wvalid_next;
    m_axil_bready_reg <= m_axil_bready_next;

    if (rst) begin
        state_reg <= STATE_IDLE;

        s_axil_awready_reg <= '0;
        s_axil_wready_reg <= '0;
        s_axil_bvalid_reg <= '0;

        m_axil_awvalid_reg <= '0;
        m_axil_wvalid_reg <= '0;
        m_axil_bready_reg <= '0;
    end
end

endmodule

`resetall
