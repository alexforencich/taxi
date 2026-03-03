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
 * Corundum-micro completion write module
 */
module cndm_micro_cpl_wr
(
    input  wire logic         clk,
    input  wire logic         rst,

    /*
     * Control register interface
     */
    taxi_axil_if.wr_slv       s_axil_ctrl_wr,
    taxi_axil_if.rd_slv       s_axil_ctrl_rd,

    /*
     * Datapath control register interface
     */
    taxi_apb_if.slv           s_apb_dp_ctrl,

    /*
     * DMA
     */
    taxi_dma_desc_if.req_src  dma_wr_desc_req,
    taxi_dma_desc_if.sts_snk  dma_wr_desc_sts,
    taxi_dma_ram_if.rd_slv    dma_ram_rd,

    taxi_axis_if.snk          axis_cpl[2],
    output wire logic         irq
);

localparam AXIL_ADDR_W = s_axil_ctrl_wr.ADDR_W;
localparam AXIL_DATA_W = s_axil_ctrl_wr.DATA_W;

localparam APB_ADDR_W = s_apb_dp_ctrl.ADDR_W;
localparam APB_DATA_W = s_apb_dp_ctrl.DATA_W;

logic         txcq_en_reg = '0;
logic [3:0]   txcq_size_reg = '0;
logic [63:0]  txcq_base_addr_reg = '0;
logic         rxcq_en_reg = '0;
logic [3:0]   rxcq_size_reg = '0;
logic [63:0]  rxcq_base_addr_reg = '0;

logic [15:0] txcq_prod_ptr_reg = '0;
logic [15:0] rxcq_prod_ptr_reg = '0;

logic s_axil_ctrl_awready_reg = 1'b0;
logic s_axil_ctrl_wready_reg = 1'b0;
logic s_axil_ctrl_bvalid_reg = 1'b0;

logic s_axil_ctrl_arready_reg = 1'b0;
logic [AXIL_DATA_W-1:0] s_axil_ctrl_rdata_reg = '0;
logic s_axil_ctrl_rvalid_reg = 1'b0;

assign s_axil_ctrl_wr.awready = s_axil_ctrl_awready_reg;
assign s_axil_ctrl_wr.wready = s_axil_ctrl_wready_reg;
assign s_axil_ctrl_wr.bresp = '0;
assign s_axil_ctrl_wr.buser = '0;
assign s_axil_ctrl_wr.bvalid = s_axil_ctrl_bvalid_reg;

assign s_axil_ctrl_rd.arready = s_axil_ctrl_arready_reg;
assign s_axil_ctrl_rd.rdata = s_axil_ctrl_rdata_reg;
assign s_axil_ctrl_rd.rresp = '0;
assign s_axil_ctrl_rd.ruser = '0;
assign s_axil_ctrl_rd.rvalid = s_axil_ctrl_rvalid_reg;

logic s_apb_dp_ctrl_pready_reg = 1'b0;
logic [AXIL_DATA_W-1:0] s_apb_dp_ctrl_prdata_reg = '0;

assign s_apb_dp_ctrl.pready = s_apb_dp_ctrl_pready_reg;
assign s_apb_dp_ctrl.prdata = s_apb_dp_ctrl_prdata_reg;
assign s_apb_dp_ctrl.pslverr = 1'b0;
assign s_apb_dp_ctrl.pruser = '0;
assign s_apb_dp_ctrl.pbuser = '0;

always_ff @(posedge clk) begin
    s_axil_ctrl_awready_reg <= 1'b0;
    s_axil_ctrl_wready_reg <= 1'b0;
    s_axil_ctrl_bvalid_reg <= s_axil_ctrl_bvalid_reg && !s_axil_ctrl_wr.bready;

    s_axil_ctrl_arready_reg <= 1'b0;
    s_axil_ctrl_rvalid_reg <= s_axil_ctrl_rvalid_reg && !s_axil_ctrl_rd.rready;

    s_apb_dp_ctrl_pready_reg <= 1'b0;

    if (s_axil_ctrl_wr.awvalid && s_axil_ctrl_wr.wvalid && !s_axil_ctrl_bvalid_reg) begin
        s_axil_ctrl_awready_reg <= 1'b1;
        s_axil_ctrl_wready_reg <= 1'b1;
        s_axil_ctrl_bvalid_reg <= 1'b1;

        // case ({s_axil_ctrl_wr.awaddr[9:2], 2'b00})
        //     10'h000: begin
        //         txcq_en_reg <= s_axil_ctrl_wr.wdata[0];
        //         txcq_size_reg <= s_axil_ctrl_wr.wdata[19:16];
        //     end
        //     10'h008: txcq_base_addr_reg[31:0] <= s_axil_ctrl_wr.wdata;
        //     10'h00c: txcq_base_addr_reg[63:32] <= s_axil_ctrl_wr.wdata;

        //     10'h100: begin
        //         rxcq_en_reg <= s_axil_ctrl_wr.wdata[0];
        //         rxcq_size_reg <= s_axil_ctrl_wr.wdata[19:16];
        //     end
        //     10'h108: rxcq_base_addr_reg[31:0] <= s_axil_ctrl_wr.wdata;
        //     10'h10c: rxcq_base_addr_reg[63:32] <= s_axil_ctrl_wr.wdata;
        //     default: begin end
        // endcase
    end

    if (s_axil_ctrl_rd.arvalid && !s_axil_ctrl_rvalid_reg) begin
        s_axil_ctrl_rdata_reg <= '0;

        s_axil_ctrl_arready_reg <= 1'b1;
        s_axil_ctrl_rvalid_reg <= 1'b1;

        // case ({s_axil_ctrl_rd.araddr[9:2], 2'b00})
        //     10'h000: begin
        //         s_axil_ctrl_rdata_reg[0] <= txcq_en_reg;
        //         s_axil_ctrl_rdata_reg[19:16] <= txcq_size_reg;
        //     end
        //     10'h004: s_axil_ctrl_rdata_reg[15:0] <= txcq_prod_ptr_reg;
        //     10'h008: s_axil_ctrl_rdata_reg <= txcq_base_addr_reg[31:0];
        //     10'h00c: s_axil_ctrl_rdata_reg <= txcq_base_addr_reg[63:32];

        //     10'h100: begin
        //         s_axil_ctrl_rdata_reg[0] <= rxcq_en_reg;
        //         s_axil_ctrl_rdata_reg[19:16] <= rxcq_size_reg;
        //     end
        //     10'h104: s_axil_ctrl_rdata_reg[15:0] <= rxcq_prod_ptr_reg;
        //     10'h108: s_axil_ctrl_rdata_reg <= rxcq_base_addr_reg[31:0];
        //     10'h10c: s_axil_ctrl_rdata_reg <= rxcq_base_addr_reg[63:32];
        //     default: begin end
        // endcase
    end

    if (s_apb_dp_ctrl.penable && s_apb_dp_ctrl.psel && !s_apb_dp_ctrl_pready_reg) begin
        s_apb_dp_ctrl_pready_reg <= 1'b1;
        s_apb_dp_ctrl_prdata_reg <= '0;

        if (s_apb_dp_ctrl.pwrite) begin
            case ({s_apb_dp_ctrl.paddr[9:2], 2'b00})
                10'h000: begin
                    txcq_en_reg <= s_apb_dp_ctrl.pwdata[0];
                    txcq_size_reg <= s_apb_dp_ctrl.pwdata[19:16];
                end
                10'h008: txcq_base_addr_reg[31:0] <= s_apb_dp_ctrl.pwdata;
                10'h00c: txcq_base_addr_reg[63:32] <= s_apb_dp_ctrl.pwdata;

                10'h100: begin
                    rxcq_en_reg <= s_apb_dp_ctrl.pwdata[0];
                    rxcq_size_reg <= s_apb_dp_ctrl.pwdata[19:16];
                end
                10'h108: rxcq_base_addr_reg[31:0] <= s_apb_dp_ctrl.pwdata;
                10'h10c: rxcq_base_addr_reg[63:32] <= s_apb_dp_ctrl.pwdata;
                default: begin end
            endcase
        end

        case ({s_apb_dp_ctrl.paddr[9:2], 2'b00})
            10'h000: begin
                s_apb_dp_ctrl_prdata_reg[0] <= txcq_en_reg;
                s_apb_dp_ctrl_prdata_reg[19:16] <= txcq_size_reg;
            end
            10'h004: s_apb_dp_ctrl_prdata_reg[15:0] <= txcq_prod_ptr_reg;
            10'h008: s_apb_dp_ctrl_prdata_reg <= txcq_base_addr_reg[31:0];
            10'h00c: s_apb_dp_ctrl_prdata_reg <= txcq_base_addr_reg[63:32];

            10'h100: begin
                s_apb_dp_ctrl_prdata_reg[0] <= rxcq_en_reg;
                s_apb_dp_ctrl_prdata_reg[19:16] <= rxcq_size_reg;
            end
            10'h104: s_apb_dp_ctrl_prdata_reg[15:0] <= rxcq_prod_ptr_reg;
            10'h108: s_apb_dp_ctrl_prdata_reg <= rxcq_base_addr_reg[31:0];
            10'h10c: s_apb_dp_ctrl_prdata_reg <= rxcq_base_addr_reg[63:32];
            default: begin end
        endcase
    end

    if (rst) begin
        s_axil_ctrl_awready_reg <= 1'b0;
        s_axil_ctrl_wready_reg <= 1'b0;
        s_axil_ctrl_bvalid_reg <= 1'b0;

        s_axil_ctrl_arready_reg <= 1'b0;
        s_axil_ctrl_rvalid_reg <= 1'b0;

        s_apb_dp_ctrl_pready_reg <= 1'b0;
    end
end

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

typedef enum logic [1:0] {
    STATE_IDLE,
    STATE_RX_CPL,
    STATE_WRITE_DATA
} state_t;

state_t state_reg = STATE_IDLE;

logic phase_tag_reg = 1'b0;

logic irq_reg = 1'b0;

assign irq = irq_reg;

always_ff @(posedge clk) begin
    cpl_comb.tready <= 1'b0;

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

    if (!txcq_en_reg) begin
        txcq_prod_ptr_reg <= '0;
    end

    if (!rxcq_en_reg) begin
        rxcq_prod_ptr_reg <= '0;
    end

    irq_reg <= 1'b0;

    case (state_reg)
        STATE_IDLE: begin
            dma_wr_desc_req.req_src_addr <= '0;

            if (cpl_comb.tid == 0) begin
                dma_wr_desc_req.req_dst_addr <= txcq_base_addr_reg + 64'(16'(txcq_prod_ptr_reg & ({16{1'b1}} >> (16 - txcq_size_reg))) * 16);
                phase_tag_reg <= !txcq_prod_ptr_reg[txcq_size_reg];
                if (cpl_comb.tvalid && !cpl_comb.tready) begin
                    txcq_prod_ptr_reg <= txcq_prod_ptr_reg + 1;
                    if (txcq_en_reg) begin
                        dma_wr_desc_req.req_valid <= 1'b1;
                        state_reg <= STATE_WRITE_DATA;
                    end else begin
                        state_reg <= STATE_IDLE;
                    end
                end
            end else begin
                dma_wr_desc_req.req_dst_addr <= rxcq_base_addr_reg + 64'(16'(rxcq_prod_ptr_reg & ({16{1'b1}} >> (16 - rxcq_size_reg))) * 16);
                phase_tag_reg <= !rxcq_prod_ptr_reg[rxcq_size_reg];
                if (cpl_comb.tvalid && !cpl_comb.tready) begin
                    rxcq_prod_ptr_reg <= rxcq_prod_ptr_reg + 1;
                    if (rxcq_en_reg) begin
                        dma_wr_desc_req.req_valid <= 1'b1;
                        state_reg <= STATE_WRITE_DATA;
                    end else begin
                        state_reg <= STATE_IDLE;
                    end
                end
            end
        end
        STATE_WRITE_DATA: begin
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

// extract parameters
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
