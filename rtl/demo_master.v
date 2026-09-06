// =====================================================================
// demo_master.v   (v2 - matches the v2 master_port.v interface)
// ---------------------------------------------------------------------
// EN4021 - Serial Bus Assignment : Member 1 module
//
// Thin front-end that instantiates master_port and generates its
// dvalid/dmode/daddr/dwdata stimulus, so a single master can be
// demonstrated stand-alone on the DE0 board (or driven quickly in
// simulation without writing a full testbench).
//
//   DEMO_MODE = "MANUAL" (default) -> intended for Master 1.
//       KEY[0]  : async active-low reset                -> rstn
//       KEY[1]  : press to issue ONE transaction         (debounced +
//                 edge detected internally into a single dvalid pulse)
//       SW[9]   : 0 = read , 1 = write                    -> dmode
//       SW[8:5] : slave-select nibble                      -> daddr[15:12]
//       SW[4:0] : low 5 bits of the local address (rest = 0) -> daddr[4:0]
//       dwdata  : fixed demo pattern (WDATA_PATTERN)
//       LEDR[7:0] : last drdata
//       LEDR[8]   : busy indicator (~dready while a transaction runs)
//       LEDR[9]   : done indicator (latched until the next KEY[1] press)
//
//   DEMO_MODE = "AUTO" -> intended for Master 2 (or a quick smoke test).
//       Ignores KEY[1]/SW and free-runs a write-then-read-back sequence
//       to a fixed address every AUTO_PERIOD clock cycles.
// =====================================================================

module demo_master #(
    parameter ADDR_WIDTH           = 16,
    parameter DATA_WIDTH           = 8,
    parameter SLAVE_MEM_ADDR_WIDTH = 12,
    parameter [DATA_WIDTH-1:0] WDATA_PATTERN = 8'hA5,
    parameter [ADDR_WIDTH-1:0] AUTO_ADDR     = 16'h0010,
    parameter AUTO_PERIOD           = 200,     // clocks between AUTO transactions
    parameter DEMO_MODE             = "MANUAL" // "MANUAL" or "AUTO"
)(
    input  wire        clk,
    input  wire        KEY0_n,      // board reset button (active low)
    input  wire        KEY1_n,      // board start button (active low)
    input  wire [9:0]  SW,          // board switches

    output wire [9:0]  LEDR,

    // ---- pass-through to the shared serial bus (Member 2's fabric) ----
    output wire        mwdata,
    output wire        mvalid,
    output wire        mmode,
    input  wire        mrdata,
    input  wire        svalid,
    output wire        mbreq,
    input  wire        mbgrant,
    input  wire        msplit,
    input  wire        ack
);

    wire rstn = KEY0_n;

    // -----------------------------------------------------------------
    // KEY1 debounce + rising-edge detect -> single dvalid pulse
    // -----------------------------------------------------------------
    reg [15:0] deb_sr;
    reg        key1_clean, key1_clean_d;
    wire       key1_pressed_edge;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            deb_sr       <= 16'h0000;
            key1_clean   <= 1'b0;
            key1_clean_d <= 1'b0;
        end else begin
            deb_sr <= {deb_sr[14:0], ~KEY1_n};  // active-low button -> active-high level
            if (&deb_sr)       key1_clean <= 1'b1;
            else if (~|deb_sr) key1_clean <= 1'b0;
            key1_clean_d <= key1_clean;
        end
    end
    assign key1_pressed_edge = key1_clean & ~key1_clean_d;

    // -----------------------------------------------------------------
    // AUTO mode free-running period counter
    // -----------------------------------------------------------------
    reg [31:0] auto_cnt;
    reg        auto_pulse;
    reg        auto_mode_toggle;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            auto_cnt         <= 32'd0;
            auto_pulse       <= 1'b0;
            auto_mode_toggle <= 1'b1; // start with a WRITE, then alternate
        end else begin
            auto_pulse <= 1'b0;
            if (auto_cnt == AUTO_PERIOD-1) begin
                auto_cnt         <= 32'd0;
                auto_pulse       <= 1'b1;
                auto_mode_toggle <= ~auto_mode_toggle;
            end else begin
                auto_cnt <= auto_cnt + 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------
    // Stimulus mux: MANUAL vs AUTO
    // -----------------------------------------------------------------
    wire                   dvalid;
    wire                   dmode;
    wire [ADDR_WIDTH-1:0]  daddr;
    wire [DATA_WIDTH-1:0]  dwdata;

    generate
        if (DEMO_MODE == "AUTO") begin : g_auto
            assign dvalid = auto_pulse;
            assign dmode  = auto_mode_toggle;
            assign daddr  = AUTO_ADDR;
            assign dwdata = WDATA_PATTERN;
        end else begin : g_manual
            assign dvalid = key1_pressed_edge;
            assign dmode  = SW[9];
            assign daddr  = { SW[8:5], {(ADDR_WIDTH-9){1'b0}}, SW[4:0] };
            assign dwdata = WDATA_PATTERN;
        end
    endgenerate

    // -----------------------------------------------------------------
    // Core master
    // -----------------------------------------------------------------
    wire [DATA_WIDTH-1:0] drdata;
    wire                  dready;

    master_port #(
        .ADDR_WIDTH          (ADDR_WIDTH),
        .DATA_WIDTH          (DATA_WIDTH),
        .SLAVE_MEM_ADDR_WIDTH(SLAVE_MEM_ADDR_WIDTH)
    ) u_master_port (
        .clk    (clk),
        .rstn   (rstn),

        .dwdata (dwdata),
        .drdata (drdata),
        .daddr  (daddr),
        .dvalid (dvalid),
        .dready (dready),
        .dmode  (dmode),

        .mrdata (mrdata),
        .mwdata (mwdata),
        .mmode  (mmode),
        .mvalid (mvalid),
        .svalid (svalid),

        .mbreq  (mbreq),
        .mbgrant(mbgrant),
        .msplit (msplit),

        .ack    (ack)
    );

    // -----------------------------------------------------------------
    // Status LEDs: latch "done" until the next transaction starts.
    // "done" = dready rising again after having gone busy.
    // -----------------------------------------------------------------
    reg [DATA_WIDTH-1:0] rdata_latch;
    reg                  done_latch;
    reg                  dready_d;
    reg                  busy_latch;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rdata_latch <= {DATA_WIDTH{1'b0}};
            done_latch  <= 1'b0;
            dready_d    <= 1'b1;
            busy_latch  <= 1'b0;
        end else begin
            dready_d <= dready;
            if (dvalid) begin
                done_latch <= 1'b0;
                busy_latch <= 1'b1;
            end
            if (dready && !dready_d) begin // just became ready again -> done
                rdata_latch <= drdata;
                done_latch  <= 1'b1;
                busy_latch  <= 1'b0;
            end
        end
    end

    assign LEDR[7:0] = rdata_latch;
    assign LEDR[8]   = busy_latch;
    assign LEDR[9]   = done_latch;

endmodule
