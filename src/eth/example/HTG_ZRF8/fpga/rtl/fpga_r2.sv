// SPDX-License-Identifier: MIT
/*

Copyright (c) 2021-2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * FPGA top-level module for HTG-ZRF8-R2
 */
module fpga #
(
    // simulation (set to avoid vendor primitives)
    parameter logic SIM = 1'b0,
    // vendor ("GENERIC", "XILINX", "ALTERA")
    parameter string VENDOR = "XILINX",
    // device family
    parameter string FAMILY = "zynquplusRFSOC",
    // MAC configuration
    parameter logic CFG_LOW_LATENCY = 1'b1,
    parameter logic COMBINED_MAC_PCS = 1'b1,
    parameter MAC_DATA_W = 512
)
(
    /*
     * Clock: 200 MHz LVDS
     */
    input  wire logic         clk_pl_user1_p,
    input  wire logic         clk_pl_user1_n,
    input  wire logic         fpga_refclk_p,
    input  wire logic         fpga_refclk_n,
    input  wire logic         fpga_sysref_p,
    input  wire logic         fpga_sysref_n,

    /*
     * GPIO
     */
    input  wire logic         btn,
    input  wire logic [3:0]   sw,
    output wire logic [3:0]   led,

    /*
     * I2C for board management
     */
    inout  wire logic         i2c_scl,
    inout  wire logic         i2c_sda,
    output wire logic         i2c_rst_n,

    /*
     * PLL
     */
    output wire logic         clk_fdec,
    output wire logic         clk_finc,
    input  wire logic         clk_intr_n,
    input  wire logic         clk_lol_n,
    output wire logic         clk_sync_n,
    output wire logic         clk_rst_n,
    output wire logic         lmk_rst,
    output wire logic [1:0]   lmk_clkin_s,

    /*
     * UART: 921600 bps, 8N1
     */
    output wire logic         uart_rxd,
    input  wire logic         uart_txd,
    input  wire logic         uart_rts,
    output wire logic         uart_cts,
    output wire logic         uart_rst_n,
    input  wire logic         uart_suspend_n,

    /*
     * FMC+
     */
    // output wire logic [33:0]  fmc_la_p,
    // output wire logic [33:0]  fmc_la_n,
    output wire logic         fmc_qsfp_modsell,
    output wire logic         fmc_qsfp_resetl,
    output wire logic         fmc_qsfp_lpmode,

    output wire logic         fmc_dp_c2m_p[8],
    output wire logic         fmc_dp_c2m_n[8],
    input  wire logic         fmc_dp_m2c_p[8],
    input  wire logic         fmc_dp_m2c_n[8],
    input  wire logic         fmc_mgt_refclk_0_0_p,
    input  wire logic         fmc_mgt_refclk_0_0_n,
    input  wire logic         fmc_mgt_refclk_1_0_p,
    input  wire logic         fmc_mgt_refclk_1_0_n,

    /*
     * RFDC
     */
    input  wire logic [7:0]   adc_vin_p,
    input  wire logic [7:0]   adc_vin_n,

    input  wire logic         adc_refclk_0_p,
    input  wire logic         adc_refclk_0_n,
    input  wire logic         adc_refclk_1_p,
    input  wire logic         adc_refclk_1_n,
    input  wire logic         adc_refclk_2_p,
    input  wire logic         adc_refclk_2_n,
    input  wire logic         adc_refclk_3_p,
    input  wire logic         adc_refclk_3_n,

    output wire logic [7:0]   dac_vout_p,
    output wire logic [7:0]   dac_vout_n,

    // input  wire logic         dac_refclk_0_p,
    // input  wire logic         dac_refclk_0_n,
    input  wire logic         dac_refclk_1_p,
    input  wire logic         dac_refclk_1_n,

    input  wire logic         rfdc_sysref_p,
    input  wire logic         rfdc_sysref_n
);

// PLL
assign clk_fdec = 1'b0;
assign clk_finc = 1'b0;
assign clk_sync_n = 1'b1;
assign clk_rst_n = 1'b1;

assign lmk_rst = 1'b0;
assign lmk_clkin_s = 2'b00;

wire pll_i2c_busy;

// Clock and reset

wire clk_pl_user1_ibufg;
wire clk_pl_user1_bufg;

// Internal 125 MHz clock
wire clk_125mhz_mmcm_out;
wire clk_125mhz_int;
wire rst_125mhz_int;

wire mmcm_rst = pll_i2c_busy || !clk_lol_n;
wire mmcm_locked;
wire mmcm_clkfb;

IBUFGDS #(
   .DIFF_TERM("FALSE"),
   .IBUF_LOW_PWR("FALSE")
)
clk_pl_user1_ibufg_inst (
   .I (clk_pl_user1_p),
   .IB(clk_pl_user1_n),
   .O (clk_pl_user1_ibufg)
);

BUFG
clk_pl_user1_bufg_inst (
    .I(clk_pl_user1_ibufg),
    .O(clk_pl_user1_bufg)
);

// MMCM instance
MMCME4_BASE #(
    // 200 MHz input
    .CLKIN1_PERIOD(5.0),
    .REF_JITTER1(0.010),
    // 200 MHz input / 1 = 200 MHz PFD (range 10 MHz to 500 MHz)
    .DIVCLK_DIVIDE(1),
    // 200 MHz PFD * 5 = 1000 MHz VCO (range 800 MHz to 1600 MHz)
    .CLKFBOUT_MULT_F(5),
    .CLKFBOUT_PHASE(0),
    // 1000 MHz / 8 = 125 MHz, 0 degrees
    .CLKOUT0_DIVIDE_F(8),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    // Not used
    .CLKOUT1_DIVIDE(1),
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(0),
    // Not used
    .CLKOUT2_DIVIDE(1),
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
    .CLKIN1(clk_pl_user1_bufg),
    // direct clkfb feeback
    .CLKFBIN(mmcm_clkfb),
    .CLKFBOUT(mmcm_clkfb),
    .CLKFBOUTB(),
    // 125 MHz, 0 degrees
    .CLKOUT0(clk_125mhz_mmcm_out),
    .CLKOUT0B(),
    // Not used
    .CLKOUT1(),
    .CLKOUT1B(),
    // Not used
    .CLKOUT2(),
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
clk_125mhz_bufg_inst (
    .I(clk_125mhz_mmcm_out),
    .O(clk_125mhz_int)
);

taxi_sync_reset #(
    .N(4)
)
sync_reset_125mhz_inst (
    .clk(clk_125mhz_int),
    .rst(~mmcm_locked),
    .out(rst_125mhz_int)
);

wire fpga_refclk_ibufg;
wire fpga_refclk_int;
wire fpga_sysref_ibufg;
wire fpga_sysref_int;

IBUFGDS #(
   .DIFF_TERM("FALSE"),
   .IBUF_LOW_PWR("FALSE")
)
fpga_refclk_ibufg_inst (
   .O   (fpga_refclk_ibufg),
   .I   (fpga_refclk_p),
   .IB  (fpga_refclk_n)
);

BUFG
fpga_refclk_bufg_inst (
    .I(fpga_refclk_ibufg),
    .O(fpga_refclk_int)
);

IBUFGDS #(
   .DIFF_TERM("FALSE"),
   .IBUF_LOW_PWR("FALSE")
)
fpga_sysref_ibufg_inst (
   .O   (fpga_sysref_ibufg),
   .I   (fpga_sysref_p),
   .IB  (fpga_sysref_n)
);

BUFG
fpga_sysref_bufg_inst (
    .I(fpga_sysref_ibufg),
    .O(fpga_sysref_int)
);

// STARTUP instance for cfgmclk
wire cfgmclk;

STARTUPE3
startupe3_inst (
    .CFGCLK(),
    .CFGMCLK(cfgmclk),
    .DI(),
    .DO(4'd0),
    .DTS(1'b1),
    .EOS(),
    .FCSBO(1'b1),
    .FCSBTS(1'b1),
    .GSR(1'b0),
    .GTS(1'b0),
    .KEYCLEARB(1'b1),
    .PACK(1'b0),
    .PREQ(),
    .USRCCLKO(1'b0),
    .USRCCLKTS(1'b1),
    .USRDONEO(1'b0),
    .USRDONETS(1'b1)
);

wire cfgmclk_int;

BUFG
cfgmclk_bufg_inst (
    .I(cfgmclk),
    .O(cfgmclk_int)
);

wire cfgmclk_rst_int;

taxi_sync_reset #(
    .N(4)
)
sync_reset_cfgmclk_inst (
    .clk(cfgmclk_int),
    .rst(~btn),
    .out(cfgmclk_rst_int)
);

// GPIO
wire [3:0] sw_int;

taxi_debounce_switch #(
    .WIDTH(4),
    .N(4),
    .RATE(125000)
)
debounce_switch_inst (
    .clk(clk_125mhz_int),
    .rst(rst_125mhz_int),
    .in({sw}),
    .out({sw_int})
);

wire uart_txd_int;
wire uart_rts_int;

taxi_sync_signal #(
    .WIDTH(2),
    .N(2)
)
sync_signal_inst (
    .clk(clk_125mhz_int),
    .in({uart_txd, uart_rts}),
    .out({uart_txd_int, uart_rts_int})
);

wire i2c_scl_i;
wire i2c_scl_o;
wire i2c_sda_i;
wire i2c_sda_o;

assign i2c_scl_i = i2c_scl;
assign i2c_scl = i2c_scl_o ? 1'bz : 1'b0;
assign i2c_sda_i = i2c_sda;
assign i2c_sda = i2c_sda_o ? 1'bz : 1'b0;
assign i2c_rst_n = 1'b1;

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

// PLL init
taxi_axis_if #(.DATA_W(12)) pll_i2c_cmd();
taxi_axis_if #(.DATA_W(8)) pll_i2c_tx();
taxi_axis_if #(.DATA_W(8)) pll_i2c_rx();

assign pll_i2c_rx.tready = 1'b1;

taxi_i2c_master
pll_i2c_master_inst (
    .clk(cfgmclk_int),
    .rst(cfgmclk_rst_int),

    /*
     * Host interface
     */
    .s_axis_cmd(pll_i2c_cmd),
    .s_axis_tx(pll_i2c_tx),
    .m_axis_rx(pll_i2c_rx),

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
    .prescale(SIM ? 15 : 150),
    .stop_on_idle(1)
);

pll_i2c_init_r2 #(
    .SIM_SPEEDUP(SIM)
)
pll_i2c_init_inst (
    .clk(cfgmclk_int),
    .rst(cfgmclk_rst_int),

    /*
     * I2C master interface
     */
    .m_axis_cmd(pll_i2c_cmd),
    .m_axis_tx(pll_i2c_tx),

    /*
     * Status
     */
    .busy(pll_i2c_busy),

    /*
     * Configuration
     */
    .start(1'b1)
);

localparam PORT_CNT = 2;
localparam GTY_QUAD_CNT = PORT_CNT;
localparam GTY_CNT = GTY_QUAD_CNT*4;
localparam GTY_CLK_CNT = GTY_QUAD_CNT;

assign fmc_qsfp_modsell = 1'b0;
assign fmc_qsfp_resetl = 1'b1;
assign fmc_qsfp_lpmode = 1'b0;

// RF data converters
localparam ADC_CNT = 8;
localparam ADC_SAMPLE_W = 16;
localparam ADC_SAMPLE_CNT = 4;
localparam ADC_DATA_W = ADC_SAMPLE_W*ADC_SAMPLE_CNT;

localparam DAC_CNT = ADC_CNT;
localparam DAC_SAMPLE_W = ADC_SAMPLE_W;
localparam DAC_SAMPLE_CNT = ADC_SAMPLE_CNT;
localparam DAC_DATA_W = DAC_SAMPLE_W*DAC_SAMPLE_CNT;

wire axil_rfdc_clk = clk_125mhz_int;
wire axil_rfdc_rst = rst_125mhz_int;

taxi_axil_if #(
    .DATA_W(32),
    .ADDR_W(18)
) axil_rfdc();

wire axis_rfdc_clk;
wire axis_rfdc_rst;

wire [3:0] adc_clk_out;
wire [3:0] dac_clk_out;

taxi_axis_if #(
    .DATA_W(ADC_DATA_W),
    .KEEP_EN(1),
    .KEEP_W(ADC_SAMPLE_CNT),
    .LAST_EN(0),
    .USER_EN(0),
    .ID_EN(0),
    .DEST_EN(0)
) axis_adc[ADC_CNT]();

(* MARK_DEBUG = "TRUE" *)
wire [ADC_DATA_W-1:0] adc_data_0 = axis_adc[0].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [ADC_DATA_W-1:0] adc_data_1 = axis_adc[1].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [ADC_DATA_W-1:0] adc_data_2 = axis_adc[2].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [ADC_DATA_W-1:0] adc_data_3 = axis_adc[3].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [ADC_DATA_W-1:0] adc_data_4 = axis_adc[4].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [ADC_DATA_W-1:0] adc_data_5 = axis_adc[5].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [ADC_DATA_W-1:0] adc_data_6 = axis_adc[6].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [ADC_DATA_W-1:0] adc_data_7 = axis_adc[7].tdata;

taxi_axis_if #(
    .DATA_W(DAC_DATA_W),
    .KEEP_EN(1),
    .KEEP_W(DAC_SAMPLE_CNT),
    .LAST_EN(0),
    .USER_EN(0),
    .ID_EN(0),
    .DEST_EN(0)
) axis_dac[DAC_CNT]();

(* MARK_DEBUG = "TRUE" *)
wire [DAC_DATA_W-1:0] dac_data_0 = axis_dac[0].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [DAC_DATA_W-1:0] dac_data_1 = axis_dac[1].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [DAC_DATA_W-1:0] dac_data_2 = axis_dac[2].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [DAC_DATA_W-1:0] dac_data_3 = axis_dac[3].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [DAC_DATA_W-1:0] dac_data_4 = axis_dac[4].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [DAC_DATA_W-1:0] dac_data_5 = axis_dac[5].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [DAC_DATA_W-1:0] dac_data_6 = axis_dac[6].tdata;
(* MARK_DEBUG = "TRUE" *)
wire [DAC_DATA_W-1:0] dac_data_7 = axis_dac[7].tdata;

wire rfdc_mmcm_in = dac_clk_out[0];
wire rfdc_mmcm_rst = rst_125mhz_int;
wire rfdc_mmcm_clkfb;
wire rfdc_mmcm_locked;
wire rfdc_mmcm_out;

// MMCM instance
MMCME4_BASE #(
    // 62.5 MHz input
    .CLKIN1_PERIOD(16.0),
    .REF_JITTER1(0.010),
    // 62.5 MHz input / 1 = 62.5 MHz PFD (range 10 MHz to 500 MHz)
    .DIVCLK_DIVIDE(1),
    // 62.5 MHz PFD * 20 = 1250 MHz VCO (range 800 MHz to 1600 MHz)
    .CLKFBOUT_MULT_F(20),
    .CLKFBOUT_PHASE(0),
    // 1250 MHz / 5 = 250 MHz, 0 degrees
    .CLKOUT0_DIVIDE_F(5),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    // Not used
    .CLKOUT1_DIVIDE(1),
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(0),
    // Not used
    .CLKOUT2_DIVIDE(1),
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
rfdc_mmcm_inst (
    // 62.5 MHz input
    .CLKIN1(rfdc_mmcm_in),
    // direct clkfb feeback
    .CLKFBIN(rfdc_mmcm_clkfb),
    .CLKFBOUT(rfdc_mmcm_clkfb),
    .CLKFBOUTB(),
    // 250 MHz, 0 degrees
    .CLKOUT0(rfdc_mmcm_out),
    .CLKOUT0B(),
    // Not used
    .CLKOUT1(),
    .CLKOUT1B(),
    // Not used
    .CLKOUT2(),
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
    .RST(rfdc_mmcm_rst),
    // don't power down
    .PWRDWN(1'b0),
    // locked output
    .LOCKED(rfdc_mmcm_locked)
);

BUFG
axis_rfdc_bufg_inst (
    .I(rfdc_mmcm_out),
    .O(axis_rfdc_clk)
);

taxi_sync_reset #(
    .N(4)
)
axis_rfdc_sync_reset_inst (
    .clk(axis_rfdc_clk),
    .rst(!rfdc_mmcm_locked || rfdc_mmcm_rst),
    .out(axis_rfdc_rst)
);

usp_rfdc_0 rfdc_inst (
    // Common
    .sysref_in_p(rfdc_sysref_p),
    .sysref_in_n(rfdc_sysref_n),

    .s_axi_aclk(axil_rfdc_clk),
    .s_axi_aresetn(!axil_rfdc_rst),
    .s_axi_awaddr(axil_rfdc.awaddr),
    .s_axi_awvalid(axil_rfdc.awvalid),
    .s_axi_awready(axil_rfdc.awready),
    .s_axi_wdata(axil_rfdc.wdata),
    .s_axi_wstrb(axil_rfdc.wstrb),
    .s_axi_wvalid(axil_rfdc.wvalid),
    .s_axi_wready(axil_rfdc.wready),
    .s_axi_bresp(axil_rfdc.bresp),
    .s_axi_bvalid(axil_rfdc.bvalid),
    .s_axi_bready(axil_rfdc.bready),
    .s_axi_araddr(axil_rfdc.araddr),
    .s_axi_arvalid(axil_rfdc.arvalid),
    .s_axi_arready(axil_rfdc.arready),
    .s_axi_rdata(axil_rfdc.rdata),
    .s_axi_rresp(axil_rfdc.rresp),
    .s_axi_rvalid(axil_rfdc.rvalid),
    .s_axi_rready(axil_rfdc.rready),

    .irq(),

    // ADC
    .adc0_clk_p(adc_refclk_0_p),
    .adc0_clk_n(adc_refclk_0_n),
    .clk_adc0(adc_clk_out[0]),

    .adc1_clk_p(adc_refclk_1_p),
    .adc1_clk_n(adc_refclk_1_n),
    .clk_adc1(adc_clk_out[1]),

    .adc2_clk_p(adc_refclk_2_p),
    .adc2_clk_n(adc_refclk_2_n),
    .clk_adc2(adc_clk_out[2]),

    .adc3_clk_p(adc_refclk_3_p),
    .adc3_clk_n(adc_refclk_3_n),
    .clk_adc3(adc_clk_out[3]),

    .vin0_01_p(adc_vin_p[7]),
    .vin0_01_n(adc_vin_n[7]),
    .vin0_23_p(adc_vin_p[6]),
    .vin0_23_n(adc_vin_n[6]),

    .vin1_01_p(adc_vin_p[5]),
    .vin1_01_n(adc_vin_n[5]),
    .vin1_23_p(adc_vin_p[4]),
    .vin1_23_n(adc_vin_n[4]),

    .vin2_01_p(adc_vin_p[3]),
    .vin2_01_n(adc_vin_n[3]),
    .vin2_23_p(adc_vin_p[2]),
    .vin2_23_n(adc_vin_n[2]),

    .vin3_01_p(adc_vin_p[1]),
    .vin3_01_n(adc_vin_n[1]),
    .vin3_23_p(adc_vin_p[0]),
    .vin3_23_n(adc_vin_n[0]),

    .m0_axis_aresetn(!axis_rfdc_rst),
    .m0_axis_aclk(axis_rfdc_clk),
    .m00_axis_tdata(axis_adc[7].tdata),
    .m00_axis_tvalid(axis_adc[7].tvalid),
    .m00_axis_tready(axis_adc[7].tready),
    .m02_axis_tdata(axis_adc[6].tdata),
    .m02_axis_tvalid(axis_adc[6].tvalid),
    .m02_axis_tready(axis_adc[6].tready),

    .m1_axis_aresetn(!axis_rfdc_rst),
    .m1_axis_aclk(axis_rfdc_clk),
    .m10_axis_tdata(axis_adc[5].tdata),
    .m10_axis_tvalid(axis_adc[5].tvalid),
    .m10_axis_tready(axis_adc[5].tready),
    .m12_axis_tdata(axis_adc[4].tdata),
    .m12_axis_tvalid(axis_adc[4].tvalid),
    .m12_axis_tready(axis_adc[4].tready),

    .m2_axis_aresetn(!axis_rfdc_rst),
    .m2_axis_aclk(axis_rfdc_clk),
    .m20_axis_tdata(axis_adc[3].tdata),
    .m20_axis_tvalid(axis_adc[3].tvalid),
    .m20_axis_tready(axis_adc[3].tready),
    .m22_axis_tdata(axis_adc[2].tdata),
    .m22_axis_tvalid(axis_adc[2].tvalid),
    .m22_axis_tready(axis_adc[2].tready),

    .m3_axis_aresetn(!axis_rfdc_rst),
    .m3_axis_aclk(axis_rfdc_clk),
    .m30_axis_tdata(axis_adc[1].tdata),
    .m30_axis_tvalid(axis_adc[1].tvalid),
    .m30_axis_tready(axis_adc[1].tready),
    .m32_axis_tdata(axis_adc[0].tdata),
    .m32_axis_tvalid(axis_adc[0].tvalid),
    .m32_axis_tready(axis_adc[0].tready),

    .adc0_01_dsa_code(5'd27),
    .adc0_23_dsa_code(5'd27),
    .adc0_dsa_update(1'b0),
    .adc1_01_dsa_code(5'd27),
    .adc1_23_dsa_code(5'd27),
    .adc1_dsa_update(1'b0),
    .adc2_01_dsa_code(5'd27),
    .adc2_23_dsa_code(5'd27),
    .adc2_dsa_update(1'b0),
    .adc3_01_dsa_code(5'd27),
    .adc3_23_dsa_code(5'd27),
    .adc3_dsa_update(1'b0),

    // DAC
    .dac2_clk_p(dac_refclk_1_p),
    .dac2_clk_n(dac_refclk_1_n),

    .clk_dac0(dac_clk_out[0]),
    .clk_dac1(dac_clk_out[1]),
    .clk_dac2(dac_clk_out[2]),
    .clk_dac3(dac_clk_out[3]),

    .vout00_p(dac_vout_p[7]),
    .vout00_n(dac_vout_n[7]),
    .vout02_p(dac_vout_p[6]),
    .vout02_n(dac_vout_n[6]),

    .vout10_p(dac_vout_p[5]),
    .vout10_n(dac_vout_n[5]),
    .vout12_p(dac_vout_p[4]),
    .vout12_n(dac_vout_n[4]),

    .vout20_p(dac_vout_p[3]),
    .vout20_n(dac_vout_n[3]),
    .vout22_p(dac_vout_p[2]),
    .vout22_n(dac_vout_n[2]),

    .vout30_p(dac_vout_p[1]),
    .vout30_n(dac_vout_n[1]),
    .vout32_p(dac_vout_p[0]),
    .vout32_n(dac_vout_n[0]),

    .s0_axis_aresetn(!axis_rfdc_rst),
    .s0_axis_aclk(axis_rfdc_clk),
    .s00_axis_tdata(axis_dac[7].tdata),
    .s00_axis_tvalid(axis_dac[7].tvalid),
    .s00_axis_tready(axis_dac[7].tready),
    .s02_axis_tdata(axis_dac[6].tdata),
    .s02_axis_tvalid(axis_dac[6].tvalid),
    .s02_axis_tready(axis_dac[6].tready),

    .s1_axis_aresetn(!axis_rfdc_rst),
    .s1_axis_aclk(axis_rfdc_clk),
    .s10_axis_tdata(axis_dac[5].tdata),
    .s10_axis_tvalid(axis_dac[5].tvalid),
    .s10_axis_tready(axis_dac[5].tready),
    .s12_axis_tdata(axis_dac[4].tdata),
    .s12_axis_tvalid(axis_dac[4].tvalid),
    .s12_axis_tready(axis_dac[4].tready),

    .s2_axis_aresetn(!axis_rfdc_rst),
    .s2_axis_aclk(axis_rfdc_clk),
    .s20_axis_tdata(axis_dac[3].tdata),
    .s20_axis_tvalid(axis_dac[3].tvalid),
    .s20_axis_tready(axis_dac[3].tready),
    .s22_axis_tdata(axis_dac[2].tdata),
    .s22_axis_tvalid(axis_dac[2].tvalid),
    .s22_axis_tready(axis_dac[2].tready),

    .s3_axis_aresetn(!axis_rfdc_rst),
    .s3_axis_aclk(axis_rfdc_clk),
    .s30_axis_tdata(axis_dac[1].tdata),
    .s30_axis_tvalid(axis_dac[1].tvalid),
    .s30_axis_tready(axis_dac[1].tready),
    .s32_axis_tdata(axis_dac[0].tdata),
    .s32_axis_tvalid(axis_dac[0].tvalid),
    .s32_axis_tready(axis_dac[0].tready),

    .dac00_vop_code(10'd895),
    .dac02_vop_code(10'd895),
    .dac00_update_vop(1'b0),
    .dac02_update_vop(1'b0),
    .dac00_vop_done(),
    .dac02_vop_done(),
    .dac0_vop_busy(),

    .dac10_vop_code(10'd895),
    .dac12_vop_code(10'd895),
    .dac10_update_vop(1'b0),
    .dac12_update_vop(1'b0),
    .dac10_vop_done(),
    .dac12_vop_done(),
    .dac1_vop_busy(),

    .dac20_vop_code(10'd895),
    .dac22_vop_code(10'd895),
    .dac20_update_vop(1'b0),
    .dac22_update_vop(1'b0),
    .dac20_vop_done(),
    .dac22_vop_done(),
    .dac2_vop_busy(),

    .dac30_vop_code(10'd895),
    .dac32_vop_code(10'd895),
    .dac30_update_vop(1'b0),
    .dac32_update_vop(1'b0),
    .dac30_vop_done(),
    .dac32_vop_done(),
    .dac3_vop_busy()
);

fpga_core #(
    .SIM(SIM),
    .VENDOR(VENDOR),
    .FAMILY(FAMILY),
    .PORT_CNT(PORT_CNT),
    .GTY_QUAD_CNT(GTY_QUAD_CNT),
    .GTY_CNT(GTY_CNT),
    .GTY_CLK_CNT(GTY_CLK_CNT),
    .ADC_CNT(ADC_CNT),
    .DAC_CNT(DAC_CNT),
    .CFG_LOW_LATENCY(CFG_LOW_LATENCY),
    .COMBINED_MAC_PCS(COMBINED_MAC_PCS),
    .MAC_DATA_W(MAC_DATA_W)
)
core_inst (
    /*
     * Clock: 125MHz
     * Synchronous reset
     */
    .clk_125mhz(clk_125mhz_int),
    .rst_125mhz(rst_125mhz_int),
    .fpga_refclk(fpga_refclk_int),
    .fpga_sysref(fpga_sysref_int),

    /*
     * GPIO
     */
    .sw(sw_int),
    .led(led),
    .gpio(),

    /*
     * I2C for board management
     */
    .i2c_scl_i(i2c_int_scl_i),
    .i2c_scl_o(i2c_int_scl_o),
    .i2c_sda_i(i2c_int_sda_i),
    .i2c_sda_o(i2c_int_sda_o),

    /*
     * UART: 921600 bps, 8N1
     */
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd_int),
    .uart_rts(uart_rts_int),
    .uart_cts(uart_cts),
    .uart_rst_n(uart_rst_n),
    .uart_suspend_n(uart_suspend_n),

    /*
     * Ethernet: QSFP28
     */
    .eth_gty_tx_p(fmc_dp_c2m_p),
    .eth_gty_tx_n(fmc_dp_c2m_n),
    .eth_gty_rx_p(fmc_dp_m2c_p),
    .eth_gty_rx_n(fmc_dp_m2c_n),
    .eth_gty_mgt_refclk_p({fmc_mgt_refclk_1_0_p, fmc_mgt_refclk_0_0_p}),
    .eth_gty_mgt_refclk_n({fmc_mgt_refclk_1_0_n, fmc_mgt_refclk_0_0_n}),
    .eth_gty_mgt_refclk_out(),

    .eth_port_resetl(),
    .eth_port_modprsl('0),
    .eth_port_intl('1),

    /*
     * RFDC
     */
    .axil_rfdc_clk(axil_rfdc_clk),
    .axil_rfdc_rst(axil_rfdc_rst),
    .m_axil_rfdc_wr(axil_rfdc),
    .m_axil_rfdc_rd(axil_rfdc),

    .axis_rfdc_clk(axis_rfdc_clk),
    .axis_rfdc_rst(axis_rfdc_rst),
    .s_axis_adc(axis_adc),
    .m_axis_dac(axis_dac)
);

endmodule

`resetall
