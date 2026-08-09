// SPDX-License-Identifier: MIT
/*

Copyright (c) 2025 FPGA Ninja, LLC

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
    parameter string FAMILY = "zynquplus",
    // Use 90 degree clock for RGMII transmit
    parameter logic USE_CLK90 = 1'b1,
    // MAC configuration
    parameter logic CFG_LOW_LATENCY = 1'b1,
    parameter logic COMBINED_MAC_PCS = 1'b1,
    parameter MAC_DATA_W = 32
)
(
    /*
     * Clock: 25MHz
     */
    input  wire logic        clk_25mhz,

    /*
     * GPIO
     */
    output wire logic [1:0]  led,
    output wire logic [1:0]  sfp_led,

    /*
     * Ethernet: 1000BASE-T RGMII
     */
    input  wire logic        phy2_rx_clk,
    input  wire logic [3:0]  phy2_rxd,
    input  wire logic        phy2_rx_ctl,
    output wire logic        phy2_tx_clk,
    output wire logic [3:0]  phy2_txd,
    output wire logic        phy2_tx_ctl,
    output wire logic        phy2_reset_n,

    input  wire logic        phy3_rx_clk,
    input  wire logic [3:0]  phy3_rxd,
    input  wire logic        phy3_rx_ctl,
    output wire logic        phy3_tx_clk,
    output wire logic [3:0]  phy3_txd,
    output wire logic        phy3_tx_ctl,
    output wire logic        phy3_reset_n,

    /*
     * Ethernet: SFP+
     */
    input  wire logic        sfp_rx_p,
    input  wire logic        sfp_rx_n,
    output wire logic        sfp_tx_p,
    output wire logic        sfp_tx_n,
    input  wire logic        sfp_mgt_refclk_p,
    input  wire logic        sfp_mgt_refclk_n,

    output wire logic        sfp_tx_disable,
    input  wire logic        sfp_tx_fault,
    input  wire logic        sfp_rx_los,
    input  wire logic        sfp_mod_abs,
    inout  wire logic        sfp_i2c_scl,
    inout  wire logic        sfp_i2c_sda
);

// Clock and reset

// Internal 125 MHz clock
wire clk_125mhz_mmcm_out;
wire clk90_125mhz_mmcm_out;
wire clk_125mhz_int;
wire clk90_125mhz_int;
wire rst_125mhz_int;

// Internal 62.5 MHz clock
wire clk_62mhz_mmcm_out;
wire clk_62mhz_int;

// Internal 312.5 MHz clock
wire clk_312mhz_mmcm_out;
wire clk_312mhz_int;
wire rst_312mhz_int;

wire mmcm_rst = 1'b0;
wire mmcm_locked;
wire mmcm_clkfb;

// MMCM instance
MMCME4_BASE #(
    // 25 MHz input
    .CLKIN1_PERIOD(40),
    .REF_JITTER1(0.010),
    // 25 MHz input / 1 = 25 MHz PFD (range 10 MHz to 500 MHz)
    .DIVCLK_DIVIDE(1),
    // 25 MHz PFD * 50 = 1250 MHz VCO (range 800 MHz to 1600 MHz)
    .CLKFBOUT_MULT_F(50),
    .CLKFBOUT_PHASE(0),
    // 1250 MHz / 10 = 125 MHz, 0 degrees
    .CLKOUT0_DIVIDE_F(10),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    // 1250 MHz / 10 = 125 MHz, 90 degrees
    .CLKOUT1_DIVIDE(10),
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(90),
    // 1250 MHz / 20 = 62.5 MHz, 0 degrees
    .CLKOUT2_DIVIDE(20),
    .CLKOUT2_DUTY_CYCLE(0.5),
    .CLKOUT2_PHASE(0),
    // 1250 MHz / 4 = 312.5 MHz, 0 degrees
    .CLKOUT3_DIVIDE(4),
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
    // 25 MHz input
    .CLKIN1(clk_25mhz),
    // direct clkfb feeback
    .CLKFBIN(mmcm_clkfb),
    .CLKFBOUT(mmcm_clkfb),
    .CLKFBOUTB(),
    // 125 MHz, 0 degrees
    .CLKOUT0(clk_125mhz_mmcm_out),
    .CLKOUT0B(),
    // 125 MHz, 90 degrees
    .CLKOUT1(clk90_125mhz_mmcm_out),
    .CLKOUT1B(),
    // 62.5 MHz, 0 degrees
    .CLKOUT2(clk_62mhz_mmcm_out),
    .CLKOUT2B(),
    // 312.5 MHz, 0 degrees
    .CLKOUT3(clk_312mhz_mmcm_out),
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

BUFG
clk90_125mhz_bufg_inst (
    .I(clk90_125mhz_mmcm_out),
    .O(clk90_125mhz_int)
);

BUFG
clk_62mhz_bufg_inst (
    .I(clk_62mhz_mmcm_out),
    .O(clk_62mhz_int)
);

BUFG
clk_312mhz_bufg_inst (
    .I(clk_312mhz_mmcm_out),
    .O(clk_312mhz_int)
);

taxi_sync_reset #(
    .N(4)
)
sync_reset_125mhz_inst (
    .clk(clk_125mhz_int),
    .rst(~mmcm_locked),
    .out(rst_125mhz_int)
);

taxi_sync_reset #(
    .N(4)
)
sync_reset_312mhz_inst (
    .clk(clk_312mhz_int),
    .rst(~mmcm_locked),
    .out(rst_312mhz_int)
);

// GPIO
wire sfp_tx_fault_int;
wire sfp_rx_los_int;
wire sfp_mod_abs_int;

wire sfp_i2c_scl_i;
wire sfp_i2c_scl_o;
wire sfp_i2c_scl_t;
wire sfp_i2c_sda_i;
wire sfp_i2c_sda_o;
wire sfp_i2c_sda_t;

reg sfp_i2c_scl_o_reg;
reg sfp_i2c_scl_t_reg;
reg sfp_i2c_sda_o_reg;
reg sfp_i2c_sda_t_reg;

always @(posedge clk_125mhz_int) begin
    sfp_i2c_scl_o_reg <= sfp_i2c_scl_o;
    sfp_i2c_scl_t_reg <= sfp_i2c_scl_t;
    sfp_i2c_sda_o_reg <= sfp_i2c_sda_o;
    sfp_i2c_sda_t_reg <= sfp_i2c_sda_t;
end

taxi_sync_signal #(
    .WIDTH(5),
    .N(2)
)
sync_signal_inst (
    .clk(clk_125mhz_int),
    .in({sfp_tx_fault, sfp_rx_los, sfp_mod_abs, sfp_i2c_scl, sfp_i2c_sda}),
    .out({sfp_tx_fault_int, sfp_rx_los_int, sfp_mod_abs_int, sfp_i2c_scl_i, sfp_i2c_sda_i})
);

assign sfp_i2c_scl = sfp_i2c_scl_t_reg ? 1'bz : sfp_i2c_scl_o_reg;
assign sfp_i2c_sda = sfp_i2c_sda_t_reg ? 1'bz : sfp_i2c_sda_o_reg;

// IODELAY elements for RGMII interface to PHY
wire [3:0] phy2_rxd_int;
wire phy2_rx_ctl_int;

wire [3:0] phy3_rxd_int;
wire phy3_rx_ctl_int;

IDELAYCTRL #(
    .SIM_DEVICE("ULTRASCALE")
)
idelayctrl_inst (
    .REFCLK(clk_312mhz_int),
    .RST(rst_312mhz_int),
    .RDY()
);

for (genvar n = 0; n < 4; n = n + 1) begin : phy2_rxd_idelay_bit
    
    IDELAYE3 #(
        .DELAY_SRC("IDATAIN"),
        .CASCADE("NONE"),
        .DELAY_TYPE("FIXED"),
        .DELAY_VALUE(0),
        .REFCLK_FREQUENCY(312.5),
        .DELAY_FORMAT("TIME"),
        .UPDATE_MODE("SYNC"),
        .SIM_DEVICE("ULTRASCALE_PLUS")
    )
    idelay_inst (
        .CASC_IN(1'b0),
        .CASC_RETURN(1'b0),
        .CASC_OUT(),
        .IDATAIN(phy2_rxd[n]),
        .DATAIN(1'b0),
        .DATAOUT(phy2_rxd_int[n]),
        .CLK(1'b0),
        .EN_VTC(1'b1),
        .CE(1'b0),
        .INC(1'b0),
        .LOAD(1'b0),
        .RST(1'b0),
        .CNTVALUEIN(9'd0),
        .CNTVALUEOUT()
    );

end

IDELAYE3 #(
    .DELAY_SRC("IDATAIN"),
    .CASCADE("NONE"),
    .DELAY_TYPE("FIXED"),
    .DELAY_VALUE(0),
    .REFCLK_FREQUENCY(312.5),
    .DELAY_FORMAT("TIME"),
    .UPDATE_MODE("SYNC"),
    .SIM_DEVICE("ULTRASCALE_PLUS")
)
phy2_rx_ctl_idelay (
    .CASC_IN(1'b0),
    .CASC_RETURN(1'b0),
    .CASC_OUT(),
    .IDATAIN(phy2_rx_ctl),
    .DATAIN(1'b0),
    .DATAOUT(phy2_rx_ctl_int),
    .CLK(1'b0),
    .EN_VTC(1'b1),
    .CE(1'b0),
    .INC(1'b0),
    .LOAD(1'b0),
    .RST(1'b0),
    .CNTVALUEIN(9'd0),
    .CNTVALUEOUT()
);

for (genvar n = 0; n < 4; n = n + 1) begin : phy3_rxd_idelay_bit
    
    IDELAYE3 #(
        .DELAY_SRC("IDATAIN"),
        .CASCADE("NONE"),
        .DELAY_TYPE("FIXED"),
        .DELAY_VALUE(0),
        .REFCLK_FREQUENCY(312.5),
        .DELAY_FORMAT("TIME"),
        .UPDATE_MODE("SYNC"),
        .SIM_DEVICE("ULTRASCALE_PLUS")
    )
    idelay_inst (
        .CASC_IN(1'b0),
        .CASC_RETURN(1'b0),
        .CASC_OUT(),
        .IDATAIN(phy3_rxd[n]),
        .DATAIN(1'b0),
        .DATAOUT(phy3_rxd_int[n]),
        .CLK(1'b0),
        .EN_VTC(1'b1),
        .CE(1'b0),
        .INC(1'b0),
        .LOAD(1'b0),
        .RST(1'b0),
        .CNTVALUEIN(9'd0),
        .CNTVALUEOUT()
    );

end

IDELAYE3 #(
    .DELAY_SRC("IDATAIN"),
    .CASCADE("NONE"),
    .DELAY_TYPE("FIXED"),
    .DELAY_VALUE(0),
    .REFCLK_FREQUENCY(312.5),
    .DELAY_FORMAT("TIME"),
    .UPDATE_MODE("SYNC"),
    .SIM_DEVICE("ULTRASCALE_PLUS")
)
phy3_rx_ctl_idelay (
    .CASC_IN(1'b0),
    .CASC_RETURN(1'b0),
    .CASC_OUT(),
    .IDATAIN(phy3_rx_ctl),
    .DATAIN(1'b0),
    .DATAOUT(phy3_rx_ctl_int),
    .CLK(1'b0),
    .EN_VTC(1'b1),
    .CE(1'b0),
    .INC(1'b0),
    .LOAD(1'b0),
    .RST(1'b0),
    .CNTVALUEIN(9'd0),
    .CNTVALUEOUT()
);

fpga_core #(
    .SIM(SIM),
    .VENDOR(VENDOR),
    .FAMILY(FAMILY),
    .USE_CLK90(USE_CLK90),
    .CFG_LOW_LATENCY(CFG_LOW_LATENCY),
    .COMBINED_MAC_PCS(COMBINED_MAC_PCS),
    .MAC_DATA_W(MAC_DATA_W)
)
core_inst (
    /*
     * Clock: 125MHz
     * Synchronous reset
     */
    .clk(clk_125mhz_int),
    .clk90(clk90_125mhz_int),
    .rst(rst_125mhz_int),

    /*
     * GPIO
     */
    .led(led),
    .sfp_led(sfp_led),

    /*
     * Ethernet: 1000BASE-T RGMII
     */
    .phy2_rgmii_rx_clk(phy2_rx_clk),
    .phy2_rgmii_rxd(phy2_rxd_int),
    .phy2_rgmii_rx_ctl(phy2_rx_ctl_int),
    .phy2_rgmii_tx_clk(phy2_tx_clk),
    .phy2_rgmii_txd(phy2_txd),
    .phy2_rgmii_tx_ctl(phy2_tx_ctl),
    .phy2_reset_n(phy2_reset_n),

    .phy3_rgmii_rx_clk(phy3_rx_clk),
    .phy3_rgmii_rxd(phy3_rxd_int),
    .phy3_rgmii_rx_ctl(phy3_rx_ctl_int),
    .phy3_rgmii_tx_clk(phy3_tx_clk),
    .phy3_rgmii_txd(phy3_txd),
    .phy3_rgmii_tx_ctl(phy3_tx_ctl),
    .phy3_reset_n(phy3_reset_n),

    /*
     * Ethernet: SFP+
     */
    .sfp_rx_p(sfp_rx_p),
    .sfp_rx_n(sfp_rx_n),
    .sfp_tx_p(sfp_tx_p),
    .sfp_tx_n(sfp_tx_n),
    .sfp_mgt_refclk_p(sfp_mgt_refclk_p),
    .sfp_mgt_refclk_n(sfp_mgt_refclk_n),

    .sfp_tx_disable(sfp_tx_disable),
    .sfp_tx_fault(sfp_tx_fault_int),
    .sfp_rx_los(sfp_rx_los_int),
    .sfp_mod_abs(sfp_mod_abs_int),

    .sfp_i2c_scl_i(sfp_i2c_scl_i),
    .sfp_i2c_scl_o(sfp_i2c_scl_o),
    .sfp_i2c_scl_t(sfp_i2c_scl_t),
    .sfp_i2c_sda_i(sfp_i2c_sda_i),
    .sfp_i2c_sda_o(sfp_i2c_sda_o),
    .sfp_i2c_sda_t(sfp_i2c_sda_t)
);

endmodule

`resetall
