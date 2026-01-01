// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Corundum-micro descriptor read module
 */
module cndm_micro_desc_rd
(
    input  wire logic         clk,
    input  wire logic         rst,

    /*
     * DMA
     */
    taxi_dma_desc_if.req_src  dma_rd_desc_req,
    taxi_dma_desc_if.sts_snk  dma_rd_desc_sts,
    taxi_dma_ram_if.wr_slv    dma_ram_wr,

    input  wire logic         txq_en,
    input  wire logic [3:0]   txq_size,
    input  wire logic [63:0]  txq_base_addr,
    input  wire logic [15:0]  txq_prod,
    output wire logic [15:0]  txq_cons,
    input  wire logic         rxq_en,
    input  wire logic [3:0]   rxq_size,
    input  wire logic [63:0]  rxq_base_addr,
    input  wire logic [15:0]  rxq_prod,
    output wire logic [15:0]  rxq_cons,

    input  wire logic [1:0]   desc_req,
    taxi_axis_if.src          axis_desc[2]
);

localparam RAM_ADDR_W = 16;

taxi_dma_desc_if #(
    .SRC_ADDR_W(RAM_ADDR_W),
    .SRC_SEL_EN(1'b0),
    .SRC_ASID_EN(1'b0),
    .DST_ADDR_W(RAM_ADDR_W),
    .DST_SEL_EN(1'b0),
    .DST_ASID_EN(1'b0),
    .IMM_EN(1'b0),
    .LEN_W(5),
    .TAG_W(1),
    .ID_EN(0),
    .DEST_EN(1),
    .DEST_W(1),
    .USER_EN(1),
    .USER_W(1)
) dma_desc();

localparam [2:0]
    STATE_IDLE = 0,
    STATE_READ_DESC = 1,
    STATE_READ_DATA = 2,
    STATE_TX_DESC = 3;

logic [2:0] state_reg = STATE_IDLE;

logic [1:0] desc_req_reg = '0;

logic [15:0] txq_cons_ptr_reg = '0;
logic [15:0] rxq_cons_ptr_reg = '0;

assign txq_cons = txq_cons_ptr_reg;
assign rxq_cons = rxq_cons_ptr_reg;

always_ff @(posedge clk) begin
    // axis_desc.tready <= 1'b0;

    dma_rd_desc_req.req_src_sel <= '0;
    dma_rd_desc_req.req_src_asid <= '0;
    dma_rd_desc_req.req_dst_sel <= '0;
    dma_rd_desc_req.req_dst_asid <= '0;
    dma_rd_desc_req.req_imm <= '0;
    dma_rd_desc_req.req_imm_en <= '0;
    dma_rd_desc_req.req_len <= 16;
    dma_rd_desc_req.req_tag <= '0;
    dma_rd_desc_req.req_id <= '0;
    dma_rd_desc_req.req_dest <= '0;
    dma_rd_desc_req.req_user <= '0;
    dma_rd_desc_req.req_valid <= dma_rd_desc_req.req_valid && !dma_rd_desc_req.req_ready;

    dma_desc.req_src_sel <= '0;
    dma_desc.req_src_asid <= '0;
    dma_desc.req_dst_addr <= '0;
    dma_desc.req_dst_sel <= '0;
    dma_desc.req_dst_asid <= '0;
    dma_desc.req_imm <= '0;
    dma_desc.req_imm_en <= '0;
    dma_desc.req_len <= 16;
    dma_desc.req_tag <= '0;
    dma_desc.req_id <= '0;
    dma_desc.req_user <= '0;
    dma_desc.req_valid <= dma_desc.req_valid && !dma_desc.req_ready;

    desc_req_reg <= desc_req_reg | desc_req;

    if (!txq_en) begin
        txq_cons_ptr_reg <= '0;
    end

    if (!rxq_en) begin
        rxq_cons_ptr_reg <= '0;
    end

    case (state_reg)
        STATE_IDLE: begin
            if (desc_req_reg[1]) begin
                dma_rd_desc_req.req_src_addr <= rxq_base_addr + 64'(16'(rxq_cons_ptr_reg & ({16{1'b1}} >> (16 - rxq_size))) * 16);
                dma_desc.req_dest <= 1'b1;
                desc_req_reg[1] <= 1'b0;
                if (rxq_cons_ptr_reg == rxq_prod || !rxq_en) begin
                    dma_desc.req_user <= 1'b1;
                    dma_desc.req_valid <= 1'b1;
                    state_reg <= STATE_TX_DESC;
                end else begin
                    dma_desc.req_user <= 1'b0;
                    dma_rd_desc_req.req_valid <= 1'b1;
                    rxq_cons_ptr_reg <= rxq_cons_ptr_reg + 1;
                    state_reg <= STATE_READ_DESC;
                end
            end else if (desc_req_reg[0]) begin
                dma_rd_desc_req.req_src_addr <= txq_base_addr + 64'(16'(txq_cons_ptr_reg & ({16{1'b1}} >> (16 - txq_size))) * 16);
                dma_desc.req_dest <= 1'b0;
                desc_req_reg[0] <= 1'b0;
                if (txq_cons_ptr_reg == txq_prod || !txq_en) begin
                    dma_desc.req_user <= 1'b1;
                    dma_desc.req_valid <= 1'b1;
                    state_reg <= STATE_TX_DESC;
                end else begin
                    dma_desc.req_user <= 1'b0;
                    dma_rd_desc_req.req_valid <= 1'b1;
                    txq_cons_ptr_reg <= txq_cons_ptr_reg + 1;
                    state_reg <= STATE_READ_DESC;
                end
            end
        end
        STATE_READ_DESC: begin
            if (dma_rd_desc_sts.sts_valid) begin
                dma_desc.req_valid <= 1'b1;
                state_reg <= STATE_TX_DESC;
            end
        end
        STATE_TX_DESC: begin
            if (dma_desc.sts_valid) begin
                state_reg <= STATE_IDLE;
            end
        end
        default: begin
            state_reg <= STATE_IDLE;
        end
    endcase

    if (rst) begin
        state_reg <= STATE_IDLE;
    end
end

taxi_dma_ram_if #(
    .SEGS(dma_ram_wr.SEGS),
    .SEG_ADDR_W(dma_ram_wr.SEG_ADDR_W),
    .SEG_DATA_W(dma_ram_wr.SEG_DATA_W),
    .SEG_BE_W(dma_ram_wr.SEG_BE_W)
) dma_ram_rd();

taxi_dma_psdpram #(
    .SIZE(1024),
    .PIPELINE(2)
)
ram_inst (
    .clk(clk),
    .rst(rst),

    /*
     * Write port
     */
    .dma_ram_wr(dma_ram_wr),

    /*
     * Read port
     */
    .dma_ram_rd(dma_ram_rd)
);

taxi_axis_if #(
    .DATA_W(axis_desc[0].DATA_W),
    .KEEP_EN(axis_desc[0].KEEP_EN),
    .KEEP_W(axis_desc[0].KEEP_W),
    .LAST_EN(axis_desc[0].LAST_EN),
    .ID_EN(axis_desc[0].ID_EN),
    .ID_W(axis_desc[0].ID_W),
    .DEST_EN(1),
    .DEST_W(1),
    .USER_EN(axis_desc[0].USER_EN),
    .USER_W(axis_desc[0].USER_W)
) m_axis_rd_data();

taxi_dma_client_axis_source
dma_inst (
    .clk(clk),
    .rst(rst),

    /*
     * DMA descriptor
     */
    .desc_req(dma_desc),
    .desc_sts(dma_desc),

    /*
     * AXI stream read data output
     */
    .m_axis_rd_data(m_axis_rd_data),

    /*
     * RAM interface
     */
    .dma_ram_rd(dma_ram_rd),

    /*
     * Configuration
     */
    .enable(1'b1)
);

taxi_axis_demux #(
    .M_COUNT(2),
    .TDEST_ROUTE(1)
)
demux_inst (
    .clk(clk),
    .rst(rst),

    /*
     * AXI4-Stream input (sink)
     */
    .s_axis(m_axis_rd_data),

    /*
     * AXI4-Stream output (source)
     */
    .m_axis(axis_desc),

    /*
     * Control
     */
    .enable(1'b1),
    .drop(1'b0),
    .select('0)
);

endmodule

`resetall
