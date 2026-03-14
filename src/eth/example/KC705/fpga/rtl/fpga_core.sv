// SPDX-License-Identifier: MIT
/*

Copyright (c) 2014-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * FPGA core logic
 */
module fpga_core #
(
    // simulation (set to avoid vendor primitives)
    parameter logic SIM = 1'b0,
    // vendor ("GENERIC", "XILINX", "ALTERA")
    parameter string VENDOR = "XILINX",
    // device family
    parameter string FAMILY = "kintex7",
    // Use 90 degree clock for RGMII transmit
    parameter logic USE_CLK90 = 1'b1,
    // BASE-T PHY type (GMII, RGMII, SGMII)
    parameter BASET_PHY_TYPE = "GMII",
    // Invert SFP data pins
    parameter logic SFP_INVERT = 1'b1
)
(
    /*
     * Clock: 125MHz
     * Synchronous reset
     */
    input  wire logic        clk,
    input  wire logic        clk90,
    input  wire logic        rst,

    /*
     * GPIO
     */
    input  wire logic        btnu,
    input  wire logic        btnl,
    input  wire logic        btnd,
    input  wire logic        btnr,
    input  wire logic        btnc,
    input  wire logic [7:0]  sw,
    output wire logic [7:0]  led,

    /*
     * UART: 115200 bps, 8N1
     */
    input  wire logic        uart_rxd,
    output wire logic        uart_txd,
    input  wire logic        uart_rts,
    output wire logic        uart_cts,

    /*
     * I2C
     */
    input  wire logic        i2c_scl_i,
    output wire logic        i2c_scl_o,
    input  wire logic        i2c_sda_i,
    output wire logic        i2c_sda_o,

    /*
     * Ethernet: 1000BASE-X SFP
     */
    input  wire logic        sfp_gmii_clk,
    input  wire logic        sfp_gmii_rst,
    input  wire logic        sfp_gmii_clk_en,
    input  wire logic [7:0]  sfp_gmii_rxd,
    input  wire logic        sfp_gmii_rx_dv,
    input  wire logic        sfp_gmii_rx_er,
    output wire logic [7:0]  sfp_gmii_txd,
    output wire logic        sfp_gmii_tx_en,
    output wire logic        sfp_gmii_tx_er,
    output wire logic        sfp_tx_disable_b,
    input  wire logic        sfp_rx_los,

    /*
     * Ethernet: 1000BASE-T
     */
    input  wire logic        phy_sgmii_clk,
    input  wire logic        phy_sgmii_rst,
    input  wire logic        phy_sgmii_clk_en,
    input  wire logic [7:0]  phy_sgmii_rxd,
    input  wire logic        phy_sgmii_rx_dv,
    input  wire logic        phy_sgmii_rx_er,
    output wire logic [7:0]  phy_sgmii_txd,
    output wire logic        phy_sgmii_tx_en,
    output wire logic        phy_sgmii_tx_er,
    input  wire logic        phy_rgmii_rx_clk,
    input  wire logic [3:0]  phy_rgmii_rxd,
    input  wire logic        phy_rgmii_rx_ctl,
    output wire logic        phy_rgmii_tx_clk,
    output wire logic [3:0]  phy_rgmii_txd,
    output wire logic        phy_rgmii_tx_ctl,
    input  wire logic        phy_gmii_rx_clk,
    input  wire logic [7:0]  phy_gmii_rxd,
    input  wire logic        phy_gmii_rx_dv,
    input  wire logic        phy_gmii_rx_er,
    output wire logic        phy_gmii_gtx_clk,
    input  wire logic        phy_gmii_tx_clk,
    output wire logic [7:0]  phy_gmii_txd,
    output wire logic        phy_gmii_tx_en,
    output wire logic        phy_gmii_tx_er,
    output wire logic        phy_reset_n,
    input  wire logic        phy_int_n
);

assign led = sw;

// XFCP
assign uart_cts = 1'b0;

taxi_axis_if #(.DATA_W(8), .USER_EN(1), .USER_W(1)) xfcp_ds(), xfcp_us();

taxi_xfcp_if_uart #(
    .TX_FIFO_DEPTH(512),
    .RX_FIFO_DEPTH(512)
)
xfcp_if_uart_inst (
    .clk(clk),
    .rst(rst),

    /*
     * UART interface
     */
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd),

    /*
     * XFCP downstream interface
     */
    .xfcp_dsp_ds(xfcp_ds),
    .xfcp_dsp_us(xfcp_us),

    /*
     * Configuration
     */
    .prescale(16'(125000000/921600))
);

taxi_axis_if #(.DATA_W(8), .USER_EN(1), .USER_W(1)) xfcp_sw_ds[2](), xfcp_sw_us[2]();

taxi_xfcp_switch #(
    .XFCP_ID_STR("KC705"),
    .XFCP_EXT_ID(0),
    .XFCP_EXT_ID_STR("Taxi example"),
    .PORTS($size(xfcp_sw_us))
)
xfcp_sw_inst (
    .clk(clk),
    .rst(rst),

    /*
     * XFCP upstream port
     */
    .xfcp_usp_ds(xfcp_ds),
    .xfcp_usp_us(xfcp_us),

    /*
     * XFCP downstream ports
     */
    .xfcp_dsp_ds(xfcp_sw_ds),
    .xfcp_dsp_us(xfcp_sw_us)
);

taxi_axis_if #(.DATA_W(16), .KEEP_W(1), .KEEP_EN(0), .LAST_EN(0), .USER_EN(1), .USER_W(1), .ID_EN(1), .ID_W(10)) axis_stat();

taxi_xfcp_mod_stats #(
    .XFCP_ID_STR("Statistics"),
    .XFCP_EXT_ID(0),
    .XFCP_EXT_ID_STR(""),
    .STAT_COUNT_W(64),
    .STAT_PIPELINE(2)
)
xfcp_stats_inst (
    .clk(clk),
    .rst(rst),

    /*
     * XFCP upstream port
     */
    .xfcp_usp_ds(xfcp_sw_ds[0]),
    .xfcp_usp_us(xfcp_sw_us[0]),

    /*
     * Statistics increment input
     */
    .s_axis_stat(axis_stat)
);

taxi_axis_if #(.DATA_W(16), .KEEP_W(1), .KEEP_EN(0), .LAST_EN(0), .USER_EN(1), .USER_W(1), .ID_EN(1), .ID_W(10)) axis_eth_stat[2]();

taxi_axis_arb_mux #(
    .S_COUNT($size(axis_eth_stat)),
    .UPDATE_TID(1'b0),
    .ARB_ROUND_ROBIN(1'b1),
    .ARB_LSB_HIGH_PRIO(1'b0)
)
stat_mux_inst (
    .clk(clk),
    .rst(rst),

    /*
     * AXI4-Stream inputs (sink)
     */
    .s_axis(axis_eth_stat),

    /*
     * AXI4-Stream output (source)
     */
    .m_axis(axis_stat)
);

// I2C
taxi_xfcp_mod_i2c_master #(
    .XFCP_EXT_ID_STR("I2C"),
    .DEFAULT_PRESCALE(16'(125000000/200000/4))
)
xfcp_mod_i2c_inst (
    .clk(clk),
    .rst(rst),

    /*
     * XFCP upstream port
     */
    .xfcp_usp_ds(xfcp_sw_ds[1]),
    .xfcp_usp_us(xfcp_sw_us[1]),

    /*
     * I2C interface
     */
    .i2c_scl_i(i2c_scl_i),
    .i2c_scl_o(i2c_scl_o),
    .i2c_sda_i(i2c_sda_i),
    .i2c_sda_o(i2c_sda_o)
);

// BASE-T PHY
assign phy_reset_n = !rst;

taxi_axis_if #(.DATA_W(8), .ID_W(8), .USER_EN(1), .USER_W(1)) axis_eth();
taxi_axis_if #(.DATA_W(96), .KEEP_W(1), .ID_W(8)) axis_tx_cpl();

if (BASET_PHY_TYPE == "GMII") begin : baset_mac_gmii

    taxi_eth_mac_1g_gmii_fifo #(
        .SIM(SIM),
        .VENDOR(VENDOR),
        .FAMILY(FAMILY),
        .PADDING_EN(1),
        .MIN_FRAME_LEN(64),
        .STAT_EN(1),
        .STAT_TX_LEVEL(1),
        .STAT_RX_LEVEL(1),
        .STAT_ID_BASE(0),
        .STAT_UPDATE_PERIOD(1024),
        .STAT_STR_EN(1),
        .STAT_PREFIX_STR("GMII0"),
        .TX_FIFO_DEPTH(16384),
        .TX_FRAME_FIFO(1),
        .RX_FIFO_DEPTH(16384),
        .RX_FRAME_FIFO(1)
    )
    eth_mac_inst (
        .gtx_clk(clk),
        .gtx_rst(rst),
        .logic_clk(clk),
        .logic_rst(rst),

        /*
         * Transmit interface (AXI stream)
         */
        .s_axis_tx(axis_eth),
        .m_axis_tx_cpl(axis_tx_cpl),

        /*
         * Receive interface (AXI stream)
         */
        .m_axis_rx(axis_eth),

        /*
         * GMII interface
         */
        .gmii_rx_clk(phy_gmii_rx_clk),
        .gmii_rxd(phy_gmii_rxd),
        .gmii_rx_dv(phy_gmii_rx_dv),
        .gmii_rx_er(phy_gmii_rx_er),
        .gmii_tx_clk(phy_gmii_gtx_clk),
        .mii_tx_clk(phy_gmii_tx_clk),
        .gmii_txd(phy_gmii_txd),
        .gmii_tx_en(phy_gmii_tx_en),
        .gmii_tx_er(phy_gmii_tx_er),

        /*
         * Statistics
         */
        .stat_clk(clk),
        .stat_rst(rst),
        .m_axis_stat(axis_eth_stat[0]),

        /*
         * Status
         */
        .tx_error_underflow(),
        .tx_fifo_overflow(),
        .tx_fifo_bad_frame(),
        .tx_fifo_good_frame(),
        .rx_error_bad_frame(),
        .rx_error_bad_fcs(),
        .rx_fifo_overflow(),
        .rx_fifo_bad_frame(),
        .rx_fifo_good_frame(),
        .link_speed(),

        /*
         * Configuration
         */
        .cfg_tx_max_pkt_len(16'd9218),
        .cfg_tx_ifg(8'd12),
        .cfg_tx_enable(1'b1),
        .cfg_rx_max_pkt_len(16'd9218),
        .cfg_rx_enable(1'b1)
    );

    assign phy_sgmii_txd = '0;
    assign phy_sgmii_tx_en = 1'b0;
    assign phy_sgmii_tx_er = 1'b0;

    assign phy_rgmii_tx_clk = 1'b0;
    assign phy_rgmii_txd = '0;
    assign phy_rgmii_tx_ctl = 1'b0;

end else if (BASET_PHY_TYPE == "RGMII") begin : baset_mac_rgmii

    taxi_eth_mac_1g_rgmii_fifo #(
        .SIM(SIM),
        .VENDOR(VENDOR),
        .FAMILY(FAMILY),
        .USE_CLK90(USE_CLK90),
        .PADDING_EN(1),
        .MIN_FRAME_LEN(64),
        .STAT_EN(1),
        .STAT_TX_LEVEL(1),
        .STAT_RX_LEVEL(1),
        .STAT_ID_BASE(0),
        .STAT_UPDATE_PERIOD(1024),
        .STAT_STR_EN(1),
        .STAT_PREFIX_STR("RGMII0"),
        .TX_FIFO_DEPTH(16384),
        .TX_FRAME_FIFO(1),
        .RX_FIFO_DEPTH(16384),
        .RX_FRAME_FIFO(1)
    )
    eth_mac_inst (
        .gtx_clk(clk),
        .gtx_clk90(clk90),
        .gtx_rst(rst),
        .logic_clk(clk),
        .logic_rst(rst),

        /*
         * Transmit interface (AXI stream)
         */
        .s_axis_tx(axis_eth),
        .m_axis_tx_cpl(axis_tx_cpl),

        /*
         * Receive interface (AXI stream)
         */
        .m_axis_rx(axis_eth),

        /*
         * RGMII interface
         */
        .rgmii_rx_clk(phy_rgmii_rx_clk),
        .rgmii_rxd(phy_rgmii_rxd),
        .rgmii_rx_ctl(phy_rgmii_rx_ctl),
        .rgmii_tx_clk(phy_rgmii_tx_clk),
        .rgmii_txd(phy_rgmii_txd),
        .rgmii_tx_ctl(phy_rgmii_tx_ctl),

        /*
         * Statistics
         */
        .stat_clk(clk),
        .stat_rst(rst),
        .m_axis_stat(axis_eth_stat[0]),

        /*
         * Status
         */
        .tx_error_underflow(),
        .tx_fifo_overflow(),
        .tx_fifo_bad_frame(),
        .tx_fifo_good_frame(),
        .rx_error_bad_frame(),
        .rx_error_bad_fcs(),
        .rx_fifo_overflow(),
        .rx_fifo_bad_frame(),
        .rx_fifo_good_frame(),
        .link_speed(),

        /*
         * Configuration
         */
        .cfg_tx_max_pkt_len(16'd9218),
        .cfg_tx_ifg(8'd12),
        .cfg_tx_enable(1'b1),
        .cfg_rx_max_pkt_len(16'd9218),
        .cfg_rx_enable(1'b1)
    );

    assign phy_gmii_gtx_clk = 1'b0;
    assign phy_gmii_txd = '0;
    assign phy_gmii_tx_en = 1'b0;
    assign phy_gmii_tx_er = 1'b0;

    assign phy_sgmii_txd = '0;
    assign phy_sgmii_tx_en = 1'b0;
    assign phy_sgmii_tx_er = 1'b0;

end else if (BASET_PHY_TYPE == "SGMII") begin : baset_mac_sgmii

    taxi_eth_mac_1g_fifo #(
        .PADDING_EN(1),
        .MIN_FRAME_LEN(64),
        .STAT_EN(1),
        .STAT_TX_LEVEL(1),
        .STAT_RX_LEVEL(1),
        .STAT_ID_BASE(0),
        .STAT_UPDATE_PERIOD(1024),
        .STAT_STR_EN(1),
        .STAT_PREFIX_STR("SGMII0"),
        .TX_FIFO_DEPTH(16384),
        .TX_FRAME_FIFO(1),
        .RX_FIFO_DEPTH(16384),
        .RX_FRAME_FIFO(1)
    )
    eth_mac_inst (
        .rx_clk(phy_sgmii_clk),
        .rx_rst(phy_sgmii_rst),
        .tx_clk(phy_sgmii_clk),
        .tx_rst(phy_sgmii_rst),
        .logic_clk(clk),
        .logic_rst(rst),

        /*
         * Transmit interface (AXI stream)
         */
        .s_axis_tx(axis_eth),
        .m_axis_tx_cpl(axis_tx_cpl),

        /*
         * Receive interface (AXI stream)
         */
        .m_axis_rx(axis_eth),

        /*
         * GMII interface
         */
        .gmii_rxd(phy_sgmii_rxd),
        .gmii_rx_dv(phy_sgmii_rx_dv),
        .gmii_rx_er(phy_sgmii_rx_er),
        .gmii_txd(phy_sgmii_txd),
        .gmii_tx_en(phy_sgmii_tx_en),
        .gmii_tx_er(phy_sgmii_tx_er),

        /*
         * Control
         */
        .rx_clk_enable(phy_sgmii_clk_en),
        .tx_clk_enable(phy_sgmii_clk_en),
        .rx_mii_select(1'b0),
        .tx_mii_select(1'b0),

        /*
         * Statistics
         */
        .stat_clk(clk),
        .stat_rst(rst),
        .m_axis_stat(axis_eth_stat[0]),

        /*
         * Status
         */
        .tx_error_underflow(),
        .tx_fifo_overflow(),
        .tx_fifo_bad_frame(),
        .tx_fifo_good_frame(),
        .rx_error_bad_frame(),
        .rx_error_bad_fcs(),
        .rx_fifo_overflow(),
        .rx_fifo_bad_frame(),
        .rx_fifo_good_frame(),

        /*
         * Configuration
         */
        .cfg_tx_max_pkt_len(16'd9218),
        .cfg_tx_ifg(8'd12),
        .cfg_tx_enable(1'b1),
        .cfg_rx_max_pkt_len(16'd9218),
        .cfg_rx_enable(1'b1)
    );

    assign phy_gmii_gtx_clk = 1'b0;
    assign phy_gmii_txd = '0;
    assign phy_gmii_tx_en = 1'b0;
    assign phy_gmii_tx_er = 1'b0;

    assign phy_rgmii_tx_clk = 1'b0;
    assign phy_rgmii_txd = '0;
    assign phy_rgmii_tx_ctl = 1'b0;

end

// SFP+
assign sfp_tx_disable_b = 1'b1;

taxi_axis_if #(.DATA_W(8), .ID_W(8), .USER_EN(1), .USER_W(1)) axis_sfp_eth();
taxi_axis_if #(.DATA_W(96), .KEEP_W(1), .ID_W(8)) axis_sfp_tx_cpl();

taxi_eth_mac_1g_fifo #(
    .PADDING_EN(1),
    .MIN_FRAME_LEN(64),
    .STAT_EN(1),
    .STAT_TX_LEVEL(1),
    .STAT_RX_LEVEL(1),
    .STAT_ID_BASE(16+16),
    .STAT_UPDATE_PERIOD(1024),
    .STAT_STR_EN(1),
    .STAT_PREFIX_STR("SFP"),
    .TX_FIFO_DEPTH(16384),
    .TX_FRAME_FIFO(1),
    .RX_FIFO_DEPTH(16384),
    .RX_FRAME_FIFO(1)
)
eth_mac_inst (
    .rx_clk(sfp_gmii_clk),
    .rx_rst(sfp_gmii_rst),
    .tx_clk(sfp_gmii_clk),
    .tx_rst(sfp_gmii_rst),
    .logic_clk(clk),
    .logic_rst(rst),

    /*
     * Transmit interface (AXI stream)
     */
    .s_axis_tx(axis_sfp_eth),
    .m_axis_tx_cpl(axis_sfp_tx_cpl),

    /*
     * Receive interface (AXI stream)
     */
    .m_axis_rx(axis_sfp_eth),

    /*
     * GMII interface
     */
    .gmii_rxd(sfp_gmii_rxd),
    .gmii_rx_dv(sfp_gmii_rx_dv),
    .gmii_rx_er(sfp_gmii_rx_er),
    .gmii_txd(sfp_gmii_txd),
    .gmii_tx_en(sfp_gmii_tx_en),
    .gmii_tx_er(sfp_gmii_tx_er),

    /*
     * Control
     */
    .rx_clk_enable(sfp_gmii_clk_en),
    .tx_clk_enable(sfp_gmii_clk_en),
    .rx_mii_select(1'b0),
    .tx_mii_select(1'b0),

    /*
     * Statistics
     */
    .stat_clk(clk),
    .stat_rst(rst),
    .m_axis_stat(axis_eth_stat[1]),

    /*
     * Status
     */
    .tx_error_underflow(),
    .tx_fifo_overflow(),
    .tx_fifo_bad_frame(),
    .tx_fifo_good_frame(),
    .rx_error_bad_frame(),
    .rx_error_bad_fcs(),
    .rx_fifo_overflow(),
    .rx_fifo_bad_frame(),
    .rx_fifo_good_frame(),

    /*
     * Configuration
     */
    .cfg_tx_max_pkt_len(16'd9218),
    .cfg_tx_ifg(8'd12),
    .cfg_tx_enable(1'b1),
    .cfg_rx_max_pkt_len(16'd9218),
    .cfg_rx_enable(1'b1)
);

endmodule

`resetall
