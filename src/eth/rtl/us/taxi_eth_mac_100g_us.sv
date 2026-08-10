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
 * Transceiver and MAC/PHY quad wrapper for UltraScale/UltraScale+
 */
module taxi_eth_mac_100g_us #
(
    parameter logic SIM = 1'b0,
    parameter string VENDOR = "XILINX",
    parameter string FAMILY = "virtexuplus",

    parameter CNT = 4,

    // GT config
    parameter logic CFG_LOW_LATENCY = 0,

    // GT type
    parameter string GT_TYPE = "GTY",

    // PLL parameters
    parameter logic QPLL0_PD = 1'b0,
    parameter logic QPLL1_PD = 1'b1,

    // GT parameters
    // TODO switch to packed arrays; blocked on Verilator bug
    parameter logic [CNT-1:0] GT_TX_PD = '0,
    parameter logic [CNT-1:0] GT_TX_QPLL_SEL = '0,
    parameter logic [CNT-1:0] GT_TX_POLARITY = '0,
    parameter logic [CNT-1:0] GT_TX_ELECIDLE = '0,
    parameter logic [CNT-1:0] GT_TX_INHIBIT = '0,
    parameter logic [CNT-1:0][4:0] GT_TX_DIFFCTRL = '{CNT{5'd16}},
    parameter logic [CNT-1:0][6:0] GT_TX_MAINCURSOR = '{CNT{7'd64}},
    parameter logic [CNT-1:0][4:0] GT_TX_POSTCURSOR = '{CNT{5'd0}},
    parameter logic [CNT-1:0][4:0] GT_TX_PRECURSOR = '{CNT{5'd0}},
    parameter logic [CNT-1:0] GT_RX_PD = '0,
    parameter logic [CNT-1:0] GT_RX_QPLL_SEL = '0,
    parameter logic [CNT-1:0] GT_RX_LPM_EN = '1,
    parameter logic [CNT-1:0] GT_RX_POLARITY = '0,

    // MAC/PHY parameters
    parameter logic PTP_TS_EN = 1'b0,
    parameter logic PTP_TD_EN = PTP_TS_EN,
    parameter logic PTP_TS_FMT_TOD = 1'b1,
    parameter PTP_TS_W = PTP_TS_FMT_TOD ? 96 : 64,
    parameter PTP_TD_SDI_PIPELINE = 2,
    parameter TX_SERDES_PIPELINE = 1,
    parameter RX_SERDES_PIPELINE = 1,
    parameter logic PFC_EN = 1'b0,
    parameter logic PAUSE_EN = PFC_EN,
    parameter logic STAT_EN = 1'b0,
    parameter STAT_TX_LEVEL = 1,
    parameter STAT_RX_LEVEL = 1,
    parameter STAT_ID_BASE = 0,
    parameter STAT_UPDATE_PERIOD = 1024,
    parameter logic STAT_STR_EN = 1'b0,
    parameter logic [8*8-1:0] STAT_PREFIX_STR = "CMAC"
)
(
    input  wire logic                 xcvr_ctrl_clk,
    input  wire logic                 xcvr_ctrl_rst,

    /*
     * Transceiver control
     */
    taxi_apb_if.slv                   s_apb_ctrl,

    /*
     * Common
     */
    output wire logic                 xcvr_gtpowergood_out,
    input  wire logic                 xcvr_gtrefclk00_in = 1'b0,
    input  wire logic                 xcvr_qpll0pd_in = 1'b0,
    output wire logic                 xcvr_qpll0lock_out,
    output wire logic                 xcvr_qpll0clk_out,
    output wire logic                 xcvr_qpll0refclk_out,
    input  wire logic                 xcvr_gtrefclk01_in = 1'b0,
    input  wire logic                 xcvr_qpll1pd_in = 1'b0,
    output wire logic                 xcvr_qpll1lock_out,
    output wire logic                 xcvr_qpll1clk_out,
    output wire logic                 xcvr_qpll1refclk_out,

    /*
     * Serial data
     */
    output wire logic                 xcvr_txp[CNT],
    output wire logic                 xcvr_txn[CNT],
    input  wire logic                 xcvr_rxp[CNT],
    input  wire logic                 xcvr_rxn[CNT],

    /*
     * MAC clocks
     */
    output wire logic                 rx_clk[CNT],
    input  wire logic                 rx_rst_in[CNT] = '{CNT{1'b0}},
    output wire logic                 rx_rst_out[CNT],
    output wire logic                 tx_clk[CNT],
    input  wire logic                 tx_rst_in[CNT] = '{CNT{1'b0}},
    output wire logic                 tx_rst_out[CNT],

    /*
     * Transmit interface (AXI stream)
     */
    taxi_axis_if.snk                  s_axis_tx,
    taxi_axis_if.src                  m_axis_tx_cpl,

    /*
     * Receive interface (AXI stream)
     */
    taxi_axis_if.src                  m_axis_rx,

    /*
     * PTP clock
     */
    input  wire logic                 ptp_clk = 1'b0,
    input  wire logic                 ptp_rst = 1'b0,
    input  wire logic                 ptp_sample_clk = 1'b0,
    input  wire logic                 ptp_td_sdi = 1'b0,
    input  wire logic [PTP_TS_W-1:0]  tx_ptp_ts_in = '0,
    output wire logic [PTP_TS_W-1:0]  tx_ptp_ts_out,
    output wire logic                 tx_ptp_ts_step_out,
    output wire logic                 tx_ptp_locked,
    input  wire logic [PTP_TS_W-1:0]  rx_ptp_ts_in = '0,
    output wire logic [PTP_TS_W-1:0]  rx_ptp_ts_out,
    output wire logic                 rx_ptp_ts_step_out,
    output wire logic                 rx_ptp_locked,

    /*
     * Link-level Flow Control (LFC) (IEEE 802.3 annex 31B PAUSE)
     */
    input  wire logic                 tx_lfc_req = 1'b0,
    input  wire logic                 tx_lfc_resend = 1'b0,
    input  wire logic                 rx_lfc_en = 1'b0,
    output wire logic                 rx_lfc_req,
    input  wire logic                 rx_lfc_ack = 1'b0,

    /*
     * Priority Flow Control (PFC) (IEEE 802.3 annex 31D PFC)
     */
    input  wire logic [7:0]           tx_pfc_req = '0,
    input  wire logic                 tx_pfc_resend = 1'b0,
    input  wire logic [7:0]           rx_pfc_en = '0,
    output wire logic [7:0]           rx_pfc_req,
    input  wire logic [7:0]           rx_pfc_ack = '0,

    /*
     * Pause interface
     */
    input  wire logic                 tx_lfc_pause_en = 1'b0,
    input  wire logic                 tx_pause_req = 1'b0,
    output wire logic                 tx_pause_ack,

    /*
     * Statistics
     */
    input  wire logic                 stat_clk,
    input  wire logic                 stat_rst,
    taxi_axis_if.src                  m_axis_stat,

    /*
     * Status
     */
    output wire logic [1:0]           tx_start_packet,
    output wire logic [6:0]           stat_tx_byte,
    output wire logic [15:0]          stat_tx_pkt_len,
    output wire logic                 stat_tx_pkt_ucast,
    output wire logic                 stat_tx_pkt_mcast,
    output wire logic                 stat_tx_pkt_bcast,
    output wire logic                 stat_tx_pkt_vlan,
    output wire logic                 stat_tx_pkt_good,
    output wire logic                 stat_tx_pkt_bad,
    output wire logic                 stat_tx_pad_frame,
    output wire logic                 stat_tx_err_oversize,
    output wire logic                 stat_tx_err_user,
    output wire logic                 stat_tx_err_underflow,
    output wire logic [1:0]           rx_start_packet,
    output wire logic [6:0]           rx_error_count,
    output wire logic                 rx_block_lock,
    output wire logic                 rx_high_ber,
    output wire logic                 rx_status,
    output wire logic [6:0]           stat_rx_byte,
    output wire logic [15:0]          stat_rx_pkt_len,
    output wire logic                 stat_rx_pkt_fragment,
    output wire logic                 stat_rx_pkt_jabber,
    output wire logic                 stat_rx_pkt_ucast,
    output wire logic                 stat_rx_pkt_mcast,
    output wire logic                 stat_rx_pkt_bcast,
    output wire logic                 stat_rx_pkt_vlan,
    output wire logic                 stat_rx_pkt_good,
    output wire logic                 stat_rx_pkt_bad,
    output wire logic                 stat_rx_err_oversize,
    output wire logic                 stat_rx_err_bad_fcs,
    output wire logic                 stat_rx_err_bad_block,
    output wire logic                 stat_rx_err_framing,
    output wire logic                 stat_rx_err_preamble,
    input  wire logic                 stat_rx_fifo_drop = 1'b0,
    output wire logic                 stat_tx_mcf,
    output wire logic                 stat_rx_mcf,
    output wire logic                 stat_tx_lfc_pkt,
    output wire logic                 stat_tx_lfc_xon,
    output wire logic                 stat_tx_lfc_xoff,
    output wire logic                 stat_tx_lfc_paused,
    output wire logic                 stat_tx_pfc_pkt,
    output wire logic [7:0]           stat_tx_pfc_xon,
    output wire logic [7:0]           stat_tx_pfc_xoff,
    output wire logic [7:0]           stat_tx_pfc_paused,
    output wire logic                 stat_rx_lfc_pkt,
    output wire logic                 stat_rx_lfc_xon,
    output wire logic                 stat_rx_lfc_xoff,
    output wire logic                 stat_rx_lfc_paused,
    output wire logic                 stat_rx_pfc_pkt,
    output wire logic [7:0]           stat_rx_pfc_xon,
    output wire logic [7:0]           stat_rx_pfc_xoff,
    output wire logic [7:0]           stat_rx_pfc_paused,

    /*
     * Configuration
     */
    input  wire logic                 cfg_tx_pad_en = 1'b1,
    input  wire logic [7:0]           cfg_tx_min_pkt_len = 8'd60-1,
    input  wire logic [15:0]          cfg_tx_max_pkt_len = 16'd1518-1,
    input  wire logic [7:0]           cfg_tx_ifg = 8'd12,
    input  wire logic                 cfg_tx_enable = 1'b1,
    input  wire logic [15:0]          cfg_rx_max_pkt_len = 16'd1518-1,
    input  wire logic                 cfg_rx_enable = 1'b1,
    input  wire logic                 cfg_tx_prbs31_enable = 1'b0,
    input  wire logic                 cfg_rx_prbs31_enable = 1'b0,
    input  wire logic [47:0]          cfg_mcf_rx_eth_dst_mcast = 48'h01_80_C2_00_00_01,
    input  wire logic                 cfg_mcf_rx_check_eth_dst_mcast = 1'b1,
    input  wire logic [47:0]          cfg_mcf_rx_eth_dst_ucast = 48'd0,
    input  wire logic                 cfg_mcf_rx_check_eth_dst_ucast = 1'b0,
    input  wire logic [47:0]          cfg_mcf_rx_eth_src = 48'd0,
    input  wire logic                 cfg_mcf_rx_check_eth_src = 1'b0,
    input  wire logic [15:0]          cfg_mcf_rx_eth_type = 16'h8808,
    input  wire logic [15:0]          cfg_mcf_rx_opcode_lfc = 16'h0001,
    input  wire logic                 cfg_mcf_rx_check_opcode_lfc = 1'b1,
    input  wire logic [15:0]          cfg_mcf_rx_opcode_pfc = 16'h0101,
    input  wire logic                 cfg_mcf_rx_check_opcode_pfc = 1'b1,
    input  wire logic                 cfg_mcf_rx_forward = 1'b0,
    input  wire logic                 cfg_mcf_rx_enable = 1'b0,
    input  wire logic [47:0]          cfg_tx_lfc_eth_dst = 48'h01_80_C2_00_00_01,
    input  wire logic [47:0]          cfg_tx_lfc_eth_src = 48'h80_23_31_43_54_4C,
    input  wire logic [15:0]          cfg_tx_lfc_eth_type = 16'h8808,
    input  wire logic [15:0]          cfg_tx_lfc_opcode = 16'h0001,
    input  wire logic                 cfg_tx_lfc_en = 1'b0,
    input  wire logic [15:0]          cfg_tx_lfc_quanta = 16'hffff,
    input  wire logic [15:0]          cfg_tx_lfc_refresh = 16'h7fff,
    input  wire logic [47:0]          cfg_tx_pfc_eth_dst = 48'h01_80_C2_00_00_01,
    input  wire logic [47:0]          cfg_tx_pfc_eth_src = 48'h80_23_31_43_54_4C,
    input  wire logic [15:0]          cfg_tx_pfc_eth_type = 16'h8808,
    input  wire logic [15:0]          cfg_tx_pfc_opcode = 16'h0101,
    input  wire logic                 cfg_tx_pfc_en = 1'b0,
    input  wire logic [15:0]          cfg_tx_pfc_quanta[8] = '{8{16'hffff}},
    input  wire logic [15:0]          cfg_tx_pfc_refresh[8] = '{8{16'h7fff}},
    input  wire logic [15:0]          cfg_rx_lfc_opcode = 16'h0001,
    input  wire logic                 cfg_rx_lfc_en = 1'b0,
    input  wire logic [15:0]          cfg_rx_pfc_opcode = 16'h0101,
    input  wire logic                 cfg_rx_pfc_en = 1'b0
);

localparam GT_USP = FAMILY == "kintexuplus" || FAMILY == "virtexuplus" || FAMILY == "virtexuplusHBM"
    || FAMILY == "virtexuplus58G" || FAMILY == "zynquplus" || FAMILY == "zynquplusRFSOC" || FAMILY == "artixuplus";

localparam DATA_W = s_axis_tx.DATA_W;
localparam KEEP_W = s_axis_tx.KEEP_W;
localparam TX_USER_W = 1;
localparam RX_USER_W = (PTP_TS_EN ? PTP_TS_W : 0) + 1;
localparam TX_TAG_W = s_axis_tx.ID_W;

// check configuration
if (DATA_W != 512)
    $fatal(0, "Error: Interface width must be 512 (instance %m)");

if (KEEP_W*8 != DATA_W)
    $fatal(0, "Error: Interface requires byte (8-bit) granularity (instance %m)");

wire xcvr_ctrl_rst_sync;

taxi_sync_reset #(
    .N(4)
)
reset_sync_inst (
    .clk(xcvr_ctrl_clk),
    .rst(xcvr_ctrl_rst),
    .out(xcvr_ctrl_rst_sync)
);

// transceiver control
taxi_apb_if #(
    .ADDR_W(16),
    .DATA_W(16)
)
ch_apb_ctrl[CNT]();

taxi_apb_interconnect_1s #(
    .M_CNT(CNT),
    .ADDR_W(s_apb_ctrl.ADDR_W),
    .M_REGIONS(1),
    .M_BASE_ADDR('0),
    .M_ADDR_W({CNT{{1{32'd16}}}})
)
ctrl_intercon_inst (
    .clk(xcvr_ctrl_clk),
    .rst(xcvr_ctrl_rst_sync),

    /*
     * APB slave interface
     */
    .s_apb(s_apb_ctrl),

    /*
     * APB master interface
     */
    .m_apb(ch_apb_ctrl)
);

// statistics
localparam STAT_TX_CNT = STAT_TX_LEVEL == 0 ? 8 : (STAT_TX_LEVEL == 1 ? 16: 32);
localparam STAT_RX_CNT = STAT_RX_LEVEL == 0 ? 8 : (STAT_RX_LEVEL == 1 ? 16: 32);

wire tx_clk_out[CNT];
wire rx_clk_out[CNT];

assign tx_clk = '{CNT{tx_clk_out[0]}};
assign rx_clk = rx_clk_out;

wire [127:0] serdes_txdata[CNT];
wire [15:0]  serdes_txctrl0[CNT];
wire [15:0]  serdes_txctrl1[CNT];
wire [127:0] serdes_rxdata[CNT];
wire [15:0]  serdes_rxctrl0[CNT];
wire [15:0]  serdes_rxctrl1[CNT];

for (genvar n = 0; n < CNT; n = n + 1) begin : ch

    localparam HAS_COMMON = n == 0;

    wire ch_gtpowergood_out;

    wire ch_qpll0lock_out;
    wire ch_qpll0clk_out;
    wire ch_qpll0refclk_out;
    wire ch_qpll1lock_out;
    wire ch_qpll1clk_out;
    wire ch_qpll1refclk_out;

    if (HAS_COMMON) begin
        // drive outputs from common
        assign xcvr_gtpowergood_out = ch_gtpowergood_out;

        assign xcvr_qpll0lock_out = ch_qpll0lock_out;
        assign xcvr_qpll0clk_out = ch_qpll0clk_out;
        assign xcvr_qpll0refclk_out = ch_qpll0refclk_out;
        assign xcvr_qpll1lock_out = ch_qpll1lock_out;
        assign xcvr_qpll1clk_out = ch_qpll1clk_out;
        assign xcvr_qpll1refclk_out = ch_qpll1refclk_out;
    end

    taxi_eth_mac_100g_us_ch #(
        .SIM(SIM),
        .VENDOR(VENDOR),
        .FAMILY(FAMILY),

        .HAS_COMMON(HAS_COMMON),

        // GT config
        .CFG_LOW_LATENCY(CFG_LOW_LATENCY),

        // GT type
        .GT_TYPE(GT_TYPE),

        // PLL parameters
        .QPLL0_PD(QPLL0_PD),
        .QPLL1_PD(QPLL1_PD),

        // GT parameters
        .GT_TX_PD(GT_TX_PD[n]),
        .GT_TX_QPLL_SEL(GT_TX_QPLL_SEL[n]),
        .GT_TX_POLARITY(GT_TX_POLARITY[n]),
        .GT_TX_ELECIDLE(GT_TX_ELECIDLE[n]),
        .GT_TX_INHIBIT(GT_TX_INHIBIT[n]),
        .GT_TX_DIFFCTRL(GT_TX_DIFFCTRL[n]),
        .GT_TX_MAINCURSOR(GT_TX_MAINCURSOR[n]),
        .GT_TX_POSTCURSOR(GT_TX_POSTCURSOR[n]),
        .GT_TX_PRECURSOR(GT_TX_PRECURSOR[n]),
        .GT_RX_PD(GT_RX_PD[n]),
        .GT_RX_QPLL_SEL(GT_RX_QPLL_SEL[n]),
        .GT_RX_LPM_EN(GT_RX_LPM_EN[n]),
        .GT_RX_POLARITY(GT_RX_POLARITY[n])
    )
    ch_inst (
        .xcvr_ctrl_clk(xcvr_ctrl_clk),
        .xcvr_ctrl_rst(xcvr_ctrl_rst_sync),

        /*
         * Transceiver control
         */
        .s_apb_ctrl(ch_apb_ctrl[n]),

        /*
         * Common
         */
        .xcvr_gtpowergood_out(ch_gtpowergood_out),

        /*
         * PLL out
         */
        .xcvr_gtrefclk00_in(xcvr_gtrefclk00_in),
        .xcvr_qpll0pd_in(xcvr_qpll0pd_in),
        .xcvr_qpll0lock_out(ch_qpll0lock_out),
        .xcvr_qpll0clk_out(ch_qpll0clk_out),
        .xcvr_qpll0refclk_out(ch_qpll0refclk_out),
        .xcvr_gtrefclk01_in(xcvr_gtrefclk01_in),
        .xcvr_qpll1pd_in(xcvr_qpll1pd_in),
        .xcvr_qpll1lock_out(ch_qpll1lock_out),
        .xcvr_qpll1clk_out(ch_qpll1clk_out),
        .xcvr_qpll1refclk_out(ch_qpll1refclk_out),

        /*
         * PLL in
         */
        .xcvr_qpll0lock_in(xcvr_qpll0lock_out),
        .xcvr_qpll0clk_in(xcvr_qpll0clk_out),
        .xcvr_qpll0refclk_in(xcvr_qpll0refclk_out),
        .xcvr_qpll1lock_in(xcvr_qpll1lock_out),
        .xcvr_qpll1clk_in(xcvr_qpll1clk_out),
        .xcvr_qpll1refclk_in(xcvr_qpll1refclk_out),

        /*
         * Serial data
         */
        .xcvr_txp(xcvr_txp[n]),
        .xcvr_txn(xcvr_txn[n]),
        .xcvr_rxp(xcvr_rxp[n]),
        .xcvr_rxn(xcvr_rxn[n]),

        /*
         * MAC clocks
         */
        .rx_clk_out(rx_clk_out[n]),
        .rx_clk_in(rx_clk[n]),
        .rx_rst_in(rx_rst_in[n]),
        .rx_rst_out(rx_rst_out[n]),
        .tx_clk_out(tx_clk_out[n]),
        .tx_clk_in(tx_clk[n]),
        .tx_rst_in(tx_rst_in[n]),
        .tx_rst_out(tx_rst_out[n]),

        /*
         * Serdes interface
         */
        .serdes_txdata(serdes_txdata[n]),
        .serdes_txctrl0(serdes_txctrl0[n]),
        .serdes_txctrl1(serdes_txctrl1[n]),
        .serdes_rxdata(serdes_rxdata[n]),
        .serdes_rxctrl0(serdes_rxctrl0[n]),
        .serdes_rxctrl1(serdes_rxctrl1[n])
    );

end

wire [511:0] cmac_txdata;
wire [63:0]  cmac_txctrl0;
wire [63:0]  cmac_txctrl1;
wire [511:0] cmac_rxdata;
wire [63:0]  cmac_rxctrl0;
wire [63:0]  cmac_rxctrl1;

for (genvar n = 0; n < 4; n = n + 1) begin
    assign serdes_txdata[n] = cmac_txdata[n*128 +: 128];
    assign serdes_txctrl0[n] = cmac_txctrl0[n*16 +: 16];
    assign serdes_txctrl1[n] = cmac_txctrl1[n*16 +: 16];
    assign cmac_rxdata[n*128 +: 128] = serdes_rxdata[n];
    assign cmac_rxctrl0[n*16 +: 16] = serdes_rxctrl0[n];
    assign cmac_rxctrl1[n*16 +: 16] = serdes_rxctrl1[n];
end

taxi_axis_if #(.DATA_W(DATA_W), .KEEP_W(KEEP_W), .USER_EN(1), .USER_W(TX_USER_W), .ID_EN(1), .ID_W(TX_TAG_W)) axis_tx_pad();

taxi_axis_pad #(
    .ID_PAD_REG_EN(1'b0),
    .DEST_PAD_REG_EN(1'b0),
    .USER_PAD_REG_EN(1'b1),
    .MIN_LEN_W(8),
    .UNDERFLOW_DROP_EN(1'b1)
)
tx_pad_inst (
    .clk(tx_clk[0]),
    .rst(tx_rst_out[0]),

    /*
     * AXI4-Stream input (sink)
     */
    .s_axis(s_axis_tx),

    /*
     * AXI4-Stream output (source)
     */
    .m_axis(axis_tx_pad),

    /*
     * Configuration
     */
    .cfg_pad_en(cfg_tx_pad_en),
    .cfg_min_pkt_len(cfg_tx_min_pkt_len),

    /*
     * Status
     */
    .stat_pad_frame(stat_tx_pad_frame),
    .stat_err_user(),
    .stat_err_underflow(stat_tx_err_underflow)
);

if (SIM) begin : cmac
    // simulation (no CMAC)

    taxi_axis_if #(.DATA_W(DATA_W), .KEEP_W(KEEP_W), .USER_EN(1), .USER_W(TX_USER_W), .ID_EN(1), .ID_W(TX_TAG_W)) cmac_axis_tx();
    taxi_axis_if #(.DATA_W(DATA_W), .KEEP_W(KEEP_W), .USER_EN(1), .USER_W(RX_USER_W)) cmac_axis_rx();

    taxi_axis_tie
    tx_tie_inst (
        .s_axis(axis_tx_pad),
        .m_axis(cmac_axis_tx)
    );

    taxi_axis_tie
    rx_tie_inst (
        .s_axis(cmac_axis_rx),
        .m_axis(m_axis_rx)
    );

    assign rx_status = !rx_rst_out[0];

end else if (GT_USP) begin : cmac
    // UltraScale+ CMACE4

    taxi_eth_mac_100g_us_cmac cmac_inst (
        .txdata_in(cmac_txdata),
        .txctrl0_in(cmac_txctrl0),
        .txctrl1_in(cmac_txctrl1),
        .rxdata_out(cmac_rxdata),
        .rxctrl0_out(cmac_rxctrl0),
        .rxctrl1_out(cmac_rxctrl1),

        .ctl_tx_rsfec_enable(1'b1),//
        .ctl_rx_rsfec_enable(1'b1),
        .ctl_rsfec_ieee_error_indication_mode(1'b0),
        .ctl_rx_rsfec_enable_correction(1'b1),
        .ctl_rx_rsfec_enable_indication(1'b1),

        .stat_rx_rsfec_am_lock0(),
        .stat_rx_rsfec_am_lock1(),
        .stat_rx_rsfec_am_lock2(),
        .stat_rx_rsfec_am_lock3(),
        .stat_rx_rsfec_err_count0_inc(),
        .stat_rx_rsfec_err_count1_inc(),
        .stat_rx_rsfec_err_count2_inc(),
        .stat_rx_rsfec_err_count3_inc(),
        .stat_rx_rsfec_hi_ser(),
        .stat_rx_rsfec_lane_alignment_status(),
        .stat_rx_rsfec_lane_fill_0(),
        .stat_rx_rsfec_lane_fill_1(),
        .stat_rx_rsfec_lane_fill_2(),
        .stat_rx_rsfec_lane_fill_3(),
        .stat_rx_rsfec_lane_mapping(),
        .stat_rx_rsfec_cw_inc(),
        .stat_rx_rsfec_corrected_cw_inc(),
        .stat_rx_rsfec_uncorrected_cw_inc(),

        .rx_axis_tvalid(m_axis_rx.tvalid),
        .rx_axis_tdata(m_axis_rx.tdata),
        .rx_axis_tlast(m_axis_rx.tlast),
        .rx_axis_tkeep(m_axis_rx.tkeep),
        .rx_axis_tuser(m_axis_rx.tuser),

        .rx_otn_bip8_0(),
        .rx_otn_bip8_1(),
        .rx_otn_bip8_2(),
        .rx_otn_bip8_3(),
        .rx_otn_bip8_4(),
        .rx_otn_data_0(),
        .rx_otn_data_1(),
        .rx_otn_data_2(),
        .rx_otn_data_3(),
        .rx_otn_data_4(),
        .rx_otn_ena(),
        .rx_otn_lane0(),
        .rx_otn_vlmarker(),

        .rx_preambleout(),

        .rx_lane_aligner_fill_0(),
        .rx_lane_aligner_fill_1(),
        .rx_lane_aligner_fill_2(),
        .rx_lane_aligner_fill_3(),
        .rx_lane_aligner_fill_4(),
        .rx_lane_aligner_fill_5(),
        .rx_lane_aligner_fill_6(),
        .rx_lane_aligner_fill_7(),
        .rx_lane_aligner_fill_8(),
        .rx_lane_aligner_fill_9(),
        .rx_lane_aligner_fill_10(),
        .rx_lane_aligner_fill_11(),
        .rx_lane_aligner_fill_12(),
        .rx_lane_aligner_fill_13(),
        .rx_lane_aligner_fill_14(),
        .rx_lane_aligner_fill_15(),
        .rx_lane_aligner_fill_16(),
        .rx_lane_aligner_fill_17(),
        .rx_lane_aligner_fill_18(),
        .rx_lane_aligner_fill_19(),

        .rx_ptp_tstamp_out(),//
        .rx_ptp_pcslane_out(),
        .ctl_rx_systemtimerin('0),

        .stat_rx_pause(stat_rx_lfc_pkt),
        .stat_rx_pause_quanta0(),
        .stat_rx_pause_quanta1(),
        .stat_rx_pause_quanta2(),
        .stat_rx_pause_quanta3(),
        .stat_rx_pause_quanta4(),
        .stat_rx_pause_quanta5(),
        .stat_rx_pause_quanta6(),
        .stat_rx_pause_quanta7(),
        .stat_rx_pause_quanta8(),
        .stat_rx_pause_req({rx_lfc_req, rx_pfc_req}),
        .stat_rx_pause_valid(),
        .stat_rx_user_pause(stat_rx_pfc_pkt),

        .ctl_rx_check_etype_gcp(1'b1),
        .ctl_rx_check_etype_gpp(1'b1),
        .ctl_rx_check_etype_pcp(1'b1),
        .ctl_rx_check_etype_ppp(1'b1),
        .ctl_rx_check_mcast_gcp(cfg_mcf_rx_check_eth_dst_mcast),
        .ctl_rx_check_mcast_gpp(cfg_mcf_rx_check_eth_dst_mcast),
        .ctl_rx_check_mcast_pcp(cfg_mcf_rx_check_eth_dst_mcast),
        .ctl_rx_check_mcast_ppp(cfg_mcf_rx_check_eth_dst_mcast),
        .ctl_rx_check_opcode_gcp(cfg_mcf_rx_check_opcode_lfc),
        .ctl_rx_check_opcode_gpp(cfg_mcf_rx_check_opcode_lfc),
        .ctl_rx_check_opcode_pcp(cfg_mcf_rx_check_opcode_pfc),
        .ctl_rx_check_opcode_ppp(cfg_mcf_rx_check_opcode_pfc),
        .ctl_rx_check_sa_gcp(cfg_mcf_rx_check_eth_src),
        .ctl_rx_check_sa_gpp(cfg_mcf_rx_check_eth_src),
        .ctl_rx_check_sa_pcp(cfg_mcf_rx_check_eth_src),
        .ctl_rx_check_sa_ppp(cfg_mcf_rx_check_eth_src),
        .ctl_rx_check_ucast_gcp(cfg_mcf_rx_check_eth_dst_ucast),
        .ctl_rx_check_ucast_gpp(cfg_mcf_rx_check_eth_dst_ucast),
        .ctl_rx_check_ucast_pcp(cfg_mcf_rx_check_eth_dst_ucast),
        .ctl_rx_check_ucast_ppp(cfg_mcf_rx_check_eth_dst_ucast),
        .ctl_rx_enable_gcp(cfg_rx_lfc_en && PAUSE_EN),
        .ctl_rx_enable_gpp(cfg_rx_lfc_en && PAUSE_EN),
        .ctl_rx_enable_pcp(cfg_rx_pfc_en != 0 && PFC_EN),
        .ctl_rx_enable_ppp(cfg_rx_pfc_en != 0 && PFC_EN),
        .ctl_rx_pause_ack({rx_lfc_ack, rx_pfc_ack}),
        .ctl_rx_pause_enable({rx_lfc_en & PAUSE_EN, rx_pfc_en & {8{PFC_EN}}}),

        .ctl_rx_enable(cfg_rx_enable),
        .ctl_rx_force_resync('0),
        .ctl_rx_test_pattern('0),

        .rx_clk(rx_clk[0]),

        .stat_rx_aligned(),
        .stat_rx_aligned_err(),
        .stat_rx_bad_code(),
        .stat_rx_bad_fcs(),
        .stat_rx_bad_preamble(),
        .stat_rx_bad_sfd(),
        .stat_rx_bip_err_0(),
        .stat_rx_bip_err_1(),
        .stat_rx_bip_err_2(),
        .stat_rx_bip_err_3(),
        .stat_rx_bip_err_4(),
        .stat_rx_bip_err_5(),
        .stat_rx_bip_err_6(),
        .stat_rx_bip_err_7(),
        .stat_rx_bip_err_8(),
        .stat_rx_bip_err_9(),
        .stat_rx_bip_err_10(),
        .stat_rx_bip_err_11(),
        .stat_rx_bip_err_12(),
        .stat_rx_bip_err_13(),
        .stat_rx_bip_err_14(),
        .stat_rx_bip_err_15(),
        .stat_rx_bip_err_16(),
        .stat_rx_bip_err_17(),
        .stat_rx_bip_err_18(),
        .stat_rx_bip_err_19(),
        .stat_rx_block_lock(rx_block_lock),
        .stat_rx_broadcast(stat_rx_pkt_bcast),
        .stat_rx_fragment(stat_rx_pkt_fragment),
        .stat_rx_framing_err_0(),
        .stat_rx_framing_err_1(),
        .stat_rx_framing_err_2(),
        .stat_rx_framing_err_3(),
        .stat_rx_framing_err_4(),
        .stat_rx_framing_err_5(),
        .stat_rx_framing_err_6(),
        .stat_rx_framing_err_7(),
        .stat_rx_framing_err_8(),
        .stat_rx_framing_err_9(),
        .stat_rx_framing_err_10(),
        .stat_rx_framing_err_11(),
        .stat_rx_framing_err_12(),
        .stat_rx_framing_err_13(),
        .stat_rx_framing_err_14(),
        .stat_rx_framing_err_15(),
        .stat_rx_framing_err_16(),
        .stat_rx_framing_err_17(),
        .stat_rx_framing_err_18(),
        .stat_rx_framing_err_19(),
        .stat_rx_framing_err_valid_0(),
        .stat_rx_framing_err_valid_1(),
        .stat_rx_framing_err_valid_2(),
        .stat_rx_framing_err_valid_3(),
        .stat_rx_framing_err_valid_4(),
        .stat_rx_framing_err_valid_5(),
        .stat_rx_framing_err_valid_6(),
        .stat_rx_framing_err_valid_7(),
        .stat_rx_framing_err_valid_8(),
        .stat_rx_framing_err_valid_9(),
        .stat_rx_framing_err_valid_10(),
        .stat_rx_framing_err_valid_11(),
        .stat_rx_framing_err_valid_12(),
        .stat_rx_framing_err_valid_13(),
        .stat_rx_framing_err_valid_14(),
        .stat_rx_framing_err_valid_15(),
        .stat_rx_framing_err_valid_16(),
        .stat_rx_framing_err_valid_17(),
        .stat_rx_framing_err_valid_18(),
        .stat_rx_framing_err_valid_19(),
        .stat_rx_got_signal_os(),
        .stat_rx_hi_ber(rx_high_ber),
        .stat_rx_inrangeerr(),
        .stat_rx_internal_local_fault(),
        .stat_rx_jabber(stat_rx_pkt_jabber),
        .stat_rx_local_fault(),
        .stat_rx_mf_err(),
        .stat_rx_mf_len_err(),
        .stat_rx_mf_repeat_err(),
        .stat_rx_misaligned(),
        .stat_rx_multicast(stat_rx_pkt_mcast),
        .stat_rx_oversize(stat_rx_err_oversize),
        .stat_rx_packet_64_bytes(),
        .stat_rx_packet_65_127_bytes(),
        .stat_rx_packet_128_255_bytes(),
        .stat_rx_packet_256_511_bytes(),
        .stat_rx_packet_512_1023_bytes(),
        .stat_rx_packet_1024_1518_bytes(),
        .stat_rx_packet_1519_1522_bytes(),
        .stat_rx_packet_1523_1548_bytes(),
        .stat_rx_packet_1549_2047_bytes(),
        .stat_rx_packet_2048_4095_bytes(),
        .stat_rx_packet_4096_8191_bytes(),
        .stat_rx_packet_8192_9215_bytes(),
        .stat_rx_packet_bad_fcs(stat_rx_err_bad_fcs),
        .stat_rx_packet_large(),
        .stat_rx_packet_small(),

        .stat_rx_received_local_fault(),
        .stat_rx_remote_fault(),
        .stat_rx_status(rx_status),
        .stat_rx_stomped_fcs(),
        .stat_rx_synced(),
        .stat_rx_synced_err(),
        .stat_rx_test_pattern_mismatch(),
        .stat_rx_toolong(),
        .stat_rx_total_bytes(stat_rx_byte),
        .stat_rx_total_good_bytes(stat_rx_pkt_len),
        .stat_rx_total_good_packets(stat_rx_pkt_good),
        .stat_rx_total_packets(),
        .stat_rx_truncated(),
        .stat_rx_undersize(),
        .stat_rx_unicast(stat_rx_pkt_ucast),
        .stat_rx_vlan(stat_rx_pkt_vlan),
        .stat_rx_pcsl_demuxed(),
        .stat_rx_pcsl_number_0(),
        .stat_rx_pcsl_number_1(),
        .stat_rx_pcsl_number_2(),
        .stat_rx_pcsl_number_3(),
        .stat_rx_pcsl_number_4(),
        .stat_rx_pcsl_number_5(),
        .stat_rx_pcsl_number_6(),
        .stat_rx_pcsl_number_7(),
        .stat_rx_pcsl_number_8(),
        .stat_rx_pcsl_number_9(),
        .stat_rx_pcsl_number_10(),
        .stat_rx_pcsl_number_11(),
        .stat_rx_pcsl_number_12(),
        .stat_rx_pcsl_number_13(),
        .stat_rx_pcsl_number_14(),
        .stat_rx_pcsl_number_15(),
        .stat_rx_pcsl_number_16(),
        .stat_rx_pcsl_number_17(),
        .stat_rx_pcsl_number_18(),
        .stat_rx_pcsl_number_19(),

        .ctl_tx_systemtimerin('0),
        .stat_tx_ptp_fifo_read_error(),
        .stat_tx_ptp_fifo_write_error(),
        .tx_ptp_tstamp_valid_out(), //
        .tx_ptp_pcslane_out(),
        .tx_ptp_tstamp_tag_out(), //
        .tx_ptp_tstamp_out(), //
        .tx_ptp_1588op_in(2'b10),
        .tx_ptp_tag_field_in('0), //

        .stat_tx_bad_fcs(),
        .stat_tx_broadcast(stat_tx_pkt_bcast),
        .stat_tx_frame_error(stat_tx_err_user),
        .stat_tx_local_fault(),
        .stat_tx_multicast(stat_tx_pkt_mcast),
        .stat_tx_packet_64_bytes(),
        .stat_tx_packet_65_127_bytes(),
        .stat_tx_packet_128_255_bytes(),
        .stat_tx_packet_256_511_bytes(),
        .stat_tx_packet_512_1023_bytes(),
        .stat_tx_packet_1024_1518_bytes(),
        .stat_tx_packet_1519_1522_bytes(),
        .stat_tx_packet_1523_1548_bytes(),
        .stat_tx_packet_1549_2047_bytes(),
        .stat_tx_packet_2048_4095_bytes(),
        .stat_tx_packet_4096_8191_bytes(),
        .stat_tx_packet_8192_9215_bytes(),
        .stat_tx_packet_large(),
        .stat_tx_packet_small(),
        .stat_tx_total_bytes(stat_tx_byte),
        .stat_tx_total_good_bytes(stat_tx_pkt_len),
        .stat_tx_total_good_packets(stat_tx_pkt_good),
        .stat_tx_total_packets(),
        .stat_tx_unicast(stat_tx_pkt_ucast),
        .stat_tx_vlan(stat_tx_pkt_vlan),

        .ctl_tx_enable(cfg_tx_enable),
        .ctl_tx_send_idle('0),
        .ctl_tx_send_rfi('0),
        .ctl_tx_send_lfi('0),
        .ctl_tx_test_pattern('0),

        .tx_clk(tx_clk[0]),

        .stat_tx_pause_valid(),
        .stat_tx_pause(stat_tx_lfc_pkt),
        .stat_tx_user_pause(stat_tx_pfc_pkt),

        .ctl_tx_pause_enable({cfg_tx_lfc_en & PAUSE_EN, cfg_tx_pfc_en & {8{PFC_EN}}}),
        .ctl_tx_pause_quanta0(cfg_tx_pfc_quanta[0]),
        .ctl_tx_pause_quanta1(cfg_tx_pfc_quanta[1]),
        .ctl_tx_pause_quanta2(cfg_tx_pfc_quanta[2]),
        .ctl_tx_pause_quanta3(cfg_tx_pfc_quanta[3]),
        .ctl_tx_pause_quanta4(cfg_tx_pfc_quanta[4]),
        .ctl_tx_pause_quanta5(cfg_tx_pfc_quanta[5]),
        .ctl_tx_pause_quanta6(cfg_tx_pfc_quanta[6]),
        .ctl_tx_pause_quanta7(cfg_tx_pfc_quanta[7]),
        .ctl_tx_pause_quanta8(cfg_tx_lfc_quanta),
        .ctl_tx_pause_refresh_timer0(cfg_tx_pfc_refresh[0]),
        .ctl_tx_pause_refresh_timer1(cfg_tx_pfc_refresh[1]),
        .ctl_tx_pause_refresh_timer2(cfg_tx_pfc_refresh[2]),
        .ctl_tx_pause_refresh_timer3(cfg_tx_pfc_refresh[3]),
        .ctl_tx_pause_refresh_timer4(cfg_tx_pfc_refresh[4]),
        .ctl_tx_pause_refresh_timer5(cfg_tx_pfc_refresh[5]),
        .ctl_tx_pause_refresh_timer6(cfg_tx_pfc_refresh[6]),
        .ctl_tx_pause_refresh_timer7(cfg_tx_pfc_refresh[7]),
        .ctl_tx_pause_refresh_timer8(cfg_tx_lfc_refresh),
        .ctl_tx_pause_req({tx_lfc_req, tx_pfc_req}),
        .ctl_tx_resend_pause(tx_lfc_resend | tx_pfc_resend),

        .tx_axis_tready(axis_tx_pad.tready),
        .tx_axis_tvalid(axis_tx_pad.tvalid),
        .tx_axis_tdata(axis_tx_pad.tdata),
        .tx_axis_tlast(axis_tx_pad.tlast),
        .tx_axis_tkeep(axis_tx_pad.tkeep),
        .tx_axis_tuser(axis_tx_pad.tuser[0]),

        .tx_ovfout(),
        .tx_unfout(),
        .tx_preamblein(56'd0),

        .tx_reset_done(tx_rst_out[0]),
        .rx_reset_done(rx_rst_out[0]),

        .rx_serdes_reset_done({6'h3f, rx_rst_out[3], rx_rst_out[2], rx_rst_out[1], rx_rst_out[0]}),
        .rx_serdes_clk_in({6'd0, rx_clk[3], rx_clk[2], rx_clk[1], rx_clk[0]}),

        .drp_clk('0),
        .drp_addr('0),
        .drp_di('0),
        .drp_en('0),
        .drp_we('0),
        .drp_do(),
        .drp_rdy()
    );

end else begin
    // UltraScale CMACE3

    taxi_eth_mac_100g_us_cmac cmac_inst (
        .txdata_in(cmac_txdata),
        .txctrl0_in(cmac_txctrl0),
        .txctrl1_in(cmac_txctrl1),
        .rxdata_out(cmac_rxdata),
        .rxctrl0_out(cmac_rxctrl0),
        .rxctrl1_out(cmac_rxctrl1),

        .rx_axis_tvalid(m_axis_rx.tvalid),
        .rx_axis_tdata(m_axis_rx.tdata),
        .rx_axis_tlast(m_axis_rx.tlast),
        .rx_axis_tkeep(m_axis_rx.tkeep),
        .rx_axis_tuser(m_axis_rx.tuser),

        .rx_lane_aligner_fill_0(),
        .rx_lane_aligner_fill_1(),
        .rx_lane_aligner_fill_2(),
        .rx_lane_aligner_fill_3(),
        .rx_lane_aligner_fill_4(),
        .rx_lane_aligner_fill_5(),
        .rx_lane_aligner_fill_6(),
        .rx_lane_aligner_fill_7(),
        .rx_lane_aligner_fill_8(),
        .rx_lane_aligner_fill_9(),
        .rx_lane_aligner_fill_10(),
        .rx_lane_aligner_fill_11(),
        .rx_lane_aligner_fill_12(),
        .rx_lane_aligner_fill_13(),
        .rx_lane_aligner_fill_14(),
        .rx_lane_aligner_fill_15(),
        .rx_lane_aligner_fill_16(),
        .rx_lane_aligner_fill_17(),
        .rx_lane_aligner_fill_18(),
        .rx_lane_aligner_fill_19(),

        .rx_ptp_tstamp_out(),//
        .rx_ptp_pcslane_out(),
        .ctl_rx_systemtimerin('0),

        .stat_rx_pause(stat_rx_lfc_pkt),
        .stat_rx_pause_quanta0(),
        .stat_rx_pause_quanta1(),
        .stat_rx_pause_quanta2(),
        .stat_rx_pause_quanta3(),
        .stat_rx_pause_quanta4(),
        .stat_rx_pause_quanta5(),
        .stat_rx_pause_quanta6(),
        .stat_rx_pause_quanta7(),
        .stat_rx_pause_quanta8(),
        .stat_rx_pause_req({rx_lfc_req, rx_pfc_req}),
        .stat_rx_pause_valid(),
        .stat_rx_user_pause(stat_rx_pfc_pkt),

        .ctl_rx_check_etype_gcp(1'b1),
        .ctl_rx_check_etype_gpp(1'b1),
        .ctl_rx_check_etype_pcp(1'b1),
        .ctl_rx_check_etype_ppp(1'b1),
        .ctl_rx_check_mcast_gcp(cfg_mcf_rx_check_eth_dst_mcast),
        .ctl_rx_check_mcast_gpp(cfg_mcf_rx_check_eth_dst_mcast),
        .ctl_rx_check_mcast_pcp(cfg_mcf_rx_check_eth_dst_mcast),
        .ctl_rx_check_mcast_ppp(cfg_mcf_rx_check_eth_dst_mcast),
        .ctl_rx_check_opcode_gcp(cfg_mcf_rx_check_opcode_lfc),
        .ctl_rx_check_opcode_gpp(cfg_mcf_rx_check_opcode_lfc),
        .ctl_rx_check_opcode_pcp(cfg_mcf_rx_check_opcode_pfc),
        .ctl_rx_check_opcode_ppp(cfg_mcf_rx_check_opcode_pfc),
        .ctl_rx_check_sa_gcp(cfg_mcf_rx_check_eth_src),
        .ctl_rx_check_sa_gpp(cfg_mcf_rx_check_eth_src),
        .ctl_rx_check_sa_pcp(cfg_mcf_rx_check_eth_src),
        .ctl_rx_check_sa_ppp(cfg_mcf_rx_check_eth_src),
        .ctl_rx_check_ucast_gcp(cfg_mcf_rx_check_eth_dst_ucast),
        .ctl_rx_check_ucast_gpp(cfg_mcf_rx_check_eth_dst_ucast),
        .ctl_rx_check_ucast_pcp(cfg_mcf_rx_check_eth_dst_ucast),
        .ctl_rx_check_ucast_ppp(cfg_mcf_rx_check_eth_dst_ucast),
        .ctl_rx_enable_gcp(cfg_rx_lfc_en && PAUSE_EN),
        .ctl_rx_enable_gpp(cfg_rx_lfc_en && PAUSE_EN),
        .ctl_rx_enable_pcp(cfg_rx_pfc_en != 0 && PFC_EN),
        .ctl_rx_enable_ppp(cfg_rx_pfc_en != 0 && PFC_EN),
        .ctl_rx_pause_ack({rx_lfc_ack, rx_pfc_ack}),
        .ctl_rx_pause_enable({rx_lfc_en & PAUSE_EN, rx_pfc_en & {8{PFC_EN}}}),

        .ctl_rx_enable(cfg_rx_enable),
        .ctl_rx_force_resync('0),
        .ctl_rx_test_pattern('0),

        .rx_clk(rx_clk[0]),

        .stat_rx_aligned(),
        .stat_rx_aligned_err(),
        .stat_rx_bad_code(),
        .stat_rx_bad_fcs(),
        .stat_rx_bad_preamble(),
        .stat_rx_bad_sfd(),
        .stat_rx_bip_err_0(),
        .stat_rx_bip_err_1(),
        .stat_rx_bip_err_2(),
        .stat_rx_bip_err_3(),
        .stat_rx_bip_err_4(),
        .stat_rx_bip_err_5(),
        .stat_rx_bip_err_6(),
        .stat_rx_bip_err_7(),
        .stat_rx_bip_err_8(),
        .stat_rx_bip_err_9(),
        .stat_rx_bip_err_10(),
        .stat_rx_bip_err_11(),
        .stat_rx_bip_err_12(),
        .stat_rx_bip_err_13(),
        .stat_rx_bip_err_14(),
        .stat_rx_bip_err_15(),
        .stat_rx_bip_err_16(),
        .stat_rx_bip_err_17(),
        .stat_rx_bip_err_18(),
        .stat_rx_bip_err_19(),
        .stat_rx_block_lock(rx_block_lock),
        .stat_rx_broadcast(stat_rx_pkt_bcast),
        .stat_rx_fragment(stat_rx_pkt_fragment),
        .stat_rx_framing_err_0(),
        .stat_rx_framing_err_1(),
        .stat_rx_framing_err_2(),
        .stat_rx_framing_err_3(),
        .stat_rx_framing_err_4(),
        .stat_rx_framing_err_5(),
        .stat_rx_framing_err_6(),
        .stat_rx_framing_err_7(),
        .stat_rx_framing_err_8(),
        .stat_rx_framing_err_9(),
        .stat_rx_framing_err_10(),
        .stat_rx_framing_err_11(),
        .stat_rx_framing_err_12(),
        .stat_rx_framing_err_13(),
        .stat_rx_framing_err_14(),
        .stat_rx_framing_err_15(),
        .stat_rx_framing_err_16(),
        .stat_rx_framing_err_17(),
        .stat_rx_framing_err_18(),
        .stat_rx_framing_err_19(),
        .stat_rx_framing_err_valid_0(),
        .stat_rx_framing_err_valid_1(),
        .stat_rx_framing_err_valid_2(),
        .stat_rx_framing_err_valid_3(),
        .stat_rx_framing_err_valid_4(),
        .stat_rx_framing_err_valid_5(),
        .stat_rx_framing_err_valid_6(),
        .stat_rx_framing_err_valid_7(),
        .stat_rx_framing_err_valid_8(),
        .stat_rx_framing_err_valid_9(),
        .stat_rx_framing_err_valid_10(),
        .stat_rx_framing_err_valid_11(),
        .stat_rx_framing_err_valid_12(),
        .stat_rx_framing_err_valid_13(),
        .stat_rx_framing_err_valid_14(),
        .stat_rx_framing_err_valid_15(),
        .stat_rx_framing_err_valid_16(),
        .stat_rx_framing_err_valid_17(),
        .stat_rx_framing_err_valid_18(),
        .stat_rx_framing_err_valid_19(),
        .stat_rx_got_signal_os(),
        .stat_rx_hi_ber(rx_high_ber),
        .stat_rx_inrangeerr(),
        .stat_rx_internal_local_fault(),
        .stat_rx_jabber(stat_rx_pkt_jabber),
        .stat_rx_local_fault(),
        .stat_rx_mf_err(),
        .stat_rx_mf_len_err(),
        .stat_rx_mf_repeat_err(),
        .stat_rx_misaligned(),
        .stat_rx_multicast(stat_rx_pkt_mcast),
        .stat_rx_oversize(stat_rx_err_oversize),
        .stat_rx_packet_64_bytes(),
        .stat_rx_packet_65_127_bytes(),
        .stat_rx_packet_128_255_bytes(),
        .stat_rx_packet_256_511_bytes(),
        .stat_rx_packet_512_1023_bytes(),
        .stat_rx_packet_1024_1518_bytes(),
        .stat_rx_packet_1519_1522_bytes(),
        .stat_rx_packet_1523_1548_bytes(),
        .stat_rx_packet_1549_2047_bytes(),
        .stat_rx_packet_2048_4095_bytes(),
        .stat_rx_packet_4096_8191_bytes(),
        .stat_rx_packet_8192_9215_bytes(),
        .stat_rx_packet_bad_fcs(stat_rx_err_bad_fcs),
        .stat_rx_packet_large(),
        .stat_rx_packet_small(),

        .stat_rx_received_local_fault(),
        .stat_rx_remote_fault(),
        .stat_rx_status(rx_status),
        .stat_rx_stomped_fcs(),
        .stat_rx_synced(),
        .stat_rx_synced_err(),
        .stat_rx_test_pattern_mismatch(),
        .stat_rx_toolong(),
        .stat_rx_total_bytes(stat_rx_byte),
        .stat_rx_total_good_bytes(stat_rx_pkt_len),
        .stat_rx_total_good_packets(stat_rx_pkt_good),
        .stat_rx_total_packets(),
        .stat_rx_truncated(),
        .stat_rx_undersize(),
        .stat_rx_unicast(stat_rx_pkt_ucast),
        .stat_rx_vlan(stat_rx_pkt_vlan),
        .stat_rx_pcsl_demuxed(),
        .stat_rx_pcsl_number_0(),
        .stat_rx_pcsl_number_1(),
        .stat_rx_pcsl_number_2(),
        .stat_rx_pcsl_number_3(),
        .stat_rx_pcsl_number_4(),
        .stat_rx_pcsl_number_5(),
        .stat_rx_pcsl_number_6(),
        .stat_rx_pcsl_number_7(),
        .stat_rx_pcsl_number_8(),
        .stat_rx_pcsl_number_9(),
        .stat_rx_pcsl_number_10(),
        .stat_rx_pcsl_number_11(),
        .stat_rx_pcsl_number_12(),
        .stat_rx_pcsl_number_13(),
        .stat_rx_pcsl_number_14(),
        .stat_rx_pcsl_number_15(),
        .stat_rx_pcsl_number_16(),
        .stat_rx_pcsl_number_17(),
        .stat_rx_pcsl_number_18(),
        .stat_rx_pcsl_number_19(),

        .ctl_tx_systemtimerin('0),
        .stat_tx_ptp_fifo_read_error(),
        .stat_tx_ptp_fifo_write_error(),
        .tx_ptp_tstamp_valid_out(), //
        .tx_ptp_pcslane_out(),
        .tx_ptp_tstamp_tag_out(), //
        .tx_ptp_tstamp_out(), //
        .tx_ptp_1588op_in(2'b10),
        .tx_ptp_tag_field_in('0), //

        .stat_tx_bad_fcs(),
        .stat_tx_broadcast(stat_tx_pkt_bcast),
        .stat_tx_frame_error(stat_tx_err_user),
        .stat_tx_local_fault(),
        .stat_tx_multicast(stat_tx_pkt_mcast),
        .stat_tx_packet_64_bytes(),
        .stat_tx_packet_65_127_bytes(),
        .stat_tx_packet_128_255_bytes(),
        .stat_tx_packet_256_511_bytes(),
        .stat_tx_packet_512_1023_bytes(),
        .stat_tx_packet_1024_1518_bytes(),
        .stat_tx_packet_1519_1522_bytes(),
        .stat_tx_packet_1523_1548_bytes(),
        .stat_tx_packet_1549_2047_bytes(),
        .stat_tx_packet_2048_4095_bytes(),
        .stat_tx_packet_4096_8191_bytes(),
        .stat_tx_packet_8192_9215_bytes(),
        .stat_tx_packet_large(),
        .stat_tx_packet_small(),
        .stat_tx_total_bytes(stat_tx_byte),
        .stat_tx_total_good_bytes(stat_tx_pkt_len),
        .stat_tx_total_good_packets(stat_tx_pkt_good),
        .stat_tx_total_packets(),
        .stat_tx_unicast(stat_tx_pkt_ucast),
        .stat_tx_vlan(stat_tx_pkt_vlan),

        .ctl_tx_enable(cfg_tx_enable),
        .ctl_tx_send_idle('0),
        .ctl_tx_send_rfi('0),
        .ctl_tx_test_pattern('0),

        .tx_clk(tx_clk[0]),

        .stat_tx_pause_valid(),
        .stat_tx_pause(stat_tx_lfc_pkt),
        .stat_tx_user_pause(stat_tx_pfc_pkt),

        .ctl_tx_pause_enable({cfg_tx_lfc_en & PAUSE_EN, cfg_tx_pfc_en & {8{PFC_EN}}}),
        .ctl_tx_pause_quanta0(cfg_tx_pfc_quanta[0]),
        .ctl_tx_pause_quanta1(cfg_tx_pfc_quanta[1]),
        .ctl_tx_pause_quanta2(cfg_tx_pfc_quanta[2]),
        .ctl_tx_pause_quanta3(cfg_tx_pfc_quanta[3]),
        .ctl_tx_pause_quanta4(cfg_tx_pfc_quanta[4]),
        .ctl_tx_pause_quanta5(cfg_tx_pfc_quanta[5]),
        .ctl_tx_pause_quanta6(cfg_tx_pfc_quanta[6]),
        .ctl_tx_pause_quanta7(cfg_tx_pfc_quanta[7]),
        .ctl_tx_pause_quanta8(cfg_tx_lfc_quanta),
        .ctl_tx_pause_refresh_timer0(cfg_tx_pfc_refresh[0]),
        .ctl_tx_pause_refresh_timer1(cfg_tx_pfc_refresh[1]),
        .ctl_tx_pause_refresh_timer2(cfg_tx_pfc_refresh[2]),
        .ctl_tx_pause_refresh_timer3(cfg_tx_pfc_refresh[3]),
        .ctl_tx_pause_refresh_timer4(cfg_tx_pfc_refresh[4]),
        .ctl_tx_pause_refresh_timer5(cfg_tx_pfc_refresh[5]),
        .ctl_tx_pause_refresh_timer6(cfg_tx_pfc_refresh[6]),
        .ctl_tx_pause_refresh_timer7(cfg_tx_pfc_refresh[7]),
        .ctl_tx_pause_refresh_timer8(cfg_tx_lfc_refresh),
        .ctl_tx_pause_req({tx_lfc_req, tx_pfc_req}),
        .ctl_tx_resend_pause(tx_lfc_resend | tx_pfc_resend),

        .tx_axis_tready(axis_tx_pad.tready),
        .tx_axis_tvalid(axis_tx_pad.tvalid),
        .tx_axis_tdata(axis_tx_pad.tdata),
        .tx_axis_tlast(axis_tx_pad.tlast),
        .tx_axis_tkeep(axis_tx_pad.tkeep),
        .tx_axis_tuser(axis_tx_pad.tuser[0]),

        .tx_ovfout(),
        .tx_unfout(),

        .tx_reset_done(tx_rst_out[0]),
        .rx_reset_done(rx_rst_out[0]),

        .rx_serdes_reset_done({6'h3f, rx_rst_out[3], rx_rst_out[2], rx_rst_out[1], rx_rst_out[0]}),
        .rx_serdes_clk_in({6'd0, rx_clk[3], rx_clk[2], rx_clk[1], rx_clk[0]}),

        .drp_clk('0),
        .drp_addr('0),
        .drp_di('0),
        .drp_en('0),
        .drp_we('0),
        .drp_do(),
        .drp_rdy()
    );

end

if (STAT_EN) begin : stats

    taxi_eth_mac_stats #(
        .STAT_TX_LEVEL(STAT_TX_LEVEL),
        .STAT_RX_LEVEL(STAT_RX_LEVEL),
        .STAT_ID_BASE(STAT_ID_BASE),
        .STAT_UPDATE_PERIOD(STAT_UPDATE_PERIOD),
        .STAT_STR_EN(STAT_STR_EN),
        .STAT_PREFIX_STR(STAT_PREFIX_STR),
        .INC_W(7)
    )
    mac_stats_inst (
        .rx_clk(rx_clk[0]),
        .rx_rst(rx_rst_out[0]),
        .tx_clk(tx_clk[0]),
        .tx_rst(tx_rst_out[0]),

        /*
         * Statistics
         */
        .stat_clk(stat_clk),
        .stat_rst(stat_rst),
        .m_axis_stat(m_axis_stat),

        /*
         * Status
         */
        .tx_start_packet(|tx_start_packet),
        .stat_tx_byte(stat_tx_byte),
        .stat_tx_pkt_len(stat_tx_pkt_len),
        .stat_tx_pkt_ucast(stat_tx_pkt_ucast),
        .stat_tx_pkt_mcast(stat_tx_pkt_mcast),
        .stat_tx_pkt_bcast(stat_tx_pkt_bcast),
        .stat_tx_pkt_vlan(stat_tx_pkt_vlan),
        .stat_tx_pkt_good(stat_tx_pkt_good),
        .stat_tx_pkt_bad(stat_tx_pkt_bad),
        .stat_tx_err_oversize(stat_tx_err_oversize),
        .stat_tx_err_user(stat_tx_err_user),
        .stat_tx_err_underflow(stat_tx_err_underflow),
        .rx_start_packet(|rx_start_packet),
        .stat_rx_byte(stat_rx_byte),
        .stat_rx_pkt_len(stat_rx_pkt_len),
        .stat_rx_pkt_fragment(stat_rx_pkt_fragment),
        .stat_rx_pkt_jabber(stat_rx_pkt_jabber),
        .stat_rx_pkt_ucast(stat_rx_pkt_ucast),
        .stat_rx_pkt_mcast(stat_rx_pkt_mcast),
        .stat_rx_pkt_bcast(stat_rx_pkt_bcast),
        .stat_rx_pkt_vlan(stat_rx_pkt_vlan),
        .stat_rx_pkt_good(stat_rx_pkt_good),
        .stat_rx_pkt_bad(stat_rx_pkt_bad),
        .stat_rx_err_oversize(stat_rx_err_oversize),
        .stat_rx_err_bad_fcs(stat_rx_err_bad_fcs),
        .stat_rx_err_bad_block(stat_rx_err_bad_block),
        .stat_rx_err_framing(stat_rx_err_framing),
        .stat_rx_err_preamble(stat_rx_err_preamble),
        .stat_rx_fifo_drop(stat_rx_fifo_drop),
        .stat_tx_mcf(stat_tx_mcf),
        .stat_rx_mcf(stat_rx_mcf),
        .stat_tx_lfc_pkt(stat_tx_lfc_pkt),
        .stat_tx_lfc_xon(stat_tx_lfc_xon),
        .stat_tx_lfc_xoff(stat_tx_lfc_xoff),
        .stat_tx_lfc_paused(stat_tx_lfc_paused),
        .stat_tx_pfc_pkt(stat_tx_pfc_pkt),
        .stat_tx_pfc_xon(stat_tx_pfc_xon),
        .stat_tx_pfc_xoff(stat_tx_pfc_xoff),
        .stat_tx_pfc_paused(stat_tx_pfc_paused),
        .stat_rx_lfc_pkt(stat_rx_lfc_pkt),
        .stat_rx_lfc_xon(stat_rx_lfc_xon),
        .stat_rx_lfc_xoff(stat_rx_lfc_xoff),
        .stat_rx_lfc_paused(stat_rx_lfc_paused),
        .stat_rx_pfc_pkt(stat_rx_pfc_pkt),
        .stat_rx_pfc_xon(stat_rx_pfc_xon),
        .stat_rx_pfc_xoff(stat_rx_pfc_xoff),
        .stat_rx_pfc_paused(stat_rx_pfc_paused)
    );

end else begin

    taxi_axis_null_src
    null_src_inst (
        .m_axis(m_axis_stat)
    );

end

endmodule

`resetall
