// SPDX-License-Identifier: CERN-OHL-S-2.0
/*

Copyright (c) 2017-2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

`timescale 1ns / 1ps

/*
 * XFCP 1xN switch
 */
module taxi_xfcp_switch #
(
    parameter PORTS = 4,
    parameter logic [15:0] XFCP_ID_TYPE = 16'h0100,
    parameter XFCP_ID_STR = "XFCP Switch",
    parameter logic [8*16-1:0] XFCP_EXT_ID = 0,
    parameter XFCP_EXT_ID_STR = ""
)
(
    input  wire logic  clk,
    input  wire logic  rst,

    /*
     * XFCP upstream port
     */
    taxi_axis_if.snk   xfcp_usp_ds,
    taxi_axis_if.src   xfcp_usp_us,

    /*
     * XFCP downstream ports
     */
    taxi_axis_if.src   xfcp_dsp_ds[PORTS],
    taxi_axis_if.snk   xfcp_dsp_us[PORTS]
);

localparam CL_PORTS = PORTS > 1 ? $clog2(PORTS) : 1;
localparam CL_PORTS_P1 = $clog2(PORTS+1);

// check configuration
if (PORTS < 1 || PORTS > 256)
    $fatal(0, "Error: PORTS out of range; must be between 1 and 256");

localparam START_TAG = 8'hFF;
localparam RPATH_TAG = 8'hFE;
localparam ID_REQ = 8'hFE;
localparam ID_RESP = 8'hFF;

// ID ROM
localparam ID_PTR_W = (XFCP_EXT_ID != 0 || XFCP_EXT_ID_STR != 0) ? 6 : 5;
localparam ID_ROM_SIZE = 2**ID_PTR_W;
logic [7:0] id_rom[ID_ROM_SIZE];

logic [ID_PTR_W-1:0] id_ptr_reg = '0, id_ptr_next;

integer j;

initial begin
    // init ID ROM
    for (integer i = 0; i < ID_ROM_SIZE; i = i + 1) begin
        id_rom[i] = 0;
    end

    // binary part
    {id_rom[1], id_rom[0]} = 16'h0100 | (XFCP_ID_TYPE & 16'h00FF); // module type (switch)
    id_rom[2] = 8'd1; // upstream port count
    id_rom[3] = 8'(PORTS); // downstream port count

    // string part
    // find string length
    j = 0;
    for (integer i = 1; i <= 16; i = i + 1) begin
        if (j == i-1 && (XFCP_ID_STR >> (i*8)) > 0) begin
            j = i;
        end
    end

    // pack string
    for (integer i = 0; i <= j; i = i + 1) begin
        id_rom[i+16] = XFCP_ID_STR[8*(j-i) +: 8];
    end

    if (XFCP_EXT_ID != 0 || XFCP_EXT_ID_STR != 0) begin
        // extended ID

        // binary part
        for (integer i = 0; i < 16; i = i + 1) begin
            id_rom[i+32] = XFCP_EXT_ID[8*i +: 8];
        end

        // string part
        // find string length
        j = 0;
        for (integer i = 1; i <= 16; i = i + 1) begin
            if (j == i-1 && (XFCP_EXT_ID_STR >> (i*8)) > 0) begin
                j = i;
            end
        end

        // pack string
        for (integer i = 0; i <= j; i = i + 1) begin
            id_rom[i+48] = XFCP_EXT_ID_STR[8*(j-i) +: 8];
        end
    end
end

typedef enum logic [2:0] {
    DN_STATE_IDLE,
    DN_STATE_TRANSFER,
    DN_STATE_HEADER,
    DN_STATE_PKT,
    DN_STATE_ID
} dn_state_t;

dn_state_t dn_state_reg = DN_STATE_IDLE, dn_state_next;

typedef enum logic [0:0] {
    UP_STATE_IDLE,
    UP_STATE_TRANSFER
} up_state_t;

up_state_t up_state_reg = UP_STATE_IDLE, up_state_next;

logic [CL_PORTS-1:0] dn_select_reg = '0, dn_select_next;
logic dn_frame_reg = 1'b0, dn_frame_next;
logic dn_enable_reg = 1'b0, dn_enable_next;

logic [CL_PORTS_P1-1:0] up_select_reg = '0, up_select_next;
logic up_frame_reg = 1'b0, up_frame_next;

logic xfcp_usp_ds_tready_reg = 1'b0, xfcp_usp_ds_tready_next;

logic [PORTS-1:0] xfcp_dsp_us_tready_reg = '0, xfcp_dsp_us_tready_next;

wire [PORTS-1:0] xfcp_dsp_ds_tready;
wire [PORTS-1:0] xfcp_dsp_ds_tvalid;

// internal datapath
logic [7:0] xfcp_usp_us_tdata_int;
logic       xfcp_usp_us_tvalid_int;
logic       xfcp_usp_us_tready_int_reg = 1'b0;
logic       xfcp_usp_us_tlast_int;
logic       xfcp_usp_us_tuser_int;
wire        xfcp_usp_us_tready_int_early;

logic [7:0]       xfcp_dsp_ds_tdata_int;
logic [PORTS-1:0] xfcp_dsp_ds_tvalid_int;
logic             xfcp_dsp_ds_tready_int_reg = 1'b0;
logic             xfcp_dsp_ds_tlast_int;
logic             xfcp_dsp_ds_tuser_int;
wire              xfcp_dsp_ds_tready_int_early;

logic [7:0] int_loop_tdata_reg = 8'd0, int_loop_tdata_next;
logic       int_loop_tvalid_reg = 1'b0, int_loop_tvalid_next;
logic       int_loop_tready;
logic       int_loop_tready_early;
logic       int_loop_tlast_reg = 1'b0, int_loop_tlast_next;
logic       int_loop_tuser_reg = 1'b0, int_loop_tuser_next;

assign xfcp_usp_ds.tready = xfcp_usp_ds_tready_reg;

// unpack interface array
wire [PORTS+1-1:0]  xfcp_dsp_us_tready;
wire [7:0]          xfcp_dsp_us_tdata[PORTS+1];
wire [PORTS+1-1:0]  xfcp_dsp_us_tvalid;
wire [PORTS+1-1:0]  xfcp_dsp_us_tlast;
wire                xfcp_dsp_us_tuser[PORTS+1];

for (genvar n = 0; n < PORTS; n = n + 1) begin
    assign xfcp_dsp_us_tdata[n] = xfcp_dsp_us[n].tdata;
    assign xfcp_dsp_us_tvalid[n] = xfcp_dsp_us[n].tvalid;
    assign xfcp_dsp_us[n].tready = xfcp_dsp_us_tready_reg[n];
    assign xfcp_dsp_us_tlast[n] = xfcp_dsp_us[n].tlast;
    assign xfcp_dsp_us_tuser[n] = xfcp_dsp_us[n].tuser;

    assign xfcp_dsp_us_tready[n] = xfcp_dsp_us[n].tready;
end

assign xfcp_dsp_us_tdata[PORTS] = int_loop_tdata_reg;
assign xfcp_dsp_us_tvalid[PORTS] = int_loop_tvalid_reg;
assign xfcp_dsp_us_tlast[PORTS] = int_loop_tlast_reg;
assign xfcp_dsp_us_tuser[PORTS] = int_loop_tuser_reg;

assign xfcp_dsp_us_tready[PORTS] = int_loop_tready;

// mux for downstream output control signals
wire current_output_tvalid = xfcp_dsp_ds_tvalid[dn_select_reg];
wire current_output_tready = xfcp_dsp_ds_tready[dn_select_reg];

// mux for incoming downstream packet
wire [7:0] current_input_tdata  = xfcp_dsp_us_tdata[up_select_reg];
wire       current_input_tvalid = xfcp_dsp_us_tvalid[up_select_reg];
wire       current_input_tready = xfcp_dsp_us_tready[up_select_reg];
wire       current_input_tlast  = xfcp_dsp_us_tlast[up_select_reg];
wire       current_input_tuser  = xfcp_dsp_us_tuser[up_select_reg];

// downstream control logic
always_comb begin
    dn_state_next = DN_STATE_IDLE;

    dn_select_next = dn_select_reg;
    dn_frame_next = dn_frame_reg;
    dn_enable_next = dn_enable_reg;

    id_ptr_next = id_ptr_reg;

    xfcp_usp_ds_tready_next = 1'b0;

    xfcp_dsp_ds_tdata_int = xfcp_usp_ds.tdata;
    xfcp_dsp_ds_tvalid_int = PORTS'(xfcp_usp_ds.tvalid && xfcp_usp_ds.tready && dn_enable_reg) << dn_select_reg;
    xfcp_dsp_ds_tlast_int = xfcp_usp_ds.tlast;
    xfcp_dsp_ds_tuser_int = xfcp_usp_ds.tuser;

    int_loop_tdata_next = int_loop_tdata_reg;
    int_loop_tvalid_next = int_loop_tvalid_reg && !int_loop_tready;
    int_loop_tlast_next = int_loop_tlast_reg;
    int_loop_tuser_next = int_loop_tuser_reg;

    if (xfcp_usp_ds.tready & xfcp_usp_ds.tvalid) begin
        // end of frame detection
        if (xfcp_usp_ds.tlast) begin
            dn_frame_next = 1'b0;
            dn_enable_next = 1'b0;
        end
    end

    case (dn_state_reg)
        DN_STATE_IDLE: begin
            // wait for incoming upstream packet
            xfcp_usp_ds_tready_next = 1'b1;
            id_ptr_next = '0;

            if (!dn_frame_reg && xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                // start of frame
                dn_frame_next = 1'b1;
                if (xfcp_usp_ds.tdata == RPATH_TAG || xfcp_usp_ds.tdata == START_TAG) begin
                    // packet for us

                    int_loop_tdata_next = xfcp_usp_ds.tdata;
                    int_loop_tvalid_next = xfcp_usp_ds.tvalid;
                    int_loop_tlast_next = xfcp_usp_ds.tlast;
                    int_loop_tuser_next = xfcp_usp_ds.tuser;

                    xfcp_usp_ds_tready_next = int_loop_tready_early;

                    if (xfcp_usp_ds.tdata == RPATH_TAG) begin
                        // has rpath
                        dn_state_next = DN_STATE_HEADER;
                    end else begin
                        // no rpath
                        dn_state_next = DN_STATE_PKT;
                    end
                end else begin
                    // route packet
                    dn_enable_next = 1'b1;
                    dn_select_next = CL_PORTS'(xfcp_usp_ds.tdata);
                    xfcp_usp_ds_tready_next = xfcp_dsp_ds_tready_int_early;
                    dn_state_next = DN_STATE_TRANSFER;
                    if (xfcp_usp_ds.tdata >= 8'(PORTS)) begin
                        // out of range
                        dn_enable_next = 1'b0;
                    end
                end
            end else begin
                dn_state_next = DN_STATE_IDLE;
            end
        end
        DN_STATE_TRANSFER: begin
            // transfer upstream packet through proper downstream port
            if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                // end of frame detection
                if (xfcp_usp_ds.tlast) begin
                    dn_frame_next = 1'b0;
                    dn_enable_next = 1'b0;
                    dn_state_next = DN_STATE_IDLE;
                end else begin
                    dn_state_next = DN_STATE_TRANSFER;
                end
            end else begin
                dn_state_next = DN_STATE_TRANSFER;
            end
            xfcp_usp_ds_tready_next = xfcp_dsp_ds_tready_int_early && dn_frame_next;
        end
        DN_STATE_HEADER: begin
            // loop back header

            xfcp_usp_ds_tready_next = int_loop_tready_early;

            if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                int_loop_tdata_next = xfcp_usp_ds.tdata;
                int_loop_tvalid_next = 1'b1;
                int_loop_tlast_next = xfcp_usp_ds.tlast;
                int_loop_tuser_next = xfcp_usp_ds.tuser;

                // end of header detection
                if (xfcp_usp_ds.tdata == START_TAG) begin
                    dn_state_next = DN_STATE_PKT;
                end else begin
                    dn_state_next = DN_STATE_HEADER;
                end
            end else begin
                dn_state_next = DN_STATE_HEADER;
            end
        end
        DN_STATE_PKT: begin
            // packet type

            xfcp_usp_ds_tready_next = int_loop_tready_early;

            if (xfcp_usp_ds.tready && xfcp_usp_ds.tvalid) begin
                int_loop_tdata_next = xfcp_usp_ds.tdata;
                int_loop_tvalid_next = 1'b1;
                int_loop_tlast_next = xfcp_usp_ds.tlast;
                int_loop_tuser_next = xfcp_usp_ds.tuser;

                if (xfcp_usp_ds.tdata == ID_REQ) begin
                    // ID packet
                    int_loop_tdata_next = ID_RESP;
                    int_loop_tlast_next = 1'b0;
                    dn_state_next = DN_STATE_ID;
                end else begin
                    // something else
                    int_loop_tlast_next = 1'b1;
                    int_loop_tuser_next = 1'b1;
                    dn_state_next = DN_STATE_IDLE;
                end
            end else begin
                dn_state_next = DN_STATE_PKT;
            end
        end
        DN_STATE_ID: begin
            // send ID

            xfcp_usp_ds_tready_next = dn_frame_next;

            if (int_loop_tready) begin
                int_loop_tdata_next = id_rom[id_ptr_reg];
                int_loop_tvalid_next = 1'b1;
                int_loop_tlast_next = 1'b0;
                int_loop_tuser_next = 1'b0;

                id_ptr_next = id_ptr_reg + 1;
                if (id_ptr_reg == ID_ROM_SIZE-1) begin
                    int_loop_tlast_next = 1'b1;
                    dn_state_next = DN_STATE_IDLE;
                end else begin
                    dn_state_next = DN_STATE_ID;
                end
            end else begin
                dn_state_next = DN_STATE_ID;
            end
        end
        default: begin
            dn_state_next = DN_STATE_IDLE;
        end
    endcase
end

// upstream control logic
wire [PORTS+1-1:0] req;
wire [PORTS+1-1:0] ack;
wire [PORTS+1-1:0] grant;
wire grant_valid;
wire [CL_PORTS_P1-1:0] grant_index;

// arbiter instance
taxi_arbiter #(
    .PORTS(PORTS+1),
    .ARB_ROUND_ROBIN(1),
    .ARB_BLOCK(1),
    .ARB_BLOCK_ACK(1),
    .LSB_HIGH_PRIO(1)
)
arb_inst (
    .clk(clk),
    .rst(rst),
    .req(req),
    .ack(ack),
    .grant(grant),
    .grant_valid(grant_valid),
    .grant_index(grant_index)
);

assign req = xfcp_dsp_us_tvalid & ~grant;
assign ack = grant & xfcp_dsp_us_tvalid & xfcp_dsp_us_tready & xfcp_dsp_us_tlast;

always_comb begin
    up_state_next = UP_STATE_IDLE;

    up_select_next = up_select_reg;
    up_frame_next = up_frame_reg;


    xfcp_usp_us_tdata_int = current_input_tdata;
    xfcp_usp_us_tvalid_int = current_input_tvalid && current_input_tready && up_frame_reg;
    xfcp_usp_us_tlast_int = current_input_tlast;
    xfcp_usp_us_tuser_int = current_input_tuser;

    if (current_input_tready && current_input_tvalid) begin
        if (current_input_tlast) begin
            // end of frame detection
            up_frame_next = 1'b0;
        end
    end

    case (up_state_reg)
        UP_STATE_IDLE: begin
            // wait for incoming downstream packet
            if (grant_valid && xfcp_usp_us_tready_int_reg) begin
                up_frame_next = 1'b1;
                up_select_next = grant_index;
                up_state_next = UP_STATE_TRANSFER;

                if (up_select_next == CL_PORTS_P1'(PORTS)) begin
                    // internal loop; don't add port
                end else begin
                    // prepend port to packet
                    xfcp_usp_us_tdata_int = 8'(grant_index);
                    xfcp_usp_us_tvalid_int = 1'b1;
                    xfcp_usp_us_tlast_int = 1'b0;
                    xfcp_usp_us_tuser_int = 1'b0;
                end
            end else begin
                up_state_next = UP_STATE_IDLE;
            end
        end
        UP_STATE_TRANSFER: begin
            // transfer downstream packet out through upstream port
            if (current_input_tvalid && current_input_tready) begin
                if (current_input_tlast) begin
                    up_frame_next = 1'b0;
                    up_state_next = UP_STATE_IDLE;
                end else begin
                    up_state_next = UP_STATE_TRANSFER;
                end
            end else begin
                up_state_next = UP_STATE_TRANSFER;
            end
        end
    endcase
end

always_comb begin
    xfcp_dsp_us_tready_next = '0;

    // int_loop_tready_early = 1'b0;

    // generate ready signal on selected port
    if (up_select_next == CL_PORTS_P1'(PORTS)) begin
        // int_loop_tready_early = xfcp_usp_us_tready_int_early && up_frame_next;
    end else begin
        xfcp_dsp_us_tready_next = PORTS'(xfcp_usp_us_tready_int_early && up_frame_next) << up_select_next;
    end
end

always_comb begin
    int_loop_tready_early = xfcp_usp_us_tready_int_early && up_frame_next;
end

always_comb begin
    int_loop_tready = xfcp_usp_us_tready_int_reg && up_frame_reg;
end

always_ff @(posedge clk) begin
    dn_state_reg <= dn_state_next;
    up_state_reg <= up_state_next;

    id_ptr_reg <= id_ptr_next;

    dn_select_reg <= dn_select_next;
    dn_frame_reg <= dn_frame_next;
    dn_enable_reg <= dn_enable_next;

    up_select_reg <= up_select_next;
    up_frame_reg <= up_frame_next;

    xfcp_usp_ds_tready_reg <= xfcp_usp_ds_tready_next;
    xfcp_dsp_us_tready_reg <= xfcp_dsp_us_tready_next;

    int_loop_tdata_reg <= int_loop_tdata_next;
    int_loop_tvalid_reg <= int_loop_tvalid_next;
    int_loop_tlast_reg <= int_loop_tlast_next;
    int_loop_tuser_reg <= int_loop_tuser_next;

    if (rst) begin
        dn_state_reg <= DN_STATE_IDLE;
        up_state_reg <= UP_STATE_IDLE;
        dn_select_reg <= '0;
        dn_frame_reg <= 1'b0;
        dn_enable_reg <= 1'b0;
        up_select_reg <= '0;
        up_frame_reg <= 1'b0;
        xfcp_usp_ds_tready_reg <= 1'b0;
        xfcp_dsp_us_tready_reg <= '0;
        int_loop_tvalid_reg <= 1'b0;
    end
end

// upstream output datapath logic
logic [7:0]  xfcp_usp_us_tdata_reg = 8'd0;
logic        xfcp_usp_us_tvalid_reg = 1'b0, xfcp_usp_us_tvalid_next;
logic        xfcp_usp_us_tlast_reg = 1'b0;
logic        xfcp_usp_us_tuser_reg = 1'b0;

logic [7:0]  temp_xfcp_usp_us_tdata_reg = 8'd0;
logic        temp_xfcp_usp_us_tvalid_reg = 1'b0, temp_xfcp_usp_us_tvalid_next;
logic        temp_xfcp_usp_us_tlast_reg = 1'b0;
logic        temp_xfcp_usp_us_tuser_reg = 1'b0;

// datapath control
logic store_xfcp_usp_us_int_to_output;
logic store_xfcp_usp_us_int_to_temp;
logic store_xfcp_usp_us_temp_to_output;

assign xfcp_usp_us.tdata = xfcp_usp_us_tdata_reg;
assign xfcp_usp_us.tkeep = '1;
assign xfcp_usp_us.tstrb = xfcp_usp_us.tkeep;
assign xfcp_usp_us.tvalid = xfcp_usp_us_tvalid_reg;
assign xfcp_usp_us.tlast = xfcp_usp_us_tlast_reg;
assign xfcp_usp_us.tid = '0;
assign xfcp_usp_us.tdest = '0;
assign xfcp_usp_us.tuser = xfcp_usp_us_tuser_reg;

// enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
assign xfcp_usp_us_tready_int_early = xfcp_usp_us.tready || (!temp_xfcp_usp_us_tvalid_reg && (!xfcp_usp_us_tvalid_reg || !xfcp_usp_us_tvalid_int));

always_comb begin
    // transfer sink ready state to source
    xfcp_usp_us_tvalid_next = xfcp_usp_us_tvalid_reg;
    temp_xfcp_usp_us_tvalid_next = temp_xfcp_usp_us_tvalid_reg;

    store_xfcp_usp_us_int_to_output = 1'b0;
    store_xfcp_usp_us_int_to_temp = 1'b0;
    store_xfcp_usp_us_temp_to_output = 1'b0;

    if (xfcp_usp_us_tready_int_reg) begin
        // input is ready
        if (xfcp_usp_us.tready || !xfcp_usp_us_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            xfcp_usp_us_tvalid_next = xfcp_usp_us_tvalid_int;
            store_xfcp_usp_us_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_xfcp_usp_us_tvalid_next = xfcp_usp_us_tvalid_int;
            store_xfcp_usp_us_int_to_temp = 1'b1;
        end
    end else if (xfcp_usp_us.tready) begin
        // input is not ready, but output is ready
        xfcp_usp_us_tvalid_next = temp_xfcp_usp_us_tvalid_reg;
        temp_xfcp_usp_us_tvalid_next = 1'b0;
        store_xfcp_usp_us_temp_to_output = 1'b1;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        xfcp_usp_us_tvalid_reg <= 1'b0;
        xfcp_usp_us_tready_int_reg <= 1'b0;
        temp_xfcp_usp_us_tvalid_reg <= 1'b0;
    end else begin
        xfcp_usp_us_tvalid_reg <= xfcp_usp_us_tvalid_next;
        xfcp_usp_us_tready_int_reg <= xfcp_usp_us_tready_int_early;
        temp_xfcp_usp_us_tvalid_reg <= temp_xfcp_usp_us_tvalid_next;
    end

    // datapath
    if (store_xfcp_usp_us_int_to_output) begin
        xfcp_usp_us_tdata_reg <= xfcp_usp_us_tdata_int;
        xfcp_usp_us_tlast_reg <= xfcp_usp_us_tlast_int;
        xfcp_usp_us_tuser_reg <= xfcp_usp_us_tuser_int;
    end else if (store_xfcp_usp_us_temp_to_output) begin
        xfcp_usp_us_tdata_reg <= temp_xfcp_usp_us_tdata_reg;
        xfcp_usp_us_tlast_reg <= temp_xfcp_usp_us_tlast_reg;
        xfcp_usp_us_tuser_reg <= temp_xfcp_usp_us_tuser_reg;
    end

    if (store_xfcp_usp_us_int_to_temp) begin
        temp_xfcp_usp_us_tdata_reg <= xfcp_usp_us_tdata_int;
        temp_xfcp_usp_us_tlast_reg <= xfcp_usp_us_tlast_int;
        temp_xfcp_usp_us_tuser_reg <= xfcp_usp_us_tuser_int;
    end
end

// downstream output datapath logic
logic [7:0]       xfcp_dsp_ds_tdata_reg = 8'd0;
logic [PORTS-1:0] xfcp_dsp_ds_tvalid_reg = '0, xfcp_dsp_ds_tvalid_next;
logic             xfcp_dsp_ds_tlast_reg = 1'b0;
logic             xfcp_dsp_ds_tuser_reg = 1'b0;

logic [7:0]       temp_xfcp_dsp_ds_tdata_reg = 8'd0;
logic [PORTS-1:0] temp_xfcp_dsp_ds_tvalid_reg = '0, temp_xfcp_dsp_ds_tvalid_next;
logic             temp_xfcp_dsp_ds_tlast_reg = 1'b0;
logic             temp_xfcp_dsp_ds_tuser_reg = 1'b0;

// datapath control
logic store_xfcp_dsp_ds_to_output;
logic store_xfcp_dsp_ds_to_temp;
logic store_xfcp_dsp_ds_temp_to_output;

assign xfcp_dsp_ds_tvalid = xfcp_dsp_ds_tvalid_reg;

for (genvar k = 0; k < PORTS; k = k + 1) begin
    assign xfcp_dsp_ds[k].tdata  = xfcp_dsp_ds_tdata_reg;
    assign xfcp_dsp_ds[k].tkeep  = '1;
    assign xfcp_dsp_ds[k].tstrb  = xfcp_dsp_ds[k].tkeep;
    assign xfcp_dsp_ds[k].tvalid = xfcp_dsp_ds_tvalid_reg[k];
    assign xfcp_dsp_ds[k].tlast  = xfcp_dsp_ds_tlast_reg;
    assign xfcp_dsp_ds[k].tid    = '0;
    assign xfcp_dsp_ds[k].tdest  = '0;
    assign xfcp_dsp_ds[k].tuser  = xfcp_dsp_ds_tuser_reg;

    assign xfcp_dsp_ds_tready[k] = xfcp_dsp_ds[k].tready;
end

// enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
assign xfcp_dsp_ds_tready_int_early = ((xfcp_dsp_ds_tready & xfcp_dsp_ds_tvalid) != 0) || ((temp_xfcp_dsp_ds_tvalid_reg == 0) && ((xfcp_dsp_ds_tvalid == 0) || (xfcp_dsp_ds_tvalid_int == 0)));

always_comb begin
    // transfer sink ready state to source
    xfcp_dsp_ds_tvalid_next = xfcp_dsp_ds_tvalid_reg;
    temp_xfcp_dsp_ds_tvalid_next = temp_xfcp_dsp_ds_tvalid_reg;

    store_xfcp_dsp_ds_to_output = 1'b0;
    store_xfcp_dsp_ds_to_temp = 1'b0;
    store_xfcp_dsp_ds_temp_to_output = 1'b0;

    if (xfcp_dsp_ds_tready_int_reg) begin
        // input is ready
        if (((xfcp_dsp_ds_tready & xfcp_dsp_ds_tvalid) != 0) || (xfcp_dsp_ds_tvalid == 0)) begin
            // output is ready or currently not valid, transfer data to output
            xfcp_dsp_ds_tvalid_next = xfcp_dsp_ds_tvalid_int;
            store_xfcp_dsp_ds_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_xfcp_dsp_ds_tvalid_next = xfcp_dsp_ds_tvalid_int;
            store_xfcp_dsp_ds_to_temp = 1'b1;
        end
    end else if ((xfcp_dsp_ds_tready & xfcp_dsp_ds_tvalid) != 0) begin
        // input is not ready, but output is ready
        xfcp_dsp_ds_tvalid_next = temp_xfcp_dsp_ds_tvalid_reg;
        temp_xfcp_dsp_ds_tvalid_next = '0;
        store_xfcp_dsp_ds_temp_to_output = 1'b1;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        xfcp_dsp_ds_tvalid_reg <= '0;
        xfcp_dsp_ds_tready_int_reg <= 1'b0;
        temp_xfcp_dsp_ds_tvalid_reg <= '0;
    end else begin
        xfcp_dsp_ds_tvalid_reg <= xfcp_dsp_ds_tvalid_next;
        xfcp_dsp_ds_tready_int_reg <= xfcp_dsp_ds_tready_int_early;
        temp_xfcp_dsp_ds_tvalid_reg <= temp_xfcp_dsp_ds_tvalid_next;
    end

    // datapath
    if (store_xfcp_dsp_ds_to_output) begin
        xfcp_dsp_ds_tdata_reg <= xfcp_dsp_ds_tdata_int;
        xfcp_dsp_ds_tlast_reg <= xfcp_dsp_ds_tlast_int;
        xfcp_dsp_ds_tuser_reg <= xfcp_dsp_ds_tuser_int;
    end else if (store_xfcp_dsp_ds_temp_to_output) begin
        xfcp_dsp_ds_tdata_reg <= temp_xfcp_dsp_ds_tdata_reg;
        xfcp_dsp_ds_tlast_reg <= temp_xfcp_dsp_ds_tlast_reg;
        xfcp_dsp_ds_tuser_reg <= temp_xfcp_dsp_ds_tuser_reg;
    end

    if (store_xfcp_dsp_ds_to_temp) begin
        temp_xfcp_dsp_ds_tdata_reg <= xfcp_dsp_ds_tdata_int;
        temp_xfcp_dsp_ds_tlast_reg <= xfcp_dsp_ds_tlast_int;
        temp_xfcp_dsp_ds_tuser_reg <= xfcp_dsp_ds_tuser_int;
    end
end

endmodule
