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
 * UltraScale PCIe MSI shim
 */
module taxi_pcie_us_msi #
(
    parameter MSI_CNT = 32
)
(
    input  wire logic                clk,
    input  wire logic                rst,

    /*
     * Interrupt request inputs
     */
    input  wire logic [MSI_CNT-1:0]  msi_irq,

    /*
     * Interface to UltraScale PCIe IP core
     */
    input  wire logic [3:0]          cfg_interrupt_msi_enable,
    input  wire logic [7:0]          cfg_interrupt_msi_vf_enable,
    input  wire logic [11:0]         cfg_interrupt_msi_mmenable,
    input  wire logic                cfg_interrupt_msi_mask_update,
    input  wire logic [31:0]         cfg_interrupt_msi_data,
    output wire logic [3:0]          cfg_interrupt_msi_select,
    output wire logic [31:0]         cfg_interrupt_msi_int,
    output wire logic [31:0]         cfg_interrupt_msi_pending_status,
    output wire logic                cfg_interrupt_msi_pending_status_data_enable,
    output wire logic [3:0]          cfg_interrupt_msi_pending_status_function_num,
    input  wire logic                cfg_interrupt_msi_sent,
    input  wire logic                cfg_interrupt_msi_fail,
    output wire logic [2:0]          cfg_interrupt_msi_attr,
    output wire logic                cfg_interrupt_msi_tph_present,
    output wire logic [1:0]          cfg_interrupt_msi_tph_type,
    output wire logic [7:0]          cfg_interrupt_msi_tph_st_tag,
    output wire logic [7:0]          cfg_interrupt_msi_function_number
);

logic active_reg = 1'b0, active_next;

logic [MSI_CNT-1:0] msi_irq_reg = '0;
logic [MSI_CNT-1:0] msi_irq_last_reg = '0;
logic [MSI_CNT-1:0] msi_irq_active_reg = '0, msi_irq_active_next;

logic [MSI_CNT-1:0] msi_irq_mask_reg = '0, msi_irq_mask_next;

logic [MSI_CNT-1:0] msi_int_reg = '0, msi_int_next;

assign cfg_interrupt_msi_select = '0; // request PF0 mask on cfg_interrupt_msi_data
assign cfg_interrupt_msi_int = msi_int_reg;
assign cfg_interrupt_msi_pending_status = msi_irq_reg;
assign cfg_interrupt_msi_pending_status_data_enable = 1'b1; // set PF0 pending status
assign cfg_interrupt_msi_pending_status_function_num = '0; // set PF0 pending status
assign cfg_interrupt_msi_attr = 3'd0;
assign cfg_interrupt_msi_tph_present = 1'b0; // no TPH
assign cfg_interrupt_msi_tph_type = '0;
assign cfg_interrupt_msi_tph_st_tag = '0;
assign cfg_interrupt_msi_function_number = '0; // send MSI for PF0

wire [MSI_CNT-1:0] message_enable_mask = cfg_interrupt_msi_mmenable[2:0] > 3'd4 ? {32{1'b1}} : {32{1'b1}} >> (32 - (1 << cfg_interrupt_msi_mmenable[2:0]));

logic [MSI_CNT-1:0] ack;
wire [MSI_CNT-1:0] grant;
wire grant_valid;

// arbiter instance
taxi_arbiter #(
    .PORTS(MSI_CNT),
    .ARB_ROUND_ROBIN(1),
    .ARB_BLOCK(1),
    .ARB_BLOCK_ACK(1),
    .LSB_HIGH_PRIO(1)
)
arb_inst (
    .clk(clk),
    .rst(rst),
    .req(msi_irq_active_reg & msi_irq_mask_reg & ~grant),
    .ack(ack),
    .grant(grant),
    .grant_valid(grant_valid),
    .grant_index()
);

always_comb begin
    active_next = active_reg;

    msi_irq_active_next = (msi_irq_active_reg | (msi_irq_reg & ~msi_irq_last_reg));

    if (cfg_interrupt_msi_enable[0]) begin
        msi_irq_mask_next = ~cfg_interrupt_msi_data & message_enable_mask;
    end else begin
        msi_irq_mask_next = '0;
    end

    msi_int_next = '0;

    ack = '0;

    if (!active_reg) begin
        if (cfg_interrupt_msi_enable[0] && grant_valid) begin
            msi_int_next = grant;
            active_next = 1'b1;
        end
    end else begin
        if (cfg_interrupt_msi_sent || cfg_interrupt_msi_fail) begin
            if (cfg_interrupt_msi_sent) begin
                msi_irq_active_next = msi_irq_active_next & ~grant;
            end
            ack = grant;
            active_next = 1'b0;
        end
    end
end

always_ff @(posedge clk) begin
    active_reg <= active_next;
    msi_irq_reg <= msi_irq;
    msi_irq_last_reg <= msi_irq_reg;
    msi_irq_active_reg <= msi_irq_active_next;
    msi_irq_mask_reg <= msi_irq_mask_next;
    msi_int_reg <= msi_int_next;

    if (rst) begin
        active_reg <= 1'b0;
        msi_irq_reg <= '0;
        msi_irq_last_reg <= '0;
        msi_irq_active_reg <= '0;
        msi_irq_mask_reg <= '0;
        msi_int_reg <= '0;
    end
end

endmodule

`resetall
