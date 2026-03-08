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
 * AXI4 lite crossbar (write)
 */
module taxi_axil_crossbar_wr #
(
    // Number of AXI inputs (slave interfaces)
    parameter S_COUNT = 4,
    // Number of AXI outputs (master interfaces)
    parameter M_COUNT = 4,
    // Address width in bits for address decoding
    parameter ADDR_W = 32,
    // TODO fix parametrization once verilator issue 5890 is fixed
    // Number of concurrent operations for each slave interface
    // S_COUNT concatenated fields of 32 bits
    parameter S_ACCEPT = {S_COUNT{32'd16}},
    // Number of regions per master interface
    parameter M_REGIONS = 1,
    // Master interface base addresses
    // M_COUNT concatenated fields of M_REGIONS concatenated fields of ADDR_W bits
    // set to zero for default addressing based on M_ADDR_W
    parameter M_BASE_ADDR = '0,
    // Master interface address widths
    // M_COUNT concatenated fields of M_REGIONS concatenated fields of 32 bits
    parameter M_ADDR_W = {M_COUNT{{M_REGIONS{32'd24}}}},
    // Write connections between interfaces
    // M_COUNT concatenated fields of S_COUNT bits
    parameter M_CONNECT = {M_COUNT{{S_COUNT{1'b1}}}},
    // Number of concurrent operations for each master interface
    // M_COUNT concatenated fields of 32 bits
    parameter M_ISSUE = {M_COUNT{32'd16}},
    // Secure master (fail operations based on awprot/arprot)
    // M_COUNT bits
    parameter M_SECURE = {M_COUNT{1'b0}},
    // Slave interface AW channel register type (input)
    // 0 to bypass, 1 for simple buffer, 2 for skid buffer
    parameter S_AW_REG_TYPE = {S_COUNT{2'd0}},
    // Slave interface W channel register type (input)
    // 0 to bypass, 1 for simple buffer, 2 for skid buffer
    parameter S_W_REG_TYPE = {S_COUNT{2'd0}},
    // Slave interface B channel register type (output)
    // 0 to bypass, 1 for simple buffer, 2 for skid buffer
    parameter S_B_REG_TYPE = {S_COUNT{2'd1}},
    // Master interface AW channel register type (output)
    // 0 to bypass, 1 for simple buffer, 2 for skid buffer
    parameter M_AW_REG_TYPE = {M_COUNT{2'd1}},
    // Master interface W channel register type (output)
    // 0 to bypass, 1 for simple buffer, 2 for skid buffer
    parameter M_W_REG_TYPE = {M_COUNT{2'd2}},
    // Master interface B channel register type (input)
    // 0 to bypass, 1 for simple buffer, 2 for skid buffer
    parameter M_B_REG_TYPE = {M_COUNT{2'd0}}
)
(
    input  wire logic    clk,
    input  wire logic    rst,

    /*
     * AXI4-lite slave interfaces
     */
    taxi_axil_if.wr_slv  s_axil_wr[S_COUNT],

    /*
     * AXI4-lite master interfaces
     */
    taxi_axil_if.wr_mst  m_axil_wr[M_COUNT]
);

// extract parameters
localparam DATA_W = s_axil_wr[0].DATA_W;
localparam S_ADDR_W = s_axil_wr[0].ADDR_W;
localparam STRB_W = s_axil_wr[0].STRB_W;
localparam logic AWUSER_EN = s_axil_wr[0].AWUSER_EN && m_axil_wr[0].AWUSER_EN;
localparam AWUSER_W = s_axil_wr[0].AWUSER_W;
localparam logic WUSER_EN = s_axil_wr[0].WUSER_EN && m_axil_wr[0].WUSER_EN;
localparam WUSER_W = s_axil_wr[0].WUSER_W;
localparam logic BUSER_EN = s_axil_wr[0].BUSER_EN && m_axil_wr[0].BUSER_EN;
localparam BUSER_W = s_axil_wr[0].BUSER_W;

localparam AXIL_M_ADDR_W = m_axil_wr[0].ADDR_W;

localparam CL_S_COUNT = $clog2(S_COUNT);
localparam CL_M_COUNT = $clog2(M_COUNT);
localparam CL_S_COUNT_INT = CL_S_COUNT > 0 ? CL_S_COUNT : 1;
localparam CL_M_COUNT_INT = CL_M_COUNT > 0 ? CL_M_COUNT : 1;

localparam [S_COUNT-1:0][31:0] S_ACCEPT_INT = S_ACCEPT;
localparam [M_COUNT-1:0][31:0] M_ISSUE_INT = M_ISSUE;

// check configuration
if (s_axil_wr[0].ADDR_W != ADDR_W)
    $fatal(0, "Error: Interface ADDR_W parameter mismatch (instance %m)");

if (m_axil_wr[0].DATA_W != DATA_W)
    $fatal(0, "Error: Interface DATA_W parameter mismatch (instance %m)");

if (m_axil_wr[0].STRB_W != STRB_W)
    $fatal(0, "Error: Interface STRB_W parameter mismatch (instance %m)");

wire [ADDR_W-1:0]    int_s_axil_awaddr[S_COUNT];
wire [2:0]           int_s_axil_awprot[S_COUNT];
wire [AWUSER_W-1:0]  int_s_axil_awuser[S_COUNT];

logic [M_COUNT-1:0]  int_axil_awvalid[S_COUNT];
logic [S_COUNT-1:0]  int_axil_awready[M_COUNT];

wire [DATA_W-1:0]    int_s_axil_wdata[S_COUNT];
wire [STRB_W-1:0]    int_s_axil_wstrb[S_COUNT];
wire [WUSER_W-1:0]   int_s_axil_wuser[S_COUNT];

logic [M_COUNT-1:0]  int_axil_wvalid[S_COUNT];
logic [S_COUNT-1:0]  int_axil_wready[M_COUNT];

wire [1:0]           int_m_axil_bresp[M_COUNT];
wire [BUSER_W-1:0]   int_m_axil_buser[M_COUNT];

logic [S_COUNT-1:0]  int_axil_bvalid[M_COUNT];
logic [M_COUNT-1:0]  int_axil_bready[S_COUNT];

for (genvar m = 0; m < S_COUNT; m = m + 1) begin : s_ifaces

    taxi_axil_if #(
        .DATA_W(s_axil_wr[0].DATA_W),
        .ADDR_W(s_axil_wr[0].ADDR_W),
        .STRB_W(s_axil_wr[0].STRB_W),
        .AWUSER_EN(s_axil_wr[0].AWUSER_EN),
        .AWUSER_W(s_axil_wr[0].AWUSER_W),
        .WUSER_EN(s_axil_wr[0].WUSER_EN),
        .WUSER_W(s_axil_wr[0].WUSER_W),
        .BUSER_EN(s_axil_wr[0].BUSER_EN),
        .BUSER_W(s_axil_wr[0].BUSER_W)
    ) int_axil();

    // S side register
    taxi_axil_register_wr #(
        .AW_REG_TYPE(S_AW_REG_TYPE[m*2 +: 2]),
        .W_REG_TYPE(S_W_REG_TYPE[m*2 +: 2]),
        .B_REG_TYPE(S_B_REG_TYPE[m*2 +: 2])
    )
    reg_inst (
        .clk(clk),
        .rst(rst),

        /*
         * AXI4-Lite slave interface
         */
        .s_axil_wr(s_axil_wr[m]),

        /*
         * AXI4-Lite master interface
         */
        .m_axil_wr(int_axil)
    );

    // response routing FIFO
    localparam FIFO_AW = $clog2(S_ACCEPT_INT[m])+1;

    logic [FIFO_AW+1-1:0] fifo_wr_ptr_reg = '0;
    logic [FIFO_AW+1-1:0] fifo_rd_ptr_reg = '0;

    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    logic [CL_M_COUNT_INT-1:0] fifo_select[2**FIFO_AW] = '{default: '0};
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    logic fifo_decerr[2**FIFO_AW] = '{default: '0};

    wire [CL_M_COUNT_INT-1:0] fifo_wr_select;
    wire fifo_wr_decerr;
    wire fifo_wr_en;

    logic [CL_M_COUNT_INT-1:0] fifo_rd_select_reg = '0;
    logic fifo_rd_decerr_reg = 1'b0;
    logic fifo_rd_valid_reg = 1'b0;
    wire fifo_rd_en;
    logic fifo_half_full_reg = 1'b0;

    wire fifo_empty = fifo_rd_ptr_reg == fifo_wr_ptr_reg;

    always_ff @(posedge clk) begin
        if (fifo_wr_en) begin
            fifo_select[fifo_wr_ptr_reg[FIFO_AW-1:0]] <= fifo_wr_select;
            fifo_decerr[fifo_wr_ptr_reg[FIFO_AW-1:0]] <= fifo_wr_decerr;
            fifo_wr_ptr_reg <= fifo_wr_ptr_reg + 1;
        end

        fifo_rd_valid_reg <= fifo_rd_valid_reg && !fifo_rd_en;

        if ((fifo_rd_ptr_reg != fifo_wr_ptr_reg) && (!fifo_rd_valid_reg || fifo_rd_en)) begin
            fifo_rd_select_reg <= fifo_select[fifo_rd_ptr_reg[FIFO_AW-1:0]];
            fifo_rd_decerr_reg <= fifo_decerr[fifo_rd_ptr_reg[FIFO_AW-1:0]];
            fifo_rd_valid_reg <= 1'b1;
            fifo_rd_ptr_reg <= fifo_rd_ptr_reg + 1;
        end

        fifo_half_full_reg <= $unsigned(fifo_wr_ptr_reg - fifo_rd_ptr_reg) >= 2**(FIFO_AW-1);

        if (rst) begin
            fifo_wr_ptr_reg <= '0;
            fifo_rd_ptr_reg <= '0;
            fifo_rd_valid_reg <= 1'b0;
        end
    end

    // address decode and admission control
    wire [CL_M_COUNT_INT-1:0] a_select;

    wire m_axil_avalid;
    wire m_axil_aready;

    wire [CL_M_COUNT_INT-1:0] m_wc_select;
    wire m_wc_decerr;
    wire m_wc_valid;
    wire m_wc_ready;

    wire [CL_M_COUNT_INT-1:0] m_rc_select;
    wire m_rc_decerr;
    wire m_rc_valid;
    wire m_rc_ready;

    taxi_axil_crossbar_addr #(
        .S(m),
        .S_COUNT(S_COUNT),
        .M_COUNT(M_COUNT),
        .SEL_W(CL_M_COUNT_INT),
        .ADDR_W(ADDR_W),
        .STRB_W(STRB_W),
        .M_REGIONS(M_REGIONS),
        .M_BASE_ADDR(M_BASE_ADDR),
        .M_ADDR_W(M_ADDR_W),
        .M_CONNECT(M_CONNECT),
        .M_SECURE(M_SECURE),
        .WC_OUTPUT(1)
    )
    addr_inst (
        .clk(clk),
        .rst(rst),

        /*
         * Address input
         */
        .s_axil_aaddr(int_axil.awaddr),
        .s_axil_aprot(int_axil.awprot),
        .s_axil_avalid(int_axil.awvalid),
        .s_axil_aready(int_axil.awready),

        /*
         * Address output
         */
        .m_select(a_select),
        .m_axil_avalid(m_axil_avalid),
        .m_axil_aready(m_axil_aready),

        /*
         * Write command output
         */
        .m_wc_select(m_wc_select),
        .m_wc_decerr(m_wc_decerr),
        .m_wc_valid(m_wc_valid),
        .m_wc_ready(m_wc_ready),

        /*
         * Response command output
         */
        .m_rc_select(m_rc_select),
        .m_rc_decerr(m_rc_decerr),
        .m_rc_valid(m_rc_valid),
        .m_rc_ready(m_rc_ready)
    );

    assign int_s_axil_awaddr[m] = int_axil.awaddr;
    assign int_s_axil_awprot[m] = int_axil.awprot;
    assign int_s_axil_awuser[m] = int_axil.awuser;

    always_comb begin
        int_axil_awvalid[m] = '0;
        int_axil_awvalid[m][a_select] = m_axil_avalid;
    end
    assign m_axil_aready = int_axil_awready[a_select][m];

    // write command handling
    logic [CL_M_COUNT_INT-1:0] w_select_reg = '0, w_select_next;
    logic w_drop_reg = 1'b0, w_drop_next;
    logic w_select_valid_reg = 1'b0, w_select_valid_next;

    assign m_wc_ready = !w_select_valid_reg;

    always_comb begin
        w_select_next = w_select_reg;
        w_drop_next = w_drop_reg && !(int_axil.wvalid && int_axil.wready);
        w_select_valid_next = w_select_valid_reg && !(int_axil.wvalid && int_axil.wready);

        if (m_wc_valid && !w_select_valid_reg) begin
            w_select_next = m_wc_select;
            w_drop_next = m_wc_decerr;
            w_select_valid_next = m_wc_valid;
        end
    end

    always_ff @(posedge clk) begin
        w_select_valid_reg <= w_select_valid_next;
        w_select_reg <= w_select_next;
        w_drop_reg <= w_drop_next;

        if (rst) begin
            w_select_valid_reg <= 1'b0;
        end
    end

    // write data forwarding
    assign int_s_axil_wdata[m] = int_axil.wdata;
    assign int_s_axil_wstrb[m] = int_axil.wstrb;
    assign int_s_axil_wuser[m] = int_axil.wuser;

    always_comb begin
        int_axil_wvalid[m] = '0;
        int_axil_wvalid[m][w_select_reg] = int_axil.wvalid && w_select_valid_reg && !w_drop_reg;
    end
    assign int_axil.wready = int_axil_wready[w_select_reg][m] || w_drop_reg;

    // response handling
    assign fifo_wr_select = m_rc_select;
    assign fifo_wr_decerr = m_rc_decerr;
    assign fifo_wr_en = m_rc_valid && !fifo_half_full_reg;
    assign m_rc_ready = !fifo_half_full_reg;

    // write response handling
    wire [CL_M_COUNT_INT-1:0] b_select = M_COUNT > 1 ? fifo_rd_select_reg : '0;
    wire b_decerr = fifo_rd_decerr_reg;
    wire b_valid = fifo_rd_valid_reg;

    // write response mux
    assign int_axil.bresp = b_decerr ? 2'b11 : int_m_axil_bresp[b_select];
    assign int_axil.buser = b_decerr ? '0 : int_m_axil_buser[b_select];
    assign int_axil.bvalid = (b_decerr ? 1'b1 : int_axil_bvalid[b_select][m]) && b_valid;

    always_comb begin
        int_axil_bready[m] = '0;
        int_axil_bready[m][b_select] = b_valid && int_axil.bready;
    end

    assign fifo_rd_en = int_axil.bvalid && int_axil.bready && b_valid;

end // s_ifaces

for (genvar n = 0; n < M_COUNT; n = n + 1) begin : m_ifaces

    taxi_axil_if #(
        .DATA_W(m_axil_wr[0].DATA_W),
        .ADDR_W(m_axil_wr[0].ADDR_W),
        .STRB_W(m_axil_wr[0].STRB_W),
        .AWUSER_EN(m_axil_wr[0].AWUSER_EN),
        .AWUSER_W(m_axil_wr[0].AWUSER_W),
        .WUSER_EN(m_axil_wr[0].WUSER_EN),
        .WUSER_W(m_axil_wr[0].WUSER_W),
        .BUSER_EN(m_axil_wr[0].BUSER_EN),
        .BUSER_W(m_axil_wr[0].BUSER_W)
    ) int_axil();

    // response routing FIFO
    localparam FIFO_AW = $clog2(M_ISSUE_INT[n])+1;

    logic [FIFO_AW+1-1:0] fifo_wr_ptr_reg = '0;
    logic [FIFO_AW+1-1:0] fifo_rd_ptr_reg = '0;

    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    logic [CL_S_COUNT_INT-1:0] fifo_select[2**FIFO_AW] = '{default: '0};
    wire [CL_S_COUNT_INT-1:0] fifo_wr_select;
    wire fifo_wr_en;
    wire fifo_rd_en;
    logic fifo_half_full_reg = 1'b0;

    wire fifo_empty = fifo_rd_ptr_reg == fifo_wr_ptr_reg;

    always_ff @(posedge clk) begin
        if (fifo_wr_en) begin
            fifo_select[fifo_wr_ptr_reg[FIFO_AW-1:0]] <= fifo_wr_select;
            fifo_wr_ptr_reg <= fifo_wr_ptr_reg + 1;
        end
        if (fifo_rd_en) begin
            fifo_rd_ptr_reg <= fifo_rd_ptr_reg + 1;
        end

        fifo_half_full_reg <= $unsigned(fifo_wr_ptr_reg - fifo_rd_ptr_reg) >= 2**(FIFO_AW-1);

        if (rst) begin
            fifo_wr_ptr_reg <= '0;
            fifo_rd_ptr_reg <= '0;
        end
    end

    // address arbitration
    logic [CL_S_COUNT_INT-1:0] w_select_reg = '0, w_select_next;
    logic w_select_valid_reg = 1'b0, w_select_valid_next;
    logic w_select_new_reg = 1'b0, w_select_new_next;

    wire [S_COUNT-1:0] a_req;
    wire [S_COUNT-1:0] a_ack;
    wire [S_COUNT-1:0] a_grant;
    wire a_grant_valid;
    wire [CL_S_COUNT_INT-1:0] a_grant_index;

    if (S_COUNT > 1) begin : arb

        taxi_arbiter #(
            .PORTS(S_COUNT),
            .ARB_ROUND_ROBIN(1),
            .ARB_BLOCK(1),
            .ARB_BLOCK_ACK(1),
            .LSB_HIGH_PRIO(1)
        )
        a_arb_inst (
            .clk(clk),
            .rst(rst),
            .req(a_req),
            .ack(a_ack),
            .grant(a_grant),
            .grant_valid(a_grant_valid),
            .grant_index(a_grant_index)
        );

    end else begin

        logic grant_valid_reg = 1'b0;

        always @(posedge clk) begin
            if (a_req) begin
                grant_valid_reg <= 1'b1;
            end

            if (a_ack || rst) begin
                grant_valid_reg <= 1'b0;
            end
        end

        assign a_grant_valid = grant_valid_reg;
        assign a_grant = grant_valid_reg;
        assign a_grant_index = '0;

    end

    // address mux
    assign int_axil.awaddr   = AXIL_M_ADDR_W'(int_s_axil_awaddr[a_grant_index]);
    assign int_axil.awprot   = int_s_axil_awprot[a_grant_index];
    assign int_axil.awuser   = int_s_axil_awuser[a_grant_index];
    assign int_axil.awvalid  = int_axil_awvalid[a_grant_index][n] && a_grant_valid;

    always_comb begin
        int_axil_awready[n] = '0;
        int_axil_awready[n][a_grant_index] = a_grant_valid && int_axil.awready;
    end

    for (genvar m = 0; m < S_COUNT; m = m + 1) begin
        assign a_req[m] = int_axil_awvalid[m][n] && !a_grant_valid && !fifo_half_full_reg && !w_select_valid_next;
        assign a_ack[m] = a_grant[m] && int_axil_awvalid[m][n] && int_axil.awready;
    end

    assign fifo_wr_select = a_grant_index;
    assign fifo_wr_en = int_axil.awvalid && int_axil.awready && a_grant_valid;

    // write data mux
    assign int_axil.wdata   = int_s_axil_wdata[w_select_reg];
    assign int_axil.wstrb   = int_s_axil_wstrb[w_select_reg];
    assign int_axil.wuser   = int_s_axil_wuser[w_select_reg];
    assign int_axil.wvalid  = int_axil_wvalid[w_select_reg][n] && w_select_valid_reg;

    always_comb begin
        int_axil_wready[n] = '0;
        int_axil_wready[n][w_select_reg] = w_select_valid_reg && int_axil.wready;
    end

    // write data routing
    always_comb begin
        w_select_next = w_select_reg;
        w_select_valid_next = w_select_valid_reg && !(int_axil.wvalid && int_axil.wready);
        w_select_new_next = w_select_new_reg || a_grant_valid == 0 || a_ack != 0;

        if (a_grant_valid && !w_select_valid_reg && w_select_new_reg) begin
            w_select_next = a_grant_index;
            w_select_valid_next = a_grant_valid;
            w_select_new_next = 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        w_select_reg <= w_select_next;
        w_select_valid_reg <= w_select_valid_next;
        w_select_new_reg <= w_select_new_next;

        if (rst) begin
            w_select_valid_reg <= 1'b0;
            w_select_new_reg <= 1'b1;
        end
    end

    // write response forwarding
    wire [CL_S_COUNT_INT-1:0] b_select = S_COUNT > 1 ? fifo_select[fifo_rd_ptr_reg[FIFO_AW-1:0]] : '0;

    assign int_m_axil_bresp[n] = int_axil.bresp;
    assign int_m_axil_buser[n] = int_axil.buser;

    always_comb begin
        int_axil_bvalid[n] = '0;
        int_axil_bvalid[n][b_select] = int_axil.bvalid;
    end
    assign int_axil.bready = int_axil_bready[b_select][n];

    assign fifo_rd_en = int_axil.bvalid && int_axil.bready;

    // M side register
    taxi_axil_register_wr #(
        .AW_REG_TYPE(M_AW_REG_TYPE[n*2 +: 2]),
        .W_REG_TYPE(M_W_REG_TYPE[n*2 +: 2]),
        .B_REG_TYPE(M_B_REG_TYPE[n*2 +: 2])
    )
    reg_inst (
        .clk(clk),
        .rst(rst),

        /*
         * AXI4-Lite slave interface
         */
        .s_axil_wr(int_axil),

        /*
         * AXI4-Lite master interface
         */
        .m_axil_wr(m_axil_wr[n])
    );

end // m_ifaces

endmodule

`resetall
