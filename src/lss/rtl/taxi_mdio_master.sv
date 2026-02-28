// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2015-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * MDIO master
 */
module taxi_mdio_master (
    input  wire logic        clk,
    input  wire logic        rst,

    /*
     * Host interface
     */
    taxi_axis_if.snk         s_axis_cmd,
    taxi_axis_if.src         m_axis_rd_data,

    /*
     * MDIO to PHY
     */
    output wire logic        mdc_o,
    input  wire logic        mdio_i,
    output wire logic        mdio_o,
    output wire logic        mdio_t,

    /*
     * Status
     */
    output wire logic        busy,

    /*
     * Configuration
     */
    input  wire logic [7:0]  prescale
);

typedef enum logic [1:0] {
    STATE_IDLE,
    STATE_PREAMBLE,
    STATE_TRANSFER
} state_t;

state_t state_reg = STATE_IDLE, state_next;

logic [7:0] count_reg = '0, count_next;
logic [5:0] bit_count_reg = '0, bit_count_next;
logic cycle_reg = 1'b0, cycle_next;

logic [31:0] data_reg = '0, data_next;

logic [1:0] op_reg = 2'b00, op_next;

logic s_axis_cmd_ready_reg = 1'b0, cmd_ready_next;

logic [15:0] m_axis_rd_data_reg = '0, m_axis_rd_data_next;
logic m_axis_rd_data_valid_reg = 1'b0, m_axis_rd_data_valid_next;

logic mdio_i_reg = 1'b1;

logic mdc_o_reg = 1'b0, mdc_o_next;
logic mdio_o_reg = 1'b0, mdio_o_next;
logic mdio_t_reg = 1'b1, mdio_t_next;

logic busy_reg = 1'b0;

assign s_axis_cmd.tready = s_axis_cmd_ready_reg;

assign m_axis_rd_data.tdata = m_axis_rd_data_reg;
assign m_axis_rd_data.tkeep = '1;
assign m_axis_rd_data.tstrb = m_axis_rd_data.tkeep;
assign m_axis_rd_data.tvalid = m_axis_rd_data_valid_reg;
assign m_axis_rd_data.tlast = 1'b1;
assign m_axis_rd_data.tid = '0;
assign m_axis_rd_data.tdest = '0;
assign m_axis_rd_data.tuser = '0;

assign mdc_o = mdc_o_reg;
assign mdio_o = mdio_o_reg;
assign mdio_t = mdio_t_reg;

assign busy = busy_reg;

wire [1:0]   cmd_st = s_axis_cmd.tdata[31:30];
wire [1:0]   cmd_op = s_axis_cmd.tdata[29:28];
wire [9:0]   cmd_addr = s_axis_cmd.tdata[27:18];
wire [15:0]  cmd_data = s_axis_cmd.tdata[15:0];

always_comb begin
    state_next = STATE_IDLE;

    count_next = count_reg;
    bit_count_next = bit_count_reg;
    cycle_next = cycle_reg;

    data_next = data_reg;

    op_next = op_reg;

    cmd_ready_next = 1'b0;

    m_axis_rd_data_next = m_axis_rd_data_reg;
    m_axis_rd_data_valid_next = m_axis_rd_data_valid_reg && !m_axis_rd_data.tready;

    mdc_o_next = mdc_o_reg;
    mdio_o_next = mdio_o_reg;
    mdio_t_next = mdio_t_reg;

    if (count_reg != 0) begin
        count_next = count_reg - 8'd1;
        state_next = state_reg;
    end else if (cycle_reg) begin
        cycle_next = 1'b0;
        mdc_o_next = 1'b1;
        count_next = prescale;
        state_next = state_reg;
    end else begin
        mdc_o_next = 1'b0;
        case (state_reg)
            STATE_IDLE: begin
                // idle - accept new command
                if (s_axis_cmd.tvalid) begin
                    cmd_ready_next = 1'b1;
                    data_next = {cmd_st, cmd_op, cmd_addr, 2'b10, cmd_data};
                    op_next = cmd_op;
                    mdio_t_next = 1'b0;
                    mdio_o_next = 1'b1;
                    bit_count_next = 6'd32;
                    cycle_next = 1'b1;
                    count_next = prescale;
                    state_next = STATE_PREAMBLE;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_PREAMBLE: begin
                cycle_next = 1'b1;
                count_next = prescale;
                if (bit_count_reg > 6'd1) begin
                    bit_count_next = bit_count_reg - 6'd1;
                    state_next = STATE_PREAMBLE;
                end else begin
                    bit_count_next = 6'd32;
                    {mdio_o_next, data_next} = {data_reg, mdio_i_reg};
                    state_next = STATE_TRANSFER;
                end
            end
            STATE_TRANSFER: begin
                cycle_next = 1'b1;
                count_next = prescale;
                if (op_reg[1] && bit_count_reg == 6'd19) begin
                    mdio_t_next = 1'b1;
                end
                if (bit_count_reg > 6'd1) begin
                    bit_count_next = bit_count_reg - 6'd1;
                    {mdio_o_next, data_next} = {data_reg, mdio_i_reg};
                    state_next = STATE_TRANSFER;
                end else begin
                    if (op_reg[1]) begin
                        m_axis_rd_data_next = data_reg[15:0];
                        m_axis_rd_data_valid_next = 1'b1;
                    end
                    mdio_t_next = 1'b1;
                    state_next = STATE_IDLE;
                end
            end
            default: begin
                state_next = STATE_IDLE;
            end
        endcase
    end
end

always_ff @(posedge clk) begin
    state_reg <= state_next;

    count_reg <= count_next;
    bit_count_reg <= bit_count_next;
    cycle_reg <= cycle_next;

    data_reg <= data_next;
    op_reg <= op_next;

    s_axis_cmd_ready_reg <= cmd_ready_next;

    m_axis_rd_data_reg <= m_axis_rd_data_next;
    m_axis_rd_data_valid_reg <= m_axis_rd_data_valid_next;

    mdio_i_reg <= mdio_i;

    mdc_o_reg <= mdc_o_next;
    mdio_o_reg <= mdio_o_next;
    mdio_t_reg <= mdio_t_next;

    busy_reg <= (state_next != STATE_IDLE || count_reg != 0 || cycle_reg || mdc_o);

    if (rst) begin
        state_reg <= STATE_IDLE;
        count_reg <= '0;
        bit_count_reg <= '0;
        cycle_reg <= 1'b0;
        s_axis_cmd_ready_reg <= 1'b0;
        m_axis_rd_data_valid_reg <= 1'b0;
        mdc_o_reg <= 1'b0;
        mdio_o_reg <= 1'b0;
        mdio_t_reg <= 1'b1;
        busy_reg <= 1'b0;
    end
end

endmodule

`resetall
