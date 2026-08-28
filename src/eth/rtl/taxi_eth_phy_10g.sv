// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2018-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * 10G Ethernet PHY
 */
module taxi_eth_phy_10g #
(
    parameter DATA_W = 64,
    parameter CTRL_W = (DATA_W/8),
    parameter HDR_W = 2,
    parameter logic TX_GBX_IF_EN = 1'b0,
    parameter logic RX_GBX_IF_EN = TX_GBX_IF_EN,
    parameter logic BIT_REVERSE = 1'b0,
    parameter logic SCRAMBLER_DISABLE = 1'b0,
    parameter logic PRBS31_EN = 1'b0,
    parameter TX_SERDES_PIPELINE = 0,
    parameter RX_SERDES_PIPELINE = 0,
    parameter BITSLIP_HIGH_CYCLES = 1,
    parameter BITSLIP_LOW_CYCLES = 7,
    parameter COUNT_125US = 125000/6.4
)
(
    input  wire logic               rx_clk,
    input  wire logic               rx_rst,
    input  wire logic               tx_clk,
    input  wire logic               tx_rst,

    /*
     * XGMII interface
     */
    input  wire logic [DATA_W-1:0]  xgmii_txd,
    input  wire logic [CTRL_W-1:0]  xgmii_txc,
    input  wire logic               xgmii_tx_valid = 1'b1,
    output wire logic [DATA_W-1:0]  xgmii_rxd,
    output wire logic [CTRL_W-1:0]  xgmii_rxc,
    output wire logic               xgmii_rx_valid,
    output wire logic               tx_gbx_req_sync,
    output wire logic               tx_gbx_req_stall,
    input  wire logic               tx_gbx_sync = 1'b0,
    output wire logic               rx_gbx_sync,

    /*
     * SERDES interface
     */
    output wire logic [DATA_W-1:0]  serdes_tx_data,
    output wire logic               serdes_tx_data_valid,
    output wire logic [HDR_W-1:0]   serdes_tx_hdr,
    output wire logic               serdes_tx_hdr_valid,
    input  wire logic               serdes_tx_gbx_req_sync = 1'b0,
    input  wire logic               serdes_tx_gbx_req_stall = 1'b0,
    output wire logic               serdes_tx_gbx_sync,
    input  wire logic [DATA_W-1:0]  serdes_rx_data,
    input  wire logic               serdes_rx_data_valid = 1'b1,
    input  wire logic [HDR_W-1:0]   serdes_rx_hdr,
    input  wire logic               serdes_rx_hdr_valid = 1'b1,
    input  wire logic               serdes_rx_gbx_sync = 1'b0,
    output wire logic               serdes_rx_bitslip,
    output wire logic               serdes_rx_reset_req,

    /*
     * Status
     */
    output wire logic               tx_bad_block,
    output wire logic [6:0]         rx_error_count,
    output wire logic               rx_bad_block,
    output wire logic               rx_sequence_error,
    output wire logic               rx_block_lock,
    output wire logic               rx_high_ber,
    output wire logic               rx_status,

    /*
     * Configuration
     */
    input  wire logic               cfg_tx_prbs31_enable = 1'b0,
    input  wire logic               cfg_rx_prbs31_enable = 1'b0
);

taxi_eth_phy_10g_rx #(
    .DATA_W(DATA_W),
    .CTRL_W(CTRL_W),
    .HDR_W(HDR_W),
    .GBX_IF_EN(RX_GBX_IF_EN),
    .BIT_REVERSE(BIT_REVERSE),
    .SCRAMBLER_DISABLE(SCRAMBLER_DISABLE),
    .PRBS31_EN(PRBS31_EN),
    .SERDES_PIPELINE(RX_SERDES_PIPELINE),
    .BITSLIP_HIGH_CYCLES(BITSLIP_HIGH_CYCLES),
    .BITSLIP_LOW_CYCLES(BITSLIP_LOW_CYCLES),
    .COUNT_125US(COUNT_125US)
)
eth_phy_10g_rx_inst (
    .clk(rx_clk),
    .rst(rx_rst),

    /*
     * XGMII interface
     */
    .xgmii_rxd(xgmii_rxd),
    .xgmii_rxc(xgmii_rxc),
    .xgmii_rx_valid(xgmii_rx_valid),
    .rx_gbx_sync(rx_gbx_sync),

    /*
     * SERDES interface
     */
    .serdes_rx_data(serdes_rx_data),
    .serdes_rx_data_valid(serdes_rx_data_valid),
    .serdes_rx_hdr(serdes_rx_hdr),
    .serdes_rx_hdr_valid(serdes_rx_hdr_valid),
    .serdes_rx_gbx_sync(serdes_rx_gbx_sync),
    .serdes_rx_bitslip(serdes_rx_bitslip),
    .serdes_rx_reset_req(serdes_rx_reset_req),

    /*
     * Status
     */
    .rx_error_count(rx_error_count),
    .rx_bad_block(rx_bad_block),
    .rx_sequence_error(rx_sequence_error),
    .rx_block_lock(rx_block_lock),
    .rx_high_ber(rx_high_ber),
    .rx_status(rx_status),

    /*
     * Configuration
     */
    .cfg_rx_prbs31_enable(cfg_rx_prbs31_enable)
);

taxi_eth_phy_10g_tx #(
    .DATA_W(DATA_W),
    .CTRL_W(CTRL_W),
    .HDR_W(HDR_W),
    .GBX_IF_EN(TX_GBX_IF_EN),
    .BIT_REVERSE(BIT_REVERSE),
    .SCRAMBLER_DISABLE(SCRAMBLER_DISABLE),
    .PRBS31_EN(PRBS31_EN),
    .SERDES_PIPELINE(TX_SERDES_PIPELINE)
)
eth_phy_10g_tx_inst (
    .clk(tx_clk),
    .rst(tx_rst),

    /*
     * XGMII interface
     */
    .xgmii_txd(xgmii_txd),
    .xgmii_txc(xgmii_txc),
    .xgmii_tx_valid(xgmii_tx_valid),
    .tx_gbx_req_sync(tx_gbx_req_sync),
    .tx_gbx_req_stall(tx_gbx_req_stall),
    .tx_gbx_sync(tx_gbx_sync),

    /*
     * SERDES interface
     */
    .serdes_tx_data(serdes_tx_data),
    .serdes_tx_data_valid(serdes_tx_data_valid),
    .serdes_tx_hdr(serdes_tx_hdr),
    .serdes_tx_hdr_valid(serdes_tx_hdr_valid),
    .serdes_tx_gbx_req_sync(serdes_tx_gbx_req_sync),
    .serdes_tx_gbx_req_stall(serdes_tx_gbx_req_stall),
    .serdes_tx_gbx_sync(serdes_tx_gbx_sync),

    /*
     * Status
     */
    .tx_bad_block(tx_bad_block),

    /*
     * Configuration
     */
    .cfg_tx_prbs31_enable(cfg_tx_prbs31_enable)
);

endmodule

`resetall
