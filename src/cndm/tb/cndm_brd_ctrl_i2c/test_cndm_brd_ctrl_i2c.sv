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
 * I2C master testbench
 */
module test_cndm_brd_ctrl_i2c #
(
    /* verilator lint_off WIDTHTRUNC */
    parameter logic OPTIC_EN = 1'b1,
    parameter OPTIC_CNT = 2,

    parameter logic EEPROM_EN = 1'b1,
    parameter EEPROM_IDX = OPTIC_EN ? OPTIC_CNT : 0,

    parameter logic MAC_EEPROM_EN = EEPROM_EN,
    parameter MAC_EEPROM_IDX = EEPROM_IDX,
    parameter MAC_EEPROM_OFFSET = 32,
    parameter MAC_COUNT = OPTIC_CNT,
    parameter logic MAC_FROM_BASE = 1'b1,

    parameter logic SN_EEPROM_EN = EEPROM_EN,
    parameter SN_EEPROM_IDX = EEPROM_IDX,
    parameter SN_EEPROM_OFFSET = 0,
    parameter SN_LEN = 32,

    parameter logic PLL_EN = 1'b1,
    parameter PLL_IDX = EEPROM_IDX + (EEPROM_EN ? 1 : 0),

    parameter logic MUX_EN = 1'b1,
    parameter MUX_CNT = 2,
    parameter logic [MUX_CNT-1:0][6:0] MUX_I2C_ADDR = {7'h75, 7'h74},

    parameter DEV_CNT = PLL_IDX + (PLL_EN ? 1 : 0),
    parameter logic [DEV_CNT-1:0][6:0] DEV_I2C_ADDR = {7'h5D, 7'h54, 7'h51, 7'h50},
    parameter logic [DEV_CNT-1:0][31:0] DEV_ADDR_CFG = {32'h00_00_0000, 32'h00_00_0040, 32'h7e_7f_0070, 32'h7e_7f_0070},
    parameter logic [DEV_CNT-1:0][MUX_CNT-1:0][7:0] DEV_MUX_MASK = {{8'h00, 8'h01}, {8'h07, 8'h00}, {8'h00, 8'h08}, {8'h00, 8'h04}},

    parameter I2C_PRESCALE = 2,
    parameter I2C_TBUF_CYC = 10
    /* verilator lint_on WIDTHTRUNC */
)
();

logic clk;
logic rst;

taxi_axis_if #(
    .DATA_W(32),
    .KEEP_EN(1),
    .ID_EN(1),
    .ID_W(4),
    .USER_EN(1),
    .USER_W(1)
) s_axis_cmd(), m_axis_rsp();

logic i2c_scl_i;
logic i2c_scl_o;
logic i2c_sda_i;
logic i2c_sda_o;

logic [DEV_CNT-1:0] dev_sel;
logic [DEV_CNT-1:0] dev_rst;

cndm_brd_ctrl_i2c #(
    .OPTIC_EN(OPTIC_EN),
    .OPTIC_CNT(OPTIC_CNT),

    .EEPROM_EN(EEPROM_EN),
    .EEPROM_IDX(EEPROM_IDX),

    .MAC_EEPROM_EN(MAC_EEPROM_EN),
    .MAC_EEPROM_IDX(MAC_EEPROM_IDX),
    .MAC_EEPROM_OFFSET(MAC_EEPROM_OFFSET),
    .MAC_COUNT(MAC_COUNT),
    .MAC_FROM_BASE(MAC_FROM_BASE),

    .SN_EEPROM_EN(SN_EEPROM_EN),
    .SN_EEPROM_IDX(SN_EEPROM_IDX),
    .SN_EEPROM_OFFSET(SN_EEPROM_OFFSET),
    .SN_LEN(SN_LEN),

    .PLL_EN(PLL_EN),
    .PLL_IDX(PLL_IDX),

    .MUX_EN(MUX_EN),
    .MUX_CNT(MUX_CNT),
    .MUX_I2C_ADDR(MUX_I2C_ADDR),

    .DEV_CNT(DEV_CNT),
    .DEV_I2C_ADDR(DEV_I2C_ADDR),
    .DEV_ADDR_CFG(DEV_ADDR_CFG),
    .DEV_MUX_MASK(DEV_MUX_MASK),

    .I2C_PRESCALE(I2C_PRESCALE),
    .I2C_TBUF_CYC(I2C_TBUF_CYC)
)
uut (
    .clk(clk),
    .rst(rst),

    /*
     * Board control command interface
     */
    .s_axis_cmd(s_axis_cmd),
    .m_axis_rsp(m_axis_rsp),

    /*
     * I2C interface
     */
    .i2c_scl_i(i2c_scl_i),
    .i2c_scl_o(i2c_scl_o),
    .i2c_sda_i(i2c_sda_i),
    .i2c_sda_o(i2c_sda_o),

    .dev_sel(dev_sel),
    .dev_rst(dev_rst)
);

endmodule

`resetall
