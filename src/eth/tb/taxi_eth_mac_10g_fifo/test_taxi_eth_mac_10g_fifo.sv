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
 * 10G Ethernet MAC with TX and RX FIFOs testbench
 */
module test_taxi_eth_mac_10g_fifo #
(
    /* verilator lint_off WIDTHTRUNC */
    parameter DATA_W = 8,
    parameter logic TX_GBX_IF_EN = 1'b0,
    parameter logic RX_GBX_IF_EN = TX_GBX_IF_EN,
    parameter GBX_CNT = 1,
    parameter AXIS_DATA_W = 8,
    parameter logic PADDING_EN = 1'b1,
    parameter logic DIC_EN = 1'b1,
    parameter MIN_FRAME_LEN = 64,
    parameter logic PTP_TS_EN = 1'b0,
    parameter logic PTP_TD_EN = PTP_TS_EN,
    parameter logic PTP_TS_FMT_TOD = 1'b1,
    parameter PTP_TS_W = PTP_TS_FMT_TOD ? 96 : 64,
    parameter PTP_TD_SDI_PIPELINE = 2,
    parameter TX_TAG_W = 16,
    parameter logic STAT_EN = 1'b0,
    parameter STAT_TX_LEVEL = 1,
    parameter STAT_RX_LEVEL = STAT_TX_LEVEL,
    parameter STAT_ID_BASE = 0,
    parameter STAT_UPDATE_PERIOD = 1024,
    parameter logic STAT_STR_EN = 1'b1,
    parameter logic [8*8-1:0] STAT_PREFIX_STR = "MAC",
    parameter TX_FIFO_DEPTH = 4096,
    parameter TX_FIFO_RAM_PIPELINE = 1,
    parameter logic TX_FRAME_FIFO = 1'b1,
    parameter logic TX_DROP_OVERSIZE_FRAME = TX_FRAME_FIFO,
    parameter logic TX_DROP_BAD_FRAME = TX_DROP_OVERSIZE_FRAME,
    parameter logic TX_DROP_WHEN_FULL = 1'b0,
    parameter TX_CPL_FIFO_DEPTH = 64,
    parameter RX_FIFO_DEPTH = 4096,
    parameter RX_FIFO_RAM_PIPELINE = 1,
    parameter logic RX_FRAME_FIFO = 1'b1,
    parameter logic RX_DROP_OVERSIZE_FRAME = RX_FRAME_FIFO,
    parameter logic RX_DROP_BAD_FRAME = RX_DROP_OVERSIZE_FRAME,
    parameter logic RX_DROP_WHEN_FULL = RX_DROP_OVERSIZE_FRAME
    /* verilator lint_on WIDTHTRUNC */
)
();

localparam CTRL_W = DATA_W/8;
localparam TX_USER_W = 1;
localparam RX_USER_W = (PTP_TS_EN ? PTP_TS_W : 0) + 1;

logic rx_clk;
logic rx_rst;
logic tx_clk;
logic tx_rst;
logic logic_clk;
logic logic_rst;

taxi_axis_if #(.DATA_W(AXIS_DATA_W), .USER_EN(1), .USER_W(TX_USER_W), .ID_EN(1), .ID_W(TX_TAG_W)) s_axis_tx();
taxi_axis_if #(.DATA_W(96), .KEEP_W(1), .ID_EN(1), .ID_W(TX_TAG_W)) m_axis_tx_cpl();
taxi_axis_if #(.DATA_W(AXIS_DATA_W), .USER_EN(1), .USER_W(RX_USER_W)) m_axis_rx();

logic [DATA_W-1:0] xgmii_rxd;
logic [CTRL_W-1:0] xgmii_rxc;
logic xgmii_rx_valid;
logic [DATA_W-1:0] xgmii_txd;
logic [CTRL_W-1:0] xgmii_txc;
logic xgmii_tx_valid;
logic [GBX_CNT-1:0] tx_gbx_req_sync;
logic tx_gbx_req_stall;
logic [GBX_CNT-1:0] tx_gbx_sync;

logic ptp_clk;
logic ptp_rst;
logic ptp_sample_clk;
logic ptp_td_sdi;
logic [PTP_TS_W-1:0] ptp_ts_in;
logic ptp_ts_step_in;
logic [PTP_TS_W-1:0] tx_ptp_ts_out;
logic tx_ptp_ts_step_out;
logic tx_ptp_locked;
logic [PTP_TS_W-1:0] rx_ptp_ts_out;
logic rx_ptp_ts_step_out;
logic rx_ptp_locked;

logic stat_clk;
logic stat_rst;
taxi_axis_if #(.DATA_W(16), .KEEP_W(1), .KEEP_EN(0), .LAST_EN(0), .USER_EN(1), .USER_W(1), .ID_EN(1), .ID_W(8)) m_axis_stat();

logic tx_error_underflow;
logic tx_fifo_overflow;
logic tx_fifo_bad_frame;
logic tx_fifo_good_frame;
logic rx_error_bad_frame;
logic rx_error_bad_fcs;
logic rx_fifo_overflow;
logic rx_fifo_bad_frame;
logic rx_fifo_good_frame;

logic [15:0] cfg_tx_max_pkt_len;
logic [7:0] cfg_tx_ifg;
logic cfg_tx_enable;
logic [15:0] cfg_rx_max_pkt_len;
logic cfg_rx_enable;

taxi_eth_mac_10g_fifo #(
    .DATA_W(DATA_W),
    .CTRL_W(CTRL_W),
    .TX_GBX_IF_EN(TX_GBX_IF_EN),
    .RX_GBX_IF_EN(RX_GBX_IF_EN),
    .GBX_CNT(GBX_CNT),
    .PADDING_EN(PADDING_EN),
    .DIC_EN(DIC_EN),
    .MIN_FRAME_LEN(MIN_FRAME_LEN),
    .PTP_TS_EN(PTP_TS_EN),
    .PTP_TD_EN(PTP_TD_EN),
    .PTP_TS_FMT_TOD(PTP_TS_FMT_TOD),
    .PTP_TS_W(PTP_TS_W),
    .PTP_TD_SDI_PIPELINE(PTP_TD_SDI_PIPELINE),
    .STAT_EN(STAT_EN),
    .STAT_TX_LEVEL(STAT_TX_LEVEL),
    .STAT_RX_LEVEL(STAT_RX_LEVEL),
    .STAT_ID_BASE(STAT_ID_BASE),
    .STAT_UPDATE_PERIOD(STAT_UPDATE_PERIOD),
    .STAT_STR_EN(STAT_STR_EN),
    .STAT_PREFIX_STR(STAT_PREFIX_STR),
    .TX_FIFO_DEPTH(TX_FIFO_DEPTH),
    .TX_FIFO_RAM_PIPELINE(TX_FIFO_RAM_PIPELINE),
    .TX_FRAME_FIFO(TX_FRAME_FIFO),
    .TX_DROP_OVERSIZE_FRAME(TX_DROP_OVERSIZE_FRAME),
    .TX_DROP_BAD_FRAME(TX_DROP_BAD_FRAME),
    .TX_DROP_WHEN_FULL(TX_DROP_WHEN_FULL),
    .TX_CPL_FIFO_DEPTH(TX_CPL_FIFO_DEPTH),
    .RX_FIFO_DEPTH(RX_FIFO_DEPTH),
    .RX_FIFO_RAM_PIPELINE(RX_FIFO_RAM_PIPELINE),
    .RX_FRAME_FIFO(RX_FRAME_FIFO),
    .RX_DROP_OVERSIZE_FRAME(RX_DROP_OVERSIZE_FRAME),
    .RX_DROP_BAD_FRAME(RX_DROP_BAD_FRAME),
    .RX_DROP_WHEN_FULL(RX_DROP_WHEN_FULL)
)
uut (
    .rx_clk(rx_clk),
    .rx_rst(rx_rst),
    .tx_clk(tx_clk),
    .tx_rst(tx_rst),
    .logic_clk(logic_clk),
    .logic_rst(logic_rst),

    /*
     * Transmit interface (AXI stream)
     */
    .s_axis_tx(s_axis_tx),
    .m_axis_tx_cpl(m_axis_tx_cpl),

    /*
     * Receive interface (AXI stream)
     */
    .m_axis_rx(m_axis_rx),

    /*
     * XGMII interface
     */
    .xgmii_rxd(xgmii_rxd),
    .xgmii_rxc(xgmii_rxc),
    .xgmii_rx_valid(xgmii_rx_valid),
    .xgmii_txd(xgmii_txd),
    .xgmii_txc(xgmii_txc),
    .xgmii_tx_valid(xgmii_tx_valid),
    .tx_gbx_req_sync(tx_gbx_req_sync),
    .tx_gbx_req_stall(tx_gbx_req_stall),
    .tx_gbx_sync(tx_gbx_sync),

    /*
     * PTP clock
     */
    .ptp_clk(ptp_clk),
    .ptp_rst(ptp_rst),
    .ptp_sample_clk(ptp_sample_clk),
    .ptp_td_sdi(ptp_td_sdi),
    .ptp_ts_in(ptp_ts_in),
    .ptp_ts_step_in(ptp_ts_step_in),
    .tx_ptp_ts_out(tx_ptp_ts_out),
    .tx_ptp_ts_step_out(tx_ptp_ts_step_out),
    .tx_ptp_locked(tx_ptp_locked),
    .rx_ptp_ts_out(rx_ptp_ts_out),
    .rx_ptp_ts_step_out(rx_ptp_ts_step_out),
    .rx_ptp_locked(rx_ptp_locked),

    /*
     * Statistics
     */
    .stat_clk(stat_clk),
    .stat_rst(stat_rst),
    .m_axis_stat(m_axis_stat),

    /*
     * Status
     */
    .tx_error_underflow(tx_error_underflow),
    .tx_fifo_overflow(tx_fifo_overflow),
    .tx_fifo_bad_frame(tx_fifo_bad_frame),
    .tx_fifo_good_frame(tx_fifo_good_frame),
    .rx_error_bad_frame(rx_error_bad_frame),
    .rx_error_bad_fcs(rx_error_bad_fcs),
    .rx_fifo_overflow(rx_fifo_overflow),
    .rx_fifo_bad_frame(rx_fifo_bad_frame),
    .rx_fifo_good_frame(rx_fifo_good_frame),

    /*
     * Configuration
     */
    .cfg_tx_max_pkt_len(cfg_tx_max_pkt_len),
    .cfg_tx_ifg(cfg_tx_ifg),
    .cfg_tx_enable(cfg_tx_enable),
    .cfg_rx_max_pkt_len(cfg_rx_max_pkt_len),
    .cfg_rx_enable(cfg_rx_enable)
);

endmodule

`resetall
