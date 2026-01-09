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
 * Corundum-proto receive datapath
 */
module cndm_proto_rx
(
    input  wire logic         clk,
    input  wire logic         rst,

    /*
     * DMA
     */
    taxi_dma_desc_if.req_src  dma_wr_desc_req,
    taxi_dma_desc_if.sts_snk  dma_wr_desc_sts,
    taxi_dma_ram_if.rd_slv    dma_ram_rd,

    /*
     * Receive data input
     */
    taxi_axis_if.snk          rx_data,

    /*
     * Descriptor request
     */
    output wire logic         desc_req,
    taxi_axis_if.snk          axis_desc,

    /*
     * Completion output
     */
    taxi_axis_if.src          axis_cpl
);

// Control for internal streaming DMA engine
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

// Receive datapath control state machine
localparam [2:0]
    STATE_IDLE = 0,
    STATE_RX_DATA = 1,
    STATE_READ_DESC = 2,
    STATE_WRITE_DATA = 3;

logic [2:0] state_reg = STATE_IDLE;

logic desc_req_reg = 1'b0;

assign desc_req = desc_req_reg;

always_ff @(posedge clk) begin
    desc_req_reg <= 1'b0;

    axis_desc.tready <= 1'b0;

    // Host DMA control descriptor to manage transferring packet data to host memory
    dma_wr_desc_req.req_src_sel <= '0;
    dma_wr_desc_req.req_src_asid <= '0;
    dma_wr_desc_req.req_dst_sel <= '0;
    dma_wr_desc_req.req_dst_asid <= '0;
    dma_wr_desc_req.req_imm <= '0;
    dma_wr_desc_req.req_imm_en <= '0;
    dma_wr_desc_req.req_tag <= '0;
    dma_wr_desc_req.req_id <= '0;
    dma_wr_desc_req.req_dest <= '0;
    dma_wr_desc_req.req_user <= '0;
    dma_wr_desc_req.req_valid <= dma_wr_desc_req.req_valid && !dma_wr_desc_req.req_ready;

    // Streaming DMA control descriptor to transfer packet data
    dma_desc.req_src_addr <= '0;
    dma_desc.req_src_sel <= '0;
    dma_desc.req_src_asid <= '0;
    dma_desc.req_dst_addr <= '0;
    dma_desc.req_dst_sel <= '0;
    dma_desc.req_dst_asid <= '0;
    dma_desc.req_imm <= '0;
    dma_desc.req_imm_en <= '0;
    dma_desc.req_len <= 4096;
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
            // idle state - start streaming DMA engine to receive packet
            dma_desc.req_valid <= 1'b1;
            state_reg <= STATE_RX_DATA;
        end
        STATE_RX_DATA: begin
            // RX data state - wait for streaming DMA, store packet length and start descriptor read operation
            dma_wr_desc_req.req_len <= 20'(dma_desc.sts_len);
            axis_cpl.tdata[47:32] <= 16'(dma_desc.sts_len);
            if (dma_desc.sts_valid) begin
                desc_req_reg <= 1'b1;
                state_reg <= STATE_READ_DESC;
            end
        end
        STATE_READ_DESC: begin
            // read descriptor state - wait for descriptor, start host DMA write
            axis_desc.tready <= 1'b1;

            // host address from descriptor
            dma_wr_desc_req.req_src_addr <= '0;
            dma_wr_desc_req.req_dst_addr <= axis_desc.tdata[127:64];

            if (axis_desc.tvalid && axis_desc.tready) begin
                // limit transfer length to descriptor size
                if (dma_wr_desc_req.req_len > 20'(axis_desc.tdata[47:32])) begin
                    dma_wr_desc_req.req_len <= 20'(axis_desc.tdata[47:32]);
                end

                if (axis_desc.tuser) begin
                    // failed to read desc
                    state_reg <= STATE_IDLE;
                end else begin
                    dma_wr_desc_req.req_valid <= 1'b1;
                    state_reg <= STATE_WRITE_DATA;
                end
            end
        end
        STATE_WRITE_DATA: begin
            // write data state - wait for host DMA write to complete, generate completion
            if (dma_wr_desc_sts.sts_valid) begin
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

// local RAM to store the packet data temporarily
taxi_dma_ram_if #(
    .SEGS(dma_ram_rd.SEGS),
    .SEG_ADDR_W(dma_ram_rd.SEG_ADDR_W),
    .SEG_DATA_W(dma_ram_rd.SEG_DATA_W),
    .SEG_BE_W(dma_ram_rd.SEG_BE_W)
) dma_ram_wr();

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

// streaming DMA engine to write packet data to local RAM
taxi_dma_client_axis_sink
dma_inst (
    .clk(clk),
    .rst(rst),

    /*
     * DMA descriptor
     */
    .desc_req(dma_desc),
    .desc_sts(dma_desc),

    /*
     * AXI stream write data input
     */
    .s_axis_wr_data(rx_data),

    /*
     * RAM interface
     */
    .dma_ram_wr(dma_ram_wr),

    /*
     * Configuration
     */
    .enable(1),
    .abort(0)
);


endmodule

`resetall
