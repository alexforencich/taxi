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
    taxi_dma_desc_if.req_src  dma_rd_desc_req,
    taxi_dma_desc_if.sts_snk  dma_rd_desc_sts,
    taxi_dma_ram_if.wr_slv    dma_ram_wr,

    input  wire logic [1:0]   desc_req,
    taxi_axis_if.src          axis_desc[2]
);

localparam AXIL_ADDR_W = s_axil_ctrl_wr.ADDR_W;
localparam AXIL_DATA_W = s_axil_ctrl_wr.DATA_W;

localparam APB_ADDR_W = s_apb_dp_ctrl.ADDR_W;
localparam APB_DATA_W = s_apb_dp_ctrl.DATA_W;

localparam RAM_ADDR_W = 16;

logic         txq_en_reg = '0;
logic [3:0]   txq_size_reg = '0;
logic [63:0]  txq_base_addr_reg = '0;
logic [15:0]  txq_prod_reg = '0;
logic         rxq_en_reg = '0;
logic [3:0]   rxq_size_reg = '0;
logic [63:0]  rxq_base_addr_reg = '0;
logic [15:0]  rxq_prod_reg = '0;

logic [15:0] txq_cons_ptr_reg = '0;
logic [15:0] rxq_cons_ptr_reg = '0;

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

        case ({s_axil_ctrl_wr.awaddr[9:2], 2'b00})
            // 10'h000: begin
            //     txq_en_reg <= s_axil_ctrl_wr.wdata[0];
            //     txq_size_reg <= s_axil_ctrl_wr.wdata[19:16];
            // end
            10'h004: txq_prod_reg <= s_axil_ctrl_wr.wdata[15:0];
            // 10'h008: txq_base_addr_reg[31:0] <= s_axil_ctrl_wr.wdata;
            // 10'h00c: txq_base_addr_reg[63:32] <= s_axil_ctrl_wr.wdata;

            // 10'h100: begin
            //     rxq_en_reg <= s_axil_ctrl_wr.wdata[0];
            //     rxq_size_reg <= s_axil_ctrl_wr.wdata[19:16];
            // end
            10'h104: rxq_prod_reg <= s_axil_ctrl_wr.wdata[15:0];
            // 10'h108: rxq_base_addr_reg[31:0] <= s_axil_ctrl_wr.wdata;
            // 10'h10c: rxq_base_addr_reg[63:32] <= s_axil_ctrl_wr.wdata;
            default: begin end
        endcase
    end

    if (s_axil_ctrl_rd.arvalid && !s_axil_ctrl_rvalid_reg) begin
        s_axil_ctrl_rdata_reg <= '0;

        s_axil_ctrl_arready_reg <= 1'b1;
        s_axil_ctrl_rvalid_reg <= 1'b1;

        // case ({s_axil_ctrl_rd.araddr[9:2], 2'b00})
        //     10'h000: begin
        //         s_axil_ctrl_rdata_reg[0] <= txq_en_reg;
        //         s_axil_ctrl_rdata_reg[19:16] <= txq_size_reg;
        //     end
        //     10'h004: begin
        //         s_axil_ctrl_rdata_reg[15:0] <= txq_prod_reg;
        //         s_axil_ctrl_rdata_reg[31:16] <= txq_cons_ptr_reg;
        //     end
        //     10'h008: s_axil_ctrl_rdata_reg <= txq_base_addr_reg[31:0];
        //     10'h00c: s_axil_ctrl_rdata_reg <= txq_base_addr_reg[63:32];

        //     10'h100: begin
        //         s_axil_ctrl_rdata_reg[0] <= rxq_en_reg;
        //         s_axil_ctrl_rdata_reg[19:16] <= rxq_size_reg;
        //     end
        //     10'h104: begin
        //         s_axil_ctrl_rdata_reg[15:0] <= rxq_prod_reg;
        //         s_axil_ctrl_rdata_reg[31:16] <= rxq_cons_ptr_reg;
        //     end
        //     10'h108: s_axil_ctrl_rdata_reg <= rxq_base_addr_reg[31:0];
        //     10'h10c: s_axil_ctrl_rdata_reg <= rxq_base_addr_reg[63:32];
        //     default: begin end
        // endcase
    end

    if (s_apb_dp_ctrl.penable && s_apb_dp_ctrl.psel && !s_apb_dp_ctrl_pready_reg) begin
        s_apb_dp_ctrl_pready_reg <= 1'b1;
        s_apb_dp_ctrl_prdata_reg <= '0;

        if (s_apb_dp_ctrl.pwrite) begin
            case ({s_apb_dp_ctrl.paddr[9:2], 2'b00})
                10'h000: begin
                    txq_en_reg <= s_apb_dp_ctrl.pwdata[0];
                    txq_size_reg <= s_apb_dp_ctrl.pwdata[19:16];
                end
                10'h004: txq_prod_reg <= s_apb_dp_ctrl.pwdata[15:0];
                10'h008: txq_base_addr_reg[31:0] <= s_apb_dp_ctrl.pwdata;
                10'h00c: txq_base_addr_reg[63:32] <= s_apb_dp_ctrl.pwdata;

                10'h100: begin
                    rxq_en_reg <= s_apb_dp_ctrl.pwdata[0];
                    rxq_size_reg <= s_apb_dp_ctrl.pwdata[19:16];
                end
                10'h104: rxq_prod_reg <= s_apb_dp_ctrl.pwdata[15:0];
                10'h108: rxq_base_addr_reg[31:0] <= s_apb_dp_ctrl.pwdata;
                10'h10c: rxq_base_addr_reg[63:32] <= s_apb_dp_ctrl.pwdata;
                default: begin end
            endcase
        end

        case ({s_apb_dp_ctrl.paddr[9:2], 2'b00})
            10'h000: begin
                s_apb_dp_ctrl_prdata_reg[0] <= txq_en_reg;
                s_apb_dp_ctrl_prdata_reg[19:16] <= txq_size_reg;
            end
            10'h004: begin
                s_apb_dp_ctrl_prdata_reg[15:0] <= txq_prod_reg;
                s_apb_dp_ctrl_prdata_reg[31:16] <= txq_cons_ptr_reg;
            end
            10'h008: s_apb_dp_ctrl_prdata_reg <= txq_base_addr_reg[31:0];
            10'h00c: s_apb_dp_ctrl_prdata_reg <= txq_base_addr_reg[63:32];

            10'h100: begin
                s_apb_dp_ctrl_prdata_reg[0] <= rxq_en_reg;
                s_apb_dp_ctrl_prdata_reg[19:16] <= rxq_size_reg;
            end
            10'h104: begin
                s_apb_dp_ctrl_prdata_reg[15:0] <= rxq_prod_reg;
                s_apb_dp_ctrl_prdata_reg[31:16] <= rxq_cons_ptr_reg;
            end
            10'h108: s_apb_dp_ctrl_prdata_reg <= rxq_base_addr_reg[31:0];
            10'h10c: s_apb_dp_ctrl_prdata_reg <= rxq_base_addr_reg[63:32];
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

typedef enum logic [1:0] {
    STATE_IDLE,
    STATE_READ_DESC,
    STATE_READ_DATA,
    STATE_TX_DESC
} state_t;

state_t state_reg = STATE_IDLE;

logic [1:0] desc_req_reg = '0;

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

    if (!txq_en_reg) begin
        txq_cons_ptr_reg <= '0;
    end

    if (!rxq_en_reg) begin
        rxq_cons_ptr_reg <= '0;
    end

    case (state_reg)
        STATE_IDLE: begin
            if (desc_req_reg[1]) begin
                dma_rd_desc_req.req_src_addr <= rxq_base_addr_reg + 64'(16'(rxq_cons_ptr_reg & ({16{1'b1}} >> (16 - rxq_size_reg))) * 16);
                dma_desc.req_dest <= 1'b1;
                desc_req_reg[1] <= 1'b0;
                if (rxq_cons_ptr_reg == rxq_prod_reg || !rxq_en_reg) begin
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
                dma_rd_desc_req.req_src_addr <= txq_base_addr_reg + 64'(16'(txq_cons_ptr_reg & ({16{1'b1}} >> (16 - txq_size_reg))) * 16);
                dma_desc.req_dest <= 1'b0;
                desc_req_reg[0] <= 1'b0;
                if (txq_cons_ptr_reg == txq_prod_reg || !txq_en_reg) begin
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
