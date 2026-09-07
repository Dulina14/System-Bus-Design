module slave_port #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 8,
    parameter SPLIT_EN   = 0
)(
    input clk,
    input rstn,

    // ----------------------------------------------------
    // Interface to slave memory
    // ----------------------------------------------------
    input  [DATA_WIDTH-1:0] smemrdata,
    input                   rvalid,

    output                  smemwen,
    output                  smemren,
    output [ADDR_WIDTH-1:0] smemaddr,
    output [DATA_WIDTH-1:0] smemwdata,

    // ----------------------------------------------------
    // Interface to serial bus
    // ----------------------------------------------------
    input  swdata,          // Serial address/write-data bit
    output srdata,          // Serial read-data bit

    input  smode,           // 0 = read, 1 = write
    input  mvalid,          // swdata is valid

    input  split_grant,     // Arbiter allows split transaction to resume

    output svalid,          // srdata is valid
    output sready,          // Slave ready for new transaction
    output ssplit           // Split request
);

    // ====================================================
    // Internal registers
    // ====================================================

    // Reconstructed address received serially
    reg [ADDR_WIDTH-1:0] addr;

    // Reconstructed write data received serially
    reg [DATA_WIDTH-1:0] wdata;

    // Buffer used to store memory read data
    reg [DATA_WIDTH-1:0] read_buf;

    // Indicates that read_buf contains valid data
    reg read_data_ready;

    // Stored transaction mode
    reg mode;

    // Used for address/data serialization
    reg [7:0] counter;

    // ====================================================
    // Split delay
    // ====================================================

    localparam LATENCY = 4;

    reg [7:0] rcounter;

    // ====================================================
    // FSM states
    // ====================================================

    localparam IDLE   = 3'b000,
               ADDR   = 3'b001,
               RDATA  = 3'b010,
               WDATA  = 3'b011,
               SPLIT  = 3'b100,
               SREADY = 3'b101,
               WAIT   = 3'b110,
               RVALID = 3'b111;

    reg [2:0] state;
    reg [2:0] next_state;

    // ====================================================
    // Combinational outputs
    // ====================================================

    // Slave is ready only when idle
    assign sready = (state == IDLE);

    // Split request is asserted while in SPLIT state
    assign ssplit = (state == SPLIT);

    // Read-data output is valid only in RDATA state
    assign svalid = (state == RDATA);

    // Send read data serially, LSB first
    assign srdata =
        (state == RDATA) ? read_buf[counter] : 1'b0;

    // Memory always sees the reconstructed address
    assign smemaddr = addr;

    // Memory always sees reconstructed write data
    assign smemwdata = wdata;

    // Write memory during SREADY for a write transaction
    assign smemwen =
        (state == SREADY) && mode;

    // Keep read request active until read data becomes valid.
    assign smemren =
        (!mode) &&
        (!read_data_ready) &&
        (
            (state == SREADY) ||
            (state == RVALID) ||
            (state == SPLIT) ||
            (state == WAIT)
        );

    // ====================================================
    // Next-state logic
    // ====================================================

    always @(*) begin

        // Default: remain in current state
        next_state = state;

        case (state)

            // ------------------------------------------------
            // Wait for first valid address bit
            // ------------------------------------------------
            IDLE: begin
                if (mvalid)
                    next_state = ADDR;
            end

            // ------------------------------------------------
            // Receive remaining address bits
            // ------------------------------------------------
            ADDR: begin

                // Important:
                // Do not finish unless the final bit is VALID.
                if (mvalid && (counter == ADDR_WIDTH-1)) begin

                    if (mode)
                        next_state = WDATA;     // Write operation
                    else
                        next_state = SREADY;    // Read operation
                end
            end

            // ------------------------------------------------
            // Receive write data
            // ------------------------------------------------
            WDATA: begin

                // Again, last data bit must actually be valid
                if (mvalid && (counter == DATA_WIDTH-1))
                    next_state = SREADY;
            end

            // ------------------------------------------------
            // Start memory access
            // ------------------------------------------------
            SREADY: begin

                if (mode) begin
                    // Write finishes after memory access
                    next_state = IDLE;
                end
                else begin

                    if (SPLIT_EN)
                        next_state = SPLIT;
                    else
                        next_state = RVALID;
                end
            end

            // ------------------------------------------------
            // Normal read: wait for memory data
            // ------------------------------------------------
            RVALID: begin

                if (read_data_ready)
                    next_state = RDATA;
            end

            // ------------------------------------------------
            // Split response / artificial latency
            // ------------------------------------------------
            SPLIT: begin

                if (rcounter == LATENCY-1)
                    next_state = WAIT;
            end

            // ------------------------------------------------
            // Wait until arbiter allows split transaction
            // to continue AND data is available
            // ------------------------------------------------
            WAIT: begin

                if (split_grant && read_data_ready)
                    next_state = RDATA;
            end

            // ------------------------------------------------
            // Send read data serially
            // ------------------------------------------------
            RDATA: begin

                if (counter == DATA_WIDTH-1)
                    next_state = IDLE;
            end

            default:
                next_state = IDLE;

        endcase
    end

    // ====================================================
    // FSM state register
    //
    // ASYNCHRONOUS ACTIVE-LOW RESET
    // ====================================================

    always @(posedge clk or negedge rstn) begin

        if (!rstn)
            state <= IDLE;
        else
            state <= next_state;

    end

    // ====================================================
    // Datapath / counter registers
    //
    // ASYNCHRONOUS ACTIVE-LOW RESET
    // ====================================================

    always @(posedge clk or negedge rstn) begin

        if (!rstn) begin

            addr            <= {ADDR_WIDTH{1'b0}};
            wdata           <= {DATA_WIDTH{1'b0}};
            read_buf        <= {DATA_WIDTH{1'b0}};

            mode            <= 1'b0;

            counter         <= 8'd0;
            rcounter        <= 8'd0;

            read_data_ready <= 1'b0;

        end
        else begin

            case (state)

                // ============================================
                // IDLE
                // ============================================
                IDLE: begin

                    counter         <= 8'd0;
                    rcounter        <= 8'd0;
                    read_data_ready <= 1'b0;

                    // First address bit is captured here
                    if (mvalid) begin

                        mode       <= smode;
                        addr[0]    <= swdata;
                        counter    <= 8'd1;

                    end
                end

                // ============================================
                // ADDRESS RECEIVE
                // ============================================
                ADDR: begin

                    if (mvalid) begin

                        addr[counter] <= swdata;

                        if (counter == ADDR_WIDTH-1)
                            counter <= 8'd0;
                        else
                            counter <= counter + 1'b1;

                    end
                end

                // ============================================
                // WRITE DATA RECEIVE
                // ============================================
                WDATA: begin

                    if (mvalid) begin

                        wdata[counter] <= swdata;

                        if (counter == DATA_WIDTH-1)
                            counter <= 8'd0;
                        else
                            counter <= counter + 1'b1;

                    end
                end

                // ============================================
                // MEMORY ACCESS
                // ============================================
                SREADY: begin

                    // Nothing needs to be registered here.
                    //
                    // smemwen and smemren are generated
                    // combinationally from the current state.

                end

                // ============================================
                // NORMAL READ WAIT
                // ============================================
                RVALID: begin

                    if (rvalid) begin

                        read_buf        <= smemrdata;
                        read_data_ready <= 1'b1;

                    end
                end

                // ============================================
                // SPLIT
                // ============================================
                SPLIT: begin

                    // Count split latency
                    if (rcounter < LATENCY-1)
                        rcounter <= rcounter + 1'b1;

                    // Memory may finish while transaction
                    // is split, so save its result.
                    if (!read_data_ready && rvalid) begin

                        read_buf        <= smemrdata;
                        read_data_ready <= 1'b1;

                    end
                end

                // ============================================
                // WAIT FOR SPLIT GRANT
                // ============================================
                WAIT: begin

                    rcounter <= 8'd0;

                    // Memory might finish while waiting
                    if (!read_data_ready && rvalid) begin

                        read_buf        <= smemrdata;
                        read_data_ready <= 1'b1;

                    end
                end

                // ============================================
                // SEND READ DATA
                // ============================================
                RDATA: begin

                    if (counter == DATA_WIDTH-1)
                        counter <= 8'd0;
                    else
                        counter <= counter + 1'b1;

                end

                default: begin
                    // Registers automatically retain
                    // their previous values.
                end

            endcase
        end
    end

endmodule
