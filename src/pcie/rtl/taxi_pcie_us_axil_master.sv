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
 * UltraScale PCIe AXI Lite Master
 */
module taxi_pcie_us_axil_master
(
    input  wire logic         clk,
    input  wire logic         rst,

    /*
     * UltraScale PCIe interface
     */
    taxi_axis_if.snk          s_axis_cq,
    taxi_axis_if.src          m_axis_cc,

    /*
     * AXI Lite Master output
     */
    taxi_axil_if.wr_mst       m_axil_wr,
    taxi_axil_if.rd_mst       m_axil_rd,

    /*
     * Configuration
     */
    input  wire logic [15:0]  completer_id,
    input  wire logic         completer_id_en,

    /*
     * Status
     */
    output wire logic         stat_err_cor,
    output wire logic         stat_err_uncor
);

// extract parameters
localparam AXIS_PCIE_DATA_W = s_axis_cq.DATA_W;
localparam AXIS_PCIE_KEEP_W = s_axis_cq.KEEP_W;
localparam AXIS_PCIE_CQ_USER_W = s_axis_cq.USER_W;
localparam AXIS_PCIE_CC_USER_W = m_axis_cc.USER_W;
localparam AXIL_DATA_W = m_axil_wr.DATA_W;
localparam AXIL_ADDR_W = m_axil_wr.ADDR_W;
localparam AXIL_STRB_W = m_axil_wr.STRB_W;

// check configuration
if (AXIS_PCIE_DATA_W != 64 && AXIS_PCIE_DATA_W != 128 && AXIS_PCIE_DATA_W != 256 && AXIS_PCIE_DATA_W != 512)
    $fatal(0, "Error: PCIe interface width must be 64, 128, 256, or 512 (instance %m)");

if (AXIS_PCIE_KEEP_W * 32 != AXIS_PCIE_DATA_W)
    $fatal(0, "Error: PCIe interface requires dword (32-bit) granularity (instance %m)");

if (AXIS_PCIE_DATA_W == 512) begin
    if (AXIS_PCIE_CQ_USER_W != 183)
        $fatal(0, "Error: PCIe CQ tuser width must be 183 (instance %m)");

    if (AXIS_PCIE_CC_USER_W != 81)
        $fatal(0, "Error: PCIe CC tuser width must be 81 (instance %m)");
end else begin
    if (AXIS_PCIE_CQ_USER_W != 85 && AXIS_PCIE_CQ_USER_W != 88)
        $fatal(0, "Error: PCIe CQ tuser width must be 85 or 88 (instance %m)");

    if (AXIS_PCIE_CC_USER_W != 33)
        $fatal(0, "Error: PCIe CC tuser width must be 33 (instance %m)");
end

if (AXIL_DATA_W != 32)
    $fatal(0, "Error: AXI interface width must be 32 (instance %m)");

if (AXIL_STRB_W * 8 != AXIL_DATA_W)
    $fatal(0, "Error: AXI interface requires byte (8-bit) granularity (instance %m)");

typedef enum logic [3:0] {
    REQ_MEM_READ = 4'b0000,
    REQ_MEM_WRITE = 4'b0001,
    REQ_IO_READ = 4'b0010,
    REQ_IO_WRITE = 4'b0011,
    REQ_MEM_FETCH_ADD = 4'b0100,
    REQ_MEM_SWAP = 4'b0101,
    REQ_MEM_CAS = 4'b0110,
    REQ_MEM_READ_LOCKED = 4'b0111,
    REQ_CFG_READ_0 = 4'b1000,
    REQ_CFG_READ_1 = 4'b1001,
    REQ_CFG_WRITE_0 = 4'b1010,
    REQ_CFG_WRITE_1 = 4'b1011,
    REQ_MSG = 4'b1100,
    REQ_MSG_VENDOR = 4'b1101,
    REQ_MSG_ATS = 4'b1110
} req_type_t;

typedef enum logic [2:0] {
    CPL_STATUS_SC  = 3'b000, // successful completion
    CPL_STATUS_UR  = 3'b001, // unsupported request
    CPL_STATUS_CRS = 3'b010, // configuration request retry status
    CPL_STATUS_CA  = 3'b100  // completer abort
} cpl_status_t;

typedef enum logic [2:0] {
    STATE_IDLE,
    STATE_HEADER,
    STATE_READ,
    STATE_WRITE_1,
    STATE_WRITE_2,
    STATE_WAIT_END,
    STATE_CPL_1,
    STATE_CPL_2
} state_t;

wire [63:0] req_tlp_hdr_addr;
wire [10:0] req_tlp_hdr_length;
wire [3:0] req_tlp_hdr_type;
wire [15:0] req_tlp_hdr_requester_id;
wire [7:0] req_tlp_hdr_tag;
wire [2:0] req_tlp_hdr_tc;
wire [2:0] req_tlp_hdr_attr;
wire [3:0] req_tlp_hdr_first_be;
wire [3:0] req_tlp_hdr_last_be;
wire [31:0] req_tlp_data;

if (AXIS_PCIE_DATA_W == 64) begin
    assign req_tlp_hdr_addr = {s_axis_cq.tdata[63:2], 2'b00};
    assign req_tlp_hdr_length = s_axis_cq.tdata[10:0];
    assign req_tlp_hdr_type = s_axis_cq.tdata[14:11];
    assign req_tlp_hdr_requester_id = s_axis_cq.tdata[31:16];
    assign req_tlp_hdr_tag = s_axis_cq.tdata[39:32];
    assign req_tlp_hdr_tc = s_axis_cq.tdata[59:57];
    assign req_tlp_hdr_attr = s_axis_cq.tdata[62:60];
end else begin
    assign req_tlp_hdr_addr = {s_axis_cq.tdata[63:2], 2'b00};
    assign req_tlp_hdr_length = s_axis_cq.tdata[74:64];
    assign req_tlp_hdr_type = s_axis_cq.tdata[78:75];
    assign req_tlp_hdr_requester_id = s_axis_cq.tdata[95:80];
    assign req_tlp_hdr_tag = s_axis_cq.tdata[103:96];
    assign req_tlp_hdr_tc = s_axis_cq.tdata[123:121];
    assign req_tlp_hdr_attr = s_axis_cq.tdata[126:124];
end

if (AXIS_PCIE_DATA_W == 512) begin
    assign req_tlp_hdr_first_be = s_axis_cq.tuser[3:0];
    assign req_tlp_hdr_last_be = s_axis_cq.tuser[11:8];
end else begin
    assign req_tlp_hdr_first_be = s_axis_cq.tuser[3:0];
    assign req_tlp_hdr_last_be = s_axis_cq.tuser[7:4];
end

if (AXIS_PCIE_DATA_W >= 256) begin
    assign req_tlp_data = s_axis_cq.tdata[159:128];
end else begin
    assign req_tlp_data = s_axis_cq.tdata[31:0];
end

logic [95:0] cpl_tlp_hdr;
logic [32:0] cpl_tuser_1;
logic [80:0] cpl_tuser_2;

state_t state_reg = STATE_IDLE, state_next;

logic [10:0] dword_count_reg = '0, dword_count_next;
logic [3:0] type_reg = '0, type_next;
logic [2:0] status_reg = '0, status_next;
logic [15:0] requester_id_reg = '0, requester_id_next;
logic [7:0] tag_reg = '0, tag_next;
logic [2:0] tc_reg = '0, tc_next;
logic [2:0] attr_reg = '0, attr_next;
logic [3:0] first_be_reg = '0, first_be_next;
logic [3:0] last_be_reg = '0, last_be_next;
logic cpl_data_reg = 1'b0, cpl_data_next;

logic s_axis_cq_tready_reg = 1'b0, s_axis_cq_tready_next;

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

// internal datapath
logic  [AXIS_PCIE_DATA_W-1:0]    m_axis_cc_tdata_int;
logic  [AXIS_PCIE_KEEP_W-1:0]    m_axis_cc_tkeep_int;
logic                            m_axis_cc_tvalid_int;
logic                            m_axis_cc_tready_int_reg = 1'b0;
logic                            m_axis_cc_tlast_int;
logic  [AXIS_PCIE_CC_USER_W-1:0] m_axis_cc_tuser_int;
wire                             m_axis_cc_tready_int_early;

assign s_axis_cq.tready = s_axis_cq_tready_reg;

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
    state_next = STATE_IDLE;

    s_axis_cq_tready_next = 1'b0;

    dword_count_next = dword_count_reg;
    type_next = type_reg;
    status_next = status_reg;
    requester_id_next = requester_id_reg;
    tag_next = tag_reg;
    tc_next = tc_reg;
    attr_next = attr_reg;
    first_be_next = first_be_reg;
    last_be_next = last_be_reg;
    cpl_data_next = cpl_data_reg;

    m_axis_cc_tdata_int = '0;
    m_axis_cc_tkeep_int = '0;
    m_axis_cc_tvalid_int = 1'b0;
    m_axis_cc_tlast_int = 1'b0;
    m_axis_cc_tuser_int = '0;

    casez (first_be_reg)
        4'b0000: cpl_tlp_hdr[6:0] = {m_axil_addr_reg[6:2], 2'b00}; // lower address
        4'bzzz1: cpl_tlp_hdr[6:0] = {m_axil_addr_reg[6:2], 2'b00}; // lower address
        4'bzz10: cpl_tlp_hdr[6:0] = {m_axil_addr_reg[6:2], 2'b01}; // lower address
        4'bz100: cpl_tlp_hdr[6:0] = {m_axil_addr_reg[6:2], 2'b10}; // lower address
        4'b1000: cpl_tlp_hdr[6:0] = {m_axil_addr_reg[6:2], 2'b11}; // lower address
    endcase
    cpl_tlp_hdr[9:8] = 2'b00; // AT
    casez (first_be_reg)
        4'b0000: cpl_tlp_hdr[28:16] = 13'd1; // Byte count
        4'b0001: cpl_tlp_hdr[28:16] = 13'd1; // Byte count
        4'b0010: cpl_tlp_hdr[28:16] = 13'd1; // Byte count
        4'b0100: cpl_tlp_hdr[28:16] = 13'd1; // Byte count
        4'b1000: cpl_tlp_hdr[28:16] = 13'd1; // Byte count
        4'b0011: cpl_tlp_hdr[28:16] = 13'd2; // Byte count
        4'b0110: cpl_tlp_hdr[28:16] = 13'd2; // Byte count
        4'b1100: cpl_tlp_hdr[28:16] = 13'd2; // Byte count
        4'b01z1: cpl_tlp_hdr[28:16] = 13'd3; // Byte count
        4'b1z10: cpl_tlp_hdr[28:16] = 13'd3; // Byte count
        4'b1zz1: cpl_tlp_hdr[28:16] = 13'd4; // Byte count
    endcase
    cpl_tlp_hdr[42:32] = cpl_data_reg ? 11'd1 : 11'd0; // DWORD count
    cpl_tlp_hdr[45:43] = status_reg;
    cpl_tlp_hdr[63:48] = requester_id_reg;
    cpl_tlp_hdr[71:64] = tag_reg;
    cpl_tlp_hdr[87:72] = completer_id;
    cpl_tlp_hdr[88] = completer_id_en;
    cpl_tlp_hdr[91:89] = tc_reg;
    cpl_tlp_hdr[94:92] = attr_reg;
    cpl_tlp_hdr[95] = 1'b0; // force ECRC

    // CC tuser sideband for 64 through 256-bit interface width
    cpl_tuser_1[0] = 1'b0; // discontinue
    cpl_tuser_1[32:1] = 32'd0; // parity

    // CC tuser sideband for 512-bit interface width
    cpl_tuser_2[1:0] = 2'b01; // is_sop
    cpl_tuser_2[3:2] = 2'd0; // is_sop0_ptr
    cpl_tuser_2[5:4] = 2'd0; // is_sop1_ptr
    cpl_tuser_2[7:6] = 2'b01; // is_eop
    cpl_tuser_2[11:8]  = cpl_data_reg ? 4'd3 : 4'd2; // is_eop0_ptr
    cpl_tuser_2[15:12] = 4'd0; // is_eop1_ptr
    cpl_tuser_2[16] = 1'b0; // discontinue
    cpl_tuser_2[80:17] = 64'd0; // parity

    if (AXIS_PCIE_DATA_W == 64) begin
        m_axis_cc_tdata_int = AXIS_PCIE_DATA_W'(cpl_tlp_hdr[63:0]);
        m_axis_cc_tkeep_int = AXIS_PCIE_KEEP_W'(2'b11);
        m_axis_cc_tlast_int = 1'b0;
    end else begin
        m_axis_cc_tdata_int = AXIS_PCIE_DATA_W'({m_axil_rd.rdata, cpl_tlp_hdr});
        m_axis_cc_tkeep_int = AXIS_PCIE_KEEP_W'({cpl_data_reg, 3'b111});
        m_axis_cc_tlast_int = 1'b1;
    end

    if (AXIS_PCIE_DATA_W == 512) begin
        m_axis_cc_tuser_int = AXIS_PCIE_CC_USER_W'(cpl_tuser_2);
    end else begin
        m_axis_cc_tuser_int = AXIS_PCIE_CC_USER_W'(cpl_tuser_1);
    end

    m_axil_addr_next = m_axil_addr_reg;
    m_axil_awvalid_next = m_axil_awvalid_reg && !m_axil_wr.awready;
    m_axil_wdata_next = m_axil_wdata_reg;
    m_axil_wstrb_next = m_axil_wstrb_reg;
    m_axil_wvalid_next = m_axil_wvalid_reg && !m_axil_wr.wready;
    m_axil_bready_next = 1'b0;
    m_axil_arvalid_next = m_axil_arvalid_reg && !m_axil_rd.arready;
    m_axil_rready_next = 1'b0;

    stat_err_cor_next = 1'b0;
    stat_err_uncor_next = 1'b0;

    case (state_reg)
        STATE_IDLE: begin
            // idle state, wait for completion request
            s_axis_cq_tready_next = m_axis_cc_tready_int_early;

            if (s_axis_cq.tready && s_axis_cq.tvalid) begin
                // header fields
                m_axil_addr_next = AXIL_ADDR_W'(req_tlp_hdr_addr);
                if (AXIS_PCIE_DATA_W > 64) begin
                    dword_count_next = req_tlp_hdr_length;
                    type_next = req_tlp_hdr_type;
                    requester_id_next = req_tlp_hdr_requester_id;
                    tag_next = req_tlp_hdr_tag;
                    tc_next = req_tlp_hdr_tc;
                    attr_next = req_tlp_hdr_attr;

                    // data
                    if (AXIS_PCIE_DATA_W >= 256) begin
                        m_axil_wdata_next = req_tlp_data;
                    end
                end

                first_be_next = req_tlp_hdr_first_be;
                last_be_next = req_tlp_hdr_last_be;

                m_axil_wstrb_next = first_be_next;

                cpl_data_next = 1'b1;
                status_next = CPL_STATUS_SC; // successful completion

                if (AXIS_PCIE_DATA_W == 64) begin
                    if (s_axis_cq.tlast) begin
                        // truncated packet
                        // report uncorrectable error
                        stat_err_uncor_next = 1'b1;
                        state_next = STATE_IDLE;
                    end else begin
                        state_next = STATE_HEADER;
                    end
                end else begin
                    if (type_next == REQ_MEM_READ || type_next == REQ_IO_READ) begin
                        // read request
                        cpl_data_next = 1'b1;
                        if (s_axis_cq.tlast && dword_count_next == 11'd1) begin
                            m_axil_arvalid_next = 1'b1;
                            m_axil_rready_next = m_axis_cc_tready_int_early;
                            s_axis_cq_tready_next = 1'b0;
                            state_next = STATE_READ;
                        end else begin
                            // bad length
                            cpl_data_next = 1'b0;
                            status_next = CPL_STATUS_CA; // completer abort
                            // report correctable error
                            stat_err_cor_next = 1'b1;
                            if (s_axis_cq.tlast) begin
                                s_axis_cq_tready_next = 1'b0;
                                state_next = STATE_CPL_1;
                            end else begin
                                s_axis_cq_tready_next = 1'b1;
                                state_next = STATE_WAIT_END;
                            end
                        end
                    end else if (type_next == REQ_MEM_WRITE || type_next == REQ_IO_WRITE) begin
                        // write request
                        cpl_data_next = 1'b0;
                        if (AXIS_PCIE_DATA_W >= 256 && s_axis_cq.tlast && dword_count_next == 11'd1) begin
                            m_axil_awvalid_next = 1'b1;
                            m_axil_wvalid_next = 1'b1;
                            m_axil_bready_next = 1'b1;
                            s_axis_cq_tready_next = 1'b0;
                            state_next = STATE_WRITE_2;
                        end else if (AXIS_PCIE_DATA_W < 256 && !s_axis_cq.tlast && dword_count_next == 11'd1) begin
                            s_axis_cq_tready_next = 1'b1;
                            state_next = STATE_WRITE_1;
                        end else begin
                            // bad length
                            status_next = CPL_STATUS_CA; // completer abort
                            if (type_next == REQ_MEM_WRITE) begin
                                // memory write - posted, no completion
                                // report uncorrectable error
                                stat_err_uncor_next = 1'b1;
                                if (s_axis_cq.tlast) begin
                                    s_axis_cq_tready_next = m_axis_cc_tready_int_early;
                                    state_next = STATE_IDLE;
                                end else begin
                                    s_axis_cq_tready_next = 1'b1;
                                    state_next = STATE_WAIT_END;
                                end
                            end else begin
                                // IO write - non-posted, send completion
                                // report correctable error
                                stat_err_cor_next = 1'b1;
                                if (s_axis_cq.tlast) begin
                                    s_axis_cq_tready_next = 1'b0;
                                    state_next = STATE_CPL_1;
                                end else begin
                                    s_axis_cq_tready_next = 1'b1;
                                    state_next = STATE_WAIT_END;
                                end
                            end
                        end
                    end else begin
                        // other request
                        cpl_data_next = 1'b0;
                        status_next = CPL_STATUS_UR; // unsupported request
                        if (type_next == REQ_MEM_WRITE || (type_next & 4'b1100) == 4'b1100) begin
                            // memory write or message - posted, no completion
                            // report uncorrectable error
                            stat_err_uncor_next = 1'b1;
                            if (s_axis_cq.tlast) begin
                                s_axis_cq_tready_next = m_axis_cc_tready_int_early;
                                state_next = STATE_IDLE;
                            end else begin
                                s_axis_cq_tready_next = 1'b1;
                                state_next = STATE_WAIT_END;
                            end
                        end else begin
                            // other non-posted request, send UR completion
                            // report correctable error
                            stat_err_cor_next = 1'b1;
                            if (s_axis_cq.tlast) begin
                                s_axis_cq_tready_next = 1'b0;
                                state_next = STATE_CPL_1;
                            end else begin
                                s_axis_cq_tready_next = 1'b1;
                                state_next = STATE_WAIT_END;
                            end
                        end
                    end
                end
            end else begin
                state_next = STATE_IDLE;
            end
        end
        STATE_HEADER: begin
            // header state, handle header (64-bit interface only)
            if (AXIS_PCIE_DATA_W == 64) begin
                s_axis_cq_tready_next = m_axis_cc_tready_int_early;

                // header fields
                dword_count_next = req_tlp_hdr_length;
                type_next = req_tlp_hdr_type;
                requester_id_next = req_tlp_hdr_requester_id;
                tag_next = req_tlp_hdr_tag;
                tc_next = req_tlp_hdr_tc;
                attr_next = req_tlp_hdr_attr;

                // data
                m_axil_wstrb_next = first_be_reg;

                if (s_axis_cq.tready && s_axis_cq.tvalid) begin
                    if (type_next == REQ_MEM_READ || type_next == REQ_IO_READ) begin
                        // read request
                        cpl_data_next = 1'b1;
                        if (s_axis_cq.tlast && dword_count_next == 11'd1) begin
                            m_axil_arvalid_next = 1'b1;
                            m_axil_rready_next = m_axis_cc_tready_int_early;
                            s_axis_cq_tready_next = 1'b0;
                            state_next = STATE_READ;
                        end else begin
                            // bad length
                            cpl_data_next = 1'b0;
                            status_next = CPL_STATUS_CA; // completer abort
                            // report correctable error
                            stat_err_cor_next = 1'b1;
                            if (s_axis_cq.tlast) begin
                                s_axis_cq_tready_next = 1'b0;
                                state_next = STATE_CPL_1;
                            end else begin
                                s_axis_cq_tready_next = 1'b1;
                                state_next = STATE_WAIT_END;
                            end
                        end
                    end else if (type_next == REQ_MEM_WRITE || type_next == REQ_IO_WRITE) begin
                        // write request
                        cpl_data_next = 1'b0;
                        if (!s_axis_cq.tlast && dword_count_next == 11'd1) begin
                            s_axis_cq_tready_next = 1'b1;
                            state_next = STATE_WRITE_1;
                        end else begin
                            // bad length
                            status_next = CPL_STATUS_CA; // completer abort
                            if (type_next == REQ_MEM_WRITE) begin
                                // memory write - posted, no completion
                                // report uncorrectable error
                                stat_err_uncor_next = 1'b1;
                                if (s_axis_cq.tlast) begin
                                    s_axis_cq_tready_next = m_axis_cc_tready_int_early;
                                    state_next = STATE_IDLE;
                                end else begin
                                    s_axis_cq_tready_next = 1'b1;
                                    state_next = STATE_WAIT_END;
                                end
                            end else begin
                                // other non-posted request, send UR completion
                                // report correctable error
                                stat_err_cor_next = 1'b1;
                                if (s_axis_cq.tlast) begin
                                    s_axis_cq_tready_next = 1'b0;
                                    state_next = STATE_CPL_1;
                                end else begin
                                    s_axis_cq_tready_next = 1'b1;
                                    state_next = STATE_WAIT_END;
                                end
                            end
                        end
                    end else begin
                        // other request
                        cpl_data_next = 1'b0;
                        status_next = CPL_STATUS_UR; // unsupported request
                        if (type_next == REQ_MEM_WRITE || (type_next & 4'b1100) == 4'b1100) begin
                            // memory write or message - posted, no completion
                            // report uncorrectable error
                            stat_err_uncor_next = 1'b1;
                            if (s_axis_cq.tlast) begin
                                s_axis_cq_tready_next = m_axis_cc_tready_int_early;
                                state_next = STATE_IDLE;
                            end else begin
                                s_axis_cq_tready_next = 1'b1;
                                state_next = STATE_WAIT_END;
                            end
                        end else begin
                            // other non-posted request, send UR completion
                            // report correctable error
                            stat_err_cor_next = 1'b1;
                            if (s_axis_cq.tlast) begin
                                s_axis_cq_tready_next = 1'b0;
                                state_next = STATE_CPL_1;
                            end else begin
                                s_axis_cq_tready_next = 1'b1;
                                state_next = STATE_WAIT_END;
                            end
                        end
                    end
                end else begin
                    state_next = STATE_HEADER;
                end
            end
        end
        STATE_READ: begin
            // read state, wait for read response
            m_axil_rready_next = m_axis_cc_tready_int_early;

            if (m_axil_rd.rready && m_axil_rd.rvalid) begin
                // send completion
                m_axis_cc_tvalid_int = 1'b1;

                m_axil_rready_next = 1'b0;
                if (AXIS_PCIE_DATA_W == 64) begin
                    cpl_data_next = 1'b1;
                    state_next = STATE_CPL_2;
                end else begin
                    s_axis_cq_tready_next = m_axis_cc_tready_int_early;
                    state_next = STATE_IDLE;
                end
            end else begin
                state_next = STATE_READ;
            end
        end
        STATE_WRITE_1: begin
            // write 1 state, store write data and initiate write
            s_axis_cq_tready_next = 1'b1;

            // data
            m_axil_wdata_next = req_tlp_data;

            if (s_axis_cq.tready && s_axis_cq.tvalid) begin
                if (s_axis_cq.tlast) begin
                    m_axil_awvalid_next = 1'b1;
                    m_axil_wvalid_next = 1'b1;
                    m_axil_bready_next = m_axis_cc_tready_int_early;
                    s_axis_cq_tready_next = 1'b0;
                    state_next = STATE_WRITE_2;
                end else begin
                    cpl_data_next = 1'b0;
                    status_next = CPL_STATUS_CA; // completer abort
                    s_axis_cq_tready_next = 1'b1;
                    state_next = STATE_WAIT_END;
                end
            end else begin
                state_next = STATE_WRITE_1;
            end
        end
        STATE_WRITE_2: begin
            // write 2 state, handle write response
            m_axil_bready_next = m_axis_cc_tready_int_early;

            if (m_axil_wr.bready && m_axil_wr.bvalid) begin
                m_axil_bready_next = 1'b0;
                if (type_reg == REQ_MEM_WRITE) begin
                    // memory write - posted, no completion
                    s_axis_cq_tready_next = m_axis_cc_tready_int_early;
                    state_next = STATE_IDLE;
                end else begin
                    // IO write - non-posted, send completion
                    m_axis_cc_tvalid_int = 1'b1;

                    if (AXIS_PCIE_DATA_W == 64) begin
                        state_next = STATE_CPL_2;
                    end else begin
                        s_axis_cq_tready_next = m_axis_cc_tready_int_early;
                        state_next = STATE_IDLE;
                    end
                end
            end else begin
                state_next = STATE_WRITE_2;
            end
        end
        STATE_WAIT_END: begin
            // wait end state, wait for end of completion request
            s_axis_cq_tready_next = 1'b1;

            if (s_axis_cq.tready && s_axis_cq.tvalid) begin
                if (s_axis_cq.tlast) begin
                    // completion
                    if (type_reg == REQ_MEM_WRITE || (type_reg & 4'b1100) == 4'b1100) begin
                        // memory write or message - posted, no completion
                        s_axis_cq_tready_next = m_axis_cc_tready_int_early;
                        state_next = STATE_IDLE;
                    end else begin
                        // IO write - non-posted, send completion
                        m_axis_cc_tvalid_int = 1'b1;

                        if (m_axis_cc_tready_int_reg) begin
                            if (AXIS_PCIE_DATA_W == 64) begin
                                state_next = STATE_CPL_2;
                            end else begin
                                s_axis_cq_tready_next = m_axis_cc_tready_int_early;
                                state_next = STATE_IDLE;
                            end
                        end else begin
                            state_next = STATE_CPL_1;
                        end
                    end
                end else begin
                    state_next = STATE_WAIT_END;
                end
            end else begin
                state_next = STATE_WAIT_END;
            end
        end
        STATE_CPL_1: begin
            // send completion
            m_axis_cc_tvalid_int = 1'b1;

            if (m_axis_cc_tready_int_reg) begin
                if (AXIS_PCIE_DATA_W == 64) begin
                    cpl_data_next = 1'b0;
                    state_next = STATE_CPL_2;
                end else begin
                    s_axis_cq_tready_next = m_axis_cc_tready_int_early;
                    state_next = STATE_IDLE;
                end
            end else begin
                state_next = STATE_CPL_1;
            end
        end
        STATE_CPL_2: begin
            // send rest of completion (64-bit interface only)
            if (AXIS_PCIE_DATA_W == 64) begin
                m_axis_cc_tvalid_int = 1'b1;
                m_axis_cc_tdata_int = AXIS_PCIE_DATA_W'({m_axil_rd.rdata, cpl_tlp_hdr[95:64]});
                m_axis_cc_tkeep_int = AXIS_PCIE_KEEP_W'({cpl_data_reg, 1'b1});
                m_axis_cc_tlast_int = 1'b1;

                if (m_axis_cc_tready_int_reg) begin
                    s_axis_cq_tready_next = m_axis_cc_tready_int_early;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_CPL_2;
                end
            end
        end
    endcase
end

always_ff @(posedge clk) begin
    state_reg <= state_next;

    dword_count_reg <= dword_count_next;
    type_reg <= type_next;
    tag_reg <= tag_next;
    status_reg <= status_next;
    requester_id_reg <= requester_id_next;
    tc_reg <= tc_next;
    attr_reg <= attr_next;
    first_be_reg <= first_be_next;
    last_be_reg <= last_be_next;
    cpl_data_reg <= cpl_data_next;

    s_axis_cq_tready_reg <= s_axis_cq_tready_next;

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

    if (rst) begin
        state_reg <= STATE_IDLE;
        s_axis_cq_tready_reg <= 1'b0;

        m_axil_awvalid_reg <= 1'b0;
        m_axil_wvalid_reg <= 1'b0;
        m_axil_bready_reg <= 1'b0;
        m_axil_arvalid_reg <= 1'b0;
        m_axil_rready_reg <= 1'b0;

        stat_err_cor_reg <= 1'b0;
        stat_err_uncor_reg <= 1'b0;
    end
end

// output datapath logic
logic [AXIS_PCIE_DATA_W-1:0]    m_axis_cc_tdata_reg = '0;
logic [AXIS_PCIE_KEEP_W-1:0]    m_axis_cc_tkeep_reg = '0;
logic                           m_axis_cc_tvalid_reg = 1'b0, m_axis_cc_tvalid_next;
logic                           m_axis_cc_tlast_reg = 1'b0;
logic [AXIS_PCIE_CC_USER_W-1:0] m_axis_cc_tuser_reg = '0;

logic [AXIS_PCIE_DATA_W-1:0]    temp_m_axis_cc_tdata_reg = '0;
logic [AXIS_PCIE_KEEP_W-1:0]    temp_m_axis_cc_tkeep_reg = '0;
logic                           temp_m_axis_cc_tvalid_reg = 1'b0, temp_m_axis_cc_tvalid_next;
logic                           temp_m_axis_cc_tlast_reg = 1'b0;
logic [AXIS_PCIE_CC_USER_W-1:0] temp_m_axis_cc_tuser_reg = '0;

// datapath control
logic store_axis_int_to_output;
logic store_axis_int_to_temp;
logic store_axis_temp_to_output;

assign m_axis_cc.tdata = m_axis_cc_tdata_reg;
assign m_axis_cc.tkeep = m_axis_cc_tkeep_reg;
assign m_axis_cc.tstrb = m_axis_cc.tkeep;
assign m_axis_cc.tvalid = m_axis_cc_tvalid_reg;
assign m_axis_cc.tlast = m_axis_cc_tlast_reg;
assign m_axis_cc.tuser = m_axis_cc_tuser_reg;
assign m_axis_cc.tid = '0;
assign m_axis_cc.tdest = '0;

// enable ready input next cycle if output is ready or if both output registers are empty
assign m_axis_cc_tready_int_early = m_axis_cc.tready || (!temp_m_axis_cc_tvalid_reg && !m_axis_cc_tvalid_reg);

always_comb begin
    // transfer sink ready state to source
    m_axis_cc_tvalid_next = m_axis_cc_tvalid_reg;
    temp_m_axis_cc_tvalid_next = temp_m_axis_cc_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_axis_temp_to_output = 1'b0;

    if (m_axis_cc_tready_int_reg) begin
        // input is ready
        if (m_axis_cc.tready || !m_axis_cc_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_axis_cc_tvalid_next = m_axis_cc_tvalid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_axis_cc_tvalid_next = m_axis_cc_tvalid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_axis_cc.tready) begin
        // input is not ready, but output is ready
        m_axis_cc_tvalid_next = temp_m_axis_cc_tvalid_reg;
        temp_m_axis_cc_tvalid_next = 1'b0;
        store_axis_temp_to_output = 1'b1;
    end
end

always_ff @(posedge clk) begin
    m_axis_cc_tvalid_reg <= m_axis_cc_tvalid_next;
    m_axis_cc_tready_int_reg <= m_axis_cc_tready_int_early;
    temp_m_axis_cc_tvalid_reg <= temp_m_axis_cc_tvalid_next;

    // datapath
    if (store_axis_int_to_output) begin
        m_axis_cc_tdata_reg <= m_axis_cc_tdata_int;
        m_axis_cc_tkeep_reg <= m_axis_cc_tkeep_int;
        m_axis_cc_tlast_reg <= m_axis_cc_tlast_int;
        m_axis_cc_tuser_reg <= m_axis_cc_tuser_int;
    end else if (store_axis_temp_to_output) begin
        m_axis_cc_tdata_reg <= temp_m_axis_cc_tdata_reg;
        m_axis_cc_tkeep_reg <= temp_m_axis_cc_tkeep_reg;
        m_axis_cc_tlast_reg <= temp_m_axis_cc_tlast_reg;
        m_axis_cc_tuser_reg <= temp_m_axis_cc_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
        temp_m_axis_cc_tdata_reg <= m_axis_cc_tdata_int;
        temp_m_axis_cc_tkeep_reg <= m_axis_cc_tkeep_int;
        temp_m_axis_cc_tlast_reg <= m_axis_cc_tlast_int;
        temp_m_axis_cc_tuser_reg <= m_axis_cc_tuser_int;
    end

    if (rst) begin
        m_axis_cc_tvalid_reg <= 1'b0;
        m_axis_cc_tready_int_reg <= 1'b0;
        temp_m_axis_cc_tvalid_reg <= 1'b0;
    end
end

endmodule

`resetall
