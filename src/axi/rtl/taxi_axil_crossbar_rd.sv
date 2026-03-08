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
 * AXI4 lite crossbar (read)
 */
module taxi_axil_crossbar_rd #
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
    // Read connections between interfaces
    // M_COUNT concatenated fields of S_COUNT bits
    parameter M_CONNECT = {M_COUNT{{S_COUNT{1'b1}}}},
    // Number of concurrent operations for each master interface
    // M_COUNT concatenated fields of 32 bits
    parameter M_ISSUE = {M_COUNT{32'd16}},
    // Secure master (fail operations based on awprot/arprot)
    // M_COUNT bits
    parameter M_SECURE = {M_COUNT{1'b0}},
    // Slave interface AR channel register type (input)
    // 0 to bypass, 1 for simple buffer, 2 for skid buffer
    parameter S_AR_REG_TYPE = {S_COUNT{2'd0}},
    // Slave interface R channel register type (output)
    // 0 to bypass, 1 for simple buffer, 2 for skid buffer
    parameter S_R_REG_TYPE = {S_COUNT{2'd2}},
    // Master interface AR channel register type (output)
    // 0 to bypass, 1 for simple buffer, 2 for skid buffer
    parameter M_AR_REG_TYPE = {M_COUNT{2'd1}},
    // Master interface R channel register type (input)
    // 0 to bypass, 1 for simple buffer, 2 for skid buffer
    parameter M_R_REG_TYPE = {M_COUNT{2'd0}}
)
(
    input  wire logic    clk,
    input  wire logic    rst,

    /*
     * AXI4-lite slave interfaces
     */
    taxi_axil_if.rd_slv  s_axil_rd[S_COUNT],

    /*
     * AXI4-lite master interfaces
     */
    taxi_axil_if.rd_mst  m_axil_rd[M_COUNT]
);

// extract parameters
localparam DATA_W = s_axil_rd[0].DATA_W;
localparam S_ADDR_W = s_axil_rd[0].ADDR_W;
localparam STRB_W = s_axil_rd[0].STRB_W;
localparam logic ARUSER_EN = s_axil_rd[0].ARUSER_EN && m_axil_rd[0].ARUSER_EN;
localparam ARUSER_W = s_axil_rd[0].ARUSER_W;
localparam logic RUSER_EN = s_axil_rd[0].RUSER_EN && m_axil_rd[0].RUSER_EN;
localparam RUSER_W = s_axil_rd[0].RUSER_W;

localparam AXIL_M_ADDR_W = m_axil_rd[0].ADDR_W;

localparam CL_S_COUNT = $clog2(S_COUNT);
localparam CL_M_COUNT = $clog2(M_COUNT);
localparam CL_S_COUNT_INT = CL_S_COUNT > 0 ? CL_S_COUNT : 1;
localparam CL_M_COUNT_INT = CL_M_COUNT > 0 ? CL_M_COUNT : 1;

localparam [S_COUNT-1:0][31:0] S_ACCEPT_INT = S_ACCEPT;
localparam [M_COUNT-1:0][31:0] M_ISSUE_INT = M_ISSUE;

// check configuration
if (s_axil_rd[0].ADDR_W != ADDR_W)
    $fatal(0, "Error: Interface ADDR_W parameter mismatch (instance %m)");

if (m_axil_rd[0].DATA_W != DATA_W)
    $fatal(0, "Error: Interface DATA_W parameter mismatch (instance %m)");

if (m_axil_rd[0].STRB_W != STRB_W)
    $fatal(0, "Error: Interface STRB_W parameter mismatch (instance %m)");

wire [ADDR_W-1:0]    int_s_axil_araddr[S_COUNT];
wire [2:0]           int_s_axil_arprot[S_COUNT];
wire [ARUSER_W-1:0]  int_s_axil_aruser[S_COUNT];

logic [M_COUNT-1:0]  int_axil_arvalid[S_COUNT];
logic [S_COUNT-1:0]  int_axil_arready[M_COUNT];

wire [DATA_W-1:0]    int_m_axil_rdata[M_COUNT];
wire [1:0]           int_m_axil_rresp[M_COUNT];
wire [RUSER_W-1:0]   int_m_axil_ruser[M_COUNT];

logic [S_COUNT-1:0]  int_axil_rvalid[M_COUNT];
logic [M_COUNT-1:0]  int_axil_rready[S_COUNT];

for (genvar m = 0; m < S_COUNT; m = m + 1) begin : s_ifaces

    taxi_axil_if #(
        .DATA_W(s_axil_rd[0].DATA_W),
        .ADDR_W(s_axil_rd[0].ADDR_W),
        .STRB_W(s_axil_rd[0].STRB_W),
        .ARUSER_EN(s_axil_rd[0].ARUSER_EN),
        .ARUSER_W(s_axil_rd[0].ARUSER_W),
        .RUSER_EN(s_axil_rd[0].RUSER_EN),
        .RUSER_W(s_axil_rd[0].RUSER_W)
    ) int_axil();

    // S side register
    taxi_axil_register_rd #(
        .AR_REG_TYPE(S_AR_REG_TYPE[m*2 +: 2]),
        .R_REG_TYPE(S_R_REG_TYPE[m*2 +: 2])
    )
    reg_inst (
        .clk(clk),
        .rst(rst),

        /*
         * AXI4-Lite slave interface
         */
        .s_axil_rd(s_axil_rd[m]),

        /*
         * AXI4-Lite master interface
         */
        .m_axil_rd(int_axil)
    );

    // response routing FIFO
    localparam FIFO_AW = $clog2(S_ACCEPT_INT[m])+1;

    logic [FIFO_AW+1-1:0] fifo_wr_ptr_reg = 0;
    logic [FIFO_AW+1-1:0] fifo_rd_ptr_reg = 0;

    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    logic [CL_M_COUNT_INT-1:0] fifo_select[2**FIFO_AW] = '{default: '0};
    (* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)
    logic fifo_decerr[2**FIFO_AW] = '{default: '0};

    wire [CL_M_COUNT_INT-1:0] fifo_wr_select;
    wire fifo_wr_decerr;
    wire fifo_wr_en;

    logic [CL_M_COUNT_INT-1:0] fifo_rd_select_reg = 0;
    logic fifo_rd_decerr_reg = 0;
    logic fifo_rd_valid_reg = 0;
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
            fifo_wr_ptr_reg <= 0;
            fifo_rd_ptr_reg <= 0;
            fifo_rd_valid_reg <= 1'b0;
        end
    end

    // address decode and admission control
    wire [CL_M_COUNT_INT-1:0] a_select;

    wire m_axil_avalid;
    wire m_axil_aready;

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
        .WC_OUTPUT(0)
    )
    addr_inst (
        .clk(clk),
        .rst(rst),

        /*
         * Address input
         */
        .s_axil_aaddr(int_axil.araddr),
        .s_axil_aprot(int_axil.arprot),
        .s_axil_avalid(int_axil.arvalid),
        .s_axil_aready(int_axil.arready),

        /*
         * Address output
         */
        .m_select(a_select),
        .m_axil_avalid(m_axil_avalid),
        .m_axil_aready(m_axil_aready),

        /*
         * Write command output
         */
        .m_wc_select(),
        .m_wc_decerr(),
        .m_wc_valid(),
        .m_wc_ready(1'b1),

        /*
         * Response command output
         */
        .m_rc_select(m_rc_select),
        .m_rc_decerr(m_rc_decerr),
        .m_rc_valid(m_rc_valid),
        .m_rc_ready(m_rc_ready)
    );

    assign int_s_axil_araddr[m] = int_axil.araddr;
    assign int_s_axil_arprot[m] = int_axil.arprot;
    assign int_s_axil_aruser[m] = int_axil.aruser;

    always_comb begin
        int_axil_arvalid[m] = '0;
        int_axil_arvalid[m][a_select] = m_axil_avalid;
    end
    assign m_axil_aready = int_axil_arready[a_select][m];

    // response handling
    assign fifo_wr_select = m_rc_select;
    assign fifo_wr_decerr = m_rc_decerr;
    assign fifo_wr_en = m_rc_valid && !fifo_half_full_reg;
    assign m_rc_ready = !fifo_half_full_reg;

    // write response handling
    wire [CL_M_COUNT_INT-1:0] r_select = M_COUNT > 1 ? fifo_rd_select_reg : '0;
    wire r_decerr = fifo_rd_decerr_reg;
    wire r_valid = fifo_rd_valid_reg;

    // read response mux
    assign int_axil.rdata  = r_decerr ? '0 : int_m_axil_rdata[r_select];
    assign int_axil.rresp  = r_decerr ? 2'b11 : int_m_axil_rresp[r_select];
    assign int_axil.ruser  = r_decerr ? '0 : int_m_axil_ruser[r_select];
    assign int_axil.rvalid = (r_decerr ? 1'b1 : int_axil_rvalid[r_select][m]) && r_valid;

    always_comb begin
        int_axil_rready[m] = '0;
        int_axil_rready[m][r_select] = r_valid && int_axil.rready;
    end

    assign fifo_rd_en = int_axil.rvalid && int_axil.rready && r_valid;

end // s_ifaces

for (genvar n = 0; n < M_COUNT; n = n + 1) begin : m_ifaces

    taxi_axil_if #(
        .DATA_W(m_axil_rd[0].DATA_W),
        .ADDR_W(m_axil_rd[0].ADDR_W),
        .STRB_W(m_axil_rd[0].STRB_W),
        .ARUSER_EN(m_axil_rd[0].ARUSER_EN),
        .ARUSER_W(m_axil_rd[0].ARUSER_W),
        .RUSER_EN(m_axil_rd[0].RUSER_EN),
        .RUSER_W(m_axil_rd[0].RUSER_W)
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
    assign int_axil.araddr   = AXIL_M_ADDR_W'(int_s_axil_araddr[a_grant_index]);
    assign int_axil.arprot   = int_s_axil_arprot[a_grant_index];
    assign int_axil.aruser   = int_s_axil_aruser[a_grant_index];
    assign int_axil.arvalid  = int_axil_arvalid[a_grant_index][n] && a_grant_valid;

    always_comb begin
        int_axil_arready[n] = '0;
        int_axil_arready[n][a_grant_index] = a_grant_valid && int_axil.arready;
    end

    for (genvar m = 0; m < S_COUNT; m = m + 1) begin
        assign a_req[m] = int_axil_arvalid[m][n] && !a_grant_valid && !fifo_half_full_reg;
        assign a_ack[m] = a_grant[m] && int_axil_arvalid[m][n] && int_axil.arready;
    end

    assign fifo_wr_select = a_grant_index;
    assign fifo_wr_en = int_axil.arvalid && int_axil.arready && a_grant_valid;

    // read response forwarding
    wire [CL_S_COUNT_INT-1:0] r_select = S_COUNT > 1 ? fifo_select[fifo_rd_ptr_reg[FIFO_AW-1:0]] : '0;

    assign int_m_axil_rdata[n] = int_axil.rdata;
    assign int_m_axil_rresp[n] = int_axil.rresp;
    assign int_m_axil_ruser[n] = int_axil.ruser;

    always_comb begin
        int_axil_rvalid[n] = '0;
        int_axil_rvalid[n][r_select] = int_axil.rvalid;
    end
    assign int_axil.rready = int_axil_rready[r_select][n];

    assign fifo_rd_en = int_axil.rvalid && int_axil.rready;

    // M side register
    taxi_axil_register_rd #(
        .AR_REG_TYPE(M_AR_REG_TYPE[n*2 +: 2]),
        .R_REG_TYPE(M_R_REG_TYPE[n*2 +: 2])
    )
    reg_inst (
        .clk(clk),
        .rst(rst),

        /*
         * AXI4-Lite slave interface
         */
        .s_axil_rd(int_axil),

        /*
         * AXI4-Lite master interface
         */
        .m_axil_rd(m_axil_rd[n])
    );

end // m_ifaces

endmodule

`resetall
