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
 * FPGA top-level module
 */
module fpga #
(
    // simulation (set to avoid vendor primitives)
    parameter logic SIM = 1'b0,
    // vendor ("GENERIC", "XILINX", "ALTERA")
    parameter string VENDOR = "XILINX",
    // device family
    parameter string FAMILY = "kintex7",
    // Use 90 degree clock for RGMII transmit
    parameter logic USE_CLK90 = 1'b1,
    // BASE-T PHY type (GMII, RGMII)
    parameter BASET_PHY_TYPE = "GMII",
    // SFP rate selection (0 for 1G, 1 for 10G)
    parameter logic SFP_RATE = 1'b1,
    // Invert SFP data pins
    parameter logic SFP_INVERT = 1'b1,
    // 10G MAC configuration
    parameter logic CFG_LOW_LATENCY = 1'b1,
    parameter logic COMBINED_MAC_PCS = 1'b1
)
(
    /*
     * Clock: 200MHz
     * Reset: Push button, active high
     */
    input  wire logic        clk_200mhz_p,
    input  wire logic        clk_200mhz_n,
    input  wire logic        reset,

    /*
     * GPIO
     */
    input  wire logic        btnu,
    input  wire logic        btnl,
    input  wire logic        btnd,
    input  wire logic        btnr,
    input  wire logic        btnc,
    input  wire logic [3:0]  sw,
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
    inout  wire logic        i2c_scl,
    inout  wire logic        i2c_sda,
    output wire logic        i2c_mux_reset,

    /*
     * Ethernet: SFP+
     */
    input  wire logic        sfp_rx_p,
    input  wire logic        sfp_rx_n,
    output wire logic        sfp_tx_p,
    output wire logic        sfp_tx_n,
    input  wire logic        sfp_mgt_refclk_p,
    input  wire logic        sfp_mgt_refclk_n,

    output wire logic        si5324_rst,
    input  wire logic        si5324_int,

    output wire logic        sfp_tx_disable_b,
    input  wire logic        sfp_rx_los,

    /*
     * Ethernet: 1000BASE-T GMII or RGMII
     */
    input  wire logic        phy_rx_clk,
    input  wire logic [7:0]  phy_rxd,
    input  wire logic        phy_rx_dv,
    input  wire logic        phy_rx_er,
    output wire logic        phy_gtx_clk,
    input  wire logic        phy_tx_clk,
    output wire logic [7:0]  phy_txd,
    output wire logic        phy_tx_en,
    output wire logic        phy_tx_er,
    output wire logic        phy_reset_n,
    input  wire logic        phy_int_n
);

// Clock and reset

wire clk_200mhz_ibufg;

// Internal 125 MHz clock
wire clk_mmcm_out;
wire clk_int;
wire clk90_mmcm_out;
wire clk90_int;
wire rst_int;

wire clk_200mhz_mmcm_out;
wire clk_200mhz_int;

wire mmcm_rst = reset;
wire mmcm_locked;
wire mmcm_clkfb;

IBUFGDS
clk_200mhz_ibufgds_inst(
    .I(clk_200mhz_p),
    .IB(clk_200mhz_n),
    .O(clk_200mhz_ibufg)
);

// MMCM instance
MMCME2_BASE #(
    // 200 MHz input
    .CLKIN1_PERIOD(5.0),
    .REF_JITTER1(0.010),
    // 200 MHz input / 1 = 200 MHz PFD (range 10 MHz to 500 MHz)
    .DIVCLK_DIVIDE(1),
    // 200 MHz PFD * 5 = 1000 MHz VCO (range 600 MHz to 1440 MHz)
    .CLKFBOUT_MULT_F(5),
    .CLKFBOUT_PHASE(0),
    // 1000 MHz VCO / 8 = 125 MHz, 0 degrees
    .CLKOUT0_DIVIDE_F(8),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    // 1000 MHz VCO / 8 = 125 MHz, 90 degrees
    .CLKOUT1_DIVIDE(8),
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(90),
    // 1000 MHz VCO / 5 = 200 MHz, 0 degrees
    .CLKOUT2_DIVIDE(5),
    .CLKOUT2_DUTY_CYCLE(0.5),
    .CLKOUT2_PHASE(0),
    // Not used
    .CLKOUT3_DIVIDE(1),
    .CLKOUT3_DUTY_CYCLE(0.5),
    .CLKOUT3_PHASE(0),
    // Not used
    .CLKOUT4_DIVIDE(1),
    .CLKOUT4_DUTY_CYCLE(0.5),
    .CLKOUT4_PHASE(0),
    .CLKOUT4_CASCADE("FALSE"),
    // Not used
    .CLKOUT5_DIVIDE(1),
    .CLKOUT5_DUTY_CYCLE(0.5),
    .CLKOUT5_PHASE(0),
    // Not used
    .CLKOUT6_DIVIDE(1),
    .CLKOUT6_DUTY_CYCLE(0.5),
    .CLKOUT6_PHASE(0),

    // optimized bandwidth
    .BANDWIDTH("OPTIMIZED"),
    // don't wait for lock during startup
    .STARTUP_WAIT("FALSE")
)
clk_mmcm_inst (
    // 200 MHz input
    .CLKIN1(clk_200mhz_ibufg),
    // direct clkfb feeback
    .CLKFBIN(mmcm_clkfb),
    .CLKFBOUT(mmcm_clkfb),
    .CLKFBOUTB(),
    // 125 MHz, 0 degrees
    .CLKOUT0(clk_mmcm_out),
    .CLKOUT0B(),
    // 125 MHz, 90 degrees
    .CLKOUT1(clk90_mmcm_out),
    .CLKOUT1B(),
    // 200 MHz, 0 degrees
    .CLKOUT2(clk_200mhz_mmcm_out),
    .CLKOUT2B(),
    // Not used
    .CLKOUT3(),
    .CLKOUT3B(),
    // Not used
    .CLKOUT4(),
    // Not used
    .CLKOUT5(),
    // Not used
    .CLKOUT6(),
    // reset input
    .RST(mmcm_rst),
    // don't power down
    .PWRDWN(1'b0),
    // locked output
    .LOCKED(mmcm_locked)
);

BUFG
clk_bufg_inst (
    .I(clk_mmcm_out),
    .O(clk_int)
);

BUFG
clk90_bufg_inst (
    .I(clk90_mmcm_out),
    .O(clk90_int)
);

BUFG
clk_200mhz_bufg_inst (
    .I(clk_200mhz_mmcm_out),
    .O(clk_200mhz_int)
);

taxi_sync_reset #(
    .N(4)
)
sync_reset_inst (
    .clk(clk_int),
    .rst(~mmcm_locked),
    .out(rst_int)
);

// GPIO
wire btnu_int;
wire btnl_int;
wire btnd_int;
wire btnr_int;
wire btnc_int;
wire [3:0] sw_int;

taxi_debounce_switch #(
    .WIDTH(9),
    .N(4),
    .RATE(125000)
)
debounce_switch_inst (
    .clk(clk_int),
    .rst(rst_int),
    .in({btnu,
        btnl,
        btnd,
        btnr,
        btnc,
        sw}),
    .out({btnu_int,
        btnl_int,
        btnd_int,
        btnr_int,
        btnc_int,
        sw_int})
);

wire uart_rxd_int;
wire uart_rts_int;

taxi_sync_signal #(
    .WIDTH(2),
    .N(2)
)
sync_signal_inst (
    .clk(clk_int),
    .in({uart_rxd, uart_rts}),
    .out({uart_rxd_int, uart_rts_int})
);

// I2C
wire i2c_scl_i;
wire i2c_scl_o;
wire i2c_sda_i;
wire i2c_sda_o;

assign i2c_scl_i = i2c_scl;
assign i2c_scl = i2c_scl_o ? 1'bz : 1'b0;
assign i2c_sda_i = i2c_sda;
assign i2c_sda = i2c_sda_o ? 1'bz : 1'b0;

wire i2c_init_scl_i = i2c_scl_i;
wire i2c_init_scl_o;
wire i2c_init_sda_i = i2c_sda_i;
wire i2c_init_sda_o;

wire i2c_int_scl_i = i2c_scl_i;
wire i2c_int_scl_o;
wire i2c_int_sda_i = i2c_sda_i;
wire i2c_int_sda_o;

assign i2c_scl_o = i2c_init_scl_o & i2c_int_scl_o;
assign i2c_sda_o = i2c_init_sda_o & i2c_int_sda_o;

// Si5324 init
taxi_axis_if #(.DATA_W(12)) si5324_i2c_cmd();
taxi_axis_if #(.DATA_W(8)) si5324_i2c_tx();
taxi_axis_if #(.DATA_W(8)) si5324_i2c_rx();

assign si5324_i2c_rx.tready = 1'b1;

wire si5324_i2c_busy;

assign si5324_rst = ~rst_int;

taxi_i2c_master
si5324_i2c_master_inst (
    .clk(clk_int),
    .rst(rst_int),

    /*
     * Host interface
     */
    .s_axis_cmd(si5324_i2c_cmd),
    .s_axis_tx(si5324_i2c_tx),
    .m_axis_rx(si5324_i2c_rx),

    /*
     * I2C interface
     */
    .scl_i(i2c_init_scl_i),
    .scl_o(i2c_init_scl_o),
    .sda_i(i2c_init_sda_i),
    .sda_o(i2c_init_sda_o),

    /*
     * Status
     */
    .busy(),
    .bus_control(),
    .bus_active(),
    .missed_ack(),

    /*
     * Configuration
     */
    .prescale(SIM ? 32 : 312),
    .stop_on_idle(1)
);

si5324_i2c_init #(
    .SIM_SPEEDUP(SIM)
)
si5324_i2c_init_inst (
    .clk(clk_int),
    .rst(rst_int),

    /*
     * I2C master interface
     */
    .m_axis_cmd(si5324_i2c_cmd),
    .m_axis_tx(si5324_i2c_tx),

    /*
     * Status
     */
    .busy(si5324_i2c_busy),

    /*
     * Configuration
     */
    .start(1'b1)
);

wire phy_rgmii_rx_clk_int;
wire [3:0] phy_rgmii_rxd_int;
wire phy_rgmii_rx_ctl_int;
wire phy_rgmii_tx_clk_int;
wire [3:0] phy_rgmii_txd_int;
wire phy_rgmii_tx_ctl_int;

wire phy_gmii_rx_clk_int;
wire [7:0] phy_gmii_rxd_int;
wire phy_gmii_rx_dv_int;
wire phy_gmii_rx_er_int;
wire phy_gmii_gtx_clk_int;
wire phy_gmii_tx_clk_int;
wire [7:0] phy_gmii_txd_int;
wire phy_gmii_tx_en_int;
wire phy_gmii_tx_er_int;

if (BASET_PHY_TYPE == "RGMII") begin : phy_if

    assign phy_rgmii_rx_clk_int = phy_rx_clk;

    // IODELAY elements for RGMII interface to PHY
    IDELAYCTRL
    idelayctrl_inst (
        .REFCLK(clk_200mhz_int),
        .RST(rst_int),
        .RDY()
    );

    for (genvar n = 0; n < 4; n = n + 1) begin : phy_rxd_idelay_bit

        IDELAYE2 #(
            .IDELAY_TYPE("FIXED")
        )
        idelay_inst (
            .IDATAIN(phy_rxd[n]),
            .DATAOUT(phy_rgmii_rxd_int[n]),
            .DATAIN(1'b0),
            .C(1'b0),
            .CE(1'b0),
            .INC(1'b0),
            .CINVCTRL(1'b0),
            .CNTVALUEIN(5'd0),
            .CNTVALUEOUT(),
            .LD(1'b0),
            .LDPIPEEN(1'b0),
            .REGRST(1'b0)
        );

    end

    IDELAYE2 #(
        .IDELAY_TYPE("FIXED")
    )
    phy_rx_ctl_idelay (
        .IDATAIN(phy_rx_dv),
        .DATAOUT(phy_rgmii_rx_ctl_int),
        .DATAIN(1'b0),
        .C(1'b0),
        .CE(1'b0),
        .INC(1'b0),
        .CINVCTRL(1'b0),
        .CNTVALUEIN(5'd0),
        .CNTVALUEOUT(),
        .LD(1'b0),
        .LDPIPEEN(1'b0),
        .REGRST(1'b0)
    );

    assign phy_gtx_clk = phy_rgmii_tx_clk_int;
    assign phy_txd[3:0] = phy_rgmii_txd_int;
    assign phy_tx_en = phy_rgmii_tx_ctl_int;

    assign phy_txd[7:4] = '0;
    assign phy_tx_er = 1'b0;

    assign phy_gmii_rx_clk_int = 1'b0;
    assign phy_gmii_rxd_int = '0;
    assign phy_gmii_rx_dv_int = 1'b0;
    assign phy_gmii_rx_er_int = 1'b0;
    assign phy_gmii_tx_clk_int = 1'b0;

end else begin : phy_if

    assign phy_rgmii_rx_clk_int = 1'b0;
    assign phy_rgmii_rxd_int = '0;
    assign phy_rgmii_rx_ctl_int = 1'b0;

    assign phy_gmii_rx_clk_int = phy_rx_clk;
    assign phy_gmii_rxd_int = phy_rxd;
    assign phy_gmii_rx_dv_int = phy_rx_dv;
    assign phy_gmii_rx_er_int = phy_rx_er;

    assign phy_gtx_clk = phy_gmii_gtx_clk_int;
    assign phy_gmii_tx_clk_int = phy_tx_clk;
    assign phy_txd = phy_gmii_txd_int;
    assign phy_tx_en = phy_gmii_tx_en_int;
    assign phy_tx_er = phy_gmii_tx_er_int;

end

fpga_core #(
    .SIM(SIM),
    .VENDOR(VENDOR),
    .FAMILY(FAMILY),
    .USE_CLK90(USE_CLK90),
    .BASET_PHY_TYPE(BASET_PHY_TYPE),
    .SFP_INVERT(SFP_INVERT),
    .CFG_LOW_LATENCY(CFG_LOW_LATENCY),
    .COMBINED_MAC_PCS(COMBINED_MAC_PCS)
)
core_inst (
    /*
     * Clock: 125MHz
     * Synchronous reset
     */
    .clk(clk_int),
    .clk90(clk90_int),
    .rst(rst_int),

    /*
     * GPIO
     */
    .btnu(btnu_int),
    .btnl(btnl_int),
    .btnd(btnd_int),
    .btnr(btnr_int),
    .btnc(btnc_int),
    .sw(sw_int),
    .led(led),

    /*
     * UART: 115200 bps, 8N1
     */
    .uart_rxd(uart_rxd_int),
    .uart_txd(uart_txd),
    .uart_rts(uart_rts_int),
    .uart_cts(uart_cts),

    /*
     * I2C
     */
    .i2c_scl_i(i2c_int_scl_i),
    .i2c_scl_o(i2c_int_scl_o),
    .i2c_sda_i(i2c_int_sda_i),
    .i2c_sda_o(i2c_int_sda_o),

    /*
     * Ethernet: SFP+
     */
    .sfp_rx_p(sfp_rx_p),
    .sfp_rx_n(sfp_rx_n),
    .sfp_tx_p(sfp_tx_p),
    .sfp_tx_n(sfp_tx_n),
    .sfp_mgt_refclk_p(sfp_mgt_refclk_p),
    .sfp_mgt_refclk_n(sfp_mgt_refclk_n),

    .sfp_tx_disable_b(sfp_tx_disable_b),
    .sfp_rx_los(sfp_rx_los),

    /*
     * Ethernet: 1000BASE-T GMII/RGMII/SGMII
     */
    .phy_rgmii_rx_clk(phy_rgmii_rx_clk_int),
    .phy_rgmii_rxd(phy_rgmii_rxd_int),
    .phy_rgmii_rx_ctl(phy_rgmii_rx_ctl_int),
    .phy_rgmii_tx_clk(phy_rgmii_tx_clk_int),
    .phy_rgmii_txd(phy_rgmii_txd_int),
    .phy_rgmii_tx_ctl(phy_rgmii_tx_ctl_int),

    .phy_gmii_rx_clk(phy_gmii_rx_clk_int),
    .phy_gmii_rxd(phy_gmii_rxd_int),
    .phy_gmii_rx_dv(phy_gmii_rx_dv_int),
    .phy_gmii_rx_er(phy_gmii_rx_er_int),
    .phy_gmii_gtx_clk(phy_gmii_gtx_clk_int),
    .phy_gmii_tx_clk(phy_gmii_tx_clk_int),
    .phy_gmii_txd(phy_gmii_txd_int),
    .phy_gmii_tx_en(phy_gmii_tx_en_int),
    .phy_gmii_tx_er(phy_gmii_tx_er_int),

    .phy_reset_n(phy_reset_n),
    .phy_int_n(phy_int_n)
);

endmodule

`resetall
