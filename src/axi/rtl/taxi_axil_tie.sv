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
 * AXI4 lite tie
 */
module taxi_axil_tie
(
    /*
     * AXI4 lite slave interface
     */
    taxi_axil_if.wr_slv  s_axil_wr,
    taxi_axil_if.rd_slv  s_axil_rd,

    /*
     * AXI4 lite master interface
     */
    taxi_axil_if.wr_mst  m_axil_wr,
    taxi_axil_if.rd_mst  m_axil_rd
);

taxi_axil_tie_wr
wr_inst (
    /*
     * AXI4 lite slave interface
     */
    .s_axil_wr(s_axil_wr),

    /*
     * AXI4 lite master interface
     */
    .m_axil_wr(m_axil_wr)
);

taxi_axil_tie_rd
rd_inst (
    /*
     * AXI4 lite slave interface
     */
    .s_axil_rd(s_axil_rd),

    /*
     * AXI4 lite master interface
     */
    .m_axil_rd(m_axil_rd)
);

endmodule

`resetall
