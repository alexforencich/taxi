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
 * Corundum-proto transmit path
 */
module cndm_proto_tx
(
    input  wire logic         clk,
    input  wire logic         rst,

    /*
     * DMA
     */
    taxi_dma_desc_if.req_src  dma_rd_desc_req,
    taxi_dma_desc_if.sts_snk  dma_rd_desc_sts,
    taxi_dma_ram_if.wr_slv    dma_ram_wr,

    output wire logic         desc_req,
    taxi_axis_if.snk          axis_desc,
    taxi_axis_if.src          tx_data,
    taxi_axis_if.src          axis_cpl
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
    .LEN_W(16),
    .TAG_W(1),
    .ID_EN(0),
    .DEST_EN(0),
    .USER_EN(1),
    .USER_W(1)
) dma_desc();

localparam [2:0]
    STATE_IDLE = 0,
    STATE_READ_DESC = 1,
    STATE_READ_DATA = 2,
    STATE_TX_DATA = 3;

logic [2:0] state_reg = STATE_IDLE;

logic desc_req_reg = 1'b0;

assign desc_req = desc_req_reg;

always_ff @(posedge clk) begin
    desc_req_reg <= 1'b0;

    axis_desc.tready <= 1'b0;

    dma_rd_desc_req.req_src_sel <= '0;
    dma_rd_desc_req.req_src_asid <= '0;
    dma_rd_desc_req.req_dst_sel <= '0;
    dma_rd_desc_req.req_dst_asid <= '0;
    dma_rd_desc_req.req_imm <= '0;
    dma_rd_desc_req.req_imm_en <= '0;
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
    dma_desc.req_tag <= '0;
    dma_desc.req_id <= '0;
    dma_desc.req_dest <= '0;
    dma_desc.req_user <= '0;
    dma_desc.req_valid <= dma_desc.req_valid && !dma_desc.req_ready;

    axis_cpl.tkeep <= '0;
    axis_cpl.tid <= '0;
    axis_cpl.tdest <= '0;
    axis_cpl.tuser <= '0;
    axis_cpl.tlast <= 1'b1;
    axis_cpl.tvalid <= axis_cpl.tvalid && !axis_cpl.tready;

    case (state_reg)
        STATE_IDLE: begin
            desc_req_reg <= 1'b1;
            state_reg <= STATE_READ_DESC;
        end
        STATE_READ_DESC: begin
            axis_desc.tready <= 1'b1;

            dma_rd_desc_req.req_src_addr <= axis_desc.tdata[127:64];
            dma_rd_desc_req.req_dst_addr <= '0;
            dma_rd_desc_req.req_len <= 20'(axis_desc.tdata[47:32]);

            dma_desc.req_src_addr <= '0;
            dma_desc.req_len <= axis_desc.tdata[47:32];

            if (axis_desc.tvalid && axis_desc.tready) begin
                if (axis_desc.tuser) begin
                    // failed to read desc
                    state_reg <= STATE_IDLE;
                end else begin
                    dma_rd_desc_req.req_valid <= 1'b1;
                    state_reg <= STATE_READ_DATA;
                end
            end
        end
        STATE_READ_DATA: begin
            if (dma_rd_desc_sts.sts_valid) begin
                dma_desc.req_valid <= 1'b1;
                state_reg <= STATE_TX_DATA;
            end
        end
        STATE_TX_DATA: begin
            if (dma_desc.sts_valid) begin
                axis_cpl.tvalid <= 1'b1;
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
    .SIZE(4096),
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
    .m_axis_rd_data(tx_data),

    /*
     * RAM interface
     */
    .dma_ram_rd(dma_ram_rd),

    /*
     * Configuration
     */
    .enable(1'b1)
);

endmodule

`resetall
