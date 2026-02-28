// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2018-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4 Central DMA
 */
module taxi_axi_cdma #
(
    // Maximum AXI burst length to generate
    parameter AXI_MAX_BURST_LEN = 256,
    // Enable support for unaligned transfers
    parameter logic UNALIGNED_EN = 1'b1
)
(
    input  wire logic         clk,
    input  wire logic         rst,

    /*
     * DMA descriptor
     */
    taxi_dma_desc_if.req_snk  desc_req,
    taxi_dma_desc_if.sts_src  desc_sts,

    /*
     * AXI4 master interface
     */
    taxi_axi_if.wr_mst        m_axi_wr,
    taxi_axi_if.rd_mst        m_axi_rd,

    /*
     * Configuration
     */
    input  wire logic         enable
);

// extract parameters
localparam AXI_DATA_W = m_axi_wr.DATA_W;
localparam AXI_ADDR_W = m_axi_wr.ADDR_W;
localparam AXI_STRB_W = m_axi_wr.STRB_W;
localparam AXI_ID_W = m_axi_wr.ID_W;
localparam AXI_MAX_BURST_LEN_INT = AXI_MAX_BURST_LEN < m_axi_wr.MAX_BURST_LEN ? AXI_MAX_BURST_LEN : m_axi_wr.MAX_BURST_LEN;

localparam LEN_W = desc_req.LEN_W;
localparam TAG_W = desc_req.TAG_W;

localparam AXI_BYTE_LANES = AXI_STRB_W;
localparam AXI_BYTE_SIZE = AXI_DATA_W/AXI_BYTE_LANES;
localparam AXI_BURST_SIZE = $clog2(AXI_STRB_W);
localparam AXI_MAX_BURST_SIZE = AXI_MAX_BURST_LEN_INT << AXI_BURST_SIZE;

localparam OFFSET_W = AXI_STRB_W > 1 ? $clog2(AXI_STRB_W) : 1;
localparam OFFSET_MASK = AXI_STRB_W > 1 ? {OFFSET_W{1'b1}} : 0;
localparam ADDR_MASK = {AXI_ADDR_W{1'b1}} << $clog2(AXI_STRB_W);
localparam CYCLE_CNT_W = 13 - AXI_BURST_SIZE;

localparam STATUS_FIFO_AW = 5;
localparam OUTPUT_FIFO_AW = 5;

// check configuration
if (AXI_BYTE_SIZE * AXI_STRB_W != AXI_DATA_W)
    $fatal(0, "Error: AXI data width not evenly divisible (instance %m)");

if (2**$clog2(AXI_BYTE_LANES) != AXI_BYTE_LANES)
    $fatal(0, "Error: AXI word width must be even power of two (instance %m)");

if (AXI_MAX_BURST_LEN_INT < 1 || AXI_MAX_BURST_LEN_INT > 256)
    $fatal(0, "Error: AXI_MAX_BURST_LEN must be between 1 and 256 (instance %m)");

if (desc_req.SRC_ADDR_W < AXI_ADDR_W || desc_req.DST_ADDR_W < AXI_ADDR_W)
    $fatal(0, "Error: Descriptor address width is not sufficient (instance %m)");

typedef enum logic [1:0] {
    AXI_RESP_OKAY = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
} axi_resp_t;

typedef enum logic [3:0] {
    DMA_ERROR_NONE = 4'd0,
    DMA_ERROR_TIMEOUT = 4'd1,
    DMA_ERROR_PARITY = 4'd2,
    DMA_ERROR_AXI_RD_SLVERR = 4'd4,
    DMA_ERROR_AXI_RD_DECERR = 4'd5,
    DMA_ERROR_AXI_WR_SLVERR = 4'd6,
    DMA_ERROR_AXI_WR_DECERR = 4'd7,
    DMA_ERROR_PCIE_FLR = 4'd8,
    DMA_ERROR_PCIE_CPL_POISONED = 4'd9,
    DMA_ERROR_PCIE_CPL_STATUS_UR = 4'd10,
    DMA_ERROR_PCIE_CPL_STATUS_CA = 4'd11
} dma_error_t;

typedef enum logic [1:0] {
    READ_STATE_IDLE,
    READ_STATE_START,
    READ_STATE_REQ
} read_state_t;

read_state_t read_state_reg = READ_STATE_IDLE, read_state_next;

typedef enum logic [0:0] {
    AXI_STATE_IDLE,
    AXI_STATE_WRITE
} axi_state_t;

axi_state_t axi_state_reg = AXI_STATE_IDLE, axi_state_next;

// datapath control signals
logic transfer_in_save;
logic axi_cmd_ready;
logic status_fifo_we;

logic [AXI_ADDR_W-1:0] read_addr_reg = '0, read_addr_next;
logic [AXI_ADDR_W-1:0] write_addr_reg = '0, write_addr_next;
logic [LEN_W-1:0] op_count_reg = '0, op_count_next;
logic [12:0] tr_count_reg = '0, tr_count_next;
logic [12:0] axi_count_reg = '0, axi_count_next;

logic [AXI_ADDR_W-1:0] axi_cmd_addr_reg = '0, axi_cmd_addr_next;
logic [OFFSET_W-1:0] axi_cmd_offset_reg = '0, axi_cmd_offset_next;
logic [OFFSET_W-1:0] axi_cmd_first_cycle_offset_reg = '0, axi_cmd_first_cycle_offset_next;
logic [OFFSET_W-1:0] axi_cmd_last_cycle_offset_reg = '0, axi_cmd_last_cycle_offset_next;
logic [CYCLE_CNT_W-1:0] axi_cmd_input_cycle_count_reg = '0, axi_cmd_input_cycle_count_next;
logic [CYCLE_CNT_W-1:0] axi_cmd_output_cycle_count_reg = '0, axi_cmd_output_cycle_count_next;
logic axi_cmd_bubble_cycle_reg = 1'b0, axi_cmd_bubble_cycle_next;
logic axi_cmd_last_transfer_reg = 1'b0, axi_cmd_last_transfer_next;
logic [TAG_W-1:0] axi_cmd_tag_reg = '0, axi_cmd_tag_next;
logic axi_cmd_valid_reg = 1'b0, axi_cmd_valid_next;

logic [OFFSET_W-1:0] offset_reg = '0, offset_next;
logic [OFFSET_W-1:0] first_cycle_offset_reg = '0, first_cycle_offset_next;
logic [OFFSET_W-1:0] last_cycle_offset_reg = '0, last_cycle_offset_next;
logic [CYCLE_CNT_W-1:0] input_cycle_count_reg = '0, input_cycle_count_next;
logic [CYCLE_CNT_W-1:0] output_cycle_count_reg = '0, output_cycle_count_next;
logic input_active_reg = 1'b0, input_active_next;
logic output_active_reg = 1'b0, output_active_next;
logic bubble_cycle_reg = 1'b0, bubble_cycle_next;
logic first_input_cycle_reg = 1'b0, first_input_cycle_next;
logic first_output_cycle_reg = 1'b0, first_output_cycle_next;
logic output_last_cycle_reg = 1'b0, output_last_cycle_next;
logic last_transfer_reg = 1'b0, last_transfer_next;
logic [1:0] rresp_reg = AXI_RESP_OKAY, rresp_next;
logic [1:0] bresp_reg = AXI_RESP_OKAY, bresp_next;

logic [TAG_W-1:0] tag_reg = '0, tag_next;

logic [STATUS_FIFO_AW+1-1:0] status_fifo_wr_ptr_reg = '0;
logic [STATUS_FIFO_AW+1-1:0] status_fifo_rd_ptr_reg = '0, status_fifo_rd_ptr_next;
logic [TAG_W-1:0] status_fifo_tag[2**STATUS_FIFO_AW];
logic [1:0] status_fifo_resp[2**STATUS_FIFO_AW];
logic status_fifo_last[2**STATUS_FIFO_AW];
logic [TAG_W-1:0] status_fifo_wr_tag;
logic [1:0] status_fifo_wr_resp;
logic status_fifo_wr_last;

logic [STATUS_FIFO_AW+1-1:0] active_count_reg = '0;
logic active_count_av_reg = 1'b1;
logic inc_active;
logic dec_active;

logic desc_req_ready_reg = 1'b0, desc_req_ready_next;

logic [TAG_W-1:0] desc_sts_tag_reg = '0, desc_sts_tag_next;
logic [3:0] desc_sts_error_reg = 4'd0, desc_sts_error_next;
logic desc_sts_valid_reg = 1'b0, desc_sts_valid_next;

logic [AXI_ADDR_W-1:0] m_axi_araddr_reg = '0, m_axi_araddr_next;
logic [7:0] m_axi_arlen_reg = 8'd0, m_axi_arlen_next;
logic m_axi_arvalid_reg = 1'b0, m_axi_arvalid_next;
logic m_axi_rready_reg = 1'b0, m_axi_rready_next;

logic [AXI_ADDR_W-1:0] m_axi_awaddr_reg = '0, m_axi_awaddr_next;
logic [7:0] m_axi_awlen_reg = 8'd0, m_axi_awlen_next;
logic m_axi_awvalid_reg = 1'b0, m_axi_awvalid_next;
logic m_axi_bready_reg = 1'b0, m_axi_bready_next;

logic [AXI_DATA_W-1:0] save_axi_rdata_reg = '0;

wire [AXI_DATA_W*2-1:0] axi_rdata_full = {m_axi_rd.rdata, save_axi_rdata_reg};
wire [AXI_DATA_W-1:0] shift_axi_rdata = axi_rdata_full[(OFFSET_W+1)'(AXI_STRB_W-offset_reg)*AXI_BYTE_SIZE +: AXI_DATA_W];

// internal datapath
logic  [AXI_DATA_W-1:0] m_axi_wdata_int;
logic  [AXI_STRB_W-1:0] m_axi_wstrb_int;
logic                   m_axi_wlast_int;
logic                   m_axi_wvalid_int;
wire                    m_axi_wready_int;

assign desc_req.req_ready = desc_req_ready_reg;

assign desc_sts.sts_len = '0;
assign desc_sts.sts_tag = desc_sts_tag_reg;
assign desc_sts.sts_id = '0;
assign desc_sts.sts_dest = '0;
assign desc_sts.sts_user = '0;
assign desc_sts.sts_error = desc_sts_error_reg;
assign desc_sts.sts_valid = desc_sts_valid_reg;

assign m_axi_rd.arid = '0;
assign m_axi_rd.araddr = m_axi_araddr_reg;
assign m_axi_rd.arlen = m_axi_arlen_reg;
assign m_axi_rd.arsize = 3'(AXI_BURST_SIZE);
assign m_axi_rd.arburst = 2'b01;
assign m_axi_rd.arlock = 1'b0;
assign m_axi_rd.arcache = 4'b0011;
assign m_axi_rd.arprot = 3'b010;
assign m_axi_rd.arvalid = m_axi_arvalid_reg;
assign m_axi_rd.rready = m_axi_rready_reg;

assign m_axi_wr.awid = '0;
assign m_axi_wr.awaddr = m_axi_awaddr_reg;
assign m_axi_wr.awlen = m_axi_awlen_reg;
assign m_axi_wr.awsize = 3'(AXI_BURST_SIZE);
assign m_axi_wr.awburst = 2'b01;
assign m_axi_wr.awlock = 1'b0;
assign m_axi_wr.awcache = 4'b0011;
assign m_axi_wr.awprot = 3'b010;
assign m_axi_wr.awvalid = m_axi_awvalid_reg;
assign m_axi_wr.bready = m_axi_bready_reg;

always_comb begin
    read_state_next = READ_STATE_IDLE;

    desc_req_ready_next = 1'b0;

    m_axi_araddr_next = m_axi_araddr_reg;
    m_axi_arlen_next = m_axi_arlen_reg;
    m_axi_arvalid_next = m_axi_arvalid_reg && !m_axi_rd.arready;

    read_addr_next = read_addr_reg;
    write_addr_next = write_addr_reg;
    op_count_next = op_count_reg;
    tr_count_next = tr_count_reg;
    axi_count_next = axi_count_reg;

    axi_cmd_addr_next = axi_cmd_addr_reg;
    axi_cmd_offset_next = axi_cmd_offset_reg;
    axi_cmd_first_cycle_offset_next = axi_cmd_first_cycle_offset_reg;
    axi_cmd_last_cycle_offset_next = axi_cmd_last_cycle_offset_reg;
    axi_cmd_input_cycle_count_next = axi_cmd_input_cycle_count_reg;
    axi_cmd_output_cycle_count_next = axi_cmd_output_cycle_count_reg;
    axi_cmd_bubble_cycle_next = axi_cmd_bubble_cycle_reg;
    axi_cmd_last_transfer_next = axi_cmd_last_transfer_reg;
    axi_cmd_tag_next = axi_cmd_tag_reg;
    axi_cmd_valid_next = axi_cmd_valid_reg && !axi_cmd_ready;

    inc_active = 1'b0;

    case (read_state_reg)
        READ_STATE_IDLE: begin
            // idle state - load new descriptor to start operation
            desc_req_ready_next = !axi_cmd_valid_reg && enable && active_count_av_reg;

            if (desc_req.req_ready && desc_req.req_valid) begin
                if (UNALIGNED_EN) begin
                    read_addr_next = desc_req.req_src_addr;
                    write_addr_next = desc_req.req_dst_addr;
                end else begin
                    read_addr_next = desc_req.req_src_addr & ADDR_MASK;
                    write_addr_next = desc_req.req_dst_addr & ADDR_MASK;
                end
                axi_cmd_tag_next = desc_req.req_tag;
                op_count_next = desc_req.req_len;

                desc_req_ready_next = 1'b0;
                read_state_next = READ_STATE_START;
            end else begin
                read_state_next = READ_STATE_IDLE;
            end
        end
        READ_STATE_START: begin
            // start state - compute write length
            if (!axi_cmd_valid_reg && active_count_av_reg) begin
                if (op_count_reg <= LEN_W'(AXI_MAX_BURST_SIZE) - LEN_W'(write_addr_reg & OFFSET_MASK) || AXI_MAX_BURST_SIZE >= 4096) begin
                    // packet smaller than max burst size
                    if ((12'(write_addr_reg & 12'hfff) + 12'(op_count_reg & 12'hfff)) >> 12 != 0 || op_count_reg >> 12 != 0) begin
                        // crosses 4k boundary
                        axi_count_next = 13'h1000 - 12'(write_addr_reg & 12'hfff);
                    end else begin
                        // does not cross 4k boundary
                        axi_count_next = 13'(op_count_reg);
                    end
                end else begin
                    // packet larger than max burst size
                    if ((12'(write_addr_reg & 12'hfff) + 12'(AXI_MAX_BURST_SIZE)) >> 12 != 0) begin
                        // crosses 4k boundary
                        axi_count_next = 13'h1000 - 12'(write_addr_reg & 12'hfff);
                    end else begin
                        // does not cross 4k boundary
                        axi_count_next = 13'(AXI_MAX_BURST_SIZE) - 13'(write_addr_reg & OFFSET_MASK);
                    end
                end

                write_addr_next = write_addr_reg + AXI_ADDR_W'(axi_count_next);
                op_count_next = op_count_reg - LEN_W'(axi_count_next);

                axi_cmd_addr_next = write_addr_reg;
                if (UNALIGNED_EN) begin
                    axi_cmd_input_cycle_count_next = CYCLE_CNT_W'((axi_count_next + 13'(read_addr_reg & OFFSET_MASK) - 13'd1) >> AXI_BURST_SIZE);
                    axi_cmd_output_cycle_count_next = CYCLE_CNT_W'((axi_count_next + 13'(write_addr_reg & OFFSET_MASK) - 13'd1) >> AXI_BURST_SIZE);
                    axi_cmd_offset_next = OFFSET_W'(write_addr_reg & OFFSET_MASK) - OFFSET_W'(read_addr_reg & OFFSET_MASK);
                    axi_cmd_bubble_cycle_next = OFFSET_W'(read_addr_reg & OFFSET_MASK) > OFFSET_W'(write_addr_reg & OFFSET_MASK);
                    axi_cmd_first_cycle_offset_next = OFFSET_W'(write_addr_reg & OFFSET_MASK);
                    axi_cmd_last_cycle_offset_next = axi_cmd_first_cycle_offset_next + OFFSET_W'(axi_count_next & OFFSET_MASK);
                end else begin
                    axi_cmd_input_cycle_count_next = CYCLE_CNT_W'((axi_count_next - 13'd1) >> AXI_BURST_SIZE);
                    axi_cmd_output_cycle_count_next = CYCLE_CNT_W'((axi_count_next - 13'd1) >> AXI_BURST_SIZE);
                    axi_cmd_offset_next = '0;
                    axi_cmd_bubble_cycle_next = '0;
                    axi_cmd_first_cycle_offset_next = '0;
                    axi_cmd_last_cycle_offset_next = OFFSET_W'(axi_count_next & OFFSET_MASK);
                end
                axi_cmd_last_transfer_next = op_count_next == 0;
                axi_cmd_valid_next = 1'b1;

                inc_active = 1'b1;

                read_state_next = READ_STATE_REQ;
            end else begin
                read_state_next = READ_STATE_START;
            end
        end
        READ_STATE_REQ: begin
            // request state - issue AXI read requests
            if (!m_axi_rd.arvalid) begin
                if (axi_count_reg <= 13'(AXI_MAX_BURST_SIZE) - 13'(read_addr_reg & OFFSET_MASK) || AXI_MAX_BURST_SIZE >= 4096) begin
                    // packet smaller than max burst size
                    if ((12'(read_addr_reg & 12'hfff) + 12'(axi_count_reg & 12'hfff)) >> 12 != 0 || axi_count_reg >> 12 != 0) begin
                        // crosses 4k boundary
                        tr_count_next = 13'h1000 - 12'(read_addr_reg & 12'hfff);
                    end else begin
                        // does not cross 4k boundary
                        tr_count_next = 13'(axi_count_reg);
                    end
                end else begin
                    // packet larger than max burst size
                    if ((12'(read_addr_reg & 12'hfff) + 12'(AXI_MAX_BURST_SIZE)) >> 12 != 0) begin
                        // crosses 4k boundary
                        tr_count_next = 13'h1000 - 12'(read_addr_reg & 12'hfff);
                    end else begin
                        // does not cross 4k boundary
                        tr_count_next = 13'(AXI_MAX_BURST_SIZE) - 13'(read_addr_reg & OFFSET_MASK);
                    end
                end

                m_axi_araddr_next = read_addr_reg;
                if (UNALIGNED_EN) begin
                    m_axi_arlen_next = 8'((tr_count_next + 13'(read_addr_reg & OFFSET_MASK) - 13'd1) >> AXI_BURST_SIZE);
                end else begin
                    m_axi_arlen_next = 8'((tr_count_next - 13'd1) >> AXI_BURST_SIZE);
                end
                m_axi_arvalid_next = 1'b1;

                read_addr_next = read_addr_reg + AXI_ADDR_W'(tr_count_next);
                axi_count_next = axi_count_reg - tr_count_next;

                if (axi_count_next > 0) begin
                    read_state_next = READ_STATE_REQ;
                end else if (op_count_next > 0) begin
                    read_state_next = READ_STATE_START;
                end else begin
                    desc_req_ready_next = !axi_cmd_valid_reg && enable && active_count_av_reg;
                    read_state_next = READ_STATE_IDLE;
                end
            end else begin
                read_state_next = READ_STATE_REQ;
            end
        end
        default: begin
            // invalid state
            read_state_next = READ_STATE_IDLE;
        end
    endcase
end

always_comb begin
    axi_state_next = AXI_STATE_IDLE;

    desc_sts_tag_next = desc_sts_tag_reg;
    desc_sts_error_next = desc_sts_error_reg;
    desc_sts_valid_next = 1'b0;

    m_axi_awaddr_next = m_axi_awaddr_reg;
    m_axi_awlen_next = m_axi_awlen_reg;
    m_axi_awvalid_next = m_axi_awvalid_reg && !m_axi_wr.awready;
    m_axi_wdata_int = shift_axi_rdata;
    m_axi_wstrb_int = '0;
    m_axi_wlast_int = 1'b0;
    m_axi_wvalid_int = 1'b0;
    m_axi_bready_next = 1'b0;

    m_axi_rready_next = 1'b0;

    transfer_in_save = 1'b0;
    axi_cmd_ready = 1'b0;
    status_fifo_we = 1'b0;

    offset_next = offset_reg;
    first_cycle_offset_next = first_cycle_offset_reg;
    last_cycle_offset_next = last_cycle_offset_reg;
    input_cycle_count_next = input_cycle_count_reg;
    output_cycle_count_next = output_cycle_count_reg;
    input_active_next = input_active_reg;
    output_active_next = output_active_reg;
    bubble_cycle_next = bubble_cycle_reg;
    first_input_cycle_next = first_input_cycle_reg;
    first_output_cycle_next = first_output_cycle_reg;
    output_last_cycle_next = output_last_cycle_reg;
    last_transfer_next = last_transfer_reg;

    tag_next = tag_reg;

    status_fifo_rd_ptr_next = status_fifo_rd_ptr_reg;

    dec_active = 1'b0;

    if (m_axi_rd.rready && m_axi_rd.rvalid && (m_axi_rd.rresp == AXI_RESP_SLVERR || m_axi_rd.rresp == AXI_RESP_DECERR)) begin
        rresp_next = m_axi_rd.rresp;
    end else begin
        rresp_next = rresp_reg;
    end

    if (m_axi_wr.bready && m_axi_wr.bvalid && (m_axi_wr.bresp == AXI_RESP_SLVERR || m_axi_wr.bresp == AXI_RESP_DECERR)) begin
        bresp_next = m_axi_wr.bresp;
    end else begin
        bresp_next = bresp_reg;
    end

    status_fifo_wr_tag = tag_reg;
    status_fifo_wr_resp = rresp_next;
    status_fifo_wr_last = 1'b0;

    case (axi_state_reg)
        AXI_STATE_IDLE: begin
            // idle state - load new descriptor to start operation
            m_axi_rready_next = 1'b0;

            // store transfer parameters
            if (UNALIGNED_EN) begin
                offset_next = axi_cmd_offset_reg;
                first_cycle_offset_next = axi_cmd_first_cycle_offset_reg;
            end else begin
                offset_next = 0;
                first_cycle_offset_next = 0;
            end
            last_cycle_offset_next = axi_cmd_last_cycle_offset_reg;
            input_cycle_count_next = axi_cmd_input_cycle_count_reg;
            output_cycle_count_next = axi_cmd_output_cycle_count_reg;
            bubble_cycle_next = axi_cmd_bubble_cycle_reg;
            last_transfer_next = axi_cmd_last_transfer_reg;
            tag_next = axi_cmd_tag_reg;

            output_last_cycle_next = output_cycle_count_next == 0;
            input_active_next = 1'b1;
            output_active_next = 1'b1;
            first_input_cycle_next = 1'b1;
            first_output_cycle_next = 1'b1;

            if (!m_axi_wr.awvalid && axi_cmd_valid_reg) begin
                axi_cmd_ready = 1'b1;

                m_axi_awaddr_next = axi_cmd_addr_reg;
                m_axi_awlen_next = 8'(axi_cmd_output_cycle_count_reg);
                m_axi_awvalid_next = 1'b1;

                m_axi_rready_next = m_axi_wready_int;
                axi_state_next = AXI_STATE_WRITE;
            end
        end
        AXI_STATE_WRITE: begin
            // handle AXI read data
            m_axi_rready_next = m_axi_wready_int && input_active_reg;

            if ((m_axi_rd.rready && m_axi_rd.rvalid) || !input_active_reg) begin
                // transfer in AXI read data
                transfer_in_save = m_axi_rd.rready && m_axi_rd.rvalid;

                if (UNALIGNED_EN && first_input_cycle_reg && bubble_cycle_reg) begin
                    if (input_active_reg) begin
                        input_cycle_count_next = input_cycle_count_reg - 1;
                        input_active_next = input_cycle_count_reg > 0;
                    end
                    bubble_cycle_next = 1'b0;
                    first_input_cycle_next = 1'b0;

                    m_axi_rready_next = m_axi_wready_int && input_active_next;
                    axi_state_next = AXI_STATE_WRITE;
                end else begin
                    // update counters
                    if (input_active_reg) begin
                        input_cycle_count_next = input_cycle_count_reg - 1;
                        input_active_next = input_cycle_count_reg > 0;
                    end
                    if (output_active_reg) begin
                        output_cycle_count_next = output_cycle_count_reg - 1;
                        output_active_next = output_cycle_count_reg > 0;
                    end
                    output_last_cycle_next = output_cycle_count_next == 0;
                    bubble_cycle_next = 1'b0;
                    first_input_cycle_next = 1'b0;
                    first_output_cycle_next = 1'b0;

                    // pass through read data
                    m_axi_wdata_int = shift_axi_rdata;
                    if (first_output_cycle_reg) begin
                        m_axi_wstrb_int = {AXI_STRB_W{1'b1}} << first_cycle_offset_reg;
                    end else begin
                        m_axi_wstrb_int = {AXI_STRB_W{1'b1}};
                    end
                    m_axi_wvalid_int = 1'b1;

                    if (output_last_cycle_reg) begin
                        // no more data to transfer, finish operation
                        if (last_cycle_offset_reg > 0) begin
                            m_axi_wstrb_int = m_axi_wstrb_int & {AXI_STRB_W{1'b1}} >> (OFFSET_W'(AXI_STRB_W) - OFFSET_W'(last_cycle_offset_reg));
                        end
                        m_axi_wlast_int = 1'b1;

                        status_fifo_we = 1'b1;
                        status_fifo_wr_tag = tag_reg;
                        status_fifo_wr_resp = rresp_next;
                        status_fifo_wr_last = last_transfer_reg;

                        if (last_transfer_reg) begin
                            rresp_next = AXI_RESP_OKAY;
                        end

                        m_axi_rready_next = 1'b0;
                        axi_state_next = AXI_STATE_IDLE;
                    end else begin
                        // more cycles in AXI transfer
                        axi_state_next = AXI_STATE_WRITE;
                    end
                end
            end else begin
                axi_state_next = AXI_STATE_WRITE;
            end
        end
    endcase

    if (status_fifo_rd_ptr_reg != status_fifo_wr_ptr_reg) begin
        // status FIFO not empty
        if (m_axi_wr.bready && m_axi_wr.bvalid) begin
            // got write completion, pop and return status
            desc_sts_tag_next = status_fifo_tag[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]];
            if (status_fifo_resp[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]] == AXI_RESP_SLVERR) begin
                desc_sts_error_next = DMA_ERROR_AXI_RD_SLVERR;
            end else if (status_fifo_resp[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]] == AXI_RESP_DECERR) begin
                desc_sts_error_next = DMA_ERROR_AXI_RD_DECERR;
            end else if (bresp_next == AXI_RESP_SLVERR) begin
                desc_sts_error_next = DMA_ERROR_AXI_WR_SLVERR;
            end else if (bresp_next == AXI_RESP_DECERR) begin
                desc_sts_error_next = DMA_ERROR_AXI_WR_DECERR;
            end else begin
                desc_sts_error_next = DMA_ERROR_NONE;
            end
            desc_sts_valid_next = status_fifo_last[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]];
            status_fifo_rd_ptr_next = status_fifo_rd_ptr_reg + 1;
            m_axi_bready_next = 1'b0;

            if (status_fifo_last[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]]) begin
                bresp_next = AXI_RESP_OKAY;
            end

            dec_active = 1'b1;
        end else begin
            // wait for write completion
            m_axi_bready_next = 1'b1;
        end
    end
end

always_ff @(posedge clk) begin
    read_state_reg <= read_state_next;
    axi_state_reg <= axi_state_next;

    desc_req_ready_reg <= desc_req_ready_next;

    desc_sts_tag_reg <= desc_sts_tag_next;
    desc_sts_error_reg <= desc_sts_error_next;
    desc_sts_valid_reg <= desc_sts_valid_next;

    m_axi_awaddr_reg <= m_axi_awaddr_next;
    m_axi_awlen_reg <= m_axi_awlen_next;
    m_axi_awvalid_reg <= m_axi_awvalid_next;
    m_axi_bready_reg <= m_axi_bready_next;
    m_axi_araddr_reg <= m_axi_araddr_next;
    m_axi_arlen_reg <= m_axi_arlen_next;
    m_axi_arvalid_reg <= m_axi_arvalid_next;
    m_axi_rready_reg <= m_axi_rready_next;

    read_addr_reg <= read_addr_next;
    write_addr_reg <= write_addr_next;
    op_count_reg <= op_count_next;
    tr_count_reg <= tr_count_next;
    axi_count_reg <= axi_count_next;

    axi_cmd_addr_reg <= axi_cmd_addr_next;
    axi_cmd_offset_reg <= axi_cmd_offset_next;
    axi_cmd_first_cycle_offset_reg <= axi_cmd_first_cycle_offset_next;
    axi_cmd_last_cycle_offset_reg <= axi_cmd_last_cycle_offset_next;
    axi_cmd_input_cycle_count_reg <= axi_cmd_input_cycle_count_next;
    axi_cmd_output_cycle_count_reg <= axi_cmd_output_cycle_count_next;
    axi_cmd_bubble_cycle_reg <= axi_cmd_bubble_cycle_next;
    axi_cmd_last_transfer_reg <= axi_cmd_last_transfer_next;
    axi_cmd_tag_reg <= axi_cmd_tag_next;
    axi_cmd_valid_reg <= axi_cmd_valid_next;

    offset_reg <= offset_next;
    first_cycle_offset_reg <= first_cycle_offset_next;
    last_cycle_offset_reg <= last_cycle_offset_next;
    input_cycle_count_reg <= input_cycle_count_next;
    output_cycle_count_reg <= output_cycle_count_next;
    input_active_reg <= input_active_next;
    output_active_reg <= output_active_next;
    bubble_cycle_reg <= bubble_cycle_next;
    first_input_cycle_reg <= first_input_cycle_next;
    first_output_cycle_reg <= first_output_cycle_next;
    output_last_cycle_reg <= output_last_cycle_next;
    last_transfer_reg <= last_transfer_next;
    rresp_reg <= rresp_next;
    bresp_reg <= bresp_next;

    tag_reg <= tag_next;

    if (transfer_in_save) begin
        save_axi_rdata_reg <= m_axi_rd.rdata;
    end

    if (status_fifo_we) begin
        status_fifo_tag[status_fifo_wr_ptr_reg[STATUS_FIFO_AW-1:0]] <= status_fifo_wr_tag;
        status_fifo_resp[status_fifo_wr_ptr_reg[STATUS_FIFO_AW-1:0]] <= status_fifo_wr_resp;
        status_fifo_last[status_fifo_wr_ptr_reg[STATUS_FIFO_AW-1:0]] <= status_fifo_wr_last;
        status_fifo_wr_ptr_reg <= status_fifo_wr_ptr_reg + 1;
    end
    status_fifo_rd_ptr_reg <= status_fifo_rd_ptr_next;

    if (active_count_reg < 2**STATUS_FIFO_AW && inc_active && !dec_active) begin
        active_count_reg <= active_count_reg + 1;
        active_count_av_reg <= active_count_reg < (2**STATUS_FIFO_AW-1);
    end else if (active_count_reg > 0 && !inc_active && dec_active) begin
        active_count_reg <= active_count_reg - 1;
        active_count_av_reg <= 1'b1;
    end else begin
        active_count_av_reg <= active_count_reg < 2**STATUS_FIFO_AW;
    end

    if (rst) begin
        read_state_reg <= READ_STATE_IDLE;
        axi_state_reg <= AXI_STATE_IDLE;

        desc_req_ready_reg <= 1'b0;
        desc_sts_valid_reg <= 1'b0;

        m_axi_awvalid_reg <= 1'b0;
        m_axi_bready_reg <= 1'b0;
        m_axi_arvalid_reg <= 1'b0;
        m_axi_rready_reg <= 1'b0;

        axi_cmd_valid_reg <= 1'b0;

        rresp_reg <= AXI_RESP_OKAY;
        bresp_reg <= AXI_RESP_OKAY;

        status_fifo_wr_ptr_reg <= '0;
        status_fifo_rd_ptr_reg <= '0;

        active_count_reg <= '0;
        active_count_av_reg <= 1'b1;
    end
end

// output datapath logic
logic [AXI_DATA_W-1:0] m_axi_wdata_reg  = '0;
logic [AXI_STRB_W-1:0] m_axi_wstrb_reg  = '0;
logic                  m_axi_wlast_reg  = 1'b0;
logic                  m_axi_wvalid_reg = 1'b0;

logic [OUTPUT_FIFO_AW+1-1:0] out_fifo_wr_ptr_reg = '0;
logic [OUTPUT_FIFO_AW+1-1:0] out_fifo_rd_ptr_reg = '0;
logic out_fifo_half_full_reg = 1'b0;

wire out_fifo_full = out_fifo_wr_ptr_reg == (out_fifo_rd_ptr_reg ^ {1'b1, {OUTPUT_FIFO_AW{1'b0}}});
wire out_fifo_empty = out_fifo_wr_ptr_reg == out_fifo_rd_ptr_reg;

(* ram_style = "distributed" *)
logic [AXI_DATA_W-1:0] out_fifo_wdata[2**OUTPUT_FIFO_AW];
(* ram_style = "distributed" *)
logic [AXI_STRB_W-1:0] out_fifo_wstrb[2**OUTPUT_FIFO_AW];
(* ram_style = "distributed" *)
logic                  out_fifo_wlast[2**OUTPUT_FIFO_AW];

assign m_axi_wready_int = !out_fifo_half_full_reg;

assign m_axi_wr.wdata  = m_axi_wdata_reg;
assign m_axi_wr.wstrb  = m_axi_wstrb_reg;
assign m_axi_wr.wvalid = m_axi_wvalid_reg;
assign m_axi_wr.wlast  = m_axi_wlast_reg;

always_ff @(posedge clk) begin
    m_axi_wvalid_reg <= m_axi_wvalid_reg && !m_axi_wr.wready;

    out_fifo_half_full_reg <= $unsigned(out_fifo_wr_ptr_reg - out_fifo_rd_ptr_reg) >= 2**(OUTPUT_FIFO_AW-1);

    if (!out_fifo_full && m_axi_wvalid_int) begin
        out_fifo_wdata[out_fifo_wr_ptr_reg[OUTPUT_FIFO_AW-1:0]] <= m_axi_wdata_int;
        out_fifo_wstrb[out_fifo_wr_ptr_reg[OUTPUT_FIFO_AW-1:0]] <= m_axi_wstrb_int;
        out_fifo_wlast[out_fifo_wr_ptr_reg[OUTPUT_FIFO_AW-1:0]] <= m_axi_wlast_int;
        out_fifo_wr_ptr_reg <= out_fifo_wr_ptr_reg + 1;
    end

    if (!out_fifo_empty && (!m_axi_wvalid_reg || m_axi_wr.wready)) begin
        m_axi_wdata_reg <= out_fifo_wdata[out_fifo_rd_ptr_reg[OUTPUT_FIFO_AW-1:0]];
        m_axi_wstrb_reg <= out_fifo_wstrb[out_fifo_rd_ptr_reg[OUTPUT_FIFO_AW-1:0]];
        m_axi_wlast_reg <= out_fifo_wlast[out_fifo_rd_ptr_reg[OUTPUT_FIFO_AW-1:0]];
        m_axi_wvalid_reg <= 1'b1;
        out_fifo_rd_ptr_reg <= out_fifo_rd_ptr_reg + 1;
    end

    if (rst) begin
        out_fifo_wr_ptr_reg <= '0;
        out_fifo_rd_ptr_reg <= '0;
        m_axi_wvalid_reg <= 1'b0;
    end
end

endmodule

`resetall
