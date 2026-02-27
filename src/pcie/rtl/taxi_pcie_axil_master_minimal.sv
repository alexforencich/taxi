// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2021-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * PCIe AXI Lite Master (minimal version, supports only aligned, 1 DW operations)
 */
module taxi_pcie_axil_master_minimal #
(
    // Force 64 bit address
    parameter logic TLP_FORCE_64_BIT_ADDR = 1'b0
)
(
    input  wire logic        clk,
    input  wire logic        rst,

    /*
     * TLP input (request)
     */
    taxi_pcie_tlp_if.snk     rx_req_tlp,

    /*
     * TLP output (completion)
     */
    taxi_pcie_tlp_if.src     tx_cpl_tlp,

    /*
     * AXI Lite Master output
     */
    taxi_axil_if.wr_mst      m_axil_wr,
    taxi_axil_if.rd_mst      m_axil_rd,

    /*
     * Configuration
     */
    input  wire logic [7:0]  bus_num,

    /*
     * Status
     */
    output wire logic        stat_err_cor,
    output wire logic        stat_err_uncor
);

// extract parameters
localparam TLP_SEGS = rx_req_tlp.SEGS;
localparam TLP_SEG_DATA_W = rx_req_tlp.SEG_DATA_W;
localparam TLP_SEG_EMPTY_W = rx_req_tlp.SEG_EMPTY_W;
localparam TLP_DATA_W = TLP_SEGS*TLP_SEG_DATA_W;
localparam TLP_HDR_W = rx_req_tlp.HDR_W;
localparam FUNC_NUM_W = rx_req_tlp.FUNC_NUM_W;

localparam AXIL_DATA_W = m_axil_wr.DATA_W;
localparam AXIL_ADDR_W = m_axil_wr.ADDR_W;
localparam AXIL_STRB_W = m_axil_wr.STRB_W;

localparam TLP_DATA_W_B = TLP_DATA_W/8;
localparam TLP_DATA_W_DW = TLP_DATA_W/32;

localparam TAG_W = 10;

localparam RESP_FIFO_ADDR_W = 5;

// check configuration
if (TLP_SEGS != 1)
    $fatal(0, "Error: TLP segment count must be 1 (instance %m)");

if (TLP_HDR_W != 128)
    $fatal(0, "Error: TLP segment header width must be 128 (instance %m)");

if ((2**TLP_SEG_EMPTY_W)*32*TLP_SEGS != TLP_DATA_W)
    $fatal(0, "Error: PCIe interface requires dword (32-bit) granularity (instance %m)");

if (AXIL_DATA_W != 32)
    $fatal(0, "Error: AXI lite interface width must be 32 (instance %m)");

if (AXIL_STRB_W * 8 != AXIL_DATA_W)
    $fatal(0, "Error: AXI lite interface requires byte (8-bit) granularity (instance %m)");

typedef enum logic [2:0] {
    TLP_FMT_3DW = 3'b000,
    TLP_FMT_4DW = 3'b001,
    TLP_FMT_3DW_DATA = 3'b010,
    TLP_FMT_4DW_DATA = 3'b011,
    TLP_FMT_PREFIX = 3'b100
} tlp_fmt_t;

typedef enum logic [2:0] {
    CPL_STATUS_SC  = 3'b000, // successful completion
    CPL_STATUS_UR  = 3'b001, // unsupported request
    CPL_STATUS_CRS = 3'b010, // configuration request retry status
    CPL_STATUS_CA  = 3'b100  // completer abort
} cpl_status_t;

typedef enum logic [0:0] {
    REQ_STATE_IDLE,
    REQ_STATE_WAIT_END
} req_state_t;

req_state_t req_state_reg = REQ_STATE_IDLE, req_state_next;

typedef enum logic [1:0] {
    RESP_STATE_IDLE,
    RESP_STATE_READ,
    RESP_STATE_WRITE,
    RESP_STATE_CPL
} resp_state_t;

resp_state_t resp_state_reg = RESP_STATE_IDLE, resp_state_next;

logic [2:0] rx_req_tlp_hdr_fmt;
logic [4:0] rx_req_tlp_hdr_type;
logic [2:0] rx_req_tlp_hdr_tc;
logic rx_req_tlp_hdr_ln;
logic rx_req_tlp_hdr_th;
logic rx_req_tlp_hdr_td;
logic rx_req_tlp_hdr_ep;
logic [2:0] rx_req_tlp_hdr_attr;
logic [1:0] rx_req_tlp_hdr_at;
logic [10:0] rx_req_tlp_hdr_length;
logic [15:0] rx_req_tlp_hdr_requester_id;
logic [TAG_W-1:0] rx_req_tlp_hdr_tag;
logic [3:0] rx_req_tlp_hdr_last_be;
logic [3:0] rx_req_tlp_hdr_first_be;
logic [63:0] rx_req_tlp_hdr_addr;
logic [1:0] rx_req_tlp_hdr_ph;

logic [127:0] cpl_tlp_hdr;

logic [RESP_FIFO_ADDR_W+1-1:0] resp_fifo_wr_ptr_reg = 0;
logic [RESP_FIFO_ADDR_W+1-1:0] resp_fifo_rd_ptr_reg = 0, resp_fifo_rd_ptr_next;

(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
logic resp_fifo_op_read[2**RESP_FIFO_ADDR_W];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
logic resp_fifo_op_write[2**RESP_FIFO_ADDR_W];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
logic [2:0] resp_fifo_cpl_status[2**RESP_FIFO_ADDR_W];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
logic [2:0] resp_fifo_byte_count[2**RESP_FIFO_ADDR_W];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
logic [6:0] resp_fifo_lower_addr[2**RESP_FIFO_ADDR_W];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
logic [15:0] resp_fifo_requester_id[2**RESP_FIFO_ADDR_W];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
logic [FUNC_NUM_W-1:0] resp_fifo_func_num[2**RESP_FIFO_ADDR_W];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
logic [TAG_W-1:0] resp_fifo_tag[2**RESP_FIFO_ADDR_W];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
logic [2:0] resp_fifo_tc[2**RESP_FIFO_ADDR_W];
(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
logic [2:0] resp_fifo_attr[2**RESP_FIFO_ADDR_W];

logic resp_fifo_wr_op_read;
logic resp_fifo_wr_op_write;
logic [2:0] resp_fifo_wr_cpl_status;
logic [2:0] resp_fifo_wr_byte_count;
logic [6:0] resp_fifo_wr_lower_addr;
logic [15:0] resp_fifo_wr_requester_id;
logic [FUNC_NUM_W-1:0] resp_fifo_wr_func_num;
logic [TAG_W-1:0] resp_fifo_wr_tag;
logic [2:0] resp_fifo_wr_tc;
logic [2:0] resp_fifo_wr_attr;
logic resp_fifo_we;
logic resp_fifo_half_full_reg = 1'b0;

logic resp_fifo_rd_op_read_reg = 1'b0, resp_fifo_rd_op_read_next;
logic resp_fifo_rd_op_write_reg = 1'b0, resp_fifo_rd_op_write_next;
logic [2:0] resp_fifo_rd_cpl_status_reg = CPL_STATUS_SC, resp_fifo_rd_cpl_status_next;
logic [2:0] resp_fifo_rd_byte_count_reg = '0, resp_fifo_rd_byte_count_next;
logic [6:0] resp_fifo_rd_lower_addr_reg = '0, resp_fifo_rd_lower_addr_next;
logic [15:0] resp_fifo_rd_requester_id_reg = '0, resp_fifo_rd_requester_id_next;
logic [FUNC_NUM_W-1:0] resp_fifo_rd_func_num_reg = '0, resp_fifo_rd_func_num_next;
logic [TAG_W-1:0] resp_fifo_rd_tag_reg = '0, resp_fifo_rd_tag_next;
logic [2:0] resp_fifo_rd_tc_reg = '0, resp_fifo_rd_tc_next;
logic [2:0] resp_fifo_rd_attr_reg = '0, resp_fifo_rd_attr_next;
logic resp_fifo_rd_valid_reg = 1'b0, resp_fifo_rd_valid_next;

logic rx_req_tlp_ready_reg = 1'b0, rx_req_tlp_ready_next;

logic [TLP_DATA_W-1:0] tx_cpl_tlp_data_reg = '0, tx_cpl_tlp_data_next;
logic [TLP_SEGS-1:0][TLP_SEG_EMPTY_W-1:0] tx_cpl_tlp_empty_reg = '0, tx_cpl_tlp_empty_next;
logic [TLP_SEGS-1:0][TLP_HDR_W-1:0] tx_cpl_tlp_hdr_reg = '0, tx_cpl_tlp_hdr_next;
logic [TLP_SEGS-1:0] tx_cpl_tlp_valid_reg = 0, tx_cpl_tlp_valid_next;

logic [AXIL_ADDR_W-1:0] m_axil_addr_reg = '0, m_axil_addr_next;
logic m_axil_awvalid_reg = 1'b0, m_axil_awvalid_next;
logic [AXIL_DATA_W-1:0] m_axil_wdata_reg = '0, m_axil_wdata_next;
logic [AXIL_STRB_W-1:0] m_axil_wstrb_reg = '0, m_axil_wstrb_next;
logic m_axil_wvalid_reg = 1'b0, m_axil_wvalid_next;
logic m_axil_bready_reg = 1'b0, m_axil_bready_next;
logic m_axil_arvalid_reg = 1'b0, m_axil_arvalid_next;
logic m_axil_rready_reg = 1'b0, m_axil_rready_next;

logic stat_err_cor_reg = 1'b0, stat_err_cor_next;
logic stat_err_uncor_reg = 1'b0, stat_err_uncor_next;

assign rx_req_tlp.ready = rx_req_tlp_ready_reg;

assign tx_cpl_tlp.data = tx_cpl_tlp_data_reg;
assign tx_cpl_tlp.empty = tx_cpl_tlp_empty_reg;
assign tx_cpl_tlp.hdr = tx_cpl_tlp_hdr_reg;
assign tx_cpl_tlp.seq = '0;
assign tx_cpl_tlp.bar_id = '0;
assign tx_cpl_tlp.func_num = '0;
assign tx_cpl_tlp.error = '0;
assign tx_cpl_tlp.valid = tx_cpl_tlp_valid_reg;
assign tx_cpl_tlp.sop = 1'b1;
assign tx_cpl_tlp.eop = 1'b1;

assign m_axil_wr.awaddr = m_axil_addr_reg;
assign m_axil_wr.awprot = 3'b010;
assign m_axil_wr.awuser = '0;
assign m_axil_wr.awvalid = m_axil_awvalid_reg;
assign m_axil_wr.wdata = m_axil_wdata_reg;
assign m_axil_wr.wstrb = m_axil_wstrb_reg;
assign m_axil_wr.wuser = '0;
assign m_axil_wr.wvalid = m_axil_wvalid_reg;
assign m_axil_wr.bready = m_axil_bready_reg;
assign m_axil_rd.araddr = m_axil_addr_reg;
assign m_axil_rd.arprot = 3'b010;
assign m_axil_rd.aruser = '0;
assign m_axil_rd.arvalid = m_axil_arvalid_reg;
assign m_axil_rd.rready = m_axil_rready_reg;

assign stat_err_cor = stat_err_cor_reg;
assign stat_err_uncor = stat_err_uncor_reg;

always_comb begin
    req_state_next = REQ_STATE_IDLE;

    rx_req_tlp_ready_next = 1'b0;

    m_axil_addr_next = m_axil_addr_reg;
    m_axil_awvalid_next = m_axil_awvalid_reg && !m_axil_wr.awready;
    m_axil_wdata_next = m_axil_wdata_reg;
    m_axil_wstrb_next = m_axil_wstrb_reg;
    m_axil_wvalid_next = m_axil_wvalid_reg && !m_axil_wr.wready;
    m_axil_arvalid_next = m_axil_arvalid_reg && !m_axil_rd.arready;

    stat_err_cor_next = 1'b0;
    stat_err_uncor_next = 1'b0;

    // TLP header parsing
    // DW 0
    rx_req_tlp_hdr_fmt = rx_req_tlp.hdr[0][127:125]; // fmt
    rx_req_tlp_hdr_type = rx_req_tlp.hdr[0][124:120]; // type
    rx_req_tlp_hdr_tag[9] = rx_req_tlp.hdr[0][119]; // T9
    rx_req_tlp_hdr_tc = rx_req_tlp.hdr[0][118:116]; // TC
    rx_req_tlp_hdr_tag[8] = rx_req_tlp.hdr[0][115]; // T8
    rx_req_tlp_hdr_attr[2] = rx_req_tlp.hdr[0][114]; // attr
    rx_req_tlp_hdr_ln = rx_req_tlp.hdr[0][113]; // LN
    rx_req_tlp_hdr_th = rx_req_tlp.hdr[0][112]; // TH
    rx_req_tlp_hdr_td = rx_req_tlp.hdr[0][111]; // TD
    rx_req_tlp_hdr_ep = rx_req_tlp.hdr[0][110]; // EP
    rx_req_tlp_hdr_attr[1:0] = rx_req_tlp.hdr[0][109:108]; // attr
    rx_req_tlp_hdr_at = rx_req_tlp.hdr[0][107:106]; // AT
    rx_req_tlp_hdr_length = {rx_req_tlp.hdr[0][105:96] == 0, rx_req_tlp.hdr[0][105:96]}; // length
    // DW 1
    rx_req_tlp_hdr_requester_id = rx_req_tlp.hdr[0][95:80]; // requester ID
    rx_req_tlp_hdr_tag[7:0] = rx_req_tlp.hdr[0][79:72]; // tag
    rx_req_tlp_hdr_last_be = rx_req_tlp.hdr[0][71:68]; // last BE
    rx_req_tlp_hdr_first_be = rx_req_tlp.hdr[0][67:64]; // first BE
    if (rx_req_tlp_hdr_fmt[0] || TLP_FORCE_64_BIT_ADDR) begin
        // 4 DW (64-bit address)
        // DW 2+3
        rx_req_tlp_hdr_addr = {rx_req_tlp.hdr[0][63:2], 2'b00}; // addr
        rx_req_tlp_hdr_ph = rx_req_tlp.hdr[0][1:0]; // PH
    end else begin
        // 3 DW (32-bit address)
        // DW 2
        rx_req_tlp_hdr_addr = {32'd0, rx_req_tlp.hdr[0][63:34], 2'b00}; // addr
        rx_req_tlp_hdr_ph = rx_req_tlp.hdr[0][33:32]; // PH
    end

    resp_fifo_wr_op_read = 1'b0;
    resp_fifo_wr_op_write = 1'b0;
    resp_fifo_wr_cpl_status = CPL_STATUS_SC;
    resp_fifo_wr_byte_count = '0;
    resp_fifo_wr_lower_addr = '0;
    resp_fifo_wr_requester_id = rx_req_tlp_hdr_requester_id;
    resp_fifo_wr_func_num = rx_req_tlp.func_num[0];
    resp_fifo_wr_tag = rx_req_tlp_hdr_tag;
    resp_fifo_wr_tc = rx_req_tlp_hdr_tc;
    resp_fifo_wr_attr = rx_req_tlp_hdr_attr;
    resp_fifo_we = 1'b0;

    case (req_state_reg)
        REQ_STATE_IDLE: begin
            // idle state; wait for request

            rx_req_tlp_ready_next = (!m_axil_awvalid_reg || m_axil_wr.awready)
                && (!m_axil_arvalid_reg || m_axil_rd.arready)
                && (!m_axil_wvalid_reg || m_axil_wr.wready)
                && !resp_fifo_half_full_reg;

            if (rx_req_tlp.ready && rx_req_tlp.valid[0] && rx_req_tlp.sop[0]) begin
                m_axil_addr_next = rx_req_tlp_hdr_addr;
                m_axil_wdata_next = rx_req_tlp.data[0][31:0];
                m_axil_wstrb_next = rx_req_tlp_hdr_first_be;

                if (!rx_req_tlp_hdr_fmt[1] && rx_req_tlp_hdr_type == 5'b00000) begin
                    // read request
                    if (rx_req_tlp_hdr_length == 11'd1) begin
                        // length OK

                        // perform read
                        m_axil_arvalid_next = 1'b1;

                        // finish read and return completion
                        resp_fifo_wr_op_read = 1'b1;
                        resp_fifo_wr_op_write = 1'b0;
                        resp_fifo_wr_cpl_status = CPL_STATUS_SC;

                        casez (rx_req_tlp_hdr_first_be)
                            4'b0000: resp_fifo_wr_byte_count = 3'd1;
                            4'b0001: resp_fifo_wr_byte_count = 3'd1;
                            4'b0010: resp_fifo_wr_byte_count = 3'd1;
                            4'b0100: resp_fifo_wr_byte_count = 3'd1;
                            4'b1000: resp_fifo_wr_byte_count = 3'd1;
                            4'b0011: resp_fifo_wr_byte_count = 3'd2;
                            4'b0110: resp_fifo_wr_byte_count = 3'd2;
                            4'b1100: resp_fifo_wr_byte_count = 3'd2;
                            4'b01z1: resp_fifo_wr_byte_count = 3'd3;
                            4'b1z10: resp_fifo_wr_byte_count = 3'd3;
                            4'b1zz1: resp_fifo_wr_byte_count = 3'd4;
                        endcase

                        casez (rx_req_tlp_hdr_first_be)
                            4'b0000: resp_fifo_wr_lower_addr = {rx_req_tlp_hdr_addr[6:2], 2'b00};
                            4'bzzz1: resp_fifo_wr_lower_addr = {rx_req_tlp_hdr_addr[6:2], 2'b00};
                            4'bzz10: resp_fifo_wr_lower_addr = {rx_req_tlp_hdr_addr[6:2], 2'b01};
                            4'bz100: resp_fifo_wr_lower_addr = {rx_req_tlp_hdr_addr[6:2], 2'b10};
                            4'b1000: resp_fifo_wr_lower_addr = {rx_req_tlp_hdr_addr[6:2], 2'b11};
                        endcase

                        rx_req_tlp_ready_next = 1'b0;
                    end else begin
                        // bad length
                        // report correctable error
                        stat_err_cor_next = 1'b1;

                        // return CA completion
                        resp_fifo_wr_op_read = 1'b0;
                        resp_fifo_wr_op_write = 1'b0;
                        resp_fifo_wr_cpl_status = CPL_STATUS_CA;
                        resp_fifo_wr_byte_count = '0;
                        resp_fifo_wr_lower_addr = '0;
                    end

                    resp_fifo_wr_requester_id = rx_req_tlp_hdr_requester_id;
                    resp_fifo_wr_func_num = rx_req_tlp.func_num[0];
                    resp_fifo_wr_tag = rx_req_tlp_hdr_tag;
                    resp_fifo_wr_tc = rx_req_tlp_hdr_tc;
                    resp_fifo_wr_attr = rx_req_tlp_hdr_attr;
                    resp_fifo_we = 1'b1;

                    if (rx_req_tlp.eop[0]) begin
                        req_state_next = REQ_STATE_IDLE;
                    end else begin
                        rx_req_tlp_ready_next = 1'b1;
                        req_state_next = REQ_STATE_WAIT_END;
                    end
                end else if (rx_req_tlp_hdr_fmt[1] && rx_req_tlp_hdr_type == 5'b00000) begin
                    // write request
                    if (rx_req_tlp_hdr_length == 11'd1) begin
                        // length OK

                        // perform write
                        m_axil_awvalid_next = 1'b1;
                        m_axil_wvalid_next = 1'b1;

                        // entry in FIFO for proper response ordering
                        resp_fifo_wr_op_read = 1'b0;
                        resp_fifo_wr_op_write = 1'b1;
                        resp_fifo_we = 1'b1;

                        rx_req_tlp_ready_next = 1'b0;
                    end else begin
                        // bad length
                        // report uncorrectable error
                        stat_err_uncor_next = 1'b1;
                    end

                    if (rx_req_tlp.eop) begin
                        req_state_next = REQ_STATE_IDLE;
                    end else begin
                        rx_req_tlp_ready_next = 1'b1;
                        req_state_next = REQ_STATE_WAIT_END;
                    end
                end else begin
                    // other request
                    if (rx_req_tlp_hdr_fmt[0] && ((rx_req_tlp_hdr_type & 5'b11000) == 5'b10000)) begin
                        // message - posted, no completion
                        // report uncorrectable error
                        stat_err_uncor_next = 1'b1;
                    end else if (!rx_req_tlp_hdr_fmt[0] && (rx_req_tlp_hdr_type == 5'b01010 || rx_req_tlp_hdr_type == 5'b01011)) begin
                        // completion TLP
                        // unexpected completion, advisory non-fatal error
                        // report correctable error
                        stat_err_cor_next = 1'b1;
                    end else begin
                        // other non-posted request, send UR completion
                        // report correctable error
                        stat_err_cor_next = 1'b1;

                        // UR completion
                        resp_fifo_wr_op_read = 1'b0;
                        resp_fifo_wr_op_write = 1'b0;
                        resp_fifo_wr_cpl_status = CPL_STATUS_UR;
                        resp_fifo_wr_byte_count = '0;
                        resp_fifo_wr_lower_addr = '0;
                        resp_fifo_wr_requester_id = rx_req_tlp_hdr_requester_id;
                        resp_fifo_wr_func_num = rx_req_tlp.func_num[0];
                        resp_fifo_wr_tag = rx_req_tlp_hdr_tag;
                        resp_fifo_wr_tc = rx_req_tlp_hdr_tc;
                        resp_fifo_wr_attr = rx_req_tlp_hdr_attr;
                        resp_fifo_we = 1'b1;
                    end

                    if (rx_req_tlp.eop) begin
                        req_state_next = REQ_STATE_IDLE;
                    end else begin
                        rx_req_tlp_ready_next = 1'b1;
                        req_state_next = REQ_STATE_WAIT_END;
                    end
                end
            end else begin
                req_state_next = REQ_STATE_IDLE;
            end
        end
        REQ_STATE_WAIT_END: begin
            // wait end state, wait for end of TLP
            rx_req_tlp_ready_next = 1'b1;

            if (rx_req_tlp.ready && rx_req_tlp.valid[0]) begin
                if (rx_req_tlp.eop) begin

                    rx_req_tlp_ready_next = (!m_axil_awvalid_reg || m_axil_wr.awready)
                        && (!m_axil_arvalid_reg || m_axil_rd.arready)
                        && (!m_axil_wvalid_reg || m_axil_wr.wready)
                        && !resp_fifo_half_full_reg;

                    req_state_next = REQ_STATE_IDLE;
                end else begin
                    req_state_next = REQ_STATE_WAIT_END;
                end
            end else begin
                req_state_next = REQ_STATE_WAIT_END;
            end
        end
    endcase
end

always_comb begin
    resp_state_next = RESP_STATE_IDLE;

    resp_fifo_rd_ptr_next = resp_fifo_rd_ptr_reg;

    resp_fifo_rd_op_read_next = resp_fifo_rd_op_read_reg;
    resp_fifo_rd_op_write_next = resp_fifo_rd_op_write_reg;
    resp_fifo_rd_cpl_status_next = resp_fifo_rd_cpl_status_reg;
    resp_fifo_rd_byte_count_next = resp_fifo_rd_byte_count_reg;
    resp_fifo_rd_lower_addr_next = resp_fifo_rd_lower_addr_reg;
    resp_fifo_rd_requester_id_next = resp_fifo_rd_requester_id_reg;
    resp_fifo_rd_func_num_next = resp_fifo_rd_func_num_reg;
    resp_fifo_rd_tag_next = resp_fifo_rd_tag_reg;
    resp_fifo_rd_tc_next = resp_fifo_rd_tc_reg;
    resp_fifo_rd_attr_next = resp_fifo_rd_attr_reg;
    resp_fifo_rd_valid_next = resp_fifo_rd_valid_reg;

    tx_cpl_tlp_data_next = tx_cpl_tlp_data_reg;
    tx_cpl_tlp_empty_next = tx_cpl_tlp_empty_reg;
    tx_cpl_tlp_hdr_next = tx_cpl_tlp_hdr_reg;
    tx_cpl_tlp_valid_next = tx_cpl_tlp_valid_reg && !tx_cpl_tlp.ready;

    m_axil_bready_next = 1'b0;
    m_axil_rready_next = 1'b0;

    // TLP header
    // DW 0
    cpl_tlp_hdr[127:125] = resp_fifo_rd_op_read_reg ? TLP_FMT_3DW_DATA : TLP_FMT_3DW; // fmt
    cpl_tlp_hdr[124:120] = 5'b01010; // type
    cpl_tlp_hdr[119] = resp_fifo_rd_tag_reg[9]; // T9
    cpl_tlp_hdr[118:116] = resp_fifo_rd_tc_reg; // TC
    cpl_tlp_hdr[115] = resp_fifo_rd_tag_reg[8]; // T8
    cpl_tlp_hdr[114] = resp_fifo_rd_attr_reg[2]; // attr
    cpl_tlp_hdr[113] = 1'b0; // LN
    cpl_tlp_hdr[112] = 1'b0; // TH
    cpl_tlp_hdr[111] = 1'b0; // TD
    cpl_tlp_hdr[110] = 1'b0; // EP
    cpl_tlp_hdr[109:108] = resp_fifo_rd_attr_reg[1:0]; // attr
    cpl_tlp_hdr[107:106] = 2'b00; // AT
    cpl_tlp_hdr[105:96] = resp_fifo_rd_op_read_reg ? 1 : 0; // length
    // DW 1
    cpl_tlp_hdr[95:88] = bus_num; // completer ID (bus number)
    cpl_tlp_hdr[87:80] = 8'(resp_fifo_rd_func_num_reg); // completer ID (function number)
    cpl_tlp_hdr[79:77] = resp_fifo_rd_cpl_status_reg; // completion status
    cpl_tlp_hdr[76] = 1'b0; // BCM
    cpl_tlp_hdr[75:64] = 12'(resp_fifo_rd_byte_count_reg); // byte count
    // DW 2
    cpl_tlp_hdr[63:48] = resp_fifo_rd_requester_id_reg; // requester ID
    cpl_tlp_hdr[47:40] = resp_fifo_rd_tag_reg[7:0]; // tag
    cpl_tlp_hdr[39] = 1'b0;
    cpl_tlp_hdr[38:32] = resp_fifo_rd_lower_addr_reg; // lower address
    cpl_tlp_hdr[31:0] = '0;

    case (resp_state_reg)
        RESP_STATE_IDLE: begin
            // idle state - wait for operation

            if (resp_fifo_rd_valid_reg) begin
                if (resp_fifo_rd_op_read_reg) begin
                    m_axil_rready_next = !tx_cpl_tlp_valid_reg || tx_cpl_tlp.ready;
                    resp_state_next = RESP_STATE_READ;
                end else if (resp_fifo_rd_op_write_reg) begin
                    m_axil_bready_next = 1'b1;
                    resp_state_next = RESP_STATE_WRITE;
                end else begin
                    resp_state_next = RESP_STATE_CPL;
                end
            end else begin
                resp_state_next = RESP_STATE_IDLE;
            end
        end
        RESP_STATE_READ: begin
            // read state - wait for read data and generate completion
            m_axil_rready_next = !tx_cpl_tlp_valid_reg || tx_cpl_tlp.ready;

            if (m_axil_rd.rready && m_axil_rd.rvalid) begin
                m_axil_rready_next = 1'b0;
                tx_cpl_tlp_hdr_next = cpl_tlp_hdr;
                tx_cpl_tlp_data_next =  TLP_DATA_W'(m_axil_rd.rdata);
                tx_cpl_tlp_empty_next = '0;
                tx_cpl_tlp_empty_next[0] = TLP_SEG_EMPTY_W'(TLP_DATA_W_DW-1);
                tx_cpl_tlp_valid_next = 1'b1;

                resp_fifo_rd_valid_next = 1'b0;
                resp_state_next = RESP_STATE_IDLE;
            end else begin
                resp_state_next = RESP_STATE_READ;
            end
        end
        RESP_STATE_WRITE: begin
            // write state - wait for write response
            m_axil_bready_next = 1'b1;

            if (m_axil_wr.bready && m_axil_wr.bvalid) begin
                m_axil_bready_next = 1'b0;

                resp_fifo_rd_valid_next = 1'b0;
                resp_state_next = RESP_STATE_IDLE;
            end else begin
                resp_state_next = RESP_STATE_WRITE;
            end
        end
        RESP_STATE_CPL: begin
            // completion state - generate completion

            if (!tx_cpl_tlp_valid_reg || tx_cpl_tlp.ready) begin
                tx_cpl_tlp_hdr_next = cpl_tlp_hdr;
                tx_cpl_tlp_data_next = '0;
                tx_cpl_tlp_empty_next = '0;
                tx_cpl_tlp_empty_next[0] = TLP_SEG_EMPTY_W'(TLP_DATA_W_DW-1);
                tx_cpl_tlp_valid_next = 1'b1;

                resp_fifo_rd_valid_next = 1'b0;
                resp_state_next = RESP_STATE_IDLE;
            end else begin
                resp_state_next = RESP_STATE_CPL;
            end
        end
    endcase

    if (!resp_fifo_rd_valid_next) begin
        resp_fifo_rd_op_read_next = resp_fifo_op_read[resp_fifo_rd_ptr_reg[RESP_FIFO_ADDR_W-1:0]];
        resp_fifo_rd_op_write_next = resp_fifo_op_write[resp_fifo_rd_ptr_reg[RESP_FIFO_ADDR_W-1:0]];
        resp_fifo_rd_cpl_status_next = resp_fifo_cpl_status[resp_fifo_rd_ptr_reg[RESP_FIFO_ADDR_W-1:0]];
        resp_fifo_rd_byte_count_next = resp_fifo_byte_count[resp_fifo_rd_ptr_reg[RESP_FIFO_ADDR_W-1:0]];
        resp_fifo_rd_lower_addr_next = resp_fifo_lower_addr[resp_fifo_rd_ptr_reg[RESP_FIFO_ADDR_W-1:0]];
        resp_fifo_rd_requester_id_next = resp_fifo_requester_id[resp_fifo_rd_ptr_reg[RESP_FIFO_ADDR_W-1:0]];
        resp_fifo_rd_func_num_next = resp_fifo_func_num[resp_fifo_rd_ptr_reg[RESP_FIFO_ADDR_W-1:0]];
        resp_fifo_rd_tag_next = resp_fifo_tag[resp_fifo_rd_ptr_reg[RESP_FIFO_ADDR_W-1:0]];
        resp_fifo_rd_tc_next = resp_fifo_tc[resp_fifo_rd_ptr_reg[RESP_FIFO_ADDR_W-1:0]];
        resp_fifo_rd_attr_next = resp_fifo_attr[resp_fifo_rd_ptr_reg[RESP_FIFO_ADDR_W-1:0]];
        if (resp_fifo_rd_ptr_reg != resp_fifo_wr_ptr_reg) begin
            resp_fifo_rd_ptr_next = resp_fifo_rd_ptr_reg + 1;
            resp_fifo_rd_valid_next = 1'b1;
        end
    end
end

always_ff @(posedge clk) begin
    req_state_reg <= req_state_next;
    resp_state_reg <= resp_state_next;

    rx_req_tlp_ready_reg <= rx_req_tlp_ready_next;

    tx_cpl_tlp_data_reg <= tx_cpl_tlp_data_next;
    tx_cpl_tlp_empty_reg <= tx_cpl_tlp_empty_next;
    tx_cpl_tlp_hdr_reg <= tx_cpl_tlp_hdr_next;
    tx_cpl_tlp_valid_reg <= tx_cpl_tlp_valid_next;

    m_axil_addr_reg <= m_axil_addr_next;
    m_axil_awvalid_reg <= m_axil_awvalid_next;
    m_axil_wdata_reg <= m_axil_wdata_next;
    m_axil_wstrb_reg <= m_axil_wstrb_next;
    m_axil_wvalid_reg <= m_axil_wvalid_next;
    m_axil_bready_reg <= m_axil_bready_next;
    m_axil_arvalid_reg <= m_axil_arvalid_next;
    m_axil_rready_reg <= m_axil_rready_next;

    stat_err_cor_reg <= stat_err_cor_next;
    stat_err_uncor_reg <= stat_err_uncor_next;

    if (resp_fifo_we) begin
        resp_fifo_op_read[resp_fifo_wr_ptr_reg[RESP_FIFO_ADDR_W-1:0]] <= resp_fifo_wr_op_read;
        resp_fifo_op_write[resp_fifo_wr_ptr_reg[RESP_FIFO_ADDR_W-1:0]] <= resp_fifo_wr_op_write;
        resp_fifo_cpl_status[resp_fifo_wr_ptr_reg[RESP_FIFO_ADDR_W-1:0]] <= resp_fifo_wr_cpl_status;
        resp_fifo_byte_count[resp_fifo_wr_ptr_reg[RESP_FIFO_ADDR_W-1:0]] <= resp_fifo_wr_byte_count;
        resp_fifo_lower_addr[resp_fifo_wr_ptr_reg[RESP_FIFO_ADDR_W-1:0]] <= resp_fifo_wr_lower_addr;
        resp_fifo_requester_id[resp_fifo_wr_ptr_reg[RESP_FIFO_ADDR_W-1:0]] <= resp_fifo_wr_requester_id;
        resp_fifo_func_num[resp_fifo_wr_ptr_reg[RESP_FIFO_ADDR_W-1:0]] <= resp_fifo_wr_func_num;
        resp_fifo_tag[resp_fifo_wr_ptr_reg[RESP_FIFO_ADDR_W-1:0]] <= resp_fifo_wr_tag;
        resp_fifo_tc[resp_fifo_wr_ptr_reg[RESP_FIFO_ADDR_W-1:0]] <= resp_fifo_wr_tc;
        resp_fifo_attr[resp_fifo_wr_ptr_reg[RESP_FIFO_ADDR_W-1:0]] <= resp_fifo_wr_attr;
        resp_fifo_wr_ptr_reg <= resp_fifo_wr_ptr_reg + 1;
    end
    resp_fifo_rd_ptr_reg <= resp_fifo_rd_ptr_next;

    resp_fifo_rd_op_read_reg <= resp_fifo_rd_op_read_next;
    resp_fifo_rd_op_write_reg <= resp_fifo_rd_op_write_next;
    resp_fifo_rd_cpl_status_reg <= resp_fifo_rd_cpl_status_next;
    resp_fifo_rd_byte_count_reg <= resp_fifo_rd_byte_count_next;
    resp_fifo_rd_lower_addr_reg <= resp_fifo_rd_lower_addr_next;
    resp_fifo_rd_requester_id_reg <= resp_fifo_rd_requester_id_next;
    resp_fifo_rd_func_num_reg <= resp_fifo_rd_func_num_next;
    resp_fifo_rd_tag_reg <= resp_fifo_rd_tag_next;
    resp_fifo_rd_tc_reg <= resp_fifo_rd_tc_next;
    resp_fifo_rd_attr_reg <= resp_fifo_rd_attr_next;
    resp_fifo_rd_valid_reg <= resp_fifo_rd_valid_next;

    resp_fifo_half_full_reg <= $unsigned(resp_fifo_wr_ptr_reg - resp_fifo_rd_ptr_reg) >= 2**(RESP_FIFO_ADDR_W-1);

    if (rst) begin
        req_state_reg <= REQ_STATE_IDLE;
        resp_state_reg <= RESP_STATE_IDLE;

        rx_req_tlp_ready_reg <= 1'b0;

        tx_cpl_tlp_valid_reg <= 1'b0;

        m_axil_awvalid_reg <= 1'b0;
        m_axil_wvalid_reg <= 1'b0;
        m_axil_bready_reg <= 1'b0;
        m_axil_arvalid_reg <= 1'b0;
        m_axil_rready_reg <= 1'b0;

        stat_err_cor_reg <= 1'b0;
        stat_err_uncor_reg <= 1'b0;

        resp_fifo_wr_ptr_reg <= 0;
        resp_fifo_rd_ptr_reg <= 0;
        resp_fifo_rd_valid_reg <= 1'b0;
    end
end

endmodule

`resetall
