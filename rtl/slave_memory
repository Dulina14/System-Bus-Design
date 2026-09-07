module slave_memory #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 8,
    parameter MEM_SIZE   = 4096       // Memory size in bytes
)(
    input  wire                  clk,
    input  wire                  rstn,

    input  wire                  wen,
    input  wire                  ren,

    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [DATA_WIDTH-1:0] wdata,

    output reg  [DATA_WIDTH-1:0] rdata,
    output reg                   rvalid
);

    // ====================================================
    // Memory organization
    // ====================================================

    // Number of bytes contained in one memory word
    localparam BYTES_PER_WORD = DATA_WIDTH / 8;

    // Number of actual memory locations
    localparam NUM_LOCATIONS = MEM_SIZE / BYTES_PER_WORD;

    // Number of address bits required for those locations
    localparam MEM_ADDR_WIDTH = $clog2(NUM_LOCATIONS);

    // ====================================================
    // Memory array
    // ====================================================

    reg [DATA_WIDTH-1:0] memory [0:NUM_LOCATIONS-1];

    // Memory index
    //
    // For this project DATA_WIDTH = 8, therefore each
    // address points directly to one byte.
    wire [MEM_ADDR_WIDTH-1:0] mem_addr;

    assign mem_addr = addr[MEM_ADDR_WIDTH-1:0];

    // ====================================================
    // Write operation
    // ====================================================

    // Do NOT asynchronously reset the entire memory array.
    // This allows Quartus to infer FPGA block RAM.
    always @(posedge clk) begin
        if (wen) begin
            memory[mem_addr] <= wdata;
        end
    end

    // ====================================================
    // Read operation
    //
    // Synchronous read:
    // ren asserted in one cycle
    // -> rdata/rvalid become valid after the clock edge
    // ====================================================

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rdata  <= {DATA_WIDTH{1'b0}};
            rvalid <= 1'b0;
        end
        else begin

            // By default no new read result
            rvalid <= 1'b0;

            if (ren) begin
                rdata  <= memory[mem_addr];
                rvalid <= 1'b1;
            end
        end
    end

endmodule
