// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2019-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI stream sink DMA client
 */
module taxi_dma_client_axis_sink
(
    input  wire logic         clk,
    input  wire logic         rst,

    /*
     * Descriptor
     */
    taxi_dma_desc_if.req_snk  desc_req,
    taxi_dma_desc_if.sts_src  desc_sts,

    /*
     * AXI stream write data input
     */
    taxi_axis_if.snk          s_axis_wr_data,

    /*
     * RAM interface
     */
    taxi_dma_ram_if.wr_mst    dma_ram_wr,

    /*
     * Configuration
     */
    input  wire logic         enable,
    input  wire logic         abort
);

// TODO cleanup
// verilator lint_off WIDTHEXPAND

// extract parameters
localparam RAM_SEGS = dma_ram_wr.SEGS;
localparam RAM_SEG_ADDR_W = dma_ram_wr.SEG_ADDR_W;
localparam RAM_SEG_DATA_W = dma_ram_wr.SEG_DATA_W;
localparam RAM_SEG_BE_W = dma_ram_wr.SEG_BE_W;

localparam LEN_W = desc_req.LEN_W;
localparam TAG_W = desc_req.TAG_W;

localparam AXIS_DATA_W = s_axis_wr_data.DATA_W;
localparam AXIS_KEEP_EN = s_axis_wr_data.KEEP_EN;
localparam AXIS_KEEP_W = s_axis_wr_data.KEEP_W;
localparam AXIS_LAST_EN = s_axis_wr_data.LAST_EN;
localparam AXIS_ID_EN = s_axis_wr_data.ID_EN;
localparam AXIS_ID_W = s_axis_wr_data.ID_W;
localparam AXIS_DEST_EN = s_axis_wr_data.DEST_EN;
localparam AXIS_DEST_W = s_axis_wr_data.DEST_W;
localparam AXIS_USER_EN = s_axis_wr_data.USER_EN;
localparam AXIS_USER_W = s_axis_wr_data.USER_W;

localparam RAM_ADDR_W = RAM_SEG_ADDR_W+$clog2(RAM_SEGS*RAM_SEG_BE_W);
localparam RAM_BYTE_LANES = RAM_SEG_BE_W;
localparam RAM_BYTE_SIZE = RAM_SEG_DATA_W/RAM_BYTE_LANES;

localparam AXIS_KEEP_W_INT = AXIS_KEEP_EN ? AXIS_KEEP_W : 1;
localparam AXIS_BYTE_LANES = AXIS_KEEP_W_INT;
localparam AXIS_BYTE_SIZE = AXIS_DATA_W/AXIS_BYTE_LANES;

localparam PART_COUNT = RAM_SEGS*RAM_SEG_BE_W / AXIS_KEEP_W_INT;
localparam PART_COUNT_W = PART_COUNT > 1 ? $clog2(PART_COUNT) : 1;
localparam PART_OFFSET_W = AXIS_KEEP_W_INT > 1 ? $clog2(AXIS_KEEP_W_INT) : 1;
localparam PARTS_PER_SEG = (RAM_SEG_BE_W + AXIS_KEEP_W_INT - 1) / AXIS_KEEP_W_INT;
localparam SEGS_PER_PART = (AXIS_KEEP_W_INT + RAM_SEG_BE_W - 1) / RAM_SEG_BE_W;

localparam OFFSET_W = AXIS_KEEP_W_INT > 1 ? $clog2(AXIS_KEEP_W_INT) : 1;
localparam OFFSET_MASK = AXIS_KEEP_W_INT > 1 ? {OFFSET_W{1'b1}} : 0;
localparam ADDR_MASK = {RAM_ADDR_W{1'b1}} << $clog2(AXIS_KEEP_W_INT);
localparam CYCLE_COUNT_W = LEN_W - $clog2(AXIS_KEEP_W_INT) + 1;

localparam STATUS_FIFO_AW = 5;
localparam OUTPUT_FIFO_AW = 5;

// check configuration
if (RAM_BYTE_SIZE * RAM_SEG_BE_W != RAM_SEG_DATA_W)
    $fatal(0, "Error: RAM data width not evenly divisible (instance %m)");

if (AXIS_BYTE_SIZE * AXIS_KEEP_W_INT != AXIS_DATA_W)
    $fatal(0, "Error: AXI stream data width not evenly divisible (instance %m)");

if (RAM_BYTE_SIZE != AXIS_BYTE_SIZE)
    $fatal(0, "Error: word size mismatch (instance %m)");

if (2**$clog2(RAM_BYTE_LANES) != RAM_BYTE_LANES)
    $fatal(0, "Error: RAM word width must be even power of two (instance %m)");

if (AXIS_DATA_W > RAM_SEGS*RAM_SEG_DATA_W)
    $fatal(0, "Error: AXI stream interface width must not be wider than RAM interface width (instance %m)");

if (AXIS_DATA_W*2**$clog2(PART_COUNT) != RAM_SEGS*RAM_SEG_DATA_W)
    $fatal(0, "Error: AXI stream interface width must be a power of two fraction of RAM interface width (instance %m)");

if (desc_req.DST_ADDR_W < RAM_ADDR_W)
    $fatal(0, "Error: Descriptor address width is not sufficient (instance %m)");

typedef enum logic [1:0] {
    STATE_IDLE,
    STATE_WRITE,
    STATE_DROP_DATA
} state_t;

state_t state_reg = STATE_IDLE, state_next;

logic [OFFSET_W:0] cycle_size;

logic [RAM_ADDR_W-1:0] addr_reg = '0, addr_next;
logic [AXIS_KEEP_W_INT-1:0] keep_mask_reg = '0, keep_mask_next;
logic [OFFSET_W-1:0] last_cycle_offset_reg = '0, last_cycle_offset_next;
logic [LEN_W-1:0] length_reg = '0, length_next;
logic [CYCLE_COUNT_W-1:0] cycle_count_reg = '0, cycle_count_next;
logic last_cycle_reg = 1'b0, last_cycle_next;

logic [TAG_W-1:0] tag_reg = '0, tag_next;

logic [STATUS_FIFO_AW+1-1:0] status_fifo_wr_ptr_reg = 0;
logic [STATUS_FIFO_AW+1-1:0] status_fifo_rd_ptr_reg = 0, status_fifo_rd_ptr_next;
logic [LEN_W-1:0] status_fifo_len[2**STATUS_FIFO_AW];
logic [TAG_W-1:0] status_fifo_tag[2**STATUS_FIFO_AW];
logic [AXIS_ID_W-1:0] status_fifo_id[2**STATUS_FIFO_AW];
logic [AXIS_DEST_W-1:0] status_fifo_dest[2**STATUS_FIFO_AW];
logic [AXIS_USER_W-1:0] status_fifo_user[2**STATUS_FIFO_AW];
logic [RAM_SEGS-1:0] status_fifo_mask[2**STATUS_FIFO_AW];
logic status_fifo_last[2**STATUS_FIFO_AW];
logic [LEN_W-1:0] status_fifo_wr_len;
logic [TAG_W-1:0] status_fifo_wr_tag;
logic [AXIS_ID_W-1:0] status_fifo_wr_id;
logic [AXIS_DEST_W-1:0] status_fifo_wr_dest;
logic [AXIS_USER_W-1:0] status_fifo_wr_user;
logic [RAM_SEGS-1:0] status_fifo_wr_mask;
logic status_fifo_wr_last;
logic status_fifo_we;
logic status_fifo_half_full_reg = 1'b0;

logic [STATUS_FIFO_AW+1-1:0] active_count_reg = '0;
logic active_count_av_reg = 1'b1;
logic inc_active;
logic dec_active;

logic desc_req_ready_reg = 1'b0, desc_req_ready_next;

logic [LEN_W-1:0] desc_sts_len_reg = '0, desc_sts_len_next;
logic [TAG_W-1:0] desc_sts_tag_reg = '0, desc_sts_tag_next;
logic [AXIS_ID_W-1:0] desc_sts_id_reg = '0, desc_sts_id_next;
logic [AXIS_DEST_W-1:0] desc_sts_dest_reg = '0, desc_sts_dest_next;
logic [AXIS_USER_W-1:0] desc_sts_user_reg = '0, desc_sts_user_next;
logic desc_sts_valid_reg = 1'b0, desc_sts_valid_next;

logic s_axis_wr_data_tready_reg = 1'b0, s_axis_wr_data_tready_next;

// internal datapath
logic  [RAM_SEGS-1:0][RAM_SEG_BE_W-1:0] ram_wr_cmd_be_int;
logic  [RAM_SEGS-1:0][RAM_SEG_ADDR_W-1:0] ram_wr_cmd_addr_int;
logic  [RAM_SEGS-1:0][RAM_SEG_DATA_W-1:0] ram_wr_cmd_data_int;
logic  [RAM_SEGS-1:0] ram_wr_cmd_valid_int;
wire   [RAM_SEGS-1:0] ram_wr_cmd_ready_int;

logic  [RAM_SEGS-1:0] ram_wr_cmd_mask;

wire   [RAM_SEGS-1:0] out_done;
logic  [RAM_SEGS-1:0] out_done_ack;

assign desc_req.req_ready = desc_req_ready_reg;

assign desc_sts.sts_len = desc_sts_len_reg;
assign desc_sts.sts_tag = desc_sts_tag_reg;
if (AXIS_ID_EN) begin
    assign desc_sts.sts_id = desc_sts_id_reg;
end else begin
    assign desc_sts.sts_id = '0;
end
if (AXIS_DEST_EN) begin
    assign desc_sts.sts_dest = desc_sts_dest_reg;
end else begin
    assign desc_sts.sts_dest = '0;
end
if (AXIS_USER_EN) begin
    assign desc_sts.sts_user = desc_sts_user_reg;
end else begin
    assign desc_sts.sts_user = '0;
end
assign desc_sts.sts_error = 4'd0;
assign desc_sts.sts_valid = desc_sts_valid_reg;

assign s_axis_wr_data.tready = s_axis_wr_data_tready_reg;

always_comb begin
    state_next = STATE_IDLE;

    desc_req_ready_next = 1'b0;

    desc_sts_len_next = desc_sts_len_reg;
    desc_sts_tag_next = desc_sts_tag_reg;
    desc_sts_id_next = desc_sts_id_reg;
    desc_sts_dest_next = desc_sts_dest_reg;
    desc_sts_user_next = desc_sts_user_reg;
    desc_sts_valid_next = 1'b0;

    s_axis_wr_data_tready_next = 1'b0;

    if (PART_COUNT > 1) begin
        ram_wr_cmd_be_int = (s_axis_wr_data.tkeep & keep_mask_reg) << (addr_reg & ({PART_COUNT_W{1'b1}} << PART_OFFSET_W));
    end else begin
        ram_wr_cmd_be_int = s_axis_wr_data.tkeep & keep_mask_reg;
    end
    ram_wr_cmd_addr_int = '{RAM_SEGS{addr_reg[RAM_ADDR_W-1:RAM_ADDR_W-RAM_SEG_ADDR_W]}};
    ram_wr_cmd_data_int = {PART_COUNT{s_axis_wr_data.tdata}};
    ram_wr_cmd_valid_int = '0;
    for (integer i = 0; i < RAM_SEGS; i = i + 1) begin
        ram_wr_cmd_mask[i] = ram_wr_cmd_be_int[i] != 0;
    end

    cycle_size = (OFFSET_W+1)'(AXIS_KEEP_W_INT);

    addr_next = addr_reg;
    keep_mask_next = keep_mask_reg;
    last_cycle_offset_next = last_cycle_offset_reg;
    length_next = length_reg;
    cycle_count_next = cycle_count_reg;
    last_cycle_next = last_cycle_reg;

    tag_next = tag_reg;

    status_fifo_rd_ptr_next = status_fifo_rd_ptr_reg;

    status_fifo_wr_len = 0;
    status_fifo_wr_tag = tag_reg;
    status_fifo_wr_id = s_axis_wr_data.tid;
    status_fifo_wr_dest = s_axis_wr_data.tdest;
    status_fifo_wr_user = s_axis_wr_data.tuser;
    status_fifo_wr_mask = ram_wr_cmd_mask;
    status_fifo_wr_last = 1'b0;
    status_fifo_we = 1'b0;

    inc_active = 1'b0;
    dec_active = 1'b0;

    out_done_ack = '0;

    case (state_reg)
        STATE_IDLE: begin
            // idle state - load new descriptor to start operation
            desc_req_ready_next = enable && active_count_av_reg;

            addr_next = RAM_ADDR_W'(desc_req.req_dst_addr & ADDR_MASK);
            last_cycle_offset_next = OFFSET_W'(desc_req.req_len & OFFSET_MASK);

            tag_next = desc_req.req_tag;

            length_next = 0;

            cycle_count_next = CYCLE_COUNT_W'(desc_req.req_len - LEN_W'(1)) >> $clog2(AXIS_KEEP_W_INT);
            last_cycle_next = cycle_count_next == 0;
            if (cycle_count_next == 0 && last_cycle_offset_next != 0) begin
                keep_mask_next = {AXIS_KEEP_W_INT{1'b1}} >> (AXIS_KEEP_W_INT - last_cycle_offset_next);
            end else begin
                keep_mask_next = '1;
            end

            if (desc_req.req_ready && desc_req.req_valid) begin
                desc_req_ready_next = 1'b0;
                s_axis_wr_data_tready_next = &ram_wr_cmd_ready_int && !status_fifo_half_full_reg;

                inc_active = 1'b1;

                state_next = STATE_WRITE;
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_WRITE: begin
            // write state - generate write operations
            s_axis_wr_data_tready_next = &ram_wr_cmd_ready_int && !status_fifo_half_full_reg;

            if (s_axis_wr_data.tready && s_axis_wr_data.tvalid) begin

                // update counters
                addr_next = addr_reg + RAM_ADDR_W'(AXIS_KEEP_W_INT);
                length_next = length_reg + LEN_W'(AXIS_KEEP_W_INT);
                cycle_count_next = cycle_count_reg - 1;
                last_cycle_next = cycle_count_next == 0;
                if (cycle_count_next == 0 && last_cycle_offset_reg != 0) begin
                    keep_mask_next = {AXIS_KEEP_W_INT{1'b1}} >> (AXIS_KEEP_W_INT - last_cycle_offset_reg);
                end else begin
                    keep_mask_next = '1;
                end

                if (PART_COUNT > 1) begin
                    ram_wr_cmd_be_int = (s_axis_wr_data.tkeep & keep_mask_reg) << (addr_reg & ({PART_COUNT_W{1'b1}} << PART_OFFSET_W));
                end else begin
                    ram_wr_cmd_be_int = s_axis_wr_data.tkeep & keep_mask_reg;
                end
                ram_wr_cmd_addr_int = {RAM_SEGS{addr_reg[RAM_ADDR_W-1:RAM_ADDR_W-RAM_SEG_ADDR_W]}};
                ram_wr_cmd_data_int = {PART_COUNT{s_axis_wr_data.tdata}};
                ram_wr_cmd_valid_int = ram_wr_cmd_mask;

                // enqueue status FIFO entry for write completion
                status_fifo_wr_len = length_next;
                status_fifo_wr_tag = tag_reg;
                status_fifo_wr_id = s_axis_wr_data.tid;
                status_fifo_wr_dest = s_axis_wr_data.tdest;
                status_fifo_wr_user = s_axis_wr_data.tuser;
                status_fifo_wr_mask = ram_wr_cmd_mask;
                status_fifo_wr_last = 1'b0;
                status_fifo_we = 1'b1;

                if (AXIS_LAST_EN && s_axis_wr_data.tlast) begin
                    cycle_size = (OFFSET_W+1)'(AXIS_KEEP_W_INT);
                    if (AXIS_KEEP_EN) begin
                        for (integer i = AXIS_KEEP_W_INT-1; i >= 0; i = i - 1) begin
                            if (((s_axis_wr_data.tkeep & keep_mask_reg) & (1 << i)) == 0) begin
                                cycle_size = (OFFSET_W+1)'(i);
                            end
                        end
                    end

                    // no more data to transfer, finish operation
                    if (last_cycle_reg && last_cycle_offset_reg > 0) begin
                        if (AXIS_KEEP_EN && (s_axis_wr_data.tkeep & keep_mask_reg & ~({AXIS_KEEP_W_INT{1'b1}} >> (AXIS_KEEP_W_INT - last_cycle_offset_reg))) == 0) begin
                            length_next = length_reg + LEN_W'(cycle_size);
                        end else begin
                            length_next = length_reg + LEN_W'(last_cycle_offset_reg);
                        end
                    end else begin
                        if (AXIS_KEEP_EN) begin
                            length_next = length_reg + LEN_W'(cycle_size);
                        end
                    end

                    // enqueue status FIFO entry for write completion
                    status_fifo_wr_len = length_next;
                    status_fifo_wr_tag = tag_reg;
                    status_fifo_wr_id = s_axis_wr_data.tid;
                    status_fifo_wr_dest = s_axis_wr_data.tdest;
                    status_fifo_wr_user = s_axis_wr_data.tuser;
                    status_fifo_wr_mask = ram_wr_cmd_mask;
                    status_fifo_wr_last = 1'b1;
                    status_fifo_we = 1'b1;

                    s_axis_wr_data_tready_next = 1'b0;
                    desc_req_ready_next = enable && active_count_av_reg;
                    state_next = STATE_IDLE;
                end else if (last_cycle_reg) begin
                    if (last_cycle_offset_reg > 0) begin
                        length_next = length_reg + LEN_W'(last_cycle_offset_reg);
                    end

                    // enqueue status FIFO entry for write completion
                    status_fifo_wr_len = length_next;
                    status_fifo_wr_tag = tag_reg;
                    status_fifo_wr_id = s_axis_wr_data.tid;
                    status_fifo_wr_dest = s_axis_wr_data.tdest;
                    status_fifo_wr_user = s_axis_wr_data.tuser;
                    status_fifo_wr_mask = ram_wr_cmd_mask;
                    status_fifo_wr_last = 1'b1;
                    status_fifo_we = 1'b1;

                    if (AXIS_LAST_EN) begin
                        s_axis_wr_data_tready_next = 1'b1;
                        state_next = STATE_DROP_DATA;
                    end else begin
                        s_axis_wr_data_tready_next = 1'b0;
                        desc_req_ready_next = enable && active_count_av_reg;
                        state_next = STATE_IDLE;
                    end
                end else begin
                    state_next = STATE_WRITE;
                end
            end else begin
                state_next = STATE_WRITE;
            end
        end
        STATE_DROP_DATA: begin
            // drop excess AXI stream data
            s_axis_wr_data_tready_next = 1'b1;

            if (s_axis_wr_data.tready && s_axis_wr_data.tvalid) begin
                if (s_axis_wr_data.tlast) begin
                    s_axis_wr_data_tready_next = 1'b0;
                    desc_req_ready_next = enable && active_count_av_reg;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_DROP_DATA;
                end
            end else begin
                state_next = STATE_DROP_DATA;
            end
        end
        default: begin
            state_next = STATE_IDLE;
        end
    endcase

    desc_sts_len_next = status_fifo_len[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]];
    desc_sts_tag_next = status_fifo_tag[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]];
    desc_sts_id_next = status_fifo_id[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]];
    desc_sts_dest_next = status_fifo_dest[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]];
    desc_sts_user_next = status_fifo_user[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]];
    desc_sts_valid_next = 1'b0;

    if (status_fifo_rd_ptr_reg != status_fifo_wr_ptr_reg) begin
        // status FIFO not empty
        if ((status_fifo_mask[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]] & ~out_done) == 0) begin
            // got write completion, pop and return status
            status_fifo_rd_ptr_next = status_fifo_rd_ptr_reg + 1;

            out_done_ack = status_fifo_mask[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]];

            if (status_fifo_last[status_fifo_rd_ptr_reg[STATUS_FIFO_AW-1:0]]) begin
                desc_sts_valid_next = 1'b1;

                dec_active = 1'b1;
            end
        end
    end
end

always_ff @(posedge clk) begin
    state_reg <= state_next;

    desc_req_ready_reg <= desc_req_ready_next;

    desc_sts_len_reg <= desc_sts_len_next;
    desc_sts_tag_reg <= desc_sts_tag_next;
    desc_sts_id_reg <= desc_sts_id_next;
    desc_sts_dest_reg <= desc_sts_dest_next;
    desc_sts_user_reg <= desc_sts_user_next;
    desc_sts_valid_reg <= desc_sts_valid_next;

    s_axis_wr_data_tready_reg <= s_axis_wr_data_tready_next;

    addr_reg <= addr_next;
    keep_mask_reg <= keep_mask_next;
    last_cycle_offset_reg <= last_cycle_offset_next;
    length_reg <= length_next;
    cycle_count_reg <= cycle_count_next;
    last_cycle_reg <= last_cycle_next;

    tag_reg <= tag_next;

    if (status_fifo_we) begin
        status_fifo_len[status_fifo_wr_ptr_reg[STATUS_FIFO_AW-1:0]] <= status_fifo_wr_len;
        status_fifo_tag[status_fifo_wr_ptr_reg[STATUS_FIFO_AW-1:0]] <= status_fifo_wr_tag;
        status_fifo_id[status_fifo_wr_ptr_reg[STATUS_FIFO_AW-1:0]] <= status_fifo_wr_id;
        status_fifo_dest[status_fifo_wr_ptr_reg[STATUS_FIFO_AW-1:0]] <= status_fifo_wr_dest;
        status_fifo_user[status_fifo_wr_ptr_reg[STATUS_FIFO_AW-1:0]] <= status_fifo_wr_user;
        status_fifo_mask[status_fifo_wr_ptr_reg[STATUS_FIFO_AW-1:0]] <= status_fifo_wr_mask;
        status_fifo_last[status_fifo_wr_ptr_reg[STATUS_FIFO_AW-1:0]] <= status_fifo_wr_last;
        status_fifo_wr_ptr_reg <= status_fifo_wr_ptr_reg + 1;
    end
    status_fifo_rd_ptr_reg <= status_fifo_rd_ptr_next;

    status_fifo_half_full_reg <= $unsigned(status_fifo_wr_ptr_reg - status_fifo_rd_ptr_reg) >= 2**(STATUS_FIFO_AW-1);

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
        state_reg <= STATE_IDLE;

        desc_req_ready_reg <= 1'b0;
        desc_sts_valid_reg <= 1'b0;

        s_axis_wr_data_tready_reg <= 1'b0;

        status_fifo_wr_ptr_reg <= '0;
        status_fifo_rd_ptr_reg <= '0;

        active_count_reg <= '0;
        active_count_av_reg <= 1'b1;
    end
end

// output datapath logic (write data)
for (genvar n = 0; n < RAM_SEGS; n = n + 1) begin

    logic [RAM_SEG_BE_W-1:0]   ram_wr_cmd_be_reg = '0;
    logic [RAM_SEG_ADDR_W-1:0] ram_wr_cmd_addr_reg = '0;
    logic [RAM_SEG_DATA_W-1:0] ram_wr_cmd_data_reg = '0;
    logic                      ram_wr_cmd_valid_reg = 1'b0;

    logic [OUTPUT_FIFO_AW+1-1:0] out_fifo_wr_ptr_reg = '0;
    logic [OUTPUT_FIFO_AW+1-1:0] out_fifo_rd_ptr_reg = '0;
    logic out_fifo_half_full_reg = 1'b0;

    wire out_fifo_full = out_fifo_wr_ptr_reg == (out_fifo_rd_ptr_reg ^ {1'b1, {OUTPUT_FIFO_AW{1'b0}}});
    wire out_fifo_empty = out_fifo_wr_ptr_reg == out_fifo_rd_ptr_reg;

    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    logic [RAM_SEG_BE_W-1:0]   out_fifo_wr_cmd_be[2**OUTPUT_FIFO_AW];
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    logic [RAM_SEG_ADDR_W-1:0] out_fifo_wr_cmd_addr[2**OUTPUT_FIFO_AW];
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    logic [RAM_SEG_DATA_W-1:0] out_fifo_wr_cmd_data[2**OUTPUT_FIFO_AW];

    logic [OUTPUT_FIFO_AW+1-1:0] done_count_reg = 0;
    logic done_reg = 1'b0;

    assign ram_wr_cmd_ready_int[n] = !out_fifo_half_full_reg;

    assign dma_ram_wr.wr_cmd_be[n] = ram_wr_cmd_be_reg;
    assign dma_ram_wr.wr_cmd_addr[n] = ram_wr_cmd_addr_reg;
    assign dma_ram_wr.wr_cmd_data[n] = ram_wr_cmd_data_reg;
    assign dma_ram_wr.wr_cmd_valid[n] = ram_wr_cmd_valid_reg;

    assign out_done[n] = done_reg;

    always_ff @(posedge clk) begin
        ram_wr_cmd_valid_reg <= ram_wr_cmd_valid_reg && !dma_ram_wr.wr_cmd_ready[n];

        out_fifo_half_full_reg <= $unsigned(out_fifo_wr_ptr_reg - out_fifo_rd_ptr_reg) >= 2**(OUTPUT_FIFO_AW-1);

        if (!out_fifo_full && ram_wr_cmd_valid_int[n]) begin
            out_fifo_wr_cmd_be[out_fifo_wr_ptr_reg[OUTPUT_FIFO_AW-1:0]] <= ram_wr_cmd_be_int[n];
            out_fifo_wr_cmd_addr[out_fifo_wr_ptr_reg[OUTPUT_FIFO_AW-1:0]] <= ram_wr_cmd_addr_int[n];
            out_fifo_wr_cmd_data[out_fifo_wr_ptr_reg[OUTPUT_FIFO_AW-1:0]] <= ram_wr_cmd_data_int[n];
            out_fifo_wr_ptr_reg <= out_fifo_wr_ptr_reg + 1;
        end

        if (!out_fifo_empty && (!ram_wr_cmd_valid_reg || dma_ram_wr.wr_cmd_ready[n])) begin
            ram_wr_cmd_be_reg <= out_fifo_wr_cmd_be[out_fifo_rd_ptr_reg[OUTPUT_FIFO_AW-1:0]];
            ram_wr_cmd_addr_reg <= out_fifo_wr_cmd_addr[out_fifo_rd_ptr_reg[OUTPUT_FIFO_AW-1:0]];
            ram_wr_cmd_data_reg <= out_fifo_wr_cmd_data[out_fifo_rd_ptr_reg[OUTPUT_FIFO_AW-1:0]];
            ram_wr_cmd_valid_reg <= 1'b1;
            out_fifo_rd_ptr_reg <= out_fifo_rd_ptr_reg + 1;
        end

        if (done_count_reg < 2**OUTPUT_FIFO_AW && dma_ram_wr.wr_done[n] && !out_done_ack[n]) begin
            done_count_reg <= done_count_reg + 1;
            done_reg <= 1;
        end else if (done_count_reg > 0 && !dma_ram_wr.wr_done[n] && out_done_ack[n]) begin
            done_count_reg <= done_count_reg - 1;
            done_reg <= done_count_reg > 1;
        end

        if (rst) begin
            out_fifo_wr_ptr_reg <= '0;
            out_fifo_rd_ptr_reg <= '0;
            ram_wr_cmd_valid_reg <= 1'b0;
            done_count_reg <= 0;
            done_reg <= 1'b0;
        end
    end

end

endmodule

`resetall
