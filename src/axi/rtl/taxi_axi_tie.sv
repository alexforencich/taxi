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
 * AXI4 tie
 */
module taxi_axi_tie
(
    /*
     * AXI4 slave interface
     */
    taxi_axi_if.wr_slv  s_axi_wr,
    taxi_axi_if.rd_slv  s_axi_rd,

    /*
     * AXI4 master interface
     */
    taxi_axi_if.wr_mst  m_axi_wr,
    taxi_axi_if.rd_mst  m_axi_rd
);

taxi_axi_tie_wr
wr_inst (
    /*
     * AXI4 slave interface
     */
    .s_axi_wr(s_axi_wr),

    /*
     * AXI4 master interface
     */
    .m_axi_wr(m_axi_wr)
);

taxi_axi_tie_rd
rd_inst (
    /*
     * AXI4 slave interface
     */
    .s_axi_rd(s_axi_rd),

    /*
     * AXI4 master interface
     */
    .m_axi_rd(m_axi_rd)
);

endmodule

`resetall
