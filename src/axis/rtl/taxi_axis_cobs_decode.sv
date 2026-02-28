// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2016-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4-Stream consistent overhead byte stuffing (COBS) decoder
 */
module taxi_axis_cobs_decode
(
    input  wire logic  clk,
    input  wire logic  rst,

    /*
     * AXI4-Stream input (sink)
     */
    taxi_axis_if.snk   s_axis,

    /*
     * AXI4-Stream output (source)
     */
    taxi_axis_if.src   m_axis
);

// check configuration
if (m_axis.DATA_W != 8 || s_axis.DATA_W != 8)
    $fatal(0, "Error: Interface DATA_W parameter mismatch (instance %m)");

// state register
typedef enum logic [1:0] {
    STATE_IDLE,
    STATE_SEGMENT,
    STATE_NEXT_SEGMENT
} state_t;

state_t state_reg = STATE_IDLE, state_next;

logic [7:0] count_reg = 8'd0, count_next;
logic suppress_zero_reg = 1'b0, suppress_zero_next;

logic [7:0] temp_tdata_reg = 8'd0, temp_tdata_next;
logic temp_tvalid_reg = 1'b0, temp_tvalid_next;

// internal datapath
logic [7:0] m_axis_tdata_int;
logic       m_axis_tvalid_int;
logic       m_axis_tready_int_reg = 1'b0;
logic       m_axis_tlast_int;
logic       m_axis_tuser_int;
wire        m_axis_tready_int_early;

logic s_axis_tready_reg = 1'b0, s_axis_tready_next;

assign s_axis.tready = s_axis_tready_reg;

always_comb begin
    state_next = STATE_IDLE;

    count_next = count_reg;
    suppress_zero_next = suppress_zero_reg;

    temp_tdata_next = temp_tdata_reg;
    temp_tvalid_next = temp_tvalid_reg;

    m_axis_tdata_int = 8'd0;
    m_axis_tvalid_int = 1'b0;
    m_axis_tlast_int = 1'b0;
    m_axis_tuser_int = 1'b0;

    s_axis_tready_next = 1'b0;

    case (state_reg)
        STATE_IDLE: begin
            // idle state
            s_axis_tready_next = m_axis_tready_int_early || !temp_tvalid_reg;

            // output final word
            m_axis_tdata_int = temp_tdata_reg;
            m_axis_tvalid_int = temp_tvalid_reg;
            m_axis_tlast_int = temp_tvalid_reg;
            temp_tvalid_next = temp_tvalid_reg && !m_axis_tready_int_reg;

            if (s_axis.tready && s_axis.tvalid) begin
                // valid input data
                // skip any leading zeros
                if (s_axis.tdata != 8'd0) begin
                    // store count value and zero suppress
                    count_next = s_axis.tdata-1;
                    suppress_zero_next = (s_axis.tdata == 8'd255);
                    s_axis_tready_next = m_axis_tready_int_early;
                    if (s_axis.tdata == 8'd1) begin
                        // next byte will be count value
                        state_next = STATE_NEXT_SEGMENT;
                    end else begin
                        // next byte will be data
                        state_next = STATE_SEGMENT;
                    end
                end else begin
                    state_next = STATE_IDLE;
                end
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_SEGMENT: begin
            // receive segment
            s_axis_tready_next = m_axis_tready_int_early;

            if (s_axis.tready && s_axis.tvalid) begin
                // valid input data
                // store in temp register
                temp_tdata_next = s_axis.tdata;
                temp_tvalid_next = 1'b1;
                // move temp to output
                m_axis_tdata_int = temp_tdata_reg;
                m_axis_tvalid_int = temp_tvalid_reg;
                // decrement count
                count_next = count_reg - 1;
                if (s_axis.tdata == 8'd0) begin
                    // got a zero byte in a frame - mark it as an error and re-sync
                    temp_tvalid_next = 1'b0;
                    m_axis_tvalid_int = 1'b1;
                    m_axis_tuser_int = 1'b1;
                    m_axis_tlast_int = 1'b1;
                    s_axis_tready_next = 1'b1;
                    state_next = STATE_IDLE;
                end else if (s_axis.LAST_EN && s_axis.tlast) begin
                    // end of frame
                    if (count_reg == 8'd1 && (!s_axis.USER_EN || !s_axis.tuser)) begin
                        // end of frame indication at correct time, go to idle to output final byte
                        state_next = STATE_IDLE;
                    end else begin
                        // end of frame indication at invalid time or tuser assert, so mark as an error and re-sync
                        temp_tvalid_next = 1'b0;
                        m_axis_tvalid_int = 1'b1;
                        m_axis_tuser_int = 1'b1;
                        m_axis_tlast_int = 1'b1;
                        s_axis_tready_next = 1'b1;
                        state_next = STATE_IDLE;
                    end
                end else if (count_reg == 8'd1) begin
                    // next byte will be count value
                    state_next = STATE_NEXT_SEGMENT;
                end else begin
                    // next byte will be data
                    state_next = STATE_SEGMENT;
                end
            end else begin
                state_next = STATE_SEGMENT;
            end
        end
        STATE_NEXT_SEGMENT: begin
            // next segment
            s_axis_tready_next = m_axis_tready_int_early;

            if (s_axis.tready && s_axis.tvalid) begin
                // valid input data
                // store zero in temp if not suppressed
                temp_tdata_next = 8'd0;
                temp_tvalid_next = !suppress_zero_reg;
                // move temp to output
                m_axis_tdata_int = temp_tdata_reg;
                m_axis_tvalid_int = temp_tvalid_reg;
                if (s_axis.tdata == 8'd0) begin
                    // got a zero byte delineating the end of the frame, so mark as such and re-sync
                    temp_tvalid_next = 1'b0;
                    m_axis_tuser_int = s_axis.tuser;
                    m_axis_tlast_int = 1'b1;
                    s_axis_tready_next = 1'b1;
                    state_next = STATE_IDLE;
                end else if (s_axis.LAST_EN && s_axis.tlast) begin
                    if (s_axis.tdata == 8'd1 && (!s_axis.USER_EN || !s_axis.tuser)) begin
                        // end of frame indication at correct time, go to idle to output final byte
                        state_next = STATE_IDLE;
                    end else begin
                        // end of frame indication at invalid time or tuser assert, so mark as an error and re-sync
                        temp_tvalid_next = 1'b0;
                        m_axis_tvalid_int = 1'b1;
                        m_axis_tuser_int = 1'b1;
                        m_axis_tlast_int = 1'b1;
                        s_axis_tready_next = 1'b1;
                        state_next = STATE_IDLE;
                    end
                end else begin
                    // otherwise, store count value and zero suppress
                    count_next = s_axis.tdata-1;
                    suppress_zero_next = (s_axis.tdata == 8'd255);
                    s_axis_tready_next = m_axis_tready_int_early;
                    if (s_axis.tdata == 8'd1) begin
                        // next byte will be count value
                        state_next = STATE_NEXT_SEGMENT;
                    end else begin
                        // next byte will be data
                        state_next = STATE_SEGMENT;
                    end
                end
            end else begin
                state_next = STATE_NEXT_SEGMENT;
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

    count_reg <= count_next;
    suppress_zero_reg <= suppress_zero_next;

    temp_tdata_reg <= temp_tdata_next;
    temp_tvalid_reg <= temp_tvalid_next;

    s_axis_tready_reg <= s_axis_tready_next;

    if (rst) begin
        state_reg <= STATE_IDLE;
        temp_tvalid_reg <= 1'b0;
        s_axis_tready_reg <= 1'b0;
    end
end

// output datapath logic
logic [7:0] m_axis_tdata_reg = 8'd0;
logic       m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
logic       m_axis_tlast_reg = 1'b0;
logic       m_axis_tuser_reg = 1'b0;

logic [7:0] temp_m_axis_tdata_reg = 8'd0;
logic       temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
logic       temp_m_axis_tlast_reg = 1'b0;
logic       temp_m_axis_tuser_reg = 1'b0;

// datapath control
logic store_axis_int_to_output;
logic store_axis_int_to_temp;
logic store_axis_temp_to_output;

assign m_axis.tdata = m_axis_tdata_reg;
assign m_axis.tkeep = 1'b1;
assign m_axis.tstrb = m_axis.tkeep;
assign m_axis.tvalid = m_axis_tvalid_reg;
assign m_axis.tlast = m_axis_tlast_reg;
assign m_axis.tid = '0;
assign m_axis.tdest = '0;
assign m_axis.tuser = m_axis_tuser_reg;

// enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
assign m_axis_tready_int_early = m_axis.tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !m_axis_tvalid_int));

always_comb begin
    // transfer sink ready state to source
    m_axis_tvalid_next = m_axis_tvalid_reg;
    temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_axis_temp_to_output = 1'b0;

    if (m_axis_tready_int_reg) begin
        // input is ready
        if (m_axis.tready || !m_axis_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_axis_tvalid_next = m_axis_tvalid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_axis_tvalid_next = m_axis_tvalid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_axis.tready) begin
        // input is not ready, but output is ready
        m_axis_tvalid_next = temp_m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = 1'b0;
        store_axis_temp_to_output = 1'b1;
    end
end

always_ff @(posedge clk) begin
    m_axis_tvalid_reg <= m_axis_tvalid_next;
    m_axis_tready_int_reg <= m_axis_tready_int_early;
    temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;

    // datapath
    if (store_axis_int_to_output) begin
        m_axis_tdata_reg <= m_axis_tdata_int;
        m_axis_tlast_reg <= m_axis_tlast_int;
        m_axis_tuser_reg <= m_axis_tuser_int;
    end else if (store_axis_temp_to_output) begin
        m_axis_tdata_reg <= temp_m_axis_tdata_reg;
        m_axis_tlast_reg <= temp_m_axis_tlast_reg;
        m_axis_tuser_reg <= temp_m_axis_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
        temp_m_axis_tdata_reg <= m_axis_tdata_int;
        temp_m_axis_tlast_reg <= m_axis_tlast_int;
        temp_m_axis_tuser_reg <= m_axis_tuser_int;
    end

    if (rst) begin
        m_axis_tvalid_reg <= 1'b0;
        m_axis_tready_int_reg <= 1'b0;
        temp_m_axis_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall
