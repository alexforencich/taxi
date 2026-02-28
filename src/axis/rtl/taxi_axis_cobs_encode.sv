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
 * AXI4-Stream consistent overhead byte stuffing (COBS) encoder
 */
module taxi_axis_cobs_encode #
(
    // append zero for in band framing
    parameter logic APPEND_ZERO = 1'b1
)
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
    INPUT_STATE_IDLE,
    INPUT_STATE_SEGMENT,
    INPUT_STATE_FINAL_ZERO,
    INPUT_STATE_APPEND_ZERO
} input_state_t;

input_state_t input_state_reg = INPUT_STATE_IDLE, input_state_next;

typedef enum logic [0:0] {
    OUTPUT_STATE_IDLE,
    OUTPUT_STATE_SEGMENT
} output_state_t;

output_state_t output_state_reg = OUTPUT_STATE_IDLE, output_state_next;

logic [7:0] input_count_reg = 8'd0, input_count_next;
logic [7:0] output_count_reg = 8'd0, output_count_next;
logic fail_frame_reg = 1'b0, fail_frame_next;

// internal datapath
logic [7:0] m_axis_tdata_int;
logic       m_axis_tvalid_int;
logic       m_axis_tready_int_reg = 1'b0;
logic       m_axis_tlast_int;
logic       m_axis_tuser_int;
wire        m_axis_tready_int_early;

logic s_axis_tready_mask;

taxi_axis_if #(.DATA_W(8), .USER_EN(1), .USER_W(1)) code_fifo_in(), code_fifo_out();
taxi_axis_if #(.DATA_W(8)) data_fifo_in(), data_fifo_out();

assign s_axis.tready = code_fifo_in.tready && data_fifo_in.tready && s_axis_tready_mask;

taxi_axis_fifo #(
    .DEPTH(256),
    .FRAME_FIFO(0)
)
code_fifo_inst (
    .clk(clk),
    .rst(rst),

    /*
     * AXI4-Stream input (sink)
     */
    .s_axis(code_fifo_in),

    /*
     * AXI4-Stream output (source)
     */
    .m_axis(code_fifo_out),

    /*
     * Pause
     */
    .pause_req(),
    .pause_ack(),

    /*
     * Status
     */
    .status_depth(),
    .status_depth_commit(),
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);

taxi_axis_fifo #(
    .DEPTH(256),
    .FRAME_FIFO(0)
)
data_fifo_inst (
    .clk(clk),
    .rst(rst),

    /*
     * AXI4-Stream input (sink)
     */
    .s_axis(data_fifo_in),

    /*
     * AXI4-Stream output (source)
     */
    .m_axis(data_fifo_out),

    /*
     * Pause
     */
    .pause_req(),
    .pause_ack(),

    /*
     * Status
     */
    .status_depth(),
    .status_depth_commit(),
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);

always_comb begin
    input_state_next = INPUT_STATE_IDLE;

    input_count_next = input_count_reg;

    fail_frame_next = fail_frame_reg;

    s_axis_tready_mask = 1'b0;

    code_fifo_in.tdata = 8'd0;
    code_fifo_in.tvalid = 1'b0;
    code_fifo_in.tlast = 1'b0;
    code_fifo_in.tuser = 1'b0;

    data_fifo_in.tdata = s_axis.tdata;
    data_fifo_in.tvalid = 1'b0;
    data_fifo_in.tlast = 1'b0;
    data_fifo_in.tuser = 1'b0;

    case (input_state_reg)
        INPUT_STATE_IDLE: begin
            // idle state
            s_axis_tready_mask = 1'b1;
            fail_frame_next = 1'b0;

            if (s_axis.tready && s_axis.tvalid) begin
                // valid input data

                if (s_axis.tdata == 8'd0 || (s_axis.tlast && s_axis.tuser)) begin
                    // got a zero or propagated error, so store a zero code
                    code_fifo_in.tdata = 8'd1;
                    code_fifo_in.tvalid = 1'b1;
                    if (s_axis.tlast) begin
                        // last byte, so close out the frame
                        fail_frame_next = s_axis.tuser;
                        input_state_next = INPUT_STATE_FINAL_ZERO;
                    end else begin
                        // return to idle to await next segment
                        input_state_next = INPUT_STATE_IDLE;
                    end
                end else begin
                    // got something other than a zero, so store it and init the segment counter
                    input_count_next = 8'd2;
                    data_fifo_in.tdata = s_axis.tdata;
                    data_fifo_in.tvalid = 1'b1;
                    if (s_axis.tlast) begin
                        // last byte, so store the code and close out the frame
                        code_fifo_in.tdata = 8'd2;
                        code_fifo_in.tvalid = 1'b1;
                        if (APPEND_ZERO) begin
                            // zero frame mode, need to add a zero code to end the frame
                            input_state_next = INPUT_STATE_APPEND_ZERO;
                        end else begin
                            // normal frame mode, close out the frame
                            data_fifo_in.tlast = 1'b1;
                            input_state_next = INPUT_STATE_IDLE;
                        end
                    end else begin
                        // await more segment data
                        input_state_next = INPUT_STATE_SEGMENT;
                    end
                end
            end else begin
                input_state_next = INPUT_STATE_IDLE;
            end
        end
        INPUT_STATE_SEGMENT: begin
            // encode segment
            s_axis_tready_mask = 1'b1;
            fail_frame_next = 1'b0;

            if (s_axis.tready && s_axis.tvalid) begin
                // valid input data

                if (s_axis.tdata == 8'd0 || (s_axis.tlast && s_axis.tuser)) begin
                    // got a zero or propagated error, so store the code
                    code_fifo_in.tdata = input_count_reg;
                    code_fifo_in.tvalid = 1'b1;
                    if (s_axis.tlast) begin
                        // last byte, so close out the frame
                        fail_frame_next = s_axis.tuser;
                        input_state_next = INPUT_STATE_FINAL_ZERO;
                    end else begin
                        // return to idle to await next segment
                        input_state_next = INPUT_STATE_IDLE;
                    end
                end else begin
                    // got something other than a zero, so store it and increment the segment counter
                    input_count_next = input_count_reg+1;
                    data_fifo_in.tdata = s_axis.tdata;
                    data_fifo_in.tvalid = 1'b1;
                    if (input_count_reg == 8'd254) begin
                        // 254 bytes in frame, so dump and reset counter
                        code_fifo_in.tdata = input_count_reg+1;
                        code_fifo_in.tvalid = 1'b1;
                        input_count_next = 8'd1;
                    end
                    if (s_axis.tlast) begin
                        // last byte, so store the code and close out the frame
                        code_fifo_in.tdata = input_count_reg+1;
                        code_fifo_in.tvalid = 1'b1;
                        if (APPEND_ZERO) begin
                            // zero frame mode, need to add a zero code to end the frame
                            input_state_next = INPUT_STATE_APPEND_ZERO;
                        end else begin
                            // normal frame mode, close out the frame
                            data_fifo_in.tlast = 1'b1;
                            input_state_next = INPUT_STATE_IDLE;
                        end
                    end else begin
                        // await more segment data
                        input_state_next = INPUT_STATE_SEGMENT;
                    end
                end
            end else begin
                input_state_next = INPUT_STATE_SEGMENT;
            end
        end
        INPUT_STATE_FINAL_ZERO: begin
            // final zero code required
            s_axis_tready_mask = 1'b0;

            if (code_fifo_in.tready) begin
                // push a zero code and close out frame
                if (fail_frame_reg) begin
                    code_fifo_in.tdata = 8'd2;
                    code_fifo_in.tuser = 1'b1;
                end else begin
                    code_fifo_in.tdata = 8'd1;
                end
                code_fifo_in.tvalid = 1'b1;
                if (APPEND_ZERO) begin
                    // zero frame mode, need to add a zero code to end the frame
                    input_state_next = INPUT_STATE_APPEND_ZERO;
                end else begin
                    // normal frame mode, close out the frame
                    code_fifo_in.tlast = 1'b1;
                    fail_frame_next = 1'b0;
                    input_state_next = INPUT_STATE_IDLE;
                end
            end else begin
                input_state_next = INPUT_STATE_FINAL_ZERO;
            end
        end
        INPUT_STATE_APPEND_ZERO: begin
            // append zero for zero framing
            s_axis_tready_mask = 1'b0;

            if (code_fifo_in.tready) begin
                // push frame termination code and close out frame
                code_fifo_in.tdata = 8'd0;
                code_fifo_in.tlast = 1'b1;
                code_fifo_in.tuser = fail_frame_reg;
                code_fifo_in.tvalid = 1'b1;
                fail_frame_next = 1'b0;
                input_state_next = INPUT_STATE_IDLE;
            end else begin
                input_state_next = INPUT_STATE_APPEND_ZERO;
            end
        end
    endcase
end

always_comb begin
    output_state_next = OUTPUT_STATE_IDLE;

    output_count_next = output_count_reg;

    m_axis_tdata_int = 8'd0;
    m_axis_tvalid_int = 1'b0;
    m_axis_tlast_int = 1'b0;
    m_axis_tuser_int = 1'b0;

    code_fifo_out.tready = 1'b0;

    data_fifo_out.tready = 1'b0;

    case (output_state_reg)
        OUTPUT_STATE_IDLE: begin
            // idle state

            if (m_axis_tready_int_reg && code_fifo_out.tvalid) begin
                // transfer out code byte and load counter
                m_axis_tdata_int = code_fifo_out.tdata;
                m_axis_tlast_int = code_fifo_out.tlast;
                m_axis_tuser_int = code_fifo_out.tuser && code_fifo_out.tlast;
                output_count_next = code_fifo_out.tdata-1;
                m_axis_tvalid_int = 1'b1;
                code_fifo_out.tready = 1'b1;
                if (code_fifo_out.tdata == 8'd0 || code_fifo_out.tdata == 8'd1 || code_fifo_out.tuser) begin
                    // frame termination and zero codes will be followed by codes
                    output_state_next = OUTPUT_STATE_IDLE;
                end else begin
                    // transfer out data
                    output_state_next = OUTPUT_STATE_SEGMENT;
                end
            end else begin
                output_state_next = OUTPUT_STATE_IDLE;
            end
        end
        OUTPUT_STATE_SEGMENT: begin
            // segment output

            if (m_axis_tready_int_reg && data_fifo_out.tvalid) begin
                // transfer out data byte and decrement counter
                m_axis_tdata_int = data_fifo_out.tdata;
                m_axis_tlast_int = data_fifo_out.tlast;
                output_count_next = output_count_reg - 1;
                m_axis_tvalid_int = 1'b1;
                data_fifo_out.tready = 1'b1;
                if (output_count_reg == 1) begin
                    // done with segment, get a code byte next
                    output_state_next = OUTPUT_STATE_IDLE;
                end else begin
                    // more data to transfer
                    output_state_next = OUTPUT_STATE_SEGMENT;
                end
            end else begin
                output_state_next = OUTPUT_STATE_SEGMENT;
            end
        end
    endcase
end

always_ff @(posedge clk) begin
    input_state_reg <= input_state_next;
    output_state_reg <= output_state_next;

    input_count_reg <= input_count_next;
    output_count_reg <= output_count_next;
    fail_frame_reg <= fail_frame_next;

    if (rst) begin
        input_state_reg <= INPUT_STATE_IDLE;
        output_state_reg <= OUTPUT_STATE_IDLE;
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
