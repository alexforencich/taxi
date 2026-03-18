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
 * I2C master testbench
 */
module test_taxi_i2c_master
();

logic clk;
logic rst;

taxi_axis_if #(.DATA_W(12), .KEEP_W(1)) s_axis_cmd();
taxi_axis_if #(.DATA_W(8)) s_axis_tx();
taxi_axis_if #(.DATA_W(8)) m_axis_rx();

logic scl_i;
logic scl_o;
logic sda_i;
logic sda_o;

logic busy;
logic bus_control;
logic bus_active;
logic missed_ack;

logic [15:0] prescale;
logic [15:0] tbuf_cyc;
logic stop_on_idle;

taxi_i2c_master
uut (
    .clk(clk),
    .rst(rst),

    /*
     * Host interface
     */
    .s_axis_cmd(s_axis_cmd),
    .s_axis_tx(s_axis_tx),
    .m_axis_rx(m_axis_rx),

    /*
     * I2C interface
     */
    .scl_i(scl_i),
    .scl_o(scl_o),
    .sda_i(sda_i),
    .sda_o(sda_o),

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
    .prescale(prescale),
    .tbuf_cyc(tbuf_cyc),
    .stop_on_idle(stop_on_idle)
);

endmodule

`resetall
