// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2015-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * 10G Ethernet MAC with TX and RX FIFOs
 */
module taxi_eth_mac_10g_fifo #
(
    parameter DATA_W = 64,
    parameter CTRL_W = (DATA_W/8),
    parameter logic TX_GBX_IF_EN = 1'b0,
    parameter logic RX_GBX_IF_EN = TX_GBX_IF_EN,
    parameter GBX_CNT = 1,
    parameter logic PADDING_EN = 1'b1,
    parameter logic DIC_EN = 1'b1,
    parameter MIN_FRAME_LEN = 64,
    parameter logic PTP_TS_EN = 1'b0,
    parameter logic PTP_TD_EN = PTP_TS_EN,
    parameter logic PTP_TS_FMT_TOD = 1'b1,
    parameter PTP_TS_W = PTP_TS_FMT_TOD ? 96 : 64,
    parameter PTP_TD_SDI_PIPELINE = 2,
    parameter logic STAT_EN = 1'b0,
    parameter STAT_TX_LEVEL = 1,
    parameter STAT_RX_LEVEL = 1,
    parameter STAT_ID_BASE = 0,
    parameter STAT_UPDATE_PERIOD = 1024,
    parameter logic STAT_STR_EN = 1'b0,
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
)
(
    input  wire logic                 rx_clk,
    input  wire logic                 rx_rst,
    input  wire logic                 tx_clk,
    input  wire logic                 tx_rst,
    input  wire logic                 logic_clk,
    input  wire logic                 logic_rst,

    /*
     * AXI4-Stream input (sink)
     */
    taxi_axis_if.snk                  s_axis_tx,
    taxi_axis_if.src                  m_axis_tx_cpl,

    /*
     * AXI4-Stream output (source)
     */
    taxi_axis_if.src                  m_axis_rx,

    /*
     * XGMII interface
     */
    input  wire logic [DATA_W-1:0]    xgmii_rxd,
    input  wire logic [CTRL_W-1:0]    xgmii_rxc,
    input  wire logic                 xgmii_rx_valid = 1'b1,
    output wire logic [DATA_W-1:0]    xgmii_txd,
    output wire logic [CTRL_W-1:0]    xgmii_txc,
    output wire logic                 xgmii_tx_valid,
    input  wire logic [GBX_CNT-1:0]   tx_gbx_req_sync = '0,
    input  wire logic                 tx_gbx_req_stall = 1'b0,
    output wire logic [GBX_CNT-1:0]   tx_gbx_sync,

    /*
     * PTP clock
     */
    input  wire logic                 ptp_clk = 1'b0,
    input  wire logic                 ptp_rst = 1'b0,
    input  wire logic                 ptp_sample_clk = 1'b0,
    input  wire logic                 ptp_td_sdi = 1'b0,
    input  wire logic [PTP_TS_W-1:0]  ptp_ts_in = '0,
    input  wire logic                 ptp_ts_step_in = 1'b0,
    output wire logic [PTP_TS_W-1:0]  tx_ptp_ts_out,
    output wire logic                 tx_ptp_ts_step_out,
    output wire logic                 tx_ptp_locked,
    output wire logic [PTP_TS_W-1:0]  rx_ptp_ts_out,
    output wire logic                 rx_ptp_ts_step_out,
    output wire logic                 rx_ptp_locked,

    /*
     * Statistics
     */
    input  wire logic                 stat_clk,
    input  wire logic                 stat_rst,
    taxi_axis_if.src                  m_axis_stat,

    /*
     * Status
     */
    output wire logic                 tx_error_underflow,
    output wire logic                 tx_fifo_overflow,
    output wire logic                 tx_fifo_bad_frame,
    output wire logic                 tx_fifo_good_frame,
    output wire logic                 rx_error_bad_frame,
    output wire logic                 rx_error_bad_fcs,
    output wire logic                 rx_fifo_overflow,
    output wire logic                 rx_fifo_bad_frame,
    output wire logic                 rx_fifo_good_frame,

    /*
     * Configuration
     */
    input  wire logic [15:0]          cfg_tx_max_pkt_len = 16'd1518,
    input  wire logic [7:0]           cfg_tx_ifg = 8'd12,
    input  wire logic                 cfg_tx_enable = 1'b1,
    input  wire logic [15:0]          cfg_rx_max_pkt_len = 16'd1518,
    input  wire logic                 cfg_rx_enable = 1'b1
);

localparam KEEP_W = DATA_W/8;
localparam TX_USER_W = 1;
localparam RX_USER_W = (PTP_TS_EN ? PTP_TS_W : 0) + 1;
localparam TX_TAG_W = s_axis_tx.ID_W;

taxi_axis_if #(.DATA_W(DATA_W), .KEEP_W(KEEP_W), .USER_EN(1), .USER_W(TX_USER_W), .ID_EN(1), .ID_W(TX_TAG_W)) axis_tx_int();
taxi_axis_if #(.DATA_W(PTP_TS_W), .KEEP_W(1), .ID_EN(1), .ID_W(TX_TAG_W)) axis_tx_cpl_int();
taxi_axis_if #(.DATA_W(DATA_W), .KEEP_W(KEEP_W), .USER_EN(1), .USER_W(RX_USER_W)) axis_rx_int();

// synchronize MAC status signals into logic clock domain
wire tx_error_underflow_int;

logic [0:0] tx_sync_reg_1 = '0;
logic [0:0] tx_sync_reg_2 = '0;
logic [0:0] tx_sync_reg_3 = '0;
logic [0:0] tx_sync_reg_4 = '0;

assign tx_error_underflow = tx_sync_reg_3[0] ^ tx_sync_reg_4[0];

always_ff @(posedge tx_clk or posedge tx_rst) begin
    if (tx_rst) begin
        tx_sync_reg_1 <= '0;
    end else begin
        tx_sync_reg_1 <= tx_sync_reg_1 ^ {tx_error_underflow_int};
    end
end

always_ff @(posedge logic_clk or posedge logic_rst) begin
    if (logic_rst) begin
        tx_sync_reg_2 <= '0;
        tx_sync_reg_3 <= '0;
        tx_sync_reg_4 <= '0;
    end else begin
        tx_sync_reg_2 <= tx_sync_reg_1;
        tx_sync_reg_3 <= tx_sync_reg_2;
        tx_sync_reg_4 <= tx_sync_reg_3;
    end
end

wire rx_error_bad_frame_int;
wire rx_error_bad_fcs_int;

logic [1:0] rx_sync_reg_1 = '0;
logic [1:0] rx_sync_reg_2 = '0;
logic [1:0] rx_sync_reg_3 = '0;
logic [1:0] rx_sync_reg_4 = '0;

assign rx_error_bad_frame = rx_sync_reg_3[0] ^ rx_sync_reg_4[0];
assign rx_error_bad_fcs = rx_sync_reg_3[1] ^ rx_sync_reg_4[1];

always_ff @(posedge rx_clk or posedge rx_rst) begin
    if (rx_rst) begin
        rx_sync_reg_1 <= '0;
    end else begin
        rx_sync_reg_1 <= rx_sync_reg_1 ^ {rx_error_bad_fcs_int, rx_error_bad_frame_int};
    end
end

always_ff @(posedge logic_clk or posedge logic_rst) begin
    if (logic_rst) begin
        rx_sync_reg_2 <= '0;
        rx_sync_reg_3 <= '0;
        rx_sync_reg_4 <= '0;
    end else begin
        rx_sync_reg_2 <= rx_sync_reg_1;
        rx_sync_reg_3 <= rx_sync_reg_2;
        rx_sync_reg_4 <= rx_sync_reg_3;
    end
end

// PTP timestamping
wire [PTP_TS_W-1:0]  tx_ptp_ts_int;
wire                 tx_ptp_ts_step_int;
wire                 tx_ptp_locked_int;
wire [PTP_TS_W-1:0]  rx_ptp_ts_int;
wire                 rx_ptp_ts_step_int;
wire                 rx_ptp_locked_int;

if (PTP_TS_EN && !PTP_TD_EN) begin : ptp

    taxi_ptp_clock_cdc #(
        .TS_W(PTP_TS_W),
        .NS_W(6)
    )
    tx_ptp_cdc (
        .input_clk(logic_clk),
        .input_rst(logic_rst),
        .output_clk(tx_clk),
        .output_rst(tx_rst),
        .sample_clk(ptp_sample_clk),
        .input_ts(ptp_ts_in),
        .input_ts_step(ptp_ts_step_in),
        .output_ts(tx_ptp_ts_int),
        .output_ts_step(tx_ptp_ts_step_out),
        .output_pps(),
        .output_pps_str(),
        .locked(tx_ptp_locked)
    );

    taxi_ptp_clock_cdc #(
        .TS_W(PTP_TS_W),
        .NS_W(6)
    )
    rx_ptp_cdc (
        .input_clk(logic_clk),
        .input_rst(logic_rst),
        .output_clk(rx_clk),
        .output_rst(rx_rst),
        .sample_clk(ptp_sample_clk),
        .input_ts(ptp_ts_in),
        .input_ts_step(ptp_ts_step_in),
        .output_ts(rx_ptp_ts_int),
        .output_ts_step(rx_ptp_ts_step_out),
        .output_pps(),
        .output_pps_str(),
        .locked(rx_ptp_locked)
    );

end else begin

    assign tx_ptp_ts_int = '0;
    assign tx_ptp_ts_step_out = tx_ptp_ts_step_int;
    assign rx_ptp_ts_int = '0;
    assign rx_ptp_ts_step_out = rx_ptp_ts_step_int;

    assign tx_ptp_locked = tx_ptp_locked_int;
    assign rx_ptp_locked = rx_ptp_locked_int;

end

wire stat_rx_fifo_drop;

taxi_eth_mac_10g #(
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
    .PFC_EN(1'b0),
    .PAUSE_EN(1'b0),
    .STAT_EN(STAT_EN),
    .STAT_TX_LEVEL(STAT_TX_LEVEL),
    .STAT_RX_LEVEL(STAT_RX_LEVEL),
    .STAT_ID_BASE(STAT_ID_BASE),
    .STAT_UPDATE_PERIOD(STAT_UPDATE_PERIOD),
    .STAT_STR_EN(STAT_STR_EN),
    .STAT_PREFIX_STR(STAT_PREFIX_STR)
)
eth_mac_10g_inst (
    .tx_clk(tx_clk),
    .tx_rst(tx_rst),
    .rx_clk(rx_clk),
    .rx_rst(rx_rst),

    /*
     * Transmit interface (AXI stream)
     */
    .s_axis_tx(axis_tx_int),
    .m_axis_tx_cpl(axis_tx_cpl_int),

    /*
     * Receive interface (AXI stream)
     */
    .m_axis_rx(axis_rx_int),

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
     * PTP
     */
    .ptp_clk(ptp_clk),
    .ptp_rst(ptp_rst),
    .ptp_sample_clk(ptp_sample_clk),
    .ptp_td_sdi(ptp_td_sdi),
    .tx_ptp_ts_in(tx_ptp_ts_int),
    .tx_ptp_ts_out(tx_ptp_ts_out),
    .tx_ptp_ts_step_out(tx_ptp_ts_step_int),
    .tx_ptp_locked(tx_ptp_locked_int),
    .rx_ptp_ts_in(rx_ptp_ts_int),
    .rx_ptp_ts_out(rx_ptp_ts_out),
    .rx_ptp_ts_step_out(rx_ptp_ts_step_int),
    .rx_ptp_locked(rx_ptp_locked_int),

    /*
     * Link-level Flow Control (LFC) (IEEE 802.3 annex 31B PAUSE)
     */
    .tx_lfc_req(0),
    .tx_lfc_resend(0),
    .rx_lfc_en(0),
    .rx_lfc_req(),
    .rx_lfc_ack(0),

    /*
     * Priority Flow Control (PFC) (IEEE 802.3 annex 31D PFC)
     */
    .tx_pfc_req(0),
    .tx_pfc_resend(0),
    .rx_pfc_en(0),
    .rx_pfc_req(),
    .rx_pfc_ack(0),

    /*
     * Pause interface
     */
    .tx_lfc_pause_en(0),
    .tx_pause_req(0),
    .tx_pause_ack(),

    /*
     * Statistics
     */
    .stat_clk(stat_clk),
    .stat_rst(stat_rst),
    .m_axis_stat(m_axis_stat),

    /*
     * Status
     */
    .tx_start_packet(),
    .stat_tx_byte(),
    .stat_tx_pkt_len(),
    .stat_tx_pkt_ucast(),
    .stat_tx_pkt_mcast(),
    .stat_tx_pkt_bcast(),
    .stat_tx_pkt_vlan(),
    .stat_tx_pkt_good(),
    .stat_tx_pkt_bad(),
    .stat_tx_err_oversize(),
    .stat_tx_err_user(),
    .stat_tx_err_underflow(tx_error_underflow_int),
    .rx_start_packet(),
    .stat_rx_byte(),
    .stat_rx_pkt_len(),
    .stat_rx_pkt_fragment(),
    .stat_rx_pkt_jabber(),
    .stat_rx_pkt_ucast(),
    .stat_rx_pkt_mcast(),
    .stat_rx_pkt_bcast(),
    .stat_rx_pkt_vlan(),
    .stat_rx_pkt_good(),
    .stat_rx_pkt_bad(rx_error_bad_frame_int),
    .stat_rx_err_oversize(),
    .stat_rx_err_bad_fcs(rx_error_bad_fcs_int),
    .stat_rx_err_bad_block(),
    .stat_rx_err_framing(),
    .stat_rx_err_preamble(),
    .stat_rx_fifo_drop(stat_rx_fifo_drop),
    .stat_tx_mcf(),
    .stat_rx_mcf(),
    .stat_tx_lfc_pkt(),
    .stat_tx_lfc_xon(),
    .stat_tx_lfc_xoff(),
    .stat_tx_lfc_paused(),
    .stat_tx_pfc_pkt(),
    .stat_tx_pfc_xon(),
    .stat_tx_pfc_xoff(),
    .stat_tx_pfc_paused(),
    .stat_rx_lfc_pkt(),
    .stat_rx_lfc_xon(),
    .stat_rx_lfc_xoff(),
    .stat_rx_lfc_paused(),
    .stat_rx_pfc_pkt(),
    .stat_rx_pfc_xon(),
    .stat_rx_pfc_xoff(),
    .stat_rx_pfc_paused(),

    /*
     * Configuration
     */
    .cfg_tx_max_pkt_len(cfg_tx_max_pkt_len),
    .cfg_tx_ifg(cfg_tx_ifg),
    .cfg_tx_enable(cfg_tx_enable),
    .cfg_rx_max_pkt_len(cfg_rx_max_pkt_len),
    .cfg_rx_enable(cfg_rx_enable),
    .cfg_mcf_rx_eth_dst_mcast('0),
    .cfg_mcf_rx_check_eth_dst_mcast('0),
    .cfg_mcf_rx_eth_dst_ucast('0),
    .cfg_mcf_rx_check_eth_dst_ucast('0),
    .cfg_mcf_rx_eth_src('0),
    .cfg_mcf_rx_check_eth_src('0),
    .cfg_mcf_rx_eth_type('0),
    .cfg_mcf_rx_opcode_lfc('0),
    .cfg_mcf_rx_check_opcode_lfc('0),
    .cfg_mcf_rx_opcode_pfc('0),
    .cfg_mcf_rx_check_opcode_pfc('0),
    .cfg_mcf_rx_forward('0),
    .cfg_mcf_rx_enable('0),
    .cfg_tx_lfc_eth_dst('0),
    .cfg_tx_lfc_eth_src('0),
    .cfg_tx_lfc_eth_type('0),
    .cfg_tx_lfc_opcode('0),
    .cfg_tx_lfc_en('0),
    .cfg_tx_lfc_quanta('0),
    .cfg_tx_lfc_refresh('0),
    .cfg_tx_pfc_eth_dst('0),
    .cfg_tx_pfc_eth_src('0),
    .cfg_tx_pfc_eth_type('0),
    .cfg_tx_pfc_opcode('0),
    .cfg_tx_pfc_en('0),
    .cfg_tx_pfc_quanta('{8{'0}}),
    .cfg_tx_pfc_refresh('{8{'0}}),
    .cfg_rx_lfc_opcode('0),
    .cfg_rx_lfc_en('0),
    .cfg_rx_pfc_opcode('0),
    .cfg_rx_pfc_en('0)
);

taxi_axis_async_fifo_adapter #(
    .DEPTH(TX_FIFO_DEPTH),
    .RAM_PIPELINE(TX_FIFO_RAM_PIPELINE),
    .FRAME_FIFO(TX_FRAME_FIFO),
    .USER_BAD_FRAME_VALUE(1'b1),
    .USER_BAD_FRAME_MASK(1'b1),
    .DROP_OVERSIZE_FRAME(TX_DROP_OVERSIZE_FRAME),
    .DROP_BAD_FRAME(TX_DROP_BAD_FRAME),
    .DROP_WHEN_FULL(TX_DROP_WHEN_FULL)
)
tx_fifo (
    /*
     * AXI4-Stream input (sink)
     */
    .s_clk(logic_clk),
    .s_rst(logic_rst),
    .s_axis(s_axis_tx),

    /*
     * AXI4-Stream output (source)
     */
    .m_clk(tx_clk),
    .m_rst(tx_rst),
    .m_axis(axis_tx_int),

    /*
     * Pause
     */
    .s_pause_req(1'b0),
    .s_pause_ack(),
    .m_pause_req(1'b0),
    .m_pause_ack(),

    /*
     * Status
     */
    .s_status_depth(),
    .s_status_depth_commit(),
    .s_status_overflow(tx_fifo_overflow),
    .s_status_bad_frame(tx_fifo_bad_frame),
    .s_status_good_frame(tx_fifo_good_frame),
    .m_status_depth(),
    .m_status_depth_commit(),
    .m_status_overflow(),
    .m_status_bad_frame(),
    .m_status_good_frame()
);

taxi_axis_async_fifo #(
    .DEPTH(TX_CPL_FIFO_DEPTH),
    .FRAME_FIFO(1'b0)
)
tx_cpl_fifo (
    /*
     * AXI4-Stream input (sink)
     */
    .s_clk(tx_clk),
    .s_rst(tx_rst),
    .s_axis(axis_tx_cpl_int),

    /*
     * AXI4-Stream output (source)
     */
    .m_clk(logic_clk),
    .m_rst(logic_rst),
    .m_axis(m_axis_tx_cpl),

    /*
     * Pause
     */
    .s_pause_req(1'b0),
    .s_pause_ack(),
    .m_pause_req(1'b0),
    .m_pause_ack(),

    /*
     * Status
     */
    .s_status_depth(),
    .s_status_depth_commit(),
    .s_status_overflow(),
    .s_status_bad_frame(),
    .s_status_good_frame(),
    .m_status_depth(),
    .m_status_depth_commit(),
    .m_status_overflow(),
    .m_status_bad_frame(),
    .m_status_good_frame()
);

taxi_axis_async_fifo_adapter #(
    .DEPTH(RX_FIFO_DEPTH),
    .RAM_PIPELINE(RX_FIFO_RAM_PIPELINE),
    .FRAME_FIFO(RX_FRAME_FIFO),
    .USER_BAD_FRAME_VALUE(1'b1),
    .USER_BAD_FRAME_MASK(1'b1),
    .DROP_OVERSIZE_FRAME(RX_DROP_OVERSIZE_FRAME),
    .DROP_BAD_FRAME(RX_DROP_BAD_FRAME),
    .DROP_WHEN_FULL(RX_DROP_WHEN_FULL)
)
rx_fifo (
    /*
     * AXI4-Stream input (sink)
     */
    .s_clk(rx_clk),
    .s_rst(rx_rst),
    .s_axis(axis_rx_int),

    /*
     * AXI4-Stream output (source)
     */
    .m_clk(logic_clk),
    .m_rst(logic_rst),
    .m_axis(m_axis_rx),

    /*
     * Pause
     */
    .s_pause_req(1'b0),
    .s_pause_ack(),
    .m_pause_req(1'b0),
    .m_pause_ack(),

    /*
     * Status
     */
    .s_status_depth(),
    .s_status_depth_commit(),
    .s_status_overflow(stat_rx_fifo_drop),
    .s_status_bad_frame(),
    .s_status_good_frame(),
    .m_status_depth(),
    .m_status_depth_commit(),
    .m_status_overflow(rx_fifo_overflow),
    .m_status_bad_frame(rx_fifo_bad_frame),
    .m_status_good_frame(rx_fifo_good_frame)
);

endmodule

`resetall
