`timescale 1ns/1ps

// Two-master, three-slave bit-serial bus interconnect.
// Address and payload bits travel on the one-bit wdata/rdata signals.
module serial_bus_m2_s3 #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter SLAVE_MEM_ADDR_WIDTH = 12
) (
    input  wire clk,
    input  wire reset_n,

    // Master 1 serial interface
    output wire m1_rdata,
    input  wire m1_wdata,
    input  wire m1_mode,
    input  wire m1_mvalid,
    output wire m1_svalid,
    input  wire m1_breq,
    output wire m1_bgrant,
    output wire m1_ack,
    output wire m1_split,

    // Master 2 serial interface
    output wire m2_rdata,
    input  wire m2_wdata,
    input  wire m2_mode,
    input  wire m2_mvalid,
    output wire m2_svalid,
    input  wire m2_breq,
    output wire m2_bgrant,
    output wire m2_ack,
    output wire m2_split,

    // Slave 1 serial interface
    input  wire s1_rdata,
    output wire s1_wdata,
    output wire s1_mode,
    output wire s1_mvalid,
    input  wire s1_svalid,
    input  wire s1_ready,

    // Slave 2 serial interface
    input  wire s2_rdata,
    output wire s2_wdata,
    output wire s2_mode,
    output wire s2_mvalid,
    input  wire s2_svalid,
    input  wire s2_ready,

    // Slave 3 serial interface (the only split-capable slave)
    input  wire s3_rdata,
    output wire s3_wdata,
    output wire s3_mode,
    output wire s3_mvalid,
    input  wire s3_svalid,
    input  wire s3_ready,
    input  wire s3_split,

    output wire split_grant
);

    localparam DEVICE_ADDR_WIDTH = ADDR_WIDTH - SLAVE_MEM_ADDR_WIDTH;

    wire selected_master;
    wire selected_master_wdata;
    wire selected_master_mode;
    wire selected_master_valid;

    wire [1:0] selected_slave;
    wire selected_slave_rdata;
    wire selected_slave_valid;
    wire decoder_ack;

    // DATA_WIDTH documents the logical payload width and keeps the parameter
    // set consistent with the endpoint modules. This physical path is one bit.

    bus_arbiter arbiter_inst (
        .clk(clk),
        .reset_n(reset_n),
        .master1_request(m1_breq),
        .master2_request(m2_breq),
        .slave1_ready(s1_ready),
        .slave2_ready(s2_ready),
        .split_slave_ready(s3_ready),
        .split_request(s3_split),
        .master1_grant(m1_bgrant),
        .master2_grant(m2_bgrant),
        .selected_master(selected_master),
        .master1_split(m1_split),
        .master2_split(m2_split),
        .split_resume(split_grant)
    );

    bus_mux2 #(.WIDTH(1)) master_data_mux (
        .data0(m1_wdata),
        .data1(m2_wdata),
        .select(selected_master),
        .data_out(selected_master_wdata)
    );

    bus_mux2 #(.WIDTH(2)) master_control_mux (
        .data0({m1_mode, m1_mvalid}),
        .data1({m2_mode, m2_mvalid}),
        .select(selected_master),
        .data_out({selected_master_mode, selected_master_valid})
    );

    serial_address_decoder #(
        .DEVICE_ADDR_WIDTH(DEVICE_ADDR_WIDTH),
        .SPLIT_SLAVE_INDEX(2)
    ) address_decoder_inst (
        .clk(clk),
        .reset_n(reset_n),
        .serial_data(selected_master_wdata),
        .master_valid(selected_master_valid),
        .slave1_ready(s1_ready),
        .slave2_ready(s2_ready),
        .slave3_ready(s3_ready),
        .split_request(s3_split),
        .split_resume(split_grant),
        .slave1_valid(s1_mvalid),
        .slave2_valid(s2_mvalid),
        .slave3_valid(s3_mvalid),
        .slave_select(selected_slave),
        .address_ack(decoder_ack)
    );

    bus_mux3 #(.WIDTH(1)) slave_data_mux (
        .data0(s1_rdata),
        .data1(s2_rdata),
        .data2(s3_rdata),
        .select(selected_slave),
        .data_out(selected_slave_rdata)
    );

    bus_mux3 #(.WIDTH(1)) slave_valid_mux (
        .data0(s1_svalid),
        .data1(s2_svalid),
        .data2(s3_svalid),
        .select(selected_slave),
        .data_out(selected_slave_valid)
    );

    // Data and mode are broadcast; the decoded mvalid signal determines which
    // slave is permitted to capture each serial bit.
    assign s1_wdata = selected_master_wdata;
    assign s2_wdata = selected_master_wdata;
    assign s3_wdata = selected_master_wdata;

    assign s1_mode = selected_master_mode;
    assign s2_mode = selected_master_mode;
    assign s3_mode = selected_master_mode;

    // Gate return control by grant so only the active master observes it.
    assign m1_rdata  = m1_bgrant ? selected_slave_rdata : 1'b0;
    assign m2_rdata  = m2_bgrant ? selected_slave_rdata : 1'b0;
    assign m1_svalid = selected_slave_valid & m1_bgrant;
    assign m2_svalid = selected_slave_valid & m2_bgrant;
    assign m1_ack    = decoder_ack & m1_bgrant;
    assign m2_ack    = decoder_ack & m2_bgrant;

endmodule
