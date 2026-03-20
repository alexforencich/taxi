// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * APB interconnect
 */
module taxi_apb_interconnect #
(
    // Number of upstream APB interfaces
    parameter S_CNT = 4,
    // Number of downstream APB interfaces
    parameter M_CNT = 4,
    // Width of address decoder in bits
    parameter ADDR_W = 16,
    // Number of regions per master interface
    parameter M_REGIONS = 1,
    // TODO fix parametrization once verilator issue 5890 is fixed
    // Master interface base addresses
    // M_CNT concatenated fields of M_REGIONS concatenated fields of ADDR_W bits
    // set to zero for default addressing based on M_ADDR_W
    parameter M_BASE_ADDR = '0,
    // Master interface address widths
    // M_CNT concatenated fields of M_REGIONS concatenated fields of 32 bits
    parameter M_ADDR_W = {M_CNT{{M_REGIONS{32'd24}}}},
    // Read connections between interfaces
    // M_CNT concatenated fields of S_CNT bits
    parameter M_CONNECT_RD = {M_CNT{{S_CNT{1'b1}}}},
    // Write connections between interfaces
    // M_CNT concatenated fields of S_CNT bits
    parameter M_CONNECT_WR = {M_CNT{{S_CNT{1'b1}}}},
    // Secure master (fail operations based on pprot)
    // M_CNT bits
    parameter M_SECURE = {M_CNT{1'b0}}
)
(
    input  wire logic               clk,
    input  wire logic               rst,

    /*
     * APB slave interface
     */
    taxi_apb_if.slv                 s_apb[S_CNT],

    /*
     * APB master interface
     */
    taxi_apb_if.mst                 m_apb[M_CNT]
);

// extract parameters
localparam DATA_W = s_apb[0].DATA_W;
localparam S_ADDR_W = s_apb[0].ADDR_W;
localparam STRB_W = s_apb[0].STRB_W;
localparam logic PAUSER_EN = s_apb[0].PAUSER_EN && m_apb[0].PAUSER_EN;
localparam PAUSER_W = s_apb[0].PAUSER_W;
localparam logic PWUSER_EN = s_apb[0].PWUSER_EN && m_apb[0].PWUSER_EN;
localparam PWUSER_W = s_apb[0].PWUSER_W;
localparam logic PRUSER_EN = s_apb[0].PRUSER_EN && m_apb[0].PRUSER_EN;
localparam PRUSER_W = s_apb[0].PRUSER_W;
localparam logic PBUSER_EN = s_apb[0].PBUSER_EN && m_apb[0].PBUSER_EN;
localparam PBUSER_W = s_apb[0].PBUSER_W;

localparam APB_M_ADDR_W = m_apb[0].ADDR_W;

localparam CL_S_CNT = $clog2(S_CNT);
localparam CL_S_CNT_INT = CL_S_CNT > 0 ? CL_S_CNT : 1;

localparam CL_M_CNT = $clog2(M_CNT);
localparam CL_M_CNT_INT = CL_M_CNT > 0 ? CL_M_CNT : 1;

localparam [M_CNT*M_REGIONS-1:0][31:0] M_ADDR_W_INT = M_ADDR_W;
localparam [M_CNT-1:0][S_CNT-1:0] M_CONNECT_RD_INT = M_CONNECT_RD;
localparam [M_CNT-1:0][S_CNT-1:0] M_CONNECT_WR_INT = M_CONNECT_WR;
localparam [M_CNT-1:0] M_SECURE_INT = M_SECURE;

// default address computation
function [M_CNT*M_REGIONS-1:0][ADDR_W-1:0] calcBaseAddrs(input [31:0] dummy);
    logic [ADDR_W-1:0] base;
    integer width;
    logic [ADDR_W-1:0] size;
    logic [ADDR_W-1:0] mask;
    begin
        calcBaseAddrs = '0;
        base = '0;
        for (integer i = 0; i < M_CNT*M_REGIONS; i = i + 1) begin
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

localparam [M_CNT*M_REGIONS-1:0][ADDR_W-1:0] M_BASE_ADDR_INT = M_BASE_ADDR != 0 ? (M_CNT*M_REGIONS*ADDR_W)'(M_BASE_ADDR) : calcBaseAddrs(0);

// check configuration
if (s_apb[0].ADDR_W != ADDR_W)
    $fatal(0, "Error: Interface ADDR_W parameter mismatch (instance %m)");

if (m_apb[0].DATA_W != DATA_W)
    $fatal(0, "Error: Interface DATA_W parameter mismatch (instance %m)");

if (m_apb[0].STRB_W != STRB_W)
    $fatal(0, "Error: Interface STRB_W parameter mismatch (instance %m)");

initial begin
    for (integer i = 0; i < M_CNT*M_REGIONS; i = i + 1) begin
        /* verilator lint_off UNSIGNED */
        if (M_ADDR_W_INT[i] != 0 && (M_ADDR_W_INT[i] < $clog2(STRB_W) || M_ADDR_W_INT[i] > ADDR_W)) begin
            $error("Error: address width out of range (instance %m)");
            $finish;
        end
        /* verilator lint_on UNSIGNED */
    end

    $display("Addressing configuration for apb_interconnect instance %m");
    for (integer i = 0; i < M_CNT*M_REGIONS; i = i + 1) begin
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

    for (integer i = 0; i < M_CNT*M_REGIONS; i = i + 1) begin
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

    for (integer i = 0; i < M_CNT*M_REGIONS; i = i + 1) begin
        for (integer j = i+1; j < M_CNT*M_REGIONS; j = j + 1) begin
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
    STATE_READ
} state_t;

state_t state_reg = STATE_IDLE, state_next;

logic match;

logic [CL_M_CNT_INT-1:0] m_sel_reg = '0, m_sel_next;

logic [S_CNT-1:0] s_apb_pready_reg = '0, s_apb_pready_next;
logic [DATA_W-1:0] s_apb_prdata_reg = '0, s_apb_prdata_next;
logic s_apb_pslverr_reg = 1'b0, s_apb_pslverr_next;
logic [PRUSER_W-1:0] s_apb_pruser_reg = '0, s_apb_pruser_next;
logic [PBUSER_W-1:0] s_apb_pbuser_reg = '0, s_apb_pbuser_next;

logic [ADDR_W-1:0] m_apb_paddr_reg = '0, m_apb_paddr_next;
logic [2:0] m_apb_pprot_reg = '0, m_apb_pprot_next;
logic [M_CNT-1:0] m_apb_psel_reg = '0, m_apb_psel_next;
logic m_apb_penable_reg = 1'b0, m_apb_penable_next;
logic m_apb_pwrite_reg = 1'b0, m_apb_pwrite_next;
logic [DATA_W-1:0] m_apb_pwdata_reg = '0, m_apb_pwdata_next;
logic [STRB_W-1:0] m_apb_pstrb_reg = '0, m_apb_pstrb_next;
logic [PAUSER_W-1:0] m_apb_pauser_reg = '0, m_apb_pauser_next;
logic [PWUSER_W-1:0] m_apb_pwuser_reg = '0, m_apb_pwuser_next;

// unpack interface array
wire [ADDR_W-1:0] s_apb_paddr[S_CNT];
wire [2:0] s_apb_pprot[S_CNT];
wire [S_CNT-1:0] s_apb_psel;
wire s_apb_penable[S_CNT];
wire s_apb_pwrite[S_CNT];
wire [DATA_W-1:0] s_apb_pwdata[S_CNT];
wire [STRB_W-1:0] s_apb_pstrb[S_CNT];
wire [PAUSER_W-1:0] s_apb_pauser[S_CNT];
wire [PWUSER_W-1:0] s_apb_pwuser[S_CNT];

wire [M_CNT-1:0] m_apb_pready;
wire [DATA_W-1:0] m_apb_prdata[M_CNT];
wire m_apb_pslverr[M_CNT];
wire [PRUSER_W-1:0] m_apb_pruser[M_CNT];
wire [PBUSER_W-1:0] m_apb_pbuser[M_CNT];

for (genvar n = 0; n < S_CNT; n = n + 1) begin
    assign s_apb_paddr[n] = s_apb[n].paddr;
    assign s_apb_pprot[n] = s_apb[n].pprot;
    assign s_apb_psel[n] = s_apb[n].psel;
    assign s_apb_penable[n] = s_apb[n].penable;
    assign s_apb_pwrite[n] = s_apb[n].pwrite;
    assign s_apb_pwdata[n] = s_apb[n].pwdata;
    assign s_apb_pstrb[n] = s_apb[n].pstrb;
    assign s_apb[n].pready = s_apb_pready_reg[n];
    assign s_apb[n].prdata = s_apb_prdata_reg;
    assign s_apb[n].pslverr = s_apb_pslverr_reg;
    assign s_apb_pauser[n] = s_apb[n].pauser;
    assign s_apb_pwuser[n] = s_apb[n].pwuser;
    assign s_apb[n].pruser = PRUSER_EN ? s_apb_pruser_reg : '0;
    assign s_apb[n].pbuser = PBUSER_EN ? s_apb_pbuser_reg : '0;
end

for (genvar n = 0; n < M_CNT; n = n + 1) begin
    assign m_apb[n].paddr = APB_M_ADDR_W'(m_apb_paddr_reg);
    assign m_apb[n].pprot = m_apb_pprot_reg;
    assign m_apb[n].psel = m_apb_psel_reg[n];
    assign m_apb[n].penable = m_apb_penable_reg;
    assign m_apb[n].pwrite = m_apb_pwrite_reg;
    assign m_apb[n].pwdata = m_apb_pwdata_reg;
    assign m_apb[n].pstrb = m_apb_pstrb_reg;
    assign m_apb_pready[n] = m_apb[n].pready;
    assign m_apb_prdata[n] = m_apb[n].prdata;
    assign m_apb_pslverr[n] = m_apb[n].pslverr;
    assign m_apb[n].pauser = PAUSER_EN ? m_apb_pauser_reg : '0;
    assign m_apb[n].pwuser = PWUSER_EN ? m_apb_pwuser_reg : '0;
    assign m_apb_pruser[n] = m_apb[n].pruser;
    assign m_apb_pbuser[n] = m_apb[n].pbuser;
end

// slave side mux
wire [CL_S_CNT_INT-1:0] s_sel;

wire [ADDR_W-1:0]    cur_s_apb_paddr   = s_apb_paddr[s_sel];
wire [2:0]           cur_s_apb_pprot   = s_apb_pprot[s_sel];
wire                 cur_s_apb_psel    = s_apb_psel[s_sel];
wire                 cur_s_apb_penable = s_apb_penable[s_sel];
wire                 cur_s_apb_pwrite  = s_apb_pwrite[s_sel];
wire [DATA_W-1:0]    cur_s_apb_pwdata  = s_apb_pwdata[s_sel];
wire [STRB_W-1:0]    cur_s_apb_pstrb   = s_apb_pstrb[s_sel];
wire [PAUSER_W-1:0]  cur_s_apb_pauser  = s_apb_pauser[s_sel];
wire [PWUSER_W-1:0]  cur_s_apb_pwuser  = s_apb_pwuser[s_sel];

// master side mux
wire                 cur_m_apb_pready   = m_apb_pready[m_sel_reg];
wire [DATA_W-1:0]    cur_m_apb_prdata   = m_apb_prdata[m_sel_reg];
wire                 cur_m_apb_pslverr  = m_apb_pslverr[m_sel_reg];
wire [PRUSER_W-1:0]  cur_m_apb_pruser   = m_apb_pruser[m_sel_reg];
wire [PBUSER_W-1:0]  cur_m_apb_pbuser   = m_apb_pbuser[m_sel_reg];

// arbiter instance
wire [S_CNT-1:0] req;
wire [S_CNT-1:0] ack;
wire [S_CNT-1:0] grant;
wire grant_valid;
wire [CL_S_CNT_INT-1:0] grant_index;

assign s_sel = grant_index;

if (S_CNT > 1) begin : arb

    taxi_arbiter #(
        .PORTS(S_CNT),
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
    assign grant = grant_valid_reg;
    assign grant_index = '0;

end

// req generation
assign req = s_apb_psel & ~grant;
assign ack = s_apb_pready_reg;

always_comb begin
    state_next = STATE_IDLE;

    match = 1'b0;

    m_sel_next = m_sel_reg;

    s_apb_pready_next = '0;
    s_apb_prdata_next = cur_m_apb_prdata;
    s_apb_pslverr_next = cur_m_apb_pslverr;
    s_apb_pruser_next = cur_m_apb_pruser;
    s_apb_pbuser_next = cur_m_apb_pbuser;

    m_apb_paddr_next = cur_s_apb_paddr;
    m_apb_pprot_next = cur_s_apb_pprot;
    m_apb_psel_next = '0;
    m_apb_penable_next = 1'b0;
    m_apb_pwrite_next = cur_s_apb_pwrite;
    m_apb_pwdata_next = cur_s_apb_pwdata;
    m_apb_pstrb_next = cur_s_apb_pstrb;
    m_apb_pauser_next = cur_s_apb_pauser;
    m_apb_pwuser_next = cur_s_apb_pwuser;

    case (state_reg)
        STATE_IDLE: begin
            // idle state; wait for arbitration
            m_apb_paddr_next = cur_s_apb_paddr;
            m_apb_pprot_next = cur_s_apb_pprot;
            m_apb_pwrite_next = cur_s_apb_pwrite;
            m_apb_pwdata_next = cur_s_apb_pwdata;
            m_apb_pstrb_next = cur_s_apb_pstrb;
            m_apb_pauser_next = cur_s_apb_pauser;
            m_apb_pwuser_next = cur_s_apb_pwuser;

            if (grant_valid && s_apb_pready_reg == 0) begin
                state_next = STATE_DECODE;
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_DECODE: begin
            // decode state; determine master interface

            match = 1'b0;
            for (integer i = 0; i < M_CNT; i = i + 1) begin
                for (integer j = 0; j < M_REGIONS; j = j + 1) begin
                    if (M_ADDR_W_INT[i*M_REGIONS+j] != 0 && (!M_SECURE_INT[i] || !m_apb_pprot_reg[1]) && (m_apb_pwrite_reg ? M_CONNECT_WR_INT[i][s_sel] : M_CONNECT_RD_INT[i][s_sel]) && (m_apb_paddr_reg >> M_ADDR_W_INT[i*M_REGIONS+j]) == (M_BASE_ADDR_INT[i*M_REGIONS+j] >> M_ADDR_W_INT[i*M_REGIONS+j])) begin
                        m_sel_next = CL_M_CNT_INT'(i);
                        match = 1'b1;
                    end
                end
            end

            s_apb_prdata_next = '0;
            s_apb_pslverr_next = 1'b1;

            if (match) begin
                m_apb_psel_next[m_sel_next] = 1'b1;
                state_next = STATE_READ;
            end else begin
                // no match; return decode error
                s_apb_pready_next[s_sel] = 1'b1;
                state_next = STATE_IDLE;
            end
        end
        STATE_READ: begin
            // read state; store and forward read response
            m_apb_psel_next[m_sel_reg] = 1'b1;
            m_apb_penable_next = 1'b1;

            s_apb_pready_next[s_sel] = cur_m_apb_pready;
            s_apb_prdata_next = cur_m_apb_prdata;
            s_apb_pslverr_next = cur_m_apb_pslverr;
            s_apb_pruser_next = cur_m_apb_pruser;
            s_apb_pbuser_next = cur_m_apb_pbuser;

            if (cur_m_apb_pready) begin
                m_apb_psel_next[m_sel_reg] = 1'b0;
                m_apb_penable_next = 1'b0;
                state_next = STATE_IDLE;
            end else begin
                state_next = STATE_READ;
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

    m_sel_reg <= m_sel_next;

    s_apb_pready_reg <= s_apb_pready_next;
    s_apb_prdata_reg <= s_apb_prdata_next;
    s_apb_pslverr_reg <= s_apb_pslverr_next;
    s_apb_pruser_reg <= s_apb_pruser_next;
    s_apb_pbuser_reg <= s_apb_pbuser_next;

    m_apb_paddr_reg <= m_apb_paddr_next;
    m_apb_pprot_reg <= m_apb_pprot_next;
    m_apb_psel_reg <= m_apb_psel_next;
    m_apb_penable_reg <= m_apb_penable_next;
    m_apb_pwrite_reg <= m_apb_pwrite_next;
    m_apb_pwdata_reg <= m_apb_pwdata_next;
    m_apb_pstrb_reg <= m_apb_pstrb_next;
    m_apb_pauser_reg <= m_apb_pauser_next;
    m_apb_pwuser_reg <= m_apb_pwuser_next;

    if (rst) begin
        state_reg <= STATE_IDLE;

        s_apb_pready_reg <= '0;

        m_apb_psel_reg <= '0;
        m_apb_penable_reg <= 1'b0;
    end
end

endmodule

`resetall
