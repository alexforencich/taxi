// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * APB to AXI4 lite adapter testbench
 */
module test_taxi_apb_axil_adapter #
(
    /* verilator lint_off WIDTHTRUNC */
    parameter ADDR_W = 32,
    parameter APB_DATA_W = 32,
    parameter APB_STRB_W = (APB_DATA_W/8),
    parameter AXIL_DATA_W = 32,
    parameter AXIL_STRB_W = (AXIL_DATA_W/8),
    parameter logic PAUSER_EN = 1'b0,
    parameter PAUSER_W = 1,
    parameter logic PWUSER_EN = 1'b0,
    parameter PWUSER_W = 1,
    parameter logic PRUSER_EN = 1'b0,
    parameter PRUSER_W = 1,
    parameter logic PBUSER_EN = 1'b0,
    parameter PBUSER_W = 1
    /* verilator lint_on WIDTHTRUNC */
)
();

logic clk;
logic rst;

taxi_apb_if #(
    .DATA_W(APB_DATA_W),
    .ADDR_W(ADDR_W),
    .STRB_W(APB_STRB_W),
    .PAUSER_EN(PAUSER_EN),
    .PAUSER_W(PAUSER_W),
    .PWUSER_EN(PWUSER_EN),
    .PWUSER_W(PWUSER_W),
    .PRUSER_EN(PRUSER_EN),
    .PRUSER_W(PRUSER_W),
    .PBUSER_EN(PBUSER_EN),
    .PBUSER_W(PBUSER_W)
) s_apb();

taxi_axil_if #(
    .DATA_W(AXIL_DATA_W),
    .ADDR_W(ADDR_W),
    .STRB_W(AXIL_STRB_W),
    .AWUSER_EN(PAUSER_EN),
    .AWUSER_W(PAUSER_W),
    .WUSER_EN(PWUSER_EN),
    .WUSER_W(PWUSER_W),
    .BUSER_EN(PBUSER_EN),
    .BUSER_W(PBUSER_W),
    .ARUSER_EN(PAUSER_EN),
    .ARUSER_W(PAUSER_W),
    .RUSER_EN(PRUSER_EN),
    .RUSER_W(PRUSER_W)
) m_axil();

taxi_apb_axil_adapter
uut (
    .clk(clk),
    .rst(rst),

    /*
     * APB slave interface
     */
    .s_apb(s_apb),

    /*
     * AXI4-Lite master interface
     */
    .m_axil_wr(m_axil),
    .m_axil_rd(m_axil)
);

endmodule

`resetall
