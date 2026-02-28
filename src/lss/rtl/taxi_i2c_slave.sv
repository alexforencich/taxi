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
 * I2C slave
 */
module taxi_i2c_slave #(
    parameter FILTER_LEN = 4
)
(
    input  wire logic        clk,
    input  wire logic        rst,

    /*
     * Host interface
     */
    input  wire logic        release_bus,
    taxi_axis_if.snk         s_axis_tx,
    taxi_axis_if.src         m_axis_rx,

    /*
     * I2C interface
     */
    input  wire logic        scl_i,
    output wire logic        scl_o,
    input  wire logic        sda_i,
    output wire logic        sda_o,

    /*
     * Status
     */
    output wire logic        busy,
    output wire logic [6:0]  bus_address,
    output wire logic        bus_addressed,
    output wire logic        bus_active,

    /*
     * Configuration
     */
    input  wire logic        enable = 1'b1,
    input  wire logic [6:0]  device_address,
    input  wire logic [6:0]  device_address_mask = '1
);
/*

I2C

Read
    __    ___ ___ ___ ___ ___ ___ ___ ___     ___ ___ ___ ___ ___ ___ ___ ___     ___ ___ ___ ___ ___ ___ ___ ___ ___    __
sda   \__/_6_X_5_X_4_X_3_X_2_X_1_X_0_/ R \_A_/_7_X_6_X_5_X_4_X_3_X_2_X_1_X_0_\_A_/_7_X_6_X_5_X_4_X_3_X_2_X_1_X_0_/ N \__/
    ____   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   ____
scl  ST \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ SP

Write
    __    ___ ___ ___ ___ ___ ___ ___         ___ ___ ___ ___ ___ ___ ___ ___     ___ ___ ___ ___ ___ ___ ___ ___        __
sda   \__/_6_X_5_X_4_X_3_X_2_X_1_X_0_\_W___A_/_7_X_6_X_5_X_4_X_3_X_2_X_1_X_0_\_A_/_7_X_6_X_5_X_4_X_3_X_2_X_1_X_0_\_A____/
    ____   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   ____
scl  ST \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ SP


Operation:

This module translates I2C read and write operations into AXI stream transfers.
Bytes written over I2C will be delayed by one byte time so that the last byte
in a write operation can be accurately marked.  When reading, the module will
stretch SCL by holding it low until a data byte is presented at the AXI stream
input.

Control:

release_bus
    releases control over bus

Status:

busy
    module is communicating over the bus

bus_address
    active address on bus when module is addressed

bus_addressed
    module is currently addressed on the bus

bus_active
    bus is active, not necessarily controlled by this module

Parameters:

device_address
    address of slave device

device_address_mask
    select which bits of device address to compare, set to 7'h7f
    to check all bits (single address device)

Example of interfacing with tristate pins:

assign scl_i = scl_pin;
assign scl_pin = scl_o ? 1'bz : 1'b0;
assign sda_i = sda_pin;
assign sda_pin = sda_o ? 1'bz : 1'b0;

Example of two interconnected internal I2C devices:

assign scl_1_i = scl_1_o & scl_2_o;
assign scl_2_i = scl_1_o & scl_2_o;
assign sda_1_i = sda_1_o & sda_2_o;
assign sda_2_i = sda_1_o & sda_2_o;

Example of two I2C devices sharing the same pins:

assign scl_1_i = scl_pin;
assign scl_2_i = scl_pin;
assign scl_pin = (scl_1_o & scl_2_o) ? 1'bz : 1'b0;
assign sda_1_i = sda_pin;
assign sda_2_i = sda_pin;
assign sda_pin = (sda_1_o & sda_2_o) ? 1'bz : 1'b0;

Notes:

scl_o should not be connected directly to scl_i, only via AND logic or a tristate
I/O pin.  This would prevent devices from stretching the clock period.

*/

// check configuration
if (s_axis_tx.DATA_W != 8 || m_axis_rx.DATA_W != 8)
    $fatal(0, "Data interface width must be 8 bits (instance %m)");

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

state_t state_reg = STATE_IDLE, state_next;

logic [6:0] addr_reg = '0, addr_next;
logic [7:0] data_reg = '0, data_next;
logic data_valid_reg = 1'b0, data_valid_next;
logic data_out_reg_valid_reg = 1'b0, data_out_reg_valid_next;
logic last_reg = 1'b0, last_next;

logic mode_read_reg = 1'b0, mode_read_next;

logic [3:0] bit_count_reg = '0, bit_count_next;

logic s_axis_tx_tready_reg = 1'b0, s_axis_tx_tready_next;

logic [7:0] m_axis_rx_tdata_reg = '0, m_axis_rx_tdata_next;
logic m_axis_rx_tvalid_reg = 1'b0, m_axis_rx_tvalid_next;
logic m_axis_rx_tlast_reg = 1'b0, m_axis_rx_tlast_next;

logic [FILTER_LEN-1:0] scl_i_filter_reg = '1;
logic [FILTER_LEN-1:0] sda_i_filter_reg = '1;

logic scl_i_reg = 1'b1;
logic sda_i_reg = 1'b1;

logic scl_o_reg = 1'b1, scl_o_next;
logic sda_o_reg = 1'b1, sda_o_next;

logic last_scl_i_reg = 1'b1;
logic last_sda_i_reg = 1'b1;

logic busy_reg = 1'b0;
logic bus_active_reg = 1'b0;
logic bus_addressed_reg = 1'b0, bus_addressed_next;

assign bus_address = addr_reg;

assign s_axis_tx.tready = s_axis_tx_tready_reg;

assign m_axis_rx.tdata = m_axis_rx_tdata_reg;
assign m_axis_rx.tkeep = 1'b1;
assign m_axis_rx.tstrb = m_axis_rx.tkeep;
assign m_axis_rx.tvalid = m_axis_rx_tvalid_reg;
assign m_axis_rx.tlast = m_axis_rx_tlast_reg;
assign m_axis_rx.tid = '0;
assign m_axis_rx.tdest = '0;
assign m_axis_rx.tuser = '0;

assign scl_o = scl_o_reg;
assign sda_o = sda_o_reg;

assign busy = busy_reg;
assign bus_active = bus_active_reg;
assign bus_addressed = bus_addressed_reg;

wire scl_posedge = scl_i_reg && !last_scl_i_reg;
wire scl_negedge = !scl_i_reg && last_scl_i_reg;
wire sda_posedge = sda_i_reg && !last_sda_i_reg;
wire sda_negedge = !sda_i_reg && last_sda_i_reg;

wire start_bit = sda_negedge && scl_i_reg;
wire stop_bit = sda_posedge && scl_i_reg;

always_comb begin
    state_next = STATE_IDLE;

    addr_next = addr_reg;
    data_next = data_reg;
    data_valid_next = data_valid_reg;
    data_out_reg_valid_next = data_out_reg_valid_reg;
    last_next = last_reg;

    mode_read_next = mode_read_reg;

    bit_count_next = bit_count_reg;

    s_axis_tx_tready_next = 1'b0;

    m_axis_rx_tdata_next = m_axis_rx_tdata_reg;
    m_axis_rx_tvalid_next = m_axis_rx_tvalid_reg && !m_axis_rx.tready;
    m_axis_rx_tlast_next = m_axis_rx_tlast_reg;

    scl_o_next = scl_o_reg;
    sda_o_next = sda_o_reg;

    bus_addressed_next = bus_addressed_reg;

    if (start_bit) begin
        // got start bit, latch out data, read address
        scl_o_next = 1'b1;
        sda_o_next = 1'b1;

        data_valid_next = 1'b0;
        data_out_reg_valid_next = 1'b0;
        bit_count_next = 4'd7;
        m_axis_rx_tlast_next = 1'b1;
        m_axis_rx_tvalid_next = data_out_reg_valid_reg;
        bus_addressed_next = 1'b0;
        state_next = STATE_ADDRESS;
    end else if (release_bus || stop_bit) begin
        // got stop bit or release bus command, latch out data, return to idle
        scl_o_next = 1'b1;
        sda_o_next = 1'b1;

        data_valid_next = 1'b0;
        data_out_reg_valid_next = 1'b0;
        m_axis_rx_tlast_next = 1'b1;
        m_axis_rx_tvalid_next = data_out_reg_valid_reg;
        bus_addressed_next = 1'b0;
        state_next = STATE_IDLE;
    end else begin
        case (state_reg)
            STATE_IDLE: begin
                // line idle
                scl_o_next = 1'b1;
                sda_o_next = 1'b1;

                data_valid_next = 1'b0;
                data_out_reg_valid_next = 1'b0;
                bus_addressed_next = 1'b0;
                state_next = STATE_IDLE;
            end
            STATE_ADDRESS: begin
                // read address
                scl_o_next = 1'b1;
                sda_o_next = 1'b1;

                if (scl_posedge) begin
                    if (bit_count_reg > 0) begin
                        // shift in address
                        bit_count_next = bit_count_reg-1;
                        data_next = {data_reg[6:0], sda_i_reg};
                        state_next = STATE_ADDRESS;
                    end else begin
                        // check address
                        addr_next = data_reg[6:0];
                        if (enable && (((device_address ^ addr_next) & device_address_mask) == 0)) begin
                            // it's a match, save read/write bit and send ACK
                            mode_read_next = sda_i_reg;
                            bus_addressed_next = 1'b1;
                            state_next = STATE_ACK;
                        end else begin
                            // no match, return to idle
                            state_next = STATE_IDLE;
                        end
                    end
                end else begin
                    state_next = STATE_ADDRESS;
                end
            end
            STATE_ACK: begin
                // send ACK bit
                // scl_o_next = 1'b1;
                // sda_o_next = 1'b1;

                if (scl_negedge) begin
                    sda_o_next = 1'b0;
                    bit_count_next = 4'd7;
                    if (mode_read_reg) begin
                        // reading
                        s_axis_tx_tready_next = 1'b1;
                        data_valid_next = 1'b0;
                        state_next = STATE_READ_1;
                    end else begin
                        // writing
                        state_next = STATE_WRITE_1;
                    end
                end else begin
                    state_next = STATE_ACK;
                end
            end
            STATE_WRITE_1: begin
                // write data byte
                // sda_o_next = 1'b1;

                if (scl_negedge || !scl_o_reg) begin
                    sda_o_next = 1'b1;
                    if (m_axis_rx.tvalid && !m_axis_rx.tready) begin
                        // data waiting in output register, so stretch clock
                        scl_o_next = 1'b0;
                        state_next = STATE_WRITE_1;
                    end else begin
                        scl_o_next = 1'b1;
                        if (data_valid_reg) begin
                            // store data in output register
                            m_axis_rx_tdata_next = data_reg;
                            m_axis_rx_tlast_next = 1'b0;
                        end
                        data_valid_next = 1'b0;
                        data_out_reg_valid_next = data_valid_reg;
                        state_next = STATE_WRITE_2;
                    end
                end else begin
                    state_next = STATE_WRITE_1;
                end
            end
            STATE_WRITE_2: begin
                // write data byte
                // sda_o_next = 1'b1;

                if (scl_posedge) begin
                    // shift in data bit
                    data_next = {data_reg[6:0], sda_i_reg};
                    if (bit_count_reg > 0) begin
                        bit_count_next = bit_count_reg-1;
                        state_next = STATE_WRITE_2;
                    end else begin
                        // latch out previous data byte since we now know it's not the last one
                        m_axis_rx_tvalid_next = data_out_reg_valid_reg;
                        data_out_reg_valid_next = 1'b0;
                        data_valid_next = 1'b1;
                        state_next = STATE_ACK;
                    end
                end else begin
                    state_next = STATE_WRITE_2;
                end
            end
            STATE_READ_1: begin
                // read data byte
                if (s_axis_tx.tready && s_axis_tx.tvalid) begin
                    // data valid; latch it in
                    s_axis_tx_tready_next = 1'b0;
                    data_next = s_axis_tx.tdata;
                    data_valid_next = 1'b1;
                end else begin
                    // keep ready high if we're waiting for data
                    s_axis_tx_tready_next = !data_valid_reg;
                end

                if (scl_negedge || !scl_o_reg) begin
                    // shift out data bit
                    if (!data_valid_reg) begin
                        // waiting for data, so stretch clock
                        scl_o_next = 1'b0;
                        state_next = STATE_READ_1;
                    end else begin
                        scl_o_next = 1'b1;
                        {sda_o_next, data_next} = {data_reg, 1'b0};

                        if (bit_count_reg > 0) begin
                            bit_count_next = bit_count_reg-1;
                            state_next = STATE_READ_1;
                        end else begin
                            state_next = STATE_READ_2;
                        end
                    end
                end else begin
                    state_next = STATE_READ_1;
                end
            end
            STATE_READ_2: begin
                // scl_o_next = 1'b1;

                // read ACK bit
                if (scl_negedge) begin
                    // release SDA
                    sda_o_next = 1'b1;
                    state_next = STATE_READ_3;
                end else begin
                    state_next = STATE_READ_2;
                end
            end
            STATE_READ_3: begin
                // read ACK bit
                // scl_o_next = 1'b1;
                // sda_o_next = 1'b1;

                if (scl_posedge) begin
                    if (sda_i_reg) begin
                        // NACK, return to idle
                        state_next = STATE_IDLE;
                    end else begin
                        // ACK, read another byte
                        bit_count_next = 4'd7;
                        s_axis_tx_tready_next = 1'b1;
                        data_valid_next = 1'b0;
                        state_next = STATE_READ_1;
                    end
                end else begin
                    state_next = STATE_READ_3;
                end
            end
        endcase
    end
end

always_ff @(posedge clk) begin
    state_reg <= state_next;

    addr_reg <= addr_next;
    data_reg <= data_next;
    data_valid_reg <= data_valid_next;
    data_out_reg_valid_reg <= data_out_reg_valid_next;
    last_reg <= last_next;

    mode_read_reg <= mode_read_next;

    bit_count_reg <= bit_count_next;

    s_axis_tx_tready_reg <= s_axis_tx_tready_next;

    m_axis_rx_tdata_reg <= m_axis_rx_tdata_next;
    m_axis_rx_tvalid_reg <= m_axis_rx_tvalid_next;
    m_axis_rx_tlast_reg <= m_axis_rx_tlast_next;

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

    scl_o_reg <= scl_o_next;
    sda_o_reg <= sda_o_next;

    last_scl_i_reg <= scl_i_reg;
    last_sda_i_reg <= sda_i_reg;

    busy_reg <= !(state_reg == STATE_IDLE);

    if (start_bit) begin
        bus_active_reg <= 1'b1;
    end else if (stop_bit) begin
        bus_active_reg <= 1'b0;
    end else begin
        bus_active_reg <= bus_active_reg;
    end

    bus_addressed_reg <= bus_addressed_next;

    if (rst) begin
        state_reg <= STATE_IDLE;
        s_axis_tx_tready_reg <= 1'b0;
        m_axis_rx_tvalid_reg <= 1'b0;
        scl_o_reg <= 1'b1;
        sda_o_reg <= 1'b1;
        busy_reg <= 1'b0;
        bus_active_reg <= 1'b0;
        bus_addressed_reg <= 1'b0;
    end
end

endmodule

`resetall
