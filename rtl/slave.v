module slave #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 8,
    parameter SPLIT_EN   = 0,
    parameter MEM_SIZE   = 4096
)(
    input  wire clk,
    input  wire rstn,

    // ----------------------------------------------------
    // Serial bus interface
    // ----------------------------------------------------
    input  wire swdata,         // Serial address/write-data bit from master
    output wire srdata,         // Serial read-data bit to master

    input  wire smode,          // 0 = read, 1 = write
    input  wire mvalid,         // swdata is valid

    input  wire split_grant,    // Grant to resume a split transaction

    output wire svalid,         // srdata is valid
    output wire sready,         // Slave ready for a new transaction
    output wire ssplit          // Split request
);

    // ====================================================
    // Internal signals between slave_port and slave_memory
    // ====================================================

    wire [DATA_WIDTH-1:0] smemrdata;
    wire [DATA_WIDTH-1:0] smemwdata;

    wire [ADDR_WIDTH-1:0] smemaddr;

    wire smemwen;
    wire smemren;
    wire rvalid;

    // ====================================================
    // Serial bus protocol controller
    // ====================================================

    slave_port #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .SPLIT_EN   (SPLIT_EN)
    ) slave_port_inst (
        .clk         (clk),
        .rstn        (rstn),

        // Memory-side interface
        .smemrdata   (smemrdata),
        .rvalid      (rvalid),
        .smemwen     (smemwen),
        .smemren     (smemren),
        .smemaddr    (smemaddr),
        .smemwdata   (smemwdata),

        // Serial-bus interface
        .swdata      (swdata),
        .srdata      (srdata),
        .smode       (smode),
        .mvalid      (mvalid),

        // Split support
        .split_grant (split_grant),
        .svalid      (svalid),
        .sready      (sready),
        .ssplit      (ssplit)
    );

    // ====================================================
    // Slave memory
    // ====================================================

    slave_memory #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .MEM_SIZE   (MEM_SIZE)
    ) slave_memory_inst (
        .clk         (clk),
        .rstn        (rstn),

        .wen         (smemwen),
        .ren         (smemren),

        .addr        (smemaddr),
        .wdata       (smemwdata),

        .rdata       (smemrdata),
        .rvalid      (rvalid)
    );

endmodule
