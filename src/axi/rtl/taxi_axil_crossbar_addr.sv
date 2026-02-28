// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2021-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4 lite crossbar address decode and admission control
 */
module taxi_axil_crossbar_addr #
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
    // Address width in bits for address decoding
    parameter STRB_W = 4,
    // TODO fix parametrization once verilator issue 5890 is fixed
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
    input  wire logic [ADDR_W-1:0]  s_axil_aaddr,
    input  wire logic [2:0]         s_axil_aprot,
    input  wire logic               s_axil_avalid,
    output wire logic               s_axil_aready,

    /*
     * Select output
     */
    output wire logic [SEL_W-1:0]   m_select,
    output wire logic               m_axil_avalid,
    input  wire logic               m_axil_aready,

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
    output wire logic [SEL_W-1:0]   m_rc_select,
    output wire logic               m_rc_decerr,
    output wire logic               m_rc_valid,
    input  wire logic               m_rc_ready
);

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
if (M_REGIONS < 1)
    $fatal(0, "Error: M_REGIONS must be at least 1 (instance %m)");

initial begin
    for (integer i = 0; i < M_COUNT*M_REGIONS; i = i + 1) begin
        /* verilator lint_off UNSIGNED */
        if (M_ADDR_W_INT[i] != 0 && (M_ADDR_W_INT[i] < $clog2(STRB_W) || M_ADDR_W_INT[i] > ADDR_W)) begin
            $error("Error: address width out of range (instance %m)");
            $finish;
        end
        /* verilator lint_on UNSIGNED */
    end

    $display("Addressing configuration for axil_crossbar_addr instance %m");
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

logic s_axil_aready_reg = 1'b0, s_axil_aready_next;

logic [SEL_W-1:0] m_select_reg = '0, m_select_next;
logic m_axil_avalid_reg = 1'b0, m_axil_avalid_next;
logic m_decerr_reg = 1'b0, m_decerr_next;
logic m_wc_valid_reg = 1'b0, m_wc_valid_next;
logic m_rc_valid_reg = 1'b0, m_rc_valid_next;

assign s_axil_aready = s_axil_aready_reg;

assign m_select = m_select_reg;
assign m_axil_avalid = m_axil_avalid_reg;

assign m_wc_select = m_select_reg;
assign m_wc_decerr = m_decerr_reg;
assign m_wc_valid = m_wc_valid_reg;

assign m_rc_select = m_select_reg;
assign m_rc_decerr = m_decerr_reg;
assign m_rc_valid = m_rc_valid_reg;

logic match;

always_comb begin
    state_next = STATE_IDLE;

    match = 1'b0;

    s_axil_aready_next = 1'b0;

    m_select_next = m_select_reg;
    m_axil_avalid_next = m_axil_avalid_reg && !m_axil_aready;
    m_decerr_next = m_decerr_reg;
    m_wc_valid_next = m_wc_valid_reg && !m_wc_ready;
    m_rc_valid_next = m_rc_valid_reg && !m_rc_ready;

    case (state_reg)
        STATE_IDLE: begin
            // idle state, store values
            s_axil_aready_next = 1'b0;

            if (s_axil_avalid && !s_axil_aready) begin
                match = 1'b0;
                for (integer i = 0; i < M_COUNT; i = i + 1) begin
                    for (integer j = 0; j < M_REGIONS; j = j + 1) begin
                        if (M_ADDR_W_INT[i*M_REGIONS+j] != 0 && (!M_SECURE_INT[i] || !s_axil_aprot[1]) && M_CONNECT_INT[i][S] && (s_axil_aaddr >> M_ADDR_W_INT[i*M_REGIONS+j]) == (M_BASE_ADDR_INT[i*M_REGIONS+j] >> M_ADDR_W_INT[i*M_REGIONS+j])) begin
                            m_select_next = SEL_W'(i);
                            match = 1'b1;
                        end
                    end
                end

                if (match) begin
                    // address decode successful
                    m_axil_avalid_next = 1'b1;
                    m_decerr_next = 1'b0;
                    m_wc_valid_next = WC_OUTPUT;
                    m_rc_valid_next = 1'b1;
                    state_next = STATE_DECODE;
                end else begin
                    // decode error
                    m_axil_avalid_next = 1'b0;
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
            if (!m_axil_avalid_next && (!m_wc_valid_next || !WC_OUTPUT) && !m_rc_valid_next) begin
                s_axil_aready_next = 1'b1;
                state_next = STATE_IDLE;
            end else begin
                state_next = STATE_DECODE;
            end
        end
    endcase
end

always_ff @(posedge clk) begin
    state_reg <= state_next;
    s_axil_aready_reg <= s_axil_aready_next;
    m_axil_avalid_reg <= m_axil_avalid_next;
    m_wc_valid_reg <= m_wc_valid_next;
    m_rc_valid_reg <= m_rc_valid_next;

    m_select_reg <= m_select_next;
    m_decerr_reg <= m_decerr_next;

    if (rst) begin
        state_reg <= STATE_IDLE;
        s_axil_aready_reg <= 1'b0;
        m_axil_avalid_reg <= 1'b0;
        m_wc_valid_reg <= 1'b0;
        m_rc_valid_reg <= 1'b0;
    end
end

endmodule

`resetall
