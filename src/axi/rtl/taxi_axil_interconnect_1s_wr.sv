// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2021-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4 lite interconnect
 */
module taxi_axil_interconnect_1s_wr #
(
    // Number of AXI outputs (master interfaces)
    parameter M_COUNT = 4,
    // Address width in bits for address decoding
    parameter ADDR_W = 32,
    // TODO fix parametrization once verilator issue 5890 is fixed
    // Number of concurrent operations for each slave interface
    // 1 concatenated fields of 32 bits
    // Number of regions per master interface
    parameter M_REGIONS = 1,
    // Master interface base addresses
    // M_COUNT concatenated fields of M_REGIONS concatenated fields of ADDR_W bits
    // set to zero for default addressing based on M_ADDR_W
    parameter M_BASE_ADDR = '0,
    // Master interface address widths
    // M_COUNT concatenated fields of M_REGIONS concatenated fields of 32 bits
    parameter M_ADDR_W = {M_COUNT{{M_REGIONS{32'd24}}}},
    // Number of concurrent operations for each master interface
    // M_COUNT concatenated fields of 32 bits
    // Secure master (fail operations based on awprot/arprot)
    // M_COUNT bits
    parameter M_SECURE = {M_COUNT{1'b0}}
)
(
    input  wire logic    clk,
    input  wire logic    rst,

    /*
     * AXI4-lite slave interface
     */
    taxi_axil_if.wr_slv  s_axil_wr,

    /*
     * AXI4-lite master interfaces
     */
    taxi_axil_if.wr_mst  m_axil_wr[M_COUNT]
);

taxi_axil_if #(
    .DATA_W(s_axil_wr.DATA_W),
    .ADDR_W(s_axil_wr.ADDR_W),
    .STRB_W(s_axil_wr.STRB_W),
    .AWUSER_EN(s_axil_wr.AWUSER_EN),
    .AWUSER_W(s_axil_wr.AWUSER_W),
    .WUSER_EN(s_axil_wr.WUSER_EN),
    .WUSER_W(s_axil_wr.WUSER_W),
    .BUSER_EN(s_axil_wr.BUSER_EN),
    .BUSER_W(s_axil_wr.BUSER_W),
    .ARUSER_EN(s_axil_wr.ARUSER_EN),
    .ARUSER_W(s_axil_wr.ARUSER_W),
    .RUSER_EN(s_axil_wr.RUSER_EN),
    .RUSER_W(s_axil_wr.RUSER_W)
)
s_axil_wr_int[1]();

taxi_axil_tie_wr
tie_inst (
    .s_axil_wr(s_axil_wr),
    .m_axil_wr(s_axil_wr_int[0])
);

taxi_axil_interconnect_wr #(
    .S_COUNT(1),
    .M_COUNT(M_COUNT),
    .ADDR_W(ADDR_W),
    .M_REGIONS(M_REGIONS),
    .M_BASE_ADDR(M_BASE_ADDR),
    .M_ADDR_W(M_ADDR_W),
    .M_SECURE(M_SECURE)
)
wr_inst (
    .clk(clk),
    .rst(rst),

    /*
     * AXI4-lite slave interface
     */
    .s_axil_wr(s_axil_wr_int),

    /*
     * AXI4-lite master interfaces
     */
    .m_axil_wr(m_axil_wr)
);

endmodule

`resetall
