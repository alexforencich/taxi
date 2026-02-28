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
 * AXI4 lite interconnect (read)
 */
module taxi_axil_interconnect_rd #
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
    // Read connections between interfaces
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
    taxi_axil_if.rd_slv  s_axil_rd[S_COUNT],

    /*
     * AXI4-lite master interfaces
     */
    taxi_axil_if.rd_mst  m_axil_rd[M_COUNT]
);

// extract parameters
localparam DATA_W = s_axil_rd[0].DATA_W;
localparam S_ADDR_W = s_axil_rd[0].ADDR_W;
localparam STRB_W = s_axil_rd[0].STRB_W;
localparam logic ARUSER_EN = s_axil_rd[0].ARUSER_EN && m_axil_rd[0].ARUSER_EN;
localparam ARUSER_W = s_axil_rd[0].ARUSER_W;
localparam logic RUSER_EN = s_axil_rd[0].RUSER_EN && m_axil_rd[0].RUSER_EN;
localparam RUSER_W = s_axil_rd[0].RUSER_W;

localparam AXIL_M_ADDR_W = m_axil_rd[0].ADDR_W;

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
if (s_axil_rd[0].ADDR_W != ADDR_W)
    $fatal(0, "Error: Interface ADDR_W parameter mismatch (instance %m)");

if (m_axil_rd[0].DATA_W != DATA_W)
    $fatal(0, "Error: Interface DATA_W parameter mismatch (instance %m)");

if (m_axil_rd[0].STRB_W != STRB_W)
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

typedef enum logic [1:0] {
    STATE_IDLE,
    STATE_DECODE,
    STATE_READ,
    STATE_WAIT_IDLE
} state_t;

state_t state_reg = STATE_IDLE, state_next;

logic match;

logic [CL_M_COUNT_INT-1:0] m_select_reg = '0, m_select_next;
logic [ADDR_W-1:0] axil_araddr_reg = '0, axil_araddr_next;
logic axil_araddr_valid_reg = 1'b0, axil_araddr_valid_next;
logic [2:0] axil_arprot_reg = 3'b000, axil_arprot_next;
logic [ARUSER_W-1:0] axil_aruser_reg = '0, axil_aruser_next;
logic [DATA_W-1:0] axil_rdata_reg = '0, axil_rdata_next;
logic [1:0] axil_rresp_reg = 2'b00, axil_rresp_next;
logic [RUSER_W-1:0] axil_ruser_reg = '0, axil_ruser_next;

logic [S_COUNT-1:0] s_axil_arready_reg = '0, s_axil_arready_next;
logic [S_COUNT-1:0] s_axil_rvalid_reg = '0, s_axil_rvalid_next;

logic [M_COUNT-1:0] m_axil_arvalid_reg = '0, m_axil_arvalid_next;
logic [M_COUNT-1:0] m_axil_rready_reg = '0, m_axil_rready_next;

// unpack interface array
wire [ADDR_W-1:0]    s_axil_araddr[S_COUNT];
wire [2:0]           s_axil_arprot[S_COUNT];
wire [ARUSER_W-1:0]  s_axil_aruser[S_COUNT];
wire [S_COUNT-1:0]   s_axil_arvalid;
wire [S_COUNT-1:0]   s_axil_rready;

wire [M_COUNT-1:0]   m_axil_arready;
wire [DATA_W-1:0]    m_axil_rdata[M_COUNT];
wire [1:0]           m_axil_rresp[M_COUNT];
wire [RUSER_W-1:0]   m_axil_ruser[M_COUNT];
wire [M_COUNT-1:0]   m_axil_rvalid;

for (genvar n = 0; n < S_COUNT; n = n + 1) begin
    assign s_axil_araddr[n] = s_axil_rd[n].araddr;
    assign s_axil_arprot[n] = s_axil_rd[n].arprot;
    assign s_axil_aruser[n] = s_axil_rd[n].aruser;
    assign s_axil_arvalid[n] = s_axil_rd[n].arvalid;
    assign s_axil_rd[n].arready = s_axil_arready_reg[n];
    assign s_axil_rd[n].rdata = axil_rdata_reg;
    assign s_axil_rd[n].rresp = axil_rresp_reg;
    assign s_axil_rd[n].ruser = RUSER_EN ? axil_ruser_reg : '0;
    assign s_axil_rd[n].rvalid = s_axil_rvalid_reg[n];
    assign s_axil_rready[n] = s_axil_rd[n].rready;
end

for (genvar n = 0; n < M_COUNT; n = n + 1) begin
    assign m_axil_rd[n].araddr = AXIL_M_ADDR_W'(axil_araddr_reg);
    assign m_axil_rd[n].arprot = axil_arprot_reg;
    assign m_axil_rd[n].aruser = ARUSER_EN ? axil_aruser_reg : '0;
    assign m_axil_rd[n].arvalid = m_axil_arvalid_reg[n];
    assign m_axil_arready[n] = m_axil_rd[n].arready;
    assign m_axil_rdata[n] = m_axil_rd[n].rdata;
    assign m_axil_rresp[n] = m_axil_rd[n].rresp;
    assign m_axil_ruser[n] = m_axil_rd[n].ruser;
    assign m_axil_rvalid[n] = m_axil_rd[n].rvalid;
    assign m_axil_rd[n].rready = m_axil_rready_reg[n];
end

// slave side mux
wire [CL_S_COUNT_INT-1:0] s_select;

wire [ADDR_W-1:0]    current_s_axil_araddr  = s_axil_araddr[s_select];
wire [2:0]           current_s_axil_arprot  = s_axil_arprot[s_select];
wire [ARUSER_W-1:0]  current_s_axil_aruser  = s_axil_aruser[s_select];
wire                 current_s_axil_arvalid = s_axil_arvalid[s_select];
wire                 current_s_axil_rready  = s_axil_rready[s_select];

// master side mux
wire                 current_m_axil_arready = m_axil_arready[m_select_reg];
wire [DATA_W-1:0]    current_m_axil_rdata   = m_axil_rdata[m_select_reg];
wire [1:0]           current_m_axil_rresp   = m_axil_rresp[m_select_reg];
wire [RUSER_W-1:0]   current_m_axil_ruser   = m_axil_ruser[m_select_reg];
wire                 current_m_axil_rvalid  = m_axil_rvalid[m_select_reg];

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

// req generation
assign req = s_axil_arvalid;
assign ack = grant & s_axil_rvalid_reg & s_axil_rready;

always_comb begin
    state_next = STATE_IDLE;

    match = 1'b0;

    m_select_next = m_select_reg;
    axil_araddr_next = axil_araddr_reg;
    axil_araddr_valid_next = axil_araddr_valid_reg;
    axil_arprot_next = axil_arprot_reg;
    axil_aruser_next = axil_aruser_reg;
    axil_rdata_next = axil_rdata_reg;
    axil_rresp_next = axil_rresp_reg;
    axil_ruser_next = axil_ruser_reg;

    s_axil_arready_next = '0;
    s_axil_rvalid_next = s_axil_rvalid_reg & ~s_axil_rready;

    m_axil_arvalid_next = m_axil_arvalid_reg & ~m_axil_arready;
    m_axil_rready_next = '0;

    case (state_reg)
        STATE_IDLE: begin
            // idle state; wait for arbitration
            axil_araddr_valid_next = 1'b1;
            axil_araddr_next = current_s_axil_araddr;
            axil_arprot_next = current_s_axil_arprot;
            axil_aruser_next = current_s_axil_aruser;

            if (grant_valid) begin
                s_axil_arready_next[s_select] = 1'b1;
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
                    if (M_ADDR_W_INT[i*M_REGIONS+j] != 0 && (!M_SECURE_INT[i] || !axil_arprot_reg[1]) && M_CONNECT_INT[i][s_select] && (axil_araddr_reg >> M_ADDR_W_INT[i*M_REGIONS+j]) == (M_BASE_ADDR_INT[i*M_REGIONS+j] >> M_ADDR_W_INT[i*M_REGIONS+j])) begin
                        m_select_next = CL_M_COUNT_INT'(i);
                        match = 1'b1;
                    end
                end
            end

            axil_rdata_next = '0;
            axil_rresp_next = 2'b11;

            if (match) begin
                m_axil_rready_next[m_select_next] = 1'b1;
                state_next = STATE_READ;
            end else begin
                // no match; return decode error
                s_axil_rvalid_next[s_select] = 1'b1;
                state_next = STATE_WAIT_IDLE;
            end
        end
        STATE_READ: begin
            // read state; store and forward read response
            m_axil_rready_next[m_select_reg] = 1'b1;

            if (axil_araddr_valid_reg) begin
                m_axil_arvalid_next[m_select_reg] = 1'b1;
            end
            axil_araddr_valid_next = 1'b0;

            if (m_axil_rready_reg != 0 && current_m_axil_rvalid) begin
                m_axil_rready_next[m_select_reg] = 1'b0;
                axil_rdata_next = current_m_axil_rdata;
                axil_rresp_next = current_m_axil_rresp;
                axil_ruser_next = current_m_axil_ruser;
                s_axil_rvalid_next[s_select] = 1'b1;
                state_next = STATE_WAIT_IDLE;
            end else begin
                state_next = STATE_READ;
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

    axil_araddr_reg <= axil_araddr_next;
    axil_araddr_valid_reg <= axil_araddr_valid_next;
    axil_arprot_reg <= axil_arprot_next;
    axil_aruser_reg <= axil_aruser_next;
    axil_rdata_reg <= axil_rdata_next;
    axil_rresp_reg <= axil_rresp_next;
    axil_ruser_reg <= axil_ruser_next;

    s_axil_arready_reg <= s_axil_arready_next;
    s_axil_rvalid_reg <= s_axil_rvalid_next;

    m_axil_arvalid_reg <= m_axil_arvalid_next;
    m_axil_rready_reg <= m_axil_rready_next;

    if (rst) begin
        state_reg <= STATE_IDLE;

        s_axil_arready_reg <= '0;
        s_axil_rvalid_reg <= '0;

        m_axil_arvalid_reg <= '0;
        m_axil_rready_reg <= '0;
    end
end

endmodule

`resetall
