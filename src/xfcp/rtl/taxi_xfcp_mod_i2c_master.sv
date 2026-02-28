// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2017-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * XFCP I2C master module
 */
module taxi_xfcp_mod_i2c_master #
(
    parameter logic [15:0] XFCP_ID_TYPE = 16'h2C00,
    parameter XFCP_ID_STR = "I2C Master",
    parameter logic [8*16-1:0] XFCP_EXT_ID = 0,
    parameter XFCP_EXT_ID_STR = "",
    parameter logic [15:0] DEFAULT_PRESCALE = 16'(125000000/400000/4)
)
(
    input  wire logic  clk,
    input  wire logic  rst,

    /*
     * XFCP upstream port
     */
    taxi_axis_if.snk   xfcp_usp_ds,
    taxi_axis_if.src   xfcp_usp_us,

    /*
     * I2C interface
     */
    input  wire logic  i2c_scl_i,
    output wire logic  i2c_scl_o,
    input  wire logic  i2c_sda_i,
    output wire logic  i2c_sda_o
);

localparam START_TAG = 8'hFF;
localparam RPATH_TAG = 8'hFE;
localparam I2C_REQ = 8'h2C;
localparam I2C_RESP = 8'h2D;
localparam ID_REQ = 8'hFE;
localparam ID_RESP = 8'hFF;

// ID ROM
localparam ID_PTR_W = (XFCP_EXT_ID != 0 || XFCP_EXT_ID_STR != 0) ? 6 : 5;
localparam ID_ROM_SIZE = 2**ID_PTR_W;
logic [7:0] id_rom[ID_ROM_SIZE];

logic [ID_PTR_W-1:0] id_ptr_reg = '0, id_ptr_next;

integer j;

initial begin
    // init ID ROM
    for (integer i = 0; i < ID_ROM_SIZE; i = i + 1) begin
        id_rom[i] = 0;
    end

    // binary part
    {id_rom[1], id_rom[0]} = 16'h2C00 | (16'h00FF & XFCP_ID_TYPE); // module type

    // string part
    // find string length
    j = 0;
    for (integer i = 1; i <= 16; i = i + 1) begin
        if (j == i-1 && (XFCP_ID_STR >> (i*8)) > 0) begin
            j = i;
        end
    end

    // pack string
    for (integer i = 0; i <= j; i = i + 1) begin
        id_rom[i+16] = XFCP_ID_STR[8*(j-i) +: 8];
    end

    if (XFCP_EXT_ID != 0 || XFCP_EXT_ID_STR != 0) begin
        // extended ID

        // binary part
        for (integer i = 0; i < 16; i = i + 1) begin
            id_rom[i+32] = XFCP_EXT_ID[8*i +: 8];
        end

        // string part
        // find string length
        j = 0;
        for (integer i = 1; i <= 16; i = i + 1) begin
            if (j == i-1 && (XFCP_EXT_ID_STR >> (i*8)) > 0) begin
                j = i;
            end
        end

        // pack string
        for (integer i = 0; i <= j; i = i + 1) begin
            id_rom[i+48] = XFCP_EXT_ID_STR[8*(j-i) +: 8];
        end
    end
end

typedef enum logic [3:0] {
    STATE_IDLE,
    STATE_HEADER_1,
    STATE_HEADER_2,
    STATE_PROCESS,
    STATE_STATUS,
    STATE_PRESCALE_L,
    STATE_PRESCALE_H,
    STATE_COUNT,
    STATE_NEXT_CMD,
    STATE_WRITE_DATA,
    STATE_READ_DATA,
    STATE_WAIT_LAST,
    STATE_ID
} state_t;

state_t state_reg = STATE_IDLE, state_next;

logic [7:0] count_reg = 8'd0, count_next;

logic last_cycle_reg = 1'b0;

logic [6:0] i2c_cmd_address_reg = 7'd0, i2c_cmd_address_next;
logic i2c_cmd_start_reg = 1'b0, i2c_cmd_start_next;
logic i2c_cmd_read_reg = 1'b0, i2c_cmd_read_next;
logic i2c_cmd_write_reg = 1'b0, i2c_cmd_write_next;
logic i2c_cmd_write_multi_reg = 1'b0, i2c_cmd_write_multi_next;
logic i2c_cmd_stop_reg = 1'b0, i2c_cmd_stop_next;
logic i2c_cmd_valid_reg = 1'b0, i2c_cmd_valid_next;

logic cmd_txn_stop_reg = 1'b0, cmd_txn_stop_next;

logic [7:0] i2c_wr_data_reg = 8'd0, i2c_wr_data_next;
logic i2c_wr_data_valid_reg = 1'b0, i2c_wr_data_valid_next;
logic i2c_wr_data_last_reg = 1'b0, i2c_wr_data_last_next;

logic i2c_rd_data_ready_reg = 1'b0, i2c_rd_data_ready_next;

logic [15:0] prescale_reg = DEFAULT_PRESCALE, prescale_next;
logic stop_on_idle_reg = 1'b0, stop_on_idle_next;

logic missed_ack_reg = 1'b0, missed_ack_next;

logic xfcp_usp_ds_tready_reg = 1'b0, xfcp_usp_ds_tready_next;

// internal datapath
logic [7:0]  xfcp_usp_us_tdata_int;
logic        xfcp_usp_us_tvalid_int;
logic        xfcp_usp_us_tready_int_reg = 1'b0;
logic        xfcp_usp_us_tlast_int;
logic        xfcp_usp_us_tuser_int;
wire         xfcp_usp_us_tready_int_early;

taxi_axis_if #(.DATA_W(12), .KEEP_W(1)) i2c_cmd();
taxi_axis_if #(.DATA_W(8)) i2c_rd_data(), i2c_wr_data();

assign i2c_cmd.tdata[6:0] = i2c_cmd_address_reg;
assign i2c_cmd.tdata[7] = i2c_cmd_start_reg;
assign i2c_cmd.tdata[8] = i2c_cmd_read_reg;
assign i2c_cmd.tdata[9] = i2c_cmd_write_reg;
assign i2c_cmd.tdata[10] = i2c_cmd_write_multi_reg;
assign i2c_cmd.tdata[11] = i2c_cmd_stop_reg;
assign i2c_cmd.tvalid = i2c_cmd_valid_reg;

assign i2c_wr_data.tdata = i2c_wr_data_reg;
assign i2c_wr_data.tvalid = i2c_wr_data_valid_reg;
assign i2c_wr_data.tlast = i2c_wr_data_last_reg;

assign i2c_rd_data.tready = i2c_rd_data_ready_reg;

wire busy;
wire bus_control;
wire bus_active;
wire missed_ack;

assign xfcp_usp_ds.tready = xfcp_usp_ds_tready_reg;

always_comb begin
    state_next = STATE_IDLE;

    count_next = count_reg;

    id_ptr_next = id_ptr_reg;

    i2c_cmd_address_next = i2c_cmd_address_reg;
    i2c_cmd_start_next = i2c_cmd_start_reg;
    i2c_cmd_read_next = i2c_cmd_read_reg;
    i2c_cmd_write_next = i2c_cmd_write_reg;
    i2c_cmd_write_multi_next = i2c_cmd_write_multi_reg;
    i2c_cmd_stop_next = i2c_cmd_stop_reg;
    i2c_cmd_valid_next = i2c_cmd_valid_reg && !i2c_cmd.tready;

    cmd_txn_stop_next = cmd_txn_stop_reg;

    i2c_wr_data_next = i2c_wr_data_reg;
    i2c_wr_data_valid_next = i2c_wr_data_valid_reg && !i2c_wr_data.tready;
    i2c_wr_data_last_next = i2c_wr_data_last_reg;

    i2c_rd_data_ready_next = 1'b0;

    prescale_next = prescale_reg;
    stop_on_idle_next = stop_on_idle_reg;

    missed_ack_next = missed_ack_reg || missed_ack;

    xfcp_usp_ds_tready_next = 1'b0;

    xfcp_usp_us_tdata_int = 8'd0;
    xfcp_usp_us_tvalid_int = 1'b0;
    xfcp_usp_us_tlast_int = 1'b0;
    xfcp_usp_us_tuser_int = 1'b0;

    case (state_reg)
        STATE_IDLE: begin
            // idle, wait for start of packet
            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
            id_ptr_next = '0;

            if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                if (xfcp_usp_ds.tlast) begin
                    // last asserted, ignore cycle
                    state_next = STATE_IDLE;
                end else if (xfcp_usp_ds.tdata == RPATH_TAG) begin
                    // need to pass through rpath
                    xfcp_usp_us_tdata_int = xfcp_usp_ds.tdata;
                    xfcp_usp_us_tvalid_int = 1'b1;
                    xfcp_usp_us_tlast_int = 1'b0;
                    xfcp_usp_us_tuser_int = 1'b0;
                    state_next = STATE_HEADER_1;
                end else if (xfcp_usp_ds.tdata == START_TAG) begin
                    // process header
                    xfcp_usp_us_tdata_int = xfcp_usp_ds.tdata;
                    xfcp_usp_us_tvalid_int = 1'b1;
                    xfcp_usp_us_tlast_int = 1'b0;
                    xfcp_usp_us_tuser_int = 1'b0;
                    state_next = STATE_HEADER_2;
                end else begin
                    // bad start byte, drop packet
                    state_next = STATE_WAIT_LAST;
                end
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_HEADER_1: begin
            // transfer through header
            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;

            if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                // transfer through
                xfcp_usp_us_tdata_int = xfcp_usp_ds.tdata;
                xfcp_usp_us_tvalid_int = 1'b1;
                xfcp_usp_us_tlast_int = 1'b0;
                xfcp_usp_us_tuser_int = 1'b0;

                if (xfcp_usp_ds.tlast) begin
                    // last asserted in header, mark as such and drop
                    xfcp_usp_us_tuser_int = 1'b1;
                    state_next = STATE_IDLE;
                end else if (xfcp_usp_ds.tdata == START_TAG) begin
                    // process header
                    state_next = STATE_HEADER_2;
                end else begin
                    state_next = STATE_HEADER_1;
                end
            end else begin
                state_next = STATE_HEADER_1;
            end
        end
        STATE_HEADER_2: begin
            // read packet type
            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;

            if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                if (xfcp_usp_ds.tdata == I2C_REQ && !xfcp_usp_ds.tlast) begin
                    // start of read
                    xfcp_usp_us_tdata_int = I2C_RESP;
                    xfcp_usp_us_tvalid_int = 1'b1;
                    xfcp_usp_us_tlast_int = 1'b0;
                    xfcp_usp_us_tuser_int = 1'b0;
                    state_next = STATE_PROCESS;
                end else if (xfcp_usp_ds.tdata == ID_REQ) begin
                    // identify
                    xfcp_usp_us_tdata_int = ID_RESP;
                    xfcp_usp_us_tvalid_int = 1'b1;
                    xfcp_usp_us_tlast_int = 1'b0;
                    xfcp_usp_us_tuser_int = 1'b0;
                    state_next = STATE_ID;
                end else begin
                    // invalid
                    xfcp_usp_us_tvalid_int = 1'b1;
                    xfcp_usp_us_tlast_int = 1'b1;
                    xfcp_usp_us_tuser_int = 1'b1;
                    if (xfcp_usp_ds.tlast) begin
                        state_next = STATE_IDLE;
                    end else begin
                        state_next = STATE_WAIT_LAST;
                    end
                end
            end else begin
                state_next = STATE_HEADER_2;
            end
        end
        STATE_PROCESS: begin
            // process commands
            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early && !i2c_cmd_valid_reg;

            xfcp_usp_us_tdata_int = xfcp_usp_ds.tdata;
            xfcp_usp_us_tvalid_int = xfcp_usp_ds.tready && xfcp_usp_ds.tvalid;
            xfcp_usp_us_tlast_int = xfcp_usp_ds.tlast;
            xfcp_usp_us_tuser_int = 1'b0;

            count_next = 8'd0;

            if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                if (xfcp_usp_ds.tdata[7]) begin
                    // set address
                    i2c_cmd_address_next = xfcp_usp_ds.tdata[6:0];
                    state_next = STATE_PROCESS;
                end else if (xfcp_usp_ds.tdata[6]) begin
                    if (xfcp_usp_ds.tdata[5:0] == 6'b000000) begin
                        // status query
                        xfcp_usp_ds_tready_next = 1'b0;
                        xfcp_usp_us_tlast_int = 1'b0;
                        state_next = STATE_STATUS;
                    end else if (xfcp_usp_ds.tdata[5:0] == 6'b100000) begin
                        // set prescale
                        xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                        state_next = STATE_PRESCALE_L;
                    end else begin
                        // unknown command
                        if (xfcp_usp_ds.tlast) begin
                            // last cycle; return to idle
                            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                            state_next = STATE_IDLE;
                        end else begin
                            state_next = STATE_PROCESS;
                        end
                    end
                end else begin
                    i2c_cmd_start_next = xfcp_usp_ds.tdata[0];
                    i2c_cmd_read_next = xfcp_usp_ds.tdata[1];
                    i2c_cmd_write_next = xfcp_usp_ds.tdata[2];
                    i2c_cmd_stop_next = xfcp_usp_ds.tdata[3];
                    i2c_cmd_valid_next = (i2c_cmd_start_next || i2c_cmd_read_next || i2c_cmd_write_next || i2c_cmd_stop_next);

                    cmd_txn_stop_next = i2c_cmd_stop_next;

                    if (xfcp_usp_ds.tdata[4]) begin
                        i2c_cmd_stop_next = 1'b0;

                        if (xfcp_usp_ds.tlast) begin
                            // last cycle; return to idle
                            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                            state_next = STATE_IDLE;
                        end else begin
                            // read in count value
                            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                            state_next = STATE_COUNT;
                        end
                    end else if (i2c_cmd_write_next && !i2c_cmd_read_next) begin
                        // write
                        if (xfcp_usp_ds.tlast) begin
                            // last cycle; return to idle
                            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                            state_next = STATE_IDLE;
                        end else begin
                            // start writing
                            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early && !i2c_wr_data_valid_reg;
                            state_next = STATE_WRITE_DATA;
                        end
                    end else if (i2c_cmd_read_next && !i2c_cmd_write_next) begin
                        // read
                        xfcp_usp_ds_tready_next = 1'b0;
                        xfcp_usp_us_tlast_int = 1'b0;
                        state_next = STATE_READ_DATA;
                    end else begin
                        // unknown
                        if (xfcp_usp_ds.tlast) begin
                            // last cycle; return to idle
                            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                            state_next = STATE_IDLE;
                        end else begin
                            state_next = STATE_PROCESS;
                        end
                    end
                end
            end else begin
                state_next = STATE_PROCESS;
            end
        end
        STATE_STATUS: begin
            // read status
            xfcp_usp_ds_tready_next = 1'b0;

            xfcp_usp_us_tdata_int = '0;
            xfcp_usp_us_tdata_int[0] = busy;
            xfcp_usp_us_tdata_int[1] = bus_control;
            xfcp_usp_us_tdata_int[2] = bus_active;
            xfcp_usp_us_tdata_int[3] = missed_ack_reg;
            xfcp_usp_us_tvalid_int = 1'b1;
            xfcp_usp_us_tlast_int = last_cycle_reg;
            xfcp_usp_us_tuser_int = 1'b0;

            if (xfcp_usp_us_tready_int_reg) begin
                missed_ack_next = missed_ack;

                if (last_cycle_reg) begin
                    // last cycle; return to idle
                    xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                    state_next = STATE_IDLE;
                end else begin
                    // process next command
                    xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early && !i2c_cmd_valid_reg;
                    state_next = STATE_PROCESS;
                end
            end else begin
                state_next = STATE_STATUS;
            end
        end
        STATE_PRESCALE_L: begin
            // store prescale value
            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;

            xfcp_usp_us_tdata_int = xfcp_usp_ds.tdata;
            xfcp_usp_us_tvalid_int = xfcp_usp_ds.tready && xfcp_usp_ds.tvalid;
            xfcp_usp_us_tlast_int = xfcp_usp_ds.tlast;
            xfcp_usp_us_tuser_int = 1'b0;

            if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                prescale_next[7:0] = xfcp_usp_ds.tdata;

                if (xfcp_usp_ds.tlast) begin
                    // last cycle; return to idle
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_PRESCALE_H;
                end
            end else begin
                state_next = STATE_PRESCALE_L;
            end
        end
        STATE_PRESCALE_H: begin
            // store prescale value
            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;

            xfcp_usp_us_tdata_int = xfcp_usp_ds.tdata;
            xfcp_usp_us_tvalid_int = xfcp_usp_ds.tready && xfcp_usp_ds.tvalid;
            xfcp_usp_us_tlast_int = xfcp_usp_ds.tlast;
            xfcp_usp_us_tuser_int = 1'b0;

            if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                prescale_next[15:8] = xfcp_usp_ds.tdata;

                if (xfcp_usp_ds.tlast) begin
                    // last cycle; return to idle
                    state_next = STATE_IDLE;
                end else begin
                    xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early && !i2c_cmd_valid_reg;
                    state_next = STATE_PROCESS;
                end
            end else begin
                state_next = STATE_PRESCALE_H;
            end
        end
        STATE_COUNT: begin
            // store count value
            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;

            xfcp_usp_us_tdata_int = xfcp_usp_ds.tdata;
            xfcp_usp_us_tvalid_int = xfcp_usp_ds.tready && xfcp_usp_ds.tvalid;
            xfcp_usp_us_tlast_int = xfcp_usp_ds.tlast;
            xfcp_usp_us_tuser_int = 1'b0;

            if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                count_next = xfcp_usp_ds.tdata;

                if (i2c_cmd_write_reg && !i2c_cmd_read_reg) begin
                    // write
                    if (xfcp_usp_ds.tlast) begin
                        // last cycle; return to idle
                        xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                        state_next = STATE_IDLE;
                    end else begin
                        // start writing
                        xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early && !i2c_wr_data_valid_reg;
                        state_next = STATE_WRITE_DATA;
                    end
                end else if (i2c_cmd_read_reg && !i2c_cmd_write_reg) begin
                    // start reading
                    xfcp_usp_ds_tready_next = 1'b0;
                    xfcp_usp_us_tlast_int = 1'b0;
                    state_next = STATE_READ_DATA;
                end else begin
                    // neither, process next command
                    if (xfcp_usp_ds.tlast) begin
                        // last cycle; return to idle
                        xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                        state_next = STATE_IDLE;
                    end else begin
                        xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early && !i2c_cmd_valid_reg;
                        state_next = STATE_PROCESS;
                    end
                end
            end else begin
                state_next = STATE_COUNT;
            end
        end
        STATE_NEXT_CMD: begin
            // next command

            if (~i2c_cmd_valid_reg) begin
                i2c_cmd_start_next = 1'b0;
                i2c_cmd_valid_next = 1'b1;

                count_next = count_reg - 1;

                if (count_reg == 2) begin
                    i2c_cmd_stop_next = cmd_txn_stop_reg;
                end

                if (i2c_cmd_write_reg) begin
                    xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early && !i2c_wr_data_valid_reg;
                    state_next = STATE_WRITE_DATA;
                end else if (i2c_cmd_read_reg) begin
                    xfcp_usp_ds_tready_next = 1'b0;
                    state_next = STATE_READ_DATA;
                end
            end else begin
                state_next = STATE_NEXT_CMD;
            end
        end
        STATE_WRITE_DATA: begin
            // write data
            xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early && !i2c_wr_data_valid_reg;

            xfcp_usp_us_tdata_int = xfcp_usp_ds.tdata;
            xfcp_usp_us_tvalid_int = xfcp_usp_ds.tready && xfcp_usp_ds.tvalid;
            xfcp_usp_us_tlast_int = xfcp_usp_ds.tlast;
            xfcp_usp_us_tuser_int = 1'b0;

            if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                i2c_wr_data_next = xfcp_usp_ds.tdata;
                i2c_wr_data_valid_next = 1'b1;

                if (xfcp_usp_ds.tlast) begin
                    xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                    state_next = STATE_IDLE;
                end else begin
                    if (count_reg > 1) begin
                        xfcp_usp_ds_tready_next = 1'b0;
                        state_next = STATE_NEXT_CMD;
                    end else begin
                        xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early && !i2c_cmd_valid_reg;
                        state_next = STATE_PROCESS;
                    end
                end
            end else begin
                state_next = STATE_WRITE_DATA;
            end
        end
        STATE_READ_DATA: begin
            // read data
            xfcp_usp_ds_tready_next = 1'b0;
            i2c_rd_data_ready_next = xfcp_usp_us_tready_int_early;

            xfcp_usp_us_tdata_int = i2c_rd_data.tdata;
            xfcp_usp_us_tvalid_int = i2c_rd_data.tvalid;
            xfcp_usp_us_tlast_int = last_cycle_reg;
            xfcp_usp_us_tuser_int = 1'b0;

            if (i2c_rd_data_ready_reg && i2c_rd_data.tvalid) begin
                if (count_reg > 1) begin
                    xfcp_usp_us_tlast_int = 1'b0;
                    xfcp_usp_ds_tready_next = 1'b0;
                    state_next = STATE_NEXT_CMD;
                end else begin
                    if (last_cycle_reg) begin
                        xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                        state_next = STATE_IDLE;
                    end else begin
                        xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early && !i2c_cmd_valid_reg;
                        state_next = STATE_PROCESS;
                    end
                end
            end else begin
                state_next = STATE_READ_DATA;
            end
        end
        STATE_ID: begin
            // send ID

            // drop padding
            xfcp_usp_ds_tready_next = !(last_cycle_reg || (xfcp_usp_ds.tvalid && xfcp_usp_ds.tlast));

            xfcp_usp_us_tdata_int = id_rom[id_ptr_reg];
            xfcp_usp_us_tvalid_int = 1'b1;
            xfcp_usp_us_tlast_int = 1'b0;
            xfcp_usp_us_tuser_int = 1'b0;

            if (xfcp_usp_us_tready_int_reg) begin
                id_ptr_next = id_ptr_reg + 1;
                if (id_ptr_reg == ID_ROM_SIZE-1) begin
                    xfcp_usp_us_tlast_int = 1'b1;
                    if (!(last_cycle_reg || (xfcp_usp_ds.tvalid && xfcp_usp_ds.tlast))) begin
                        state_next = STATE_WAIT_LAST;
                    end else begin
                        xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                        state_next = STATE_IDLE;
                    end
                end else begin
                    state_next = STATE_ID;
                end
            end else begin
                state_next = STATE_ID;
            end
        end
        STATE_WAIT_LAST: begin
            // wait for end of frame
            xfcp_usp_ds_tready_next = 1'b1;

            if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                if (xfcp_usp_ds.tlast) begin
                    xfcp_usp_ds_tready_next = xfcp_usp_us_tready_int_early;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_WAIT_LAST;
                end
            end else begin
                state_next = STATE_WAIT_LAST;
            end
        end
        default: begin
            // return to idle
            state_next = STATE_IDLE;
        end
    endcase
end

always_ff @(posedge clk) begin
    state_reg <= state_next;

    id_ptr_reg <= id_ptr_next;

    count_reg <= count_next;

    if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
        last_cycle_reg <= xfcp_usp_ds.tlast;
    end

    i2c_cmd_address_reg <= i2c_cmd_address_next;
    i2c_cmd_start_reg <= i2c_cmd_start_next;
    i2c_cmd_read_reg <= i2c_cmd_read_next;
    i2c_cmd_write_reg <= i2c_cmd_write_next;
    i2c_cmd_write_multi_reg <= i2c_cmd_write_multi_next;
    i2c_cmd_stop_reg <= i2c_cmd_stop_next;
    i2c_cmd_valid_reg <= i2c_cmd_valid_next;

    cmd_txn_stop_reg <= cmd_txn_stop_next;

    i2c_wr_data_reg <= i2c_wr_data_next;
    i2c_wr_data_valid_reg <= i2c_wr_data_valid_next;
    i2c_wr_data_last_reg <= i2c_wr_data_last_next;

    i2c_rd_data_ready_reg <= i2c_rd_data_ready_next;

    prescale_reg <= prescale_next;
    stop_on_idle_reg <= stop_on_idle_next;

    missed_ack_reg <= missed_ack_next;

    xfcp_usp_ds_tready_reg <= xfcp_usp_ds_tready_next;

    if (rst) begin
        state_reg <= STATE_IDLE;
        i2c_cmd_address_reg <= 7'd0;
        i2c_cmd_valid_reg <= 1'b0;
        i2c_wr_data_valid_reg <= 1'b0;
        i2c_rd_data_ready_reg <= 1'b0;
        prescale_reg <= DEFAULT_PRESCALE;
        stop_on_idle_reg <= 1'b0;
        missed_ack_reg <= 1'b0;
        xfcp_usp_ds_tready_reg <= 1'b0;
    end
end

// output datapath logic
logic [7:0]  xfcp_usp_us_tdata_reg = 8'd0;
logic        xfcp_usp_us_tvalid_reg = 1'b0, xfcp_usp_us_tvalid_next;
logic        xfcp_usp_us_tlast_reg = 1'b0;
logic        xfcp_usp_us_tuser_reg = 1'b0;

logic [7:0]  temp_xfcp_usp_us_tdata_reg = 8'd0;
logic        temp_xfcp_usp_us_tvalid_reg = 1'b0, temp_xfcp_usp_us_tvalid_next;
logic        temp_xfcp_usp_us_tlast_reg = 1'b0;
logic        temp_xfcp_usp_us_tuser_reg = 1'b0;

// datapath control
logic store_up_xfcp_int_to_output;
logic store_up_xfcp_int_to_temp;
logic store_up_xfcp_temp_to_output;

assign xfcp_usp_us.tdata = xfcp_usp_us_tdata_reg;
assign xfcp_usp_us.tkeep = '1;
assign xfcp_usp_us.tstrb = xfcp_usp_us.tkeep;
assign xfcp_usp_us.tvalid = xfcp_usp_us_tvalid_reg;
assign xfcp_usp_us.tlast = xfcp_usp_us_tlast_reg;
assign xfcp_usp_us.tid = '0;
assign xfcp_usp_us.tdest = '0;
assign xfcp_usp_us.tuser = xfcp_usp_us_tuser_reg;

// enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
assign xfcp_usp_us_tready_int_early = xfcp_usp_us.tready || (!temp_xfcp_usp_us_tvalid_reg && (!xfcp_usp_us_tvalid_reg || !xfcp_usp_us_tvalid_int));

always_comb begin
    // transfer sink ready state to source
    xfcp_usp_us_tvalid_next = xfcp_usp_us_tvalid_reg;
    temp_xfcp_usp_us_tvalid_next = temp_xfcp_usp_us_tvalid_reg;

    store_up_xfcp_int_to_output = 1'b0;
    store_up_xfcp_int_to_temp = 1'b0;
    store_up_xfcp_temp_to_output = 1'b0;

    if (xfcp_usp_us_tready_int_reg) begin
        // input is ready
        if (xfcp_usp_us.tready || !xfcp_usp_us_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            xfcp_usp_us_tvalid_next = xfcp_usp_us_tvalid_int;
            store_up_xfcp_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_xfcp_usp_us_tvalid_next = xfcp_usp_us_tvalid_int;
            store_up_xfcp_int_to_temp = 1'b1;
        end
    end else if (xfcp_usp_us.tready) begin
        // input is not ready, but output is ready
        xfcp_usp_us_tvalid_next = temp_xfcp_usp_us_tvalid_reg;
        temp_xfcp_usp_us_tvalid_next = 1'b0;
        store_up_xfcp_temp_to_output = 1'b1;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        xfcp_usp_us_tvalid_reg <= 1'b0;
        xfcp_usp_us_tready_int_reg <= 1'b0;
        temp_xfcp_usp_us_tvalid_reg <= 1'b0;
    end else begin
        xfcp_usp_us_tvalid_reg <= xfcp_usp_us_tvalid_next;
        xfcp_usp_us_tready_int_reg <= xfcp_usp_us_tready_int_early;
        temp_xfcp_usp_us_tvalid_reg <= temp_xfcp_usp_us_tvalid_next;
    end

    // datapath
    if (store_up_xfcp_int_to_output) begin
        xfcp_usp_us_tdata_reg <= xfcp_usp_us_tdata_int;
        xfcp_usp_us_tlast_reg <= xfcp_usp_us_tlast_int;
        xfcp_usp_us_tuser_reg <= xfcp_usp_us_tuser_int;
    end else if (store_up_xfcp_temp_to_output) begin
        xfcp_usp_us_tdata_reg <= temp_xfcp_usp_us_tdata_reg;
        xfcp_usp_us_tlast_reg <= temp_xfcp_usp_us_tlast_reg;
        xfcp_usp_us_tuser_reg <= temp_xfcp_usp_us_tuser_reg;
    end

    if (store_up_xfcp_int_to_temp) begin
        temp_xfcp_usp_us_tdata_reg <= xfcp_usp_us_tdata_int;
        temp_xfcp_usp_us_tlast_reg <= xfcp_usp_us_tlast_int;
        temp_xfcp_usp_us_tuser_reg <= xfcp_usp_us_tuser_int;
    end
end

taxi_i2c_master
i2c_master_inst (
    .clk(clk),
    .rst(rst),

    /*
     * Host interface
     */
    .s_axis_cmd(i2c_cmd),
    .s_axis_tx(i2c_wr_data),
    .m_axis_rx(i2c_rd_data),

    /*
     * I2C interface
     */
    .scl_i(i2c_scl_i),
    .scl_o(i2c_scl_o),
    .sda_i(i2c_sda_i),
    .sda_o(i2c_sda_o),

    /*
     * Status
     */
    .busy(busy),
    .bus_control(bus_control),
    .bus_active(bus_active),
    .missed_ack(missed_ack),

    /*
     * Configuration
     */
    .prescale(prescale_reg),
    .stop_on_idle(stop_on_idle_reg)
);

endmodule

`resetall
