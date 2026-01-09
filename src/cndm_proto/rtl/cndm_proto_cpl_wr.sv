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
 * Corundum-proto completion write module
 */
module cndm_proto_cpl_wr
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
     * Control signals from port-level control registers
     */
    input  wire logic         txcq_en,
    input  wire logic [3:0]   txcq_size,
    input  wire logic [63:0]  txcq_base_addr,
    output wire logic [15:0]  txcq_prod,
    input  wire logic         rxcq_en,
    input  wire logic [3:0]   rxcq_size,
    input  wire logic [63:0]  rxcq_base_addr,
    output wire logic [15:0]  rxcq_prod,

    /*
     * Completion inputs from TX and RX datapaths
     */
    taxi_axis_if.snk          axis_cpl[2],

    /*
     * Interrupt request output
     */
    output wire logic         irq
);

// Combined completion bus - carries both RX and TX completions, identified by tid
taxi_axis_if #(
    .DATA_W(axis_cpl[0].DATA_W),
    .KEEP_EN(axis_cpl[0].KEEP_EN),
    .KEEP_W(axis_cpl[0].KEEP_W),
    .STRB_EN(axis_cpl[0].STRB_EN),
    .LAST_EN(axis_cpl[0].LAST_EN),
    .ID_EN(1),
    .ID_W(1),
    .DEST_EN(axis_cpl[0].DEST_EN),
    .DEST_W(axis_cpl[0].DEST_W),
    .USER_EN(axis_cpl[0].USER_EN),
    .USER_W(axis_cpl[0].USER_W)
) cpl_comb();

// Completion write control state machine
localparam [2:0]
    STATE_IDLE = 0,
    STATE_RX_CPL = 1,
    STATE_WRITE_DATA = 2;

logic [2:0] state_reg = STATE_IDLE;

logic [15:0] txcq_prod_ptr_reg = '0;
logic [15:0] rxcq_prod_ptr_reg = '0;

logic phase_tag_reg = 1'b0;

logic irq_reg = 1'b0;

assign txcq_prod = txcq_prod_ptr_reg;
assign rxcq_prod = rxcq_prod_ptr_reg;

assign irq = irq_reg;

always_ff @(posedge clk) begin
    cpl_comb.tready <= 1'b0;

    // Host DMA control descriptor to manage transferring completions to host memory
    dma_wr_desc_req.req_src_sel <= '0;
    dma_wr_desc_req.req_src_asid <= '0;
    dma_wr_desc_req.req_dst_sel <= '0;
    dma_wr_desc_req.req_dst_asid <= '0;
    dma_wr_desc_req.req_imm <= '0;
    dma_wr_desc_req.req_imm_en <= '0;
    dma_wr_desc_req.req_len <= 16;
    dma_wr_desc_req.req_tag <= '0;
    dma_wr_desc_req.req_id <= '0;
    dma_wr_desc_req.req_dest <= '0;
    dma_wr_desc_req.req_user <= '0;
    dma_wr_desc_req.req_valid <= dma_wr_desc_req.req_valid && !dma_wr_desc_req.req_ready;

    // reset pointers when disabled
    if (!txcq_en) begin
        txcq_prod_ptr_reg <= '0;
    end

    if (!rxcq_en) begin
        rxcq_prod_ptr_reg <= '0;
    end

    irq_reg <= 1'b0;

    case (state_reg)
        STATE_IDLE: begin
            // idle state - wait for completion

            dma_wr_desc_req.req_src_addr <= '0;

            // arbitrate between TX and RX completions
            if (cpl_comb.tid == 0) begin
                // compute host address - base address plus producer pointer, modulo queue size
                dma_wr_desc_req.req_dst_addr <= txcq_base_addr + 64'(16'(txcq_prod_ptr_reg & ({16{1'b1}} >> (16 - txcq_size))) * 16);
                // phase tag is the inverted version of the extended producer pointer
                // each "pass" over the queue elements will invert the phase tag
                phase_tag_reg <= !txcq_prod_ptr_reg[txcq_size];
                if (cpl_comb.tvalid && !cpl_comb.tready) begin
                    // increment pointer and start transfer operation, if the queue is enabled
                    txcq_prod_ptr_reg <= txcq_prod_ptr_reg + 1;
                    if (txcq_en) begin
                        dma_wr_desc_req.req_valid <= 1'b1;
                        state_reg <= STATE_WRITE_DATA;
                    end else begin
                        state_reg <= STATE_IDLE;
                    end
                end
            end else begin
                // compute host address - base address plus producer pointer, modulo queue size
                dma_wr_desc_req.req_dst_addr <= rxcq_base_addr + 64'(16'(rxcq_prod_ptr_reg & ({16{1'b1}} >> (16 - rxcq_size))) * 16);
                // phase tag is the inverted version of the extended producer pointer
                // each "pass" over the queue elements will invert the phase tag
                phase_tag_reg <= !rxcq_prod_ptr_reg[rxcq_size];
                if (cpl_comb.tvalid && !cpl_comb.tready) begin
                    // increment pointer and start transfer operation, if the queue is enabled
                    rxcq_prod_ptr_reg <= rxcq_prod_ptr_reg + 1;
                    if (rxcq_en) begin
                        dma_wr_desc_req.req_valid <= 1'b1;
                        state_reg <= STATE_WRITE_DATA;
                    end else begin
                        state_reg <= STATE_IDLE;
                    end
                end
            end
        end
        STATE_WRITE_DATA: begin
            // write data state - wait for host DMA write to complete, issue IRQ to host
            if (dma_wr_desc_sts.sts_valid) begin
                cpl_comb.tready <= 1'b1;
                irq_reg <= 1'b1;
                state_reg <= STATE_IDLE;
            end
        end
        default: begin
            state_reg <= STATE_IDLE;
        end
    endcase

    if (rst) begin
        state_reg <= STATE_IDLE;
        txcq_prod_ptr_reg <= '0;
        rxcq_prod_ptr_reg <= '0;
        irq_reg <= 1'b0;
    end
end

// mux for completions
taxi_axis_arb_mux #(
    .S_COUNT(2),
    .UPDATE_TID(1),
    .ARB_ROUND_ROBIN(1),
    .ARB_LSB_HIGH_PRIO(1)
)
mux_inst (
    .clk(clk),
    .rst(rst),

    /*
     * AXI4-Stream input (sink)
     */
    .s_axis(axis_cpl),

    /*
     * AXI4-Stream output (source)
     */
    .m_axis(cpl_comb)
);

// "emulate" DMA RAM - pass completion data to host DMA engine along with phase tag bit
localparam SEGS = dma_ram_rd.SEGS;
localparam SEG_ADDR_W = dma_ram_rd.SEG_ADDR_W;
localparam SEG_DATA_W = dma_ram_rd.SEG_DATA_W;
localparam SEG_BE_W = dma_ram_rd.SEG_BE_W;

if (SEGS*SEG_DATA_W < 128)
    $fatal(0, "Total segmented interface width must be at least 128 (instance %m)");

wire [SEGS-1:0][SEG_DATA_W-1:0] ram_data = (SEG_DATA_W*SEGS)'({phase_tag_reg, cpl_comb.tdata[126:0]});

for (genvar n = 0; n < SEGS; n = n + 1) begin

    logic [0:0] rd_resp_valid_pipe_reg = '0;
    logic [SEG_DATA_W-1:0] rd_resp_data_pipe_reg[1];

    initial begin
        for (integer i = 0; i < 1; i = i + 1) begin
            rd_resp_data_pipe_reg[i] = '0;
        end
    end

    always_ff @(posedge clk) begin
        if (dma_ram_rd.rd_resp_ready[n]) begin
            rd_resp_valid_pipe_reg[0] <= 1'b0;
        end

        for (integer j = 0; j > 0; j = j - 1) begin
            if (dma_ram_rd.rd_resp_ready[n] || (1'(~rd_resp_valid_pipe_reg) >> j) != 0) begin
                rd_resp_valid_pipe_reg[j] <= rd_resp_valid_pipe_reg[j-1];
                rd_resp_data_pipe_reg[j] <= rd_resp_data_pipe_reg[j-1];
                rd_resp_valid_pipe_reg[j-1] <= 1'b0;
            end
        end

        if (dma_ram_rd.rd_cmd_valid[n] && dma_ram_rd.rd_cmd_ready[n]) begin
            rd_resp_valid_pipe_reg[0] <= 1'b1;
            rd_resp_data_pipe_reg[0] <= ram_data[0];
        end

        if (rst) begin
            rd_resp_valid_pipe_reg <= '0;
        end
    end

    assign dma_ram_rd.rd_cmd_ready[n] = dma_ram_rd.rd_resp_ready[n] || &rd_resp_valid_pipe_reg == 0;

    assign dma_ram_rd.rd_resp_valid[n] = rd_resp_valid_pipe_reg[0];
    assign dma_ram_rd.rd_resp_data[n] = rd_resp_data_pipe_reg[0];

end

endmodule

`resetall
