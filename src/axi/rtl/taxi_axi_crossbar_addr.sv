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
 * AXI4 crossbar address decode and admission control
 */
module taxi_axi_crossbar_addr #
(
    // Slave interface index
    parameter S = 0,
    // Number of AXI inputs (slave interfaces)
    parameter S_COUNT = 4,
    // Number of AXI outputs (master interfaces)
    parameter M_COUNT = 4,
    // Select signal width
    parameter SEL_W = $clog2(M_COUNT),
    // Address width in bits for address decoding
    parameter ADDR_W = 32,
    // ID field width
    parameter ID_W = 8,
    // TODO fix parametrization once verilator issue 5890 is fixed
    // Number of concurrent unique IDs
    parameter S_THREADS = 32'd2,
    // Number of concurrent operations
    parameter S_ACCEPT = 32'd16,
    // Number of regions per master interface
    parameter M_REGIONS = 1,
    // Master interface base addresses
    // M_COUNT concatenated fields of M_REGIONS concatenated fields of ADDR_W bits
    // set to zero for default addressing based on M_ADDR_W
    parameter M_BASE_ADDR = '0,
    // Master interface address widths
    // M_COUNT concatenated fields of M_REGIONS concatenated fields of 32 bits
    parameter M_ADDR_W = {M_COUNT{{M_REGIONS{32'd24}}}},
    // Connections between interfaces
    // M_COUNT concatenated fields of S_COUNT bits
    parameter M_CONNECT = {M_COUNT{{S_COUNT{1'b1}}}},
    // Secure master (fail operations based on awprot/arprot)
    // M_COUNT bits
    parameter M_SECURE = {M_COUNT{1'b0}},
    // Enable write command output
    parameter WC_OUTPUT = 0
)
(
    input  wire logic               clk,
    input  wire logic               rst,

    /*
     * Address input
     */
    input  wire logic [ID_W-1:0]    s_axi_aid,
    input  wire logic [ADDR_W-1:0]  s_axi_aaddr,
    input  wire logic [2:0]         s_axi_aprot,
    input  wire logic [3:0]         s_axi_aqos,
    input  wire logic               s_axi_avalid,
    output wire logic               s_axi_aready,

    /*
     * Address output
     */
    output wire logic [3:0]         m_axi_aregion,
    output wire logic [SEL_W-1:0]   m_select,
    output wire logic               m_axi_avalid,
    input  wire logic               m_axi_aready,

    /*
     * Write command output
     */
    output wire logic [SEL_W-1:0]   m_wc_select,
    output wire logic               m_wc_decerr,
    output wire logic               m_wc_valid,
    input  wire logic               m_wc_ready,

    /*
     * Reply command output
     */
    output wire logic               m_rc_decerr,
    output wire logic               m_rc_valid,
    input  wire logic               m_rc_ready,

    /*
     * Completion input
     */
    input  wire logic [ID_W-1:0]    s_cpl_id,
    input  wire logic               s_cpl_valid
);

localparam CL_S_COUNT = $clog2(S_COUNT);
localparam CL_M_COUNT = $clog2(M_COUNT);
localparam CL_S_COUNT_INT = CL_S_COUNT > 0 ? CL_S_COUNT : 1;
localparam CL_M_COUNT_INT = CL_M_COUNT > 0 ? CL_M_COUNT : 1;

localparam [M_COUNT*M_REGIONS-1:0][31:0] M_ADDR_W_INT = M_ADDR_W;
localparam [M_COUNT-1:0][S_COUNT-1:0] M_CONNECT_INT = M_CONNECT;
localparam [M_COUNT-1:0] M_SECURE_INT = M_SECURE;

localparam S_INT_THREADS = S_THREADS > S_ACCEPT ? S_ACCEPT : S_THREADS;
localparam CL_S_INT_THREADS = $clog2(S_INT_THREADS);
localparam CL_S_ACCEPT = $clog2(S_ACCEPT);

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
if (M_REGIONS < 1 || M_REGIONS > 16)
    $fatal(0, "Error: M_REGIONS must be between 1 and 16 (instance %m)");

if (S_ACCEPT < 1)
    $fatal(0, "Error: need at least 1 accept (instance %m)");

if (S_THREADS < 1)
    $fatal(0, "Error: need at least 1 thread (instance %m)");

initial begin
    if (S_THREADS > S_ACCEPT) begin
        $warning("Warning: requested thread count larger than accept count; limiting thread count to accept count (instance %m)");
    end

    for (integer i = 0; i < M_COUNT*M_REGIONS; i = i + 1) begin
        if (M_ADDR_W_INT[i] != 0 && (M_ADDR_W_INT[i] < 12 || M_ADDR_W_INT[i] > ADDR_W)) begin
            $error("Error: address width out of range (instance %m)");
            $finish;
        end
    end

    $display("Addressing configuration for axi_crossbar_addr instance %m");
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

typedef enum logic [0:0] {
    STATE_IDLE,
    STATE_DECODE
} state_t;

state_t state_reg = STATE_IDLE, state_next;

logic s_axi_aready_reg = 1'b0, s_axi_aready_next;

logic [3:0] m_axi_aregion_reg = 4'd0, m_axi_aregion_next;
logic [SEL_W-1:0] m_select_reg = '0, m_select_next;
logic m_axi_avalid_reg = 1'b0, m_axi_avalid_next;
logic m_decerr_reg = 1'b0, m_decerr_next;
logic m_wc_valid_reg = 1'b0, m_wc_valid_next;
logic m_rc_valid_reg = 1'b0, m_rc_valid_next;

assign s_axi_aready = s_axi_aready_reg;

assign m_axi_aregion = m_axi_aregion_reg;
assign m_select = m_select_reg;
assign m_axi_avalid = m_axi_avalid_reg;

assign m_wc_select = m_select_reg;
assign m_wc_decerr = m_decerr_reg;
assign m_wc_valid = m_wc_valid_reg;

assign m_rc_decerr = m_decerr_reg;
assign m_rc_valid = m_rc_valid_reg;

logic match;
logic trans_start;
logic trans_complete;

localparam TR_CNT_W = $clog2(S_ACCEPT+1);
logic [TR_CNT_W-1:0] trans_count_reg = 0;
wire trans_limit = trans_count_reg >= TR_CNT_W'(S_ACCEPT) && !trans_complete;

// transfer ID thread tracking
logic [ID_W-1:0] thread_id_reg[S_INT_THREADS-1:0];
logic [SEL_W-1:0] thread_m_reg[S_INT_THREADS-1:0];
logic [3:0] thread_region_reg[S_INT_THREADS-1:0];
logic [$clog2(S_ACCEPT+1)-1:0] thread_count_reg[S_INT_THREADS-1:0];

// TODO fix loop
/* verilator lint_off UNOPTFLAT */
wire [S_INT_THREADS-1:0] thread_active;
wire [S_INT_THREADS-1:0] thread_match;
wire [S_INT_THREADS-1:0] thread_match_dest;
wire [S_INT_THREADS-1:0] thread_cpl_match;
wire [S_INT_THREADS-1:0] thread_trans_start;
wire [S_INT_THREADS-1:0] thread_trans_complete;

for (genvar n = 0; n < S_INT_THREADS; n = n + 1) begin
    initial begin
        thread_count_reg[n] = '0;
    end

    assign thread_active[n] = thread_count_reg[n] != 0;
    assign thread_match[n] = thread_active[n] && thread_id_reg[n] == s_axi_aid;
    assign thread_match_dest[n] = thread_match[n] && thread_m_reg[n] == m_select_next && (M_REGIONS < 2 || thread_region_reg[n] == m_axi_aregion_next);
    assign thread_cpl_match[n] = thread_active[n] && thread_id_reg[n] == s_cpl_id;
    assign thread_trans_start[n] = (thread_match[n] || (!thread_active[n] && thread_match == 0 && (thread_trans_start & ({S_INT_THREADS{1'b1}} >> (S_INT_THREADS-n))) == 0)) && trans_start;
    assign thread_trans_complete[n] = thread_cpl_match[n] && trans_complete;

    always_ff @(posedge clk) begin
        if (thread_trans_start[n]) begin
            thread_id_reg[n] <= s_axi_aid;
            thread_m_reg[n] <= m_select_next;
            thread_region_reg[n] <= m_axi_aregion_next;
        end

        if (thread_trans_start[n] && !thread_trans_complete[n]) begin
            thread_count_reg[n] <= thread_count_reg[n] + 1;
        end else if (!thread_trans_start[n] && thread_trans_complete[n]) begin
            thread_count_reg[n] <= thread_count_reg[n] - 1;
        end

        if (rst) begin
            thread_count_reg[n] <= 0;
        end
    end
end

always_comb begin
    state_next = STATE_IDLE;

    match = 1'b0;
    trans_start = 1'b0;
    trans_complete = 1'b0;

    s_axi_aready_next = 1'b0;

    m_axi_aregion_next = m_axi_aregion_reg;
    m_select_next = m_select_reg;
    m_axi_avalid_next = m_axi_avalid_reg && !m_axi_aready;
    m_decerr_next = m_decerr_reg;
    m_wc_valid_next = m_wc_valid_reg && !m_wc_ready;
    m_rc_valid_next = m_rc_valid_reg && !m_rc_ready;

    case (state_reg)
        STATE_IDLE: begin
            // idle state, store values
            s_axi_aready_next = 1'b0;

            if (s_axi_avalid && !s_axi_aready) begin
                match = 1'b0;
                for (integer i = 0; i < M_COUNT; i = i + 1) begin
                    for (integer j = 0; j < M_REGIONS; j = j + 1) begin
                        if (M_ADDR_W_INT[i*M_REGIONS+j] != 0 && (!M_SECURE_INT[i] || !s_axi_aprot[1]) && M_CONNECT_INT[i][S] && (s_axi_aaddr >> M_ADDR_W_INT[i*M_REGIONS+j]) == (M_BASE_ADDR_INT[i*M_REGIONS+j] >> M_ADDR_W_INT[i*M_REGIONS+j])) begin
                            m_select_next = SEL_W'(i);
                            m_axi_aregion_next = 4'(j);
                            match = 1'b1;
                        end
                    end
                end

                if (match) begin
                    // address decode successful
                    if (!trans_limit && (thread_match_dest != 0 || (!(&thread_active) && thread_match == 0))) begin
                        // transaction limit not reached
                        m_axi_avalid_next = 1'b1;
                        m_decerr_next = 1'b0;
                        m_wc_valid_next = WC_OUTPUT;
                        m_rc_valid_next = 1'b0;
                        trans_start = 1'b1;
                        state_next = STATE_DECODE;
                    end else begin
                        // transaction limit reached; block in idle
                        state_next = STATE_IDLE;
                    end
                end else begin
                    // decode error
                    m_axi_avalid_next = 1'b0;
                    m_decerr_next = 1'b1;
                    m_wc_valid_next = WC_OUTPUT;
                    m_rc_valid_next = 1'b1;
                    state_next = STATE_DECODE;
                end
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_DECODE: begin
            if (!m_axi_avalid_next && (!m_wc_valid_next || !WC_OUTPUT) && !m_rc_valid_next) begin
                s_axi_aready_next = 1'b1;
                state_next = STATE_IDLE;
            end else begin
                state_next = STATE_DECODE;
            end
        end
    endcase

    // manage completions
    trans_complete = s_cpl_valid;
end

always_ff @(posedge clk) begin
    state_reg <= state_next;
    s_axi_aready_reg <= s_axi_aready_next;
    m_axi_avalid_reg <= m_axi_avalid_next;
    m_wc_valid_reg <= m_wc_valid_next;
    m_rc_valid_reg <= m_rc_valid_next;

    if (trans_start && !trans_complete) begin
        trans_count_reg <= trans_count_reg + 1;
    end else if (!trans_start && trans_complete) begin
        trans_count_reg <= trans_count_reg - 1;
    end

    m_axi_aregion_reg <= m_axi_aregion_next;
    m_select_reg <= m_select_next;
    m_decerr_reg <= m_decerr_next;

    if (rst) begin
        state_reg <= STATE_IDLE;
        s_axi_aready_reg <= 1'b0;
        m_axi_avalid_reg <= 1'b0;
        m_wc_valid_reg <= 1'b0;
        m_rc_valid_reg <= 1'b0;

        trans_count_reg <= 0;
    end
end

endmodule

`resetall
