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
    // BASE-T PHY type (GMII, RGMII, SGMII)
    parameter BASET_PHY_TYPE = "GMII",
    // Invert SFP data pins
    parameter logic SFP_INVERT = 1'b1
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
    input  wire logic        phy_sgmii_rx_p,
    input  wire logic        phy_sgmii_rx_n,
    output wire logic        phy_sgmii_tx_p,
    output wire logic        phy_sgmii_tx_n,
    input  wire logic        sgmii_mgt_refclk_p,
    input  wire logic        sgmii_mgt_refclk_n,

    output wire logic        sfp_tx_disable_b,
    input  wire logic        sfp_rx_los,

    /*
     * Ethernet: 1000BASE-T GMII, RGMII, or SGMII
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

wire [7:0] led_int;

// I2C
wire i2c_scl_i;
wire i2c_scl_o;
wire i2c_sda_i;
wire i2c_sda_o;

assign i2c_scl_i = i2c_scl;
assign i2c_scl = i2c_scl_o ? 1'bz : 1'b0;
assign i2c_sda_i = i2c_sda;
assign i2c_sda = i2c_sda_o ? 1'bz : 1'b0;

// SGMII interface to PHY
wire phy_sgmii_clk_int;
wire phy_sgmii_rst_int;
wire phy_sgmii_clk_en_int;
wire [7:0] phy_sgmii_txd_int;
wire phy_sgmii_tx_en_int;
wire phy_sgmii_tx_er_int;
wire [7:0] phy_sgmii_rxd_int;
wire phy_sgmii_rx_dv_int;
wire phy_sgmii_rx_er_int;

wire sgmii_gtrefclk;
wire sgmii_gtrefclk_bufg;
wire sgmii_txuserclk;
wire sgmii_txuserclk2;
wire sgmii_rxuserclk;
wire sgmii_rxuserclk2;
wire sgmii_pma_reset;
wire sgmii_mmcm_locked;

wire phy_sgmii_resetdone;

assign phy_sgmii_clk_int = sgmii_txuserclk2;

taxi_sync_reset #(
    .N(4)
)
sync_reset_sgmii_inst (
    .clk(phy_sgmii_clk_int),
    .rst(rst_int || !phy_sgmii_resetdone),
    .out(phy_sgmii_rst_int)
);

wire [15:0] sgmii_status_vect;

wire sgmii_status_link_status              = sgmii_status_vect[0];
wire sgmii_status_link_synchronization     = sgmii_status_vect[1];
wire sgmii_status_rudi_c                   = sgmii_status_vect[2];
wire sgmii_status_rudi_i                   = sgmii_status_vect[3];
wire sgmii_status_rudi_invalid             = sgmii_status_vect[4];
wire sgmii_status_rxdisperr                = sgmii_status_vect[5];
wire sgmii_status_rxnotintable             = sgmii_status_vect[6];
wire sgmii_status_phy_link_status          = sgmii_status_vect[7];
wire [1:0] sgmii_status_remote_fault_encdg = sgmii_status_vect[9:8];
wire [1:0] sgmii_status_speed              = sgmii_status_vect[11:10];
wire sgmii_status_duplex                   = sgmii_status_vect[12];
wire sgmii_status_remote_fault             = sgmii_status_vect[13];
wire [1:0] sgmii_status_pause              = sgmii_status_vect[15:14];

wire [4:0] sgmii_config_vect;

assign sgmii_config_vect[4] = 1'b1; // autonegotiation enable
assign sgmii_config_vect[3] = 1'b0; // isolate
assign sgmii_config_vect[2] = 1'b0; // power down
assign sgmii_config_vect[1] = 1'b0; // loopback enable
assign sgmii_config_vect[0] = 1'b0; // unidirectional enable

wire [15:0] sgmii_an_config_vect;

assign sgmii_an_config_vect[15]    = 1'b1;    // SGMII link status
assign sgmii_an_config_vect[14]    = 1'b1;    // SGMII Acknowledge
assign sgmii_an_config_vect[13:12] = 2'b01;   // full duplex
assign sgmii_an_config_vect[11:10] = 2'b10;   // SGMII speed
assign sgmii_an_config_vect[9]     = 1'b0;    // reserved
assign sgmii_an_config_vect[8:7]   = 2'b00;   // pause frames - SGMII reserved
assign sgmii_an_config_vect[6]     = 1'b0;    // reserved
assign sgmii_an_config_vect[5]     = 1'b0;    // full duplex - SGMII reserved
assign sgmii_an_config_vect[4:1]   = 4'b0000; // reserved
assign sgmii_an_config_vect[0]     = 1'b1;    // SGMII

sgmii_pcs_pma_0
sgmii_pcspma (
    // Transceiver Interface
    .gtrefclk_p            (sgmii_mgt_refclk_p),
    .gtrefclk_n            (sgmii_mgt_refclk_n),
    .gtrefclk_out          (sgmii_gtrefclk),
    .gtrefclk_bufg_out     (sgmii_gtrefclk_bufg),
    .txp                   (phy_sgmii_tx_p),
    .txn                   (phy_sgmii_tx_n),
    .rxp                   (phy_sgmii_rx_p),
    .rxn                   (phy_sgmii_rx_n),
    .resetdone             (phy_sgmii_resetdone),
    .userclk_out           (sgmii_txuserclk),
    .userclk2_out          (sgmii_txuserclk2),
    .rxuserclk_out         (sgmii_rxuserclk),
    .rxuserclk2_out        (sgmii_rxuserclk2),
    .independent_clock_bufg(clk_int),
    .pma_reset_out         (sgmii_pma_reset),
    .mmcm_locked_out       (sgmii_mmcm_locked),
    .gt0_qplloutclk_out    (),
    .gt0_qplloutrefclk_out (),
    // GMII Interface
    .sgmii_clk_r           (),
    .sgmii_clk_f           (),
    .sgmii_clk_en          (phy_sgmii_clk_en_int),
    .gmii_txd              (phy_sgmii_txd_int),
    .gmii_tx_en            (phy_sgmii_tx_en_int),
    .gmii_tx_er            (phy_sgmii_tx_er_int),
    .gmii_rxd              (phy_sgmii_rxd_int),
    .gmii_rx_dv            (phy_sgmii_rx_dv_int),
    .gmii_rx_er            (phy_sgmii_rx_er_int),
    .gmii_isolate          (),
    // Management: Alternative to MDIO Interface
    .configuration_vector  (sgmii_config_vect),
    .an_interrupt          (),
    .an_adv_config_vector  (sgmii_an_config_vect),
    .an_restart_config     (1'b0),
    // Speed Control
    .speed_is_10_100       (sgmii_status_speed != 2'b10),
    .speed_is_100          (sgmii_status_speed == 2'b01),
    // General IO's
    .status_vector         (sgmii_status_vect),
    .reset                 (rst_int),
    .signal_detect         (1'b1)
);

// 1000BASE-X SFP
wire sfp_gmii_clk_int;
wire sfp_gmii_rst_int;
wire sfp_gmii_clk_en_int;
wire [7:0] sfp_gmii_txd_int;
wire sfp_gmii_tx_en_int;
wire sfp_gmii_tx_er_int;
wire [7:0] sfp_gmii_rxd_int;
wire sfp_gmii_rx_dv_int;
wire sfp_gmii_rx_er_int;

wire sfp_gmii_txuserclk2 = sgmii_txuserclk2;
wire sfp_gmii_resetdone;

assign sfp_gmii_clk_int = sfp_gmii_txuserclk2;

taxi_sync_reset #(
    .N(4)
)
sync_reset_sfp_inst (
    .clk(sfp_gmii_clk_int),
    .rst(rst_int || !sfp_gmii_resetdone),
    .out(sfp_gmii_rst_int)
);

wire [15:0] sfp_status_vect;

wire sfp_status_link_status              = sfp_status_vect[0];
wire sfp_status_link_synchronization     = sfp_status_vect[1];
wire sfp_status_rudi_c                   = sfp_status_vect[2];
wire sfp_status_rudi_i                   = sfp_status_vect[3];
wire sfp_status_rudi_invalid             = sfp_status_vect[4];
wire sfp_status_rxdisperr                = sfp_status_vect[5];
wire sfp_status_rxnotintable             = sfp_status_vect[6];
wire sfp_status_phy_link_status          = sfp_status_vect[7];
wire [1:0] sfp_status_remote_fault_encdg = sfp_status_vect[9:8];
wire [1:0] sfp_status_speed              = sfp_status_vect[11:10];
wire sfp_status_duplex                   = sfp_status_vect[12];
wire sfp_status_remote_fault             = sfp_status_vect[13];
wire [1:0] sfp_status_pause              = sfp_status_vect[15:14];

wire [4:0] sfp_config_vect;

assign sfp_config_vect[4] = 1'b0; // autonegotiation enable
assign sfp_config_vect[3] = 1'b0; // isolate
assign sfp_config_vect[2] = 1'b0; // power down
assign sfp_config_vect[1] = 1'b0; // loopback enable
assign sfp_config_vect[0] = 1'b0; // unidirectional enable

basex_pcs_pma_0
sfp_pcspma (
    // Transceiver Interface
    .gtrefclk(sgmii_gtrefclk),
    .gtrefclk_bufg(sgmii_gtrefclk_bufg),
    .txp(sfp_tx_p),
    .txn(sfp_tx_n),
    .rxp(sfp_rx_p),
    .rxn(sfp_rx_n),
    .independent_clock_bufg(clk_int),
    .txoutclk(),
    .rxoutclk(),
    .resetdone(sfp_gmii_resetdone),
    .cplllock(),
    .mmcm_reset(),
    .userclk(sgmii_txuserclk),
    .userclk2(sgmii_txuserclk2),
    .pma_reset(sgmii_pma_reset),
    .mmcm_locked(sgmii_mmcm_locked),
    .rxuserclk(sgmii_rxuserclk),
    .rxuserclk2(sgmii_rxuserclk2),
    // GMII Interface
    .gmii_txd(sfp_gmii_txd_int),
    .gmii_tx_en(sfp_gmii_tx_en_int),
    .gmii_tx_er(sfp_gmii_tx_er_int),
    .gmii_rxd(sfp_gmii_rxd_int),
    .gmii_rx_dv(sfp_gmii_rx_dv_int),
    .gmii_rx_er(sfp_gmii_rx_er_int),
    .gmii_isolate(),
    // Management: Alternative to MDIO Interface
    .configuration_vector(sfp_config_vect),
    // General IO's
    .status_vector(sfp_status_vect),
    .reset(rst_int),
    .signal_detect(1'b1),

    .gt0_qplloutclk_in(1'b0),
    .gt0_qplloutrefclk_in(1'b0),
    .gt0_rxchariscomma_out(),
    .gt0_rxcharisk_out(),
    .gt0_rxbyteisaligned_out(),
    .gt0_rxbyterealign_out(),
    .gt0_rxcommadet_out(),
    .gt0_txpolarity_in(SFP_INVERT),
    .gt0_txdiffctrl_in(4'b1000),
    .gt0_txpostcursor_in(5'b00000),
    .gt0_txprecursor_in(5'b00000),
    .gt0_rxpolarity_in(SFP_INVERT),
    .gt0_txinhibit_in(1'b0),
    .gt0_txprbssel_in(3'b000),
    .gt0_txprbsforceerr_in(1'b0),
    .gt0_rxprbscntreset_in(1'b0),
    .gt0_rxprbserr_out(),
    .gt0_rxprbssel_in(3'b000),
    .gt0_loopback_in(3'b000),
    .gt0_txresetdone_out(),
    .gt0_rxresetdone_out(),
    .gt0_rxdisperr_out(),
    .gt0_txbufstatus_out(),
    .gt0_rxnotintable_out(),
    .gt0_eyescanreset_in(1'b0),
    .gt0_eyescandataerror_out(),
    .gt0_eyescantrigger_in(1'b0),
    .gt0_rxcdrhold_in(1'b0),
    .gt0_rxpmareset_in(1'b0),
    .gt0_txpmareset_in(1'b0),
    .gt0_rxpcsreset_in(1'b0),
    .gt0_txpcsreset_in(1'b0),
    .gt0_rxbufreset_in(1'b0),
    .gt0_rxbufstatus_out(),
    .gt0_rxdfelpmreset_in(1'b0),
    .gt0_rxdfeagcovrden_in(1'b0),
    .gt0_rxlpmen_in(1'b1),
    .gt0_rxmonitorout_out(),
    .gt0_rxmonitorsel_in(2'b00),
    .gt0_drpaddr_in(9'd0),
    .gt0_drpclk_in(1'b0),
    .gt0_drpdi_in(9'd0),
    .gt0_drpdo_out(),
    .gt0_drpen_in(1'b0),
    .gt0_drprdy_out(),
    .gt0_drpwe_in(1'b0),
    .gt0_dmonitorout_out()
);

assign sfp_gmii_clk_en_int = 1'b1;

// SGMII interface debug:
// SW4:1 (sw[3]) off for payload byte, on for status vector
// SW4:2 (sw[2]) off for BASE-T port (SGMII), on for SFP
// SW4:4 (sw[0]) off for LSB of status vector, on for MSB
wire [15:0] sel_sv = sw[2] ? sfp_status_vect : sgmii_status_vect;
assign led = sw[3] ? (sw[0] ? sel_sv[15:8] : sel_sv[7:0]) : led_int;

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
    .SFP_INVERT(SFP_INVERT)
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
    .led(led_int),

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
    .i2c_scl_i(i2c_scl_i),
    .i2c_scl_o(i2c_scl_o),
    .i2c_sda_i(i2c_sda_i),
    .i2c_sda_o(i2c_sda_o),

    /*
     * Ethernet: 1000BASE-X SFP
     */
    .sfp_gmii_clk(sfp_gmii_clk_int),
    .sfp_gmii_rst(sfp_gmii_rst_int),
    .sfp_gmii_clk_en(sfp_gmii_clk_en_int),
    .sfp_gmii_rxd(sfp_gmii_rxd_int),
    .sfp_gmii_rx_dv(sfp_gmii_rx_dv_int),
    .sfp_gmii_rx_er(sfp_gmii_rx_er_int),
    .sfp_gmii_txd(sfp_gmii_txd_int),
    .sfp_gmii_tx_en(sfp_gmii_tx_en_int),
    .sfp_gmii_tx_er(sfp_gmii_tx_er_int),
    .sfp_tx_disable_b(sfp_tx_disable_b),
    .sfp_rx_los(sfp_rx_los),

    /*
     * Ethernet: 1000BASE-T GMII/RGMII/SGMII
     */
    .phy_sgmii_clk(phy_sgmii_clk_int),
    .phy_sgmii_rst(phy_sgmii_rst_int),
    .phy_sgmii_clk_en(phy_sgmii_clk_en_int),
    .phy_sgmii_rxd(phy_sgmii_rxd_int),
    .phy_sgmii_rx_dv(phy_sgmii_rx_dv_int),
    .phy_sgmii_rx_er(phy_sgmii_rx_er_int),
    .phy_sgmii_txd(phy_sgmii_txd_int),
    .phy_sgmii_tx_en(phy_sgmii_tx_en_int),
    .phy_sgmii_tx_er(phy_sgmii_tx_er_int),
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
