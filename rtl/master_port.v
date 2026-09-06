--------------
//   1. ASYNC RESET (required by our assignment; the reference project's
//      master_port only resets synchronously: `state <= (!rstn) ?
//      IDLE : next_state;` inside `always @(posedge clk)`. Everything
//      here now lives in `always @(posedge clk or negedge rstn)`.)
//   2. Everything else (port names, the ADDR_WIDTH / SLAVE_MEM_ADDR_WIDTH
//      parameterisation, the state names/encodings, the LSB-first serial
//      shifting, the WAIT/ack timeout, and the split-transaction
//      handling via msplit/mbgrant only - no extra "parked" output) is
//      kept IDENTICAL to the reference so it drops straight into a
//      bus_structure / arbiter / addr_decoder built the same way the
//      reference project builds them.
//   3. Default parameters (ADDR_WIDTH=16, SLAVE_MEM_ADDR_WIDTH=12) give
//      SLAVE_DEVICE_ADDR_WIDTH = 4, i.e. a 4-bit slave-select field +
//      12-bit local address - matching our own earlier project note
//      ("send a four-bit slave ID, then a twelve-bit local address").
//      We are NOT using the bus-bridge feature from the reference
//      report (out of scope for our 2-master/3-slave assignment); the
//      wider default merely gives head-room (16 possible slave codes,
//      we only decode 3 of them in addr_decoder).
//
// FUNCTIONAL DESCRIPTION
// -----------------------------------------------------------------
//   Local (parallel) side uses a ready/valid handshake:
//     - the device drives daddr/dwdata/dmode and pulses dvalid
//     - master_port is ready for a new request whenever dready is high
//     - drdata is valid the cycle dready returns high after a read
//
//   Once dvalid is seen, master_port:
//     REQ    - asserts mbreq and waits for mbgrant
//     SADDR  - serially shifts out the top SLAVE_DEVICE_ADDR_WIDTH bits
//              of the address (the slave-select bits), LSB of that
//              field first, one bit per clock while mvalid is high
//     WAIT   - waits for the address decoder's `ack`. If ack does not
//              arrive within TIMEOUT_TIME cycles the transaction is
//              abandoned (invalid address / slave busy) and the master
//              returns to IDLE.
//     ADDR   - serially shifts out the low SLAVE_MEM_ADDR_WIDTH bits of
//              the address (the local address inside the slave), LSB
//              first
//     WDATA  - (write) serially shifts out DATA_WIDTH write-data bits
//     RDATA  - (read) serially shifts in DATA_WIDTH read-data bits,
//              gated by svalid (a bit is only captured, and the counter
//              only advances, on cycles where svalid is high)
//     SPLIT  - entered if the addressed slave raises msplit as soon as
//              RDATA begins. mbreq is kept asserted throughout (the
//              arbiter is responsible for granting the bus to the OTHER
//              master while this one is parked, and for eventually
//              re-granting mbgrant to THIS master together with msplit
//              going low); once (!msplit && mbgrant), we resume in
//              RDATA - the address is NOT resent.
//
// RESET / CLOCK
// -----------------------------------------------------------------
//   rstn : asynchronous, ACTIVE LOW.
//   clk  : all sequential logic is posedge-triggered only.
//
// IO DEFINITION
// -----------------------------------------------------------------
//  Local (parallel) side -- device / demo_master.v / testbench
//    clk, rstn     in    clock, async active-low reset
//    daddr         in    [ADDR_WIDTH-1:0]  address for the transaction
//    dwdata        in    [DATA_WIDTH-1:0]  write data
//    dmode         in    0 = read, 1 = write
//    dvalid        in    daddr/dwdata/dmode are valid; start transaction
//    drdata        out   [DATA_WIDTH-1:0]  data from a read transaction
//    dready        out   master_port is idle and ready for a new request
//
//  Serial bus side -- to Member 2's arbiter / mux / addr_decoder
//    mwdata        out   serial data output (slave-select/addr/wdata)
//    mvalid        out   mwdata is valid this cycle
//    mmode         out   0 = read, 1 = write (mirrors dmode for the
//                         duration of the transaction)
//    mrdata        in    serial data input (read data from slave)
//    svalid        in    mrdata is valid this cycle
//    mbreq         out   request the shared bus
//    mbgrant       in    arbiter grants the bus to this master
//    msplit        in    the slave currently being read from has split
//    ack           in    address decoder acknowledges a valid slave
//                         address (ends WAIT); if this never arrives,
//                         the transaction times out back to IDLE
// =====================================================================

module master_port #(
    parameter ADDR_WIDTH          = 16,
    parameter DATA_WIDTH          = 8,
    parameter SLAVE_MEM_ADDR_WIDTH = 12,
    parameter TIMEOUT_TIME        = 5
)(
    input  wire                   clk,
    input  wire                   rstn,       // async active-low reset

    // ---------------- local (parallel) side ---------------------------
    input  wire [DATA_WIDTH-1:0]  dwdata,     // write data
    output wire [DATA_WIDTH-1:0]  drdata,     // read data
    input  wire [ADDR_WIDTH-1:0]  daddr,
    input  wire                   dvalid,     // ready/valid interface
    output wire                   dready,
    input  wire                   dmode,      // 0 = read, 1 = write

    // ---------------- serial bus side ---------------------------------
    input  wire                   mrdata,     // read data (serial in)
    output reg                    mwdata,     // write data / address (serial out)
    output wire                   mmode,      // 0 = read, 1 = write
    output reg                    mvalid,     // mwdata valid
    input  wire                   svalid,     // mrdata valid

    // ---------------- arbiter side -------------------------------------
    output wire                   mbreq,
    input  wire                   mbgrant,
    input  wire                   msplit,

    // ---------------- address-decoder side ------------------------------
    input  wire                   ack
);

    localparam SLAVE_DEVICE_ADDR_WIDTH = ADDR_WIDTH - SLAVE_MEM_ADDR_WIDTH;

    // -----------------------------------------------------------------
    // Internal registers (mirrors dwdata/daddr/dmode for the duration
    // of the transaction, and the read-data accumulator)
    // -----------------------------------------------------------------
    reg [DATA_WIDTH-1:0] wdata;
    reg [ADDR_WIDTH-1:0] addr;
    reg                  mode;
    reg [DATA_WIDTH-1:0] rdata;

    // counters
    reg [7:0] counter, timeout;

    // -----------------------------------------------------------------
    // States (identical encoding to the reference project)
    // -----------------------------------------------------------------
    localparam [2:0]
        IDLE  = 3'b000,
        ADDR  = 3'b001,   // send local slave-memory address
        RDATA = 3'b010,   // read data from slave
        WDATA = 3'b011,   // write data to slave
        REQ   = 3'b100,   // request bus access
        SADDR = 3'b101,   // send slave-select address bits
        WAIT  = 3'b110,   // wait for address-decoder ack
        SPLIT = 3'b111;   // wait for a split slave to become ready

    reg [2:0] state, next_state;

    // -----------------------------------------------------------------
    // Next-state logic (combinational)
    // -----------------------------------------------------------------
    always @(*) begin
        case (state)
            IDLE  : next_state = (dvalid)  ? REQ  : IDLE;
            REQ   : next_state = (mbgrant) ? SADDR: REQ;
            SADDR : next_state = (counter == SLAVE_DEVICE_ADDR_WIDTH-1) ? WAIT : SADDR;
            WAIT  : next_state = (ack) ? ADDR : ((timeout == TIMEOUT_TIME) ? IDLE : WAIT);
            ADDR  : next_state = (counter == SLAVE_MEM_ADDR_WIDTH-1) ?
                                    ((mode) ? WDATA : RDATA) : ADDR;
            RDATA : next_state = (msplit) ? SPLIT :
                                    ((svalid && (counter == DATA_WIDTH-1)) ? IDLE : RDATA);
            WDATA : next_state = (counter == DATA_WIDTH-1) ? IDLE : WDATA;
            SPLIT : next_state = (!msplit && mbgrant) ? RDATA : SPLIT;
            default: next_state = IDLE;
        endcase
    end

    // -----------------------------------------------------------------
    // State register - ASYNC active-low reset (our assignment's
    // requirement; the reference project used a synchronous reset here)
    // -----------------------------------------------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) state <= IDLE;
        else       state <= next_state;
    end

    // -----------------------------------------------------------------
    // Combinational output assignments
    // -----------------------------------------------------------------
    assign dready = (state == IDLE);
    assign drdata = rdata;
    assign mmode  = mode;
    assign mbreq  = (state != IDLE); // keep requesting while the master
                                      // needs the bus (including SPLIT -
                                      // the arbiter, not this module,
                                      // decides who else gets the bus
                                      // meanwhile)

    // -----------------------------------------------------------------
    // Sequential datapath - ASYNC active-low reset
    // -----------------------------------------------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            wdata   <= {DATA_WIDTH{1'b0}};
            rdata   <= {DATA_WIDTH{1'b0}};
            addr    <= {ADDR_WIDTH{1'b0}};
            mode    <= 1'b0;
            counter <= 8'b0;
            mvalid  <= 1'b0;
            mwdata  <= 1'b0;
            timeout <= 8'b0;
        end else begin
            case (state)
                // -------------------------------------------------
                IDLE : begin
                    counter <= 8'b0;
                    mvalid  <= 1'b0;
                    timeout <= 8'b0;
                    if (dvalid) begin // latch the new transaction
                        wdata <= dwdata;
                        addr  <= daddr;
                        mode  <= dmode;
                    end
                end

                // -------------------------------------------------
                REQ : begin
                    // nothing to do but wait for mbgrant
                end

                // -------------------------------------------------
                SADDR : begin // send slave-select (device) address bits
                    mwdata <= addr[SLAVE_MEM_ADDR_WIDTH + counter];
                    mvalid <= 1'b1;
                    if (counter == SLAVE_DEVICE_ADDR_WIDTH-1)
                        counter <= 8'b0;
                    else
                        counter <= counter + 1'b1;
                end

                // -------------------------------------------------
                WAIT : begin
                    mvalid  <= 1'b0;
                    timeout <= timeout + 1'b1;
                end

                // -------------------------------------------------
                ADDR : begin // send local slave-memory address bits
                    mwdata <= addr[counter];
                    mvalid <= 1'b1;
                    if (counter == SLAVE_MEM_ADDR_WIDTH-1)
                        counter <= 8'b0;
                    else
                        counter <= counter + 1'b1;
                end

                // -------------------------------------------------
                RDATA : begin // receive data from slave (valid-gated)
                    mvalid <= 1'b0;
                    if (svalid) begin
                        rdata[counter] <= mrdata;
                        if (counter == DATA_WIDTH-1)
                            counter <= 8'b0;
                        else
                            counter <= counter + 1'b1;
                    end
                end

                // -------------------------------------------------
                WDATA : begin // send data to slave
                    mwdata <= wdata[counter];
                    mvalid <= 1'b1;
                    if (counter == DATA_WIDTH-1)
                        counter <= 8'b0;
                    else
                        counter <= counter + 1'b1;
                end

                // -------------------------------------------------
                SPLIT : begin // wait for the slave / arbiter
                    mvalid <= 1'b0;
                end

                default: begin
                    mvalid <= 1'b0;
                end
            endcase
        end
    end

endmodule
