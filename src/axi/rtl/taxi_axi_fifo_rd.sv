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
 * AXI4 FIFO (read)
 */
module taxi_axi_fifo_rd #
(
    // Read data FIFO depth (cycles)
    parameter FIFO_DEPTH = 32,
    // Hold read address until space available in FIFO for data, if possible
    parameter logic FIFO_DELAY = 1'b0
)
(
    input  wire logic   clk,
    input  wire logic   rst,

    /*
     * AXI4 slave interface
     */
    taxi_axi_if.rd_slv  s_axi_rd,

    /*
     * AXI4 master interface
     */
    taxi_axi_if.rd_mst  m_axi_rd
);

// extract parameters
localparam DATA_W = s_axi_rd.DATA_W;
localparam ADDR_W = s_axi_rd.ADDR_W;
localparam STRB_W = s_axi_rd.STRB_W;
localparam ID_W = s_axi_rd.ID_W;
localparam logic ARUSER_EN = s_axi_rd.ARUSER_EN && m_axi_rd.ARUSER_EN;
localparam ARUSER_W = s_axi_rd.ARUSER_W;
localparam logic RUSER_EN = s_axi_rd.RUSER_EN && m_axi_rd.RUSER_EN;
localparam RUSER_W = s_axi_rd.RUSER_W;

localparam LAST_OFFSET  = DATA_W;
localparam ID_OFFSET    = LAST_OFFSET + 1;
localparam RESP_OFFSET  = ID_OFFSET + ID_W;
localparam RUSER_OFFSET = RESP_OFFSET + 2;
localparam RWIDTH       = RUSER_OFFSET + (RUSER_EN ? RUSER_W : 0);

localparam FIFO_AW = $clog2(FIFO_DEPTH);

if (m_axi_rd.DATA_W != DATA_W)
    $fatal(0, "Error: Interface DATA_W parameter mismatch (instance %m)");

if (m_axi_rd.STRB_W != STRB_W)
    $fatal(0, "Error: Interface STRB_W parameter mismatch (instance %m)");

logic [FIFO_AW:0] wr_ptr_reg = '0, wr_ptr_next;
logic [FIFO_AW:0] wr_addr_reg = '0;
logic [FIFO_AW:0] rd_ptr_reg = '0, rd_ptr_next;
logic [FIFO_AW:0] rd_addr_reg = '0;

(* ramstyle = "no_rw_check" *)
logic [RWIDTH-1:0] mem[2**FIFO_AW];
logic [RWIDTH-1:0] mem_read_data_reg;
logic mem_read_data_valid_reg = 1'b0, mem_read_data_valid_next;

wire [RWIDTH-1:0] m_axi_r;

logic [RWIDTH-1:0] s_axi_r_reg;
logic s_axi_rvalid_reg = 1'b0, s_axi_rvalid_next;

// full when first MSB different but rest same
wire full = ((wr_ptr_reg[FIFO_AW] != rd_ptr_reg[FIFO_AW]) &&
             (wr_ptr_reg[FIFO_AW-1:0] == rd_ptr_reg[FIFO_AW-1:0]));
// empty when pointers match exactly
wire empty = wr_ptr_reg == rd_ptr_reg;

// control signals
logic write;
logic read;
logic store_output;

assign m_axi_rd.rready = !full;

assign m_axi_r[DATA_W-1:0] = m_axi_rd.rdata;
assign m_axi_r[LAST_OFFSET] = m_axi_rd.rlast;
assign m_axi_r[ID_OFFSET +: ID_W] = m_axi_rd.rid;
assign m_axi_r[RESP_OFFSET +: 2] = m_axi_rd.rresp;
if (RUSER_EN) assign m_axi_r[RUSER_OFFSET +: RUSER_W] = m_axi_rd.ruser;

if (FIFO_DELAY) begin
    // store AR channel value until there is enough space to store R channel burst in FIFO or FIFO is empty

    localparam COUNT_W = (FIFO_AW > 8 ? FIFO_AW : 8) + 1;

    typedef enum logic [0:0] {
        STATE_IDLE,
        STATE_WAIT
    } state_t;

    state_t state_reg = STATE_IDLE, state_next;

    logic [COUNT_W-1:0] count_reg = 0, count_next;

    logic [ID_W-1:0] m_axi_arid_reg = '0, m_axi_arid_next;
    logic [ADDR_W-1:0] m_axi_araddr_reg = '0, m_axi_araddr_next;
    logic [7:0] m_axi_arlen_reg = '0, m_axi_arlen_next;
    logic [2:0] m_axi_arsize_reg = '0, m_axi_arsize_next;
    logic [1:0] m_axi_arburst_reg = '0, m_axi_arburst_next;
    logic m_axi_arlock_reg = '0, m_axi_arlock_next;
    logic [3:0] m_axi_arcache_reg = '0, m_axi_arcache_next;
    logic [2:0] m_axi_arprot_reg = '0, m_axi_arprot_next;
    logic [3:0] m_axi_arqos_reg = '0, m_axi_arqos_next;
    logic [3:0] m_axi_arregion_reg = '0, m_axi_arregion_next;
    logic [ARUSER_W-1:0] m_axi_aruser_reg = '0, m_axi_aruser_next;
    logic m_axi_arvalid_reg = 1'b0, m_axi_arvalid_next;

    logic s_axi_arready_reg = 1'b0, s_axi_arready_next;

    assign m_axi_rd.arid = m_axi_arid_reg;
    assign m_axi_rd.araddr = m_axi_araddr_reg;
    assign m_axi_rd.arlen = m_axi_arlen_reg;
    assign m_axi_rd.arsize = m_axi_arsize_reg;
    assign m_axi_rd.arburst = m_axi_arburst_reg;
    assign m_axi_rd.arlock = m_axi_arlock_reg;
    assign m_axi_rd.arcache = m_axi_arcache_reg;
    assign m_axi_rd.arprot = m_axi_arprot_reg;
    assign m_axi_rd.arqos = m_axi_arqos_reg;
    assign m_axi_rd.arregion = m_axi_arregion_reg;
    assign m_axi_rd.aruser = ARUSER_EN ? m_axi_aruser_reg : '0;
    assign m_axi_rd.arvalid = m_axi_arvalid_reg;

    assign s_axi_rd.arready = s_axi_arready_reg;

    always_comb begin
        state_next = STATE_IDLE;

        count_next = count_reg;

        m_axi_arid_next = m_axi_arid_reg;
        m_axi_araddr_next = m_axi_araddr_reg;
        m_axi_arlen_next = m_axi_arlen_reg;
        m_axi_arsize_next = m_axi_arsize_reg;
        m_axi_arburst_next = m_axi_arburst_reg;
        m_axi_arlock_next = m_axi_arlock_reg;
        m_axi_arcache_next = m_axi_arcache_reg;
        m_axi_arprot_next = m_axi_arprot_reg;
        m_axi_arqos_next = m_axi_arqos_reg;
        m_axi_arregion_next = m_axi_arregion_reg;
        m_axi_aruser_next = m_axi_aruser_reg;
        m_axi_arvalid_next = m_axi_arvalid_reg && !m_axi_rd.arready;
        s_axi_arready_next = s_axi_arready_reg;

        case (state_reg)
            STATE_IDLE: begin
                s_axi_arready_next = !m_axi_rd.arvalid || m_axi_rd.arready;

                if (s_axi_rd.arready && s_axi_rd.arvalid) begin
                    s_axi_arready_next = 1'b0;

                    m_axi_arid_next = s_axi_rd.arid;
                    m_axi_araddr_next = s_axi_rd.araddr;
                    m_axi_arlen_next = s_axi_rd.arlen;
                    m_axi_arsize_next = s_axi_rd.arsize;
                    m_axi_arburst_next = s_axi_rd.arburst;
                    m_axi_arlock_next = s_axi_rd.arlock;
                    m_axi_arcache_next = s_axi_rd.arcache;
                    m_axi_arprot_next = s_axi_rd.arprot;
                    m_axi_arqos_next = s_axi_rd.arqos;
                    m_axi_arregion_next = s_axi_rd.arregion;
                    m_axi_aruser_next = s_axi_rd.aruser;

                    if (count_reg == 0 || count_reg + m_axi_arlen_next + 1 <= 2**FIFO_AW) begin
                        count_next = count_reg + m_axi_arlen_next + 1;
                        m_axi_arvalid_next = 1'b1;
                        s_axi_arready_next = 1'b0;
                        state_next = STATE_IDLE;
                    end else begin
                        s_axi_arready_next = 1'b0;
                        state_next = STATE_WAIT;
                    end
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            STATE_WAIT: begin
                s_axi_arready_next = 1'b0;

                if (count_reg == 0 || count_reg + m_axi_arlen_reg + 1 <= 2**FIFO_AW) begin
                    count_next = count_reg + m_axi_arlen_reg + 1;
                    m_axi_arvalid_next = 1'b1;
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_WAIT;
                end
            end
        endcase

        if (s_axi_rd.rready && s_axi_rd.rvalid) begin
            count_next = count_next - 1;
        end
    end

    always_ff @(posedge clk) begin
        state_reg <= state_next;
        count_reg <= count_next;

        m_axi_arid_reg <= m_axi_arid_next;
        m_axi_araddr_reg <= m_axi_araddr_next;
        m_axi_arlen_reg <= m_axi_arlen_next;
        m_axi_arsize_reg <= m_axi_arsize_next;
        m_axi_arburst_reg <= m_axi_arburst_next;
        m_axi_arlock_reg <= m_axi_arlock_next;
        m_axi_arcache_reg <= m_axi_arcache_next;
        m_axi_arprot_reg <= m_axi_arprot_next;
        m_axi_arqos_reg <= m_axi_arqos_next;
        m_axi_arregion_reg <= m_axi_arregion_next;
        m_axi_aruser_reg <= m_axi_aruser_next;
        m_axi_arvalid_reg <= m_axi_arvalid_next;
        s_axi_arready_reg <= s_axi_arready_next;

        if (rst) begin
            state_reg <= STATE_IDLE;
            count_reg <= '0;
            m_axi_arvalid_reg <= 1'b0;
            s_axi_arready_reg <= 1'b0;
        end
    end

end else begin

    // bypass AR channel
    assign m_axi_rd.arid = s_axi_rd.arid;
    assign m_axi_rd.araddr = s_axi_rd.araddr;
    assign m_axi_rd.arlen = s_axi_rd.arlen;
    assign m_axi_rd.arsize = s_axi_rd.arsize;
    assign m_axi_rd.arburst = s_axi_rd.arburst;
    assign m_axi_rd.arlock = s_axi_rd.arlock;
    assign m_axi_rd.arcache = s_axi_rd.arcache;
    assign m_axi_rd.arprot = s_axi_rd.arprot;
    assign m_axi_rd.arqos = s_axi_rd.arqos;
    assign m_axi_rd.arregion = s_axi_rd.arregion;
    assign m_axi_rd.aruser = ARUSER_EN ? s_axi_rd.aruser : '0;
    assign m_axi_rd.arvalid = s_axi_rd.arvalid;
    assign s_axi_rd.arready = m_axi_rd.arready;

end

assign s_axi_rd.rvalid = s_axi_rvalid_reg;

assign s_axi_rd.rdata = s_axi_r_reg[DATA_W-1:0];
assign s_axi_rd.rlast = s_axi_r_reg[LAST_OFFSET];
assign s_axi_rd.rid   = s_axi_r_reg[ID_OFFSET +: ID_W];
assign s_axi_rd.rresp = s_axi_r_reg[RESP_OFFSET +: 2];
if (RUSER_EN) begin
    assign s_axi_rd.ruser = s_axi_r_reg[RUSER_OFFSET +: RUSER_W];
end else begin
    assign s_axi_rd.ruser = '0;
end

// Write logic
always_comb begin
    write = 1'b0;

    wr_ptr_next = wr_ptr_reg;

    if (m_axi_rd.rvalid) begin
        // input data valid
        if (!full) begin
            // not full, perform write
            write = 1'b1;
            wr_ptr_next = wr_ptr_reg + 1;
        end
    end
end

always_ff @(posedge clk) begin
    wr_ptr_reg <= wr_ptr_next;
    wr_addr_reg <= wr_ptr_next;

    if (write) begin
        mem[wr_addr_reg[FIFO_AW-1:0]] <= m_axi_r;
    end

    if (rst) begin
        wr_ptr_reg <= '0;
    end
end

// Read logic
always_comb begin
    read = 1'b0;

    rd_ptr_next = rd_ptr_reg;

    mem_read_data_valid_next = mem_read_data_valid_reg;

    if (store_output || !mem_read_data_valid_reg) begin
        // output data not valid OR currently being transferred
        if (!empty) begin
            // not empty, perform read
            read = 1'b1;
            mem_read_data_valid_next = 1'b1;
            rd_ptr_next = rd_ptr_reg + 1;
        end else begin
            // empty, invalidate
            mem_read_data_valid_next = 1'b0;
        end
    end
end

always_ff @(posedge clk) begin
    rd_ptr_reg <= rd_ptr_next;
    rd_addr_reg <= rd_ptr_next;

    mem_read_data_valid_reg <= mem_read_data_valid_next;

    if (read) begin
        mem_read_data_reg <= mem[rd_addr_reg[FIFO_AW-1:0]];
    end

    if (rst) begin
        rd_ptr_reg <= '0;
        mem_read_data_valid_reg <= 1'b0;
    end
end

// Output register
always_comb begin
    store_output = 1'b0;

    s_axi_rvalid_next = s_axi_rvalid_reg;

    if (s_axi_rd.rready || !s_axi_rd.rvalid) begin
        store_output = 1'b1;
        s_axi_rvalid_next = mem_read_data_valid_reg;
    end
end

always_ff @(posedge clk) begin
    s_axi_rvalid_reg <= s_axi_rvalid_next;

    if (store_output) begin
        s_axi_r_reg <= mem_read_data_reg;
    end

    if (rst) begin
        s_axi_rvalid_reg <= 1'b0;
    end
end

endmodule

`resetall
