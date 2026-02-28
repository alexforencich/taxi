// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2023-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * I2C single register
 */
module taxi_i2c_single_reg #(
    parameter FILTER_LEN = 4,
    parameter logic [6:0] DEV_ADDR = 7'h70
)
(
    input  wire logic        clk,
    input  wire logic        rst,

    /*
     * I2C interface
     */
    input  wire logic        scl_i,
    output wire logic        scl_o,
    input  wire logic        sda_i,
    output wire logic        sda_o,

    /*
     * Data register
     */
    input  wire logic [7:0]  data_in = '0,
    input  wire logic        data_latch = '0,
    output wire logic [7:0]  data_out
);

typedef enum logic [2:0] {
    STATE_IDLE,
    STATE_ADDRESS,
    STATE_ACK,
    STATE_WRITE_1,
    STATE_WRITE_2,
    STATE_READ_1,
    STATE_READ_2,
    STATE_READ_3
} state_t;

state_t state_reg = STATE_IDLE;

logic [7:0] data_reg = '0;
logic [7:0] shift_reg = '0;

logic mode_read_reg = 1'b0;

logic [3:0] bit_count_reg = '0;

logic [FILTER_LEN-1:0] scl_i_filter_reg = '1;
logic [FILTER_LEN-1:0] sda_i_filter_reg = '1;

logic scl_i_reg = 1'b1;
logic sda_i_reg = 1'b1;

logic sda_o_reg = 1'b1;

logic last_scl_i_reg = 1'b1;
logic last_sda_i_reg = 1'b1;

assign scl_o = 1'b1;
assign sda_o = sda_o_reg;

assign data_out = data_reg;

wire scl_posedge = scl_i_reg && !last_scl_i_reg;
wire scl_negedge = !scl_i_reg && last_scl_i_reg;
wire sda_posedge = sda_i_reg && !last_sda_i_reg;
wire sda_negedge = !sda_i_reg && last_sda_i_reg;

wire start_bit = sda_negedge && scl_i_reg;
wire stop_bit = sda_posedge && scl_i_reg;

always_ff @(posedge clk) begin

    if (start_bit) begin
        sda_o_reg <= 1'b1;

        bit_count_reg <= 4'd7;
        state_reg <= STATE_ADDRESS;
    end else if (stop_bit) begin
        sda_o_reg <= 1'b1;

        state_reg <= STATE_IDLE;
    end else begin
        case (state_reg)
            STATE_IDLE: begin
                // line idle
                sda_o_reg <= 1'b1;

                state_reg <= STATE_IDLE;
            end
            STATE_ADDRESS: begin
                // read address
                sda_o_reg <= 1'b1;

                if (scl_posedge) begin
                    if (bit_count_reg > 0) begin
                        // shift in address
                        bit_count_reg <= bit_count_reg-1;
                        shift_reg <= {shift_reg[6:0], sda_i_reg};
                        state_reg <= STATE_ADDRESS;
                    end else begin
                        // check address
                        mode_read_reg <= sda_i_reg;
                        if (shift_reg[6:0] == DEV_ADDR) begin
                            // it's a match, send ACK
                            state_reg <= STATE_ACK;
                        end else begin
                            // no match, return to idle
                            state_reg <= STATE_IDLE;
                        end
                    end
                end else begin
                    state_reg <= STATE_ADDRESS;
                end
            end
            STATE_ACK: begin
                // send ACK bit
                if (scl_negedge) begin
                    sda_o_reg <= 1'b0;
                    bit_count_reg <= 4'd7;
                    if (mode_read_reg) begin
                        // reading
                        shift_reg <= data_reg;
                        state_reg <= STATE_READ_1;
                    end else begin
                        // writing
                        state_reg <= STATE_WRITE_1;
                    end
                end else begin
                    state_reg <= STATE_ACK;
                end
            end
            STATE_WRITE_1: begin
                // write data byte
                if (scl_negedge) begin
                    sda_o_reg <= 1'b1;
                    state_reg <= STATE_WRITE_2;
                end else begin
                    state_reg <= STATE_WRITE_1;
                end
            end
            STATE_WRITE_2: begin
                // write data byte
                sda_o_reg <= 1'b1;
                if (scl_posedge) begin
                    // shift in data bit
                    shift_reg <= {shift_reg[6:0], sda_i_reg};
                    if (bit_count_reg > 0) begin
                        bit_count_reg <= bit_count_reg-1;
                        state_reg <= STATE_WRITE_2;
                    end else begin
                        data_reg <= {shift_reg[6:0], sda_i_reg};
                        state_reg <= STATE_ACK;
                    end
                end else begin
                    state_reg <= STATE_WRITE_2;
                end
            end
            STATE_READ_1: begin
                // read data byte
                if (scl_negedge) begin
                    // shift out data bit
                    {sda_o_reg, shift_reg} <= {shift_reg, sda_i_reg};

                    if (bit_count_reg > 0) begin
                        bit_count_reg <= bit_count_reg-1;
                        state_reg <= STATE_READ_1;
                    end else begin
                        state_reg <= STATE_READ_2;
                    end
                end else begin
                    state_reg <= STATE_READ_1;
                end
            end
            STATE_READ_2: begin
                // read ACK bit
                if (scl_negedge) begin
                    // release SDA
                    sda_o_reg <= 1'b1;
                    state_reg <= STATE_READ_3;
                end else begin
                    state_reg <= STATE_READ_2;
                end
            end
            STATE_READ_3: begin
                // read ACK bit
                if (scl_posedge) begin
                    if (sda_i_reg) begin
                        // NACK, return to idle
                        state_reg <= STATE_IDLE;
                    end else begin
                        // ACK, read another byte
                        bit_count_reg <= 4'd7;
                        shift_reg <= data_reg;
                        state_reg <= STATE_READ_1;
                    end
                end else begin
                    state_reg <= STATE_READ_3;
                end
            end
        endcase
    end

    if (data_latch) begin
        data_reg <= data_in;
    end

    scl_i_filter_reg <= {scl_i_filter_reg[FILTER_LEN-2:0], scl_i};
    sda_i_filter_reg <= {sda_i_filter_reg[FILTER_LEN-2:0], sda_i};

    if (scl_i_filter_reg == '1) begin
        scl_i_reg <= 1'b1;
    end else if (scl_i_filter_reg == '0) begin
        scl_i_reg <= 1'b0;
    end

    if (sda_i_filter_reg == '1) begin
        sda_i_reg <= 1'b1;
    end else if (sda_i_filter_reg == '0) begin
        sda_i_reg <= 1'b0;
    end

    last_scl_i_reg <= scl_i_reg;
    last_sda_i_reg <= sda_i_reg;

    if (rst) begin
        state_reg <= STATE_IDLE;
        data_reg <= 8'd0;
        sda_o_reg <= 1'b1;
    end
end

endmodule

`resetall
