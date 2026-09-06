// =====================================================================
// tb_master_port.v  (v2 - matches the reference-aligned master_port.v)
// ---------------------------------------------------------------------
// Unit-level, self-checking testbench for master_port.v (Member 1).
//
// Behavioral mocks are provided for mbgrant, ack, mrdata/svalid and
// msplit so master_port can be verified in isolation:
//
//   TEST 1 - Reset test (async reset works from any state)
//   TEST 2 - Single WRITE transaction, normal bus grant
//   TEST 3 - Single READ  transaction, normal bus grant
//   TEST 4 - Master correctly WAITS for a delayed bus grant
//   TEST 5 - WAIT state times out to IDLE when ack never arrives
//   TEST 6 - READ transaction interrupted by a SPLIT, then resumed
//            (mbreq stays asserted throughout, per the reference design)
//
// Serial output (mwdata while mvalid) is captured using hierarchical
// references to the DUT's internal state/counter - normal practice for
// white-box verification code.
// =====================================================================
`timescale 1ns/1ps

module tb_master_port;

    localparam ADDR_WIDTH           = 16;
    localparam DATA_WIDTH           = 8;
    localparam SLAVE_MEM_ADDR_WIDTH = 12;
    localparam SLAVE_DEV_WIDTH      = ADDR_WIDTH - SLAVE_MEM_ADDR_WIDTH; // 4
    localparam TIMEOUT_TIME         = 5;
    localparam CLK_PERIOD           = 10;

    reg                     clk;
    reg                     rstn;

    reg  [DATA_WIDTH-1:0]   dwdata;
    wire [DATA_WIDTH-1:0]   drdata;
    reg  [ADDR_WIDTH-1:0]   daddr;
    reg                     dvalid;
    wire                    dready;
    reg                     dmode;

    wire                    mrdata;
    wire                    mwdata;
    wire                    mmode;
    wire                    mvalid;
    reg                     svalid;

    wire                    mbreq;
    reg                     mbgrant;
    reg                     msplit;

    reg                     ack;

    integer pass_count = 0;
    integer fail_count = 0;
    reg [ADDR_WIDTH-1:0] split_addr;

    master_port #(
        .ADDR_WIDTH          (ADDR_WIDTH),
        .DATA_WIDTH          (DATA_WIDTH),
        .SLAVE_MEM_ADDR_WIDTH(SLAVE_MEM_ADDR_WIDTH),
        .TIMEOUT_TIME        (TIMEOUT_TIME)
    ) uut (
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
    // Clock
    // -----------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -----------------------------------------------------------------
    // Automatic address-decoder ACK model: pulses ack two cycles after
    // mvalid falls following the SADDR phase (approximates decoder
    // latency). Suppressed entirely when `ack_enabled` is 0, so TEST 5
    // can exercise the no-ack timeout path.
    // -----------------------------------------------------------------
    reg mvalid_d;
    reg ack_enabled;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            mvalid_d <= 1'b0;
            ack      <= 1'b0;
        end else begin
            mvalid_d <= mvalid;
            ack      <= 1'b0;
            if (ack_enabled && mvalid_d && !mvalid && uut.state == uut.WAIT)
                ack <= 1'b1;
        end
    end

    // -----------------------------------------------------------------
    // Serial-output capture (address bits) via hierarchical state.
    // Bits arrive LSB-first, so shift new bits in at the TOP and shift
    // right, ending with the field reconstructed in natural bit order.
    // -----------------------------------------------------------------
    reg [SLAVE_DEV_WIDTH-1:0]       cap_saddr;
    reg [SLAVE_MEM_ADDR_WIDTH-1:0]  cap_addr;
    reg [DATA_WIDTH-1:0]            cap_wdata;

    reg [ADDR_WIDTH:0] idx_saddr, idx_addr, idx_wdata;
    reg [2:0] state_q1, state_q2; // state_q1 = state that produced THIS sample's
                                   // mwdata/mvalid (mwdata/mvalid are themselves
                                   // registered, so they lag "uut.state" by one
                                   // cycle - state_q1 undoes that lag).

    initial begin
        idx_saddr = 0; idx_addr = 0; idx_wdata = 0;
        state_q1 = 3'b0; state_q2 = 3'b0;
    end

    always @(posedge clk) begin
        #1; // sample after NBA updates settle
        if (state_q1 != state_q2) begin
            idx_saddr = 0; idx_addr = 0; idx_wdata = 0;
        end
        if (state_q1 == uut.SADDR && mvalid) begin
            cap_saddr[idx_saddr] = mwdata;
            idx_saddr = idx_saddr + 1;
        end
        if (state_q1 == uut.ADDR && mvalid) begin
            cap_addr[idx_addr] = mwdata;
            idx_addr = idx_addr + 1;
        end
        if (state_q1 == uut.WDATA && mvalid) begin
            cap_wdata[idx_wdata] = mwdata;
            idx_wdata = idx_wdata + 1;
        end
        state_q2 = state_q1;
        state_q1 = uut.state;
    end

    // -----------------------------------------------------------------
    // Drive mrdata/svalid (read-data-in) from an expected pattern
    // whenever the DUT is in RDATA, LSB first - combinationally, keyed
    // off the DUT's own bit counter so it's stable exactly when sampled.
    // -----------------------------------------------------------------
    reg [DATA_WIDTH-1:0] read_pattern;
    reg                  read_drive_en; // testbench can stall svalid

    assign mrdata = (uut.state == uut.RDATA) ? read_pattern[uut.counter] : 1'b0;
    always @(*) svalid = (uut.state == uut.RDATA) ? read_drive_en : 1'b0;

    // -----------------------------------------------------------------
    // Checking helpers
    // -----------------------------------------------------------------
    task check_equal(input [255:0] name, input [31:0] exp, input [31:0] act);
        begin
            if (exp === act) begin
                pass_count = pass_count + 1;
                $display("  [PASS] %0s : expected=0x%0h got=0x%0h", name, exp, act);
            end else begin
                fail_count = fail_count + 1;
                $display("  [FAIL] %0s : expected=0x%0h got=0x%0h", name, exp, act);
            end
        end
    endtask

    task wait_dready(input integer timeout_cycles);
        integer i;
        begin
            i = 0;
            while (!dready && i < timeout_cycles) begin
                @(posedge clk);
                i = i + 1;
            end
            if (i >= timeout_cycles) begin
                fail_count = fail_count + 1;
                $display("  [FAIL] Timeout waiting for dready");
            end
        end
    endtask

    task apply_reset;
        begin
            rstn = 1'b0;
            dvalid = 1'b0; dmode = 1'b0; daddr = 0; dwdata = 0;
            mbgrant = 1'b0; msplit = 1'b0; read_drive_en = 1'b0;
            ack_enabled = 1'b1;
            repeat (3) @(posedge clk);
            rstn = 1'b1;
            @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------
    // Issue one transaction, grant after `grant_delay` cycles
    // -----------------------------------------------------------------
    task do_transaction(
        input                          is_write,
        input [ADDR_WIDTH-1:0]         addr,
        input [DATA_WIDTH-1:0]         wdata,
        input [DATA_WIDTH-1:0]         rdata_expect,
        input integer                  grant_delay
    );
        integer d;
        begin
            cap_saddr = 0;
            cap_addr  = 0;
            cap_wdata = 0;
            read_pattern  = rdata_expect;
            read_drive_en = 1'b1;

            @(posedge clk);
            dvalid <= 1'b1;
            dmode  <= is_write;
            daddr  <= addr;
            dwdata <= wdata;
            @(posedge clk);
            dvalid <= 1'b0;

            #1;
            if (grant_delay > 1)
                check_equal("mbreq asserted while waiting for grant", 1, mbreq);
            for (d = 0; d < grant_delay; d = d + 1) @(posedge clk);
            mbgrant <= 1'b1;

            wait_dready(300);
            #1;

            check_equal("captured slave-select bits", addr[ADDR_WIDTH-1:SLAVE_MEM_ADDR_WIDTH], cap_saddr);
            check_equal("captured local address",     addr[SLAVE_MEM_ADDR_WIDTH-1:0], cap_addr);
            if (is_write)
                check_equal("captured write data", wdata, cap_wdata);
            else
                check_equal("drdata", rdata_expect, drdata);
            check_equal("mbreq released after done", 0, mbreq);

            @(posedge clk);
            mbgrant <= 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------
    initial begin
        $dumpfile("tb_master_port.vcd");
        $dumpvars(0, tb_master_port);

        $display("=====================================================");
        $display(" master_port.v (v2) self-checking testbench");
        $display("=====================================================");

        // ---------------- TEST 1 : Reset test --------------------------
        $display("\n-- TEST 1: Reset test --");
        apply_reset;
        check_equal("state == IDLE after reset", uut.IDLE, uut.state);
        check_equal("mbreq low after reset",  0, mbreq);
        check_equal("dready high after reset", 1, dready);

        // Kick off a transaction, then reset MID-transaction.
        dvalid <= 1'b1; dmode <= 1'b1; daddr <= 16'h2123; dwdata <= 8'h55;
        @(posedge clk); dvalid <= 1'b0;
        @(posedge clk); mbgrant <= 1'b1;
        repeat (3) @(posedge clk); // now somewhere mid-SADDR
        rstn = 1'b0;               // async reset asserted between clock edges
        #1;
        check_equal("state == IDLE immediately after async reset", uut.IDLE, uut.state);
        check_equal("mbreq low immediately after async reset", 0, mbreq);
        rstn = 1'b1;
        mbgrant <= 1'b0;
        @(posedge clk);

        // ---------------- TEST 2 : Single WRITE -------------------------
        $display("\n-- TEST 2: Single WRITE transaction --");
        do_transaction(1'b1, 16'h3AB2, 8'h5A, 8'h00, 1);

        // ---------------- TEST 3 : Single READ --------------------------
        $display("\n-- TEST 3: Single READ transaction --");
        do_transaction(1'b0, 16'h10F0, 8'h00, 8'hC3, 1);

        // ---------------- TEST 4 : Wait for delayed bus grant -----------
        $display("\n-- TEST 4: Master waits for a delayed bus grant --");
        do_transaction(1'b1, 16'h7555, 8'h99, 8'h00, 6);

        // ---------------- TEST 5 : WAIT-state ack timeout -----------------
        $display("\n-- TEST 5: WAIT state times out when ack never arrives --");
        begin
            ack_enabled = 1'b0; // address decoder will never ack
            @(posedge clk);
            dvalid <= 1'b1; dmode <= 1'b0; daddr <= 16'h9111;
            @(posedge clk);
            dvalid <= 1'b0;
            mbgrant <= 1'b1;

            wait (uut.state == uut.WAIT);
            // must return to IDLE within TIMEOUT_TIME cycles of entering WAIT
            wait_dready(TIMEOUT_TIME + 5);
            #1;
            check_equal("state == IDLE after ack timeout", uut.IDLE, uut.state);
            check_equal("mbreq released after timeout-abort", 0, mbreq);

            @(posedge clk);
            mbgrant <= 1'b0;
            ack_enabled = 1'b1;
            repeat (2) @(posedge clk);
        end

        // ---------------- TEST 6 : Split-transaction interruption -------
        $display("\n-- TEST 6: Read interrupted by SPLIT, then resumed --");
        begin
            cap_saddr = 0; cap_addr = 0;
            read_pattern  = 8'h7E;
            read_drive_en = 1'b1;
            split_addr    = 16'h5333;

            @(posedge clk);
            dvalid <= 1'b1; dmode <= 1'b0; daddr <= split_addr;
            @(posedge clk);
            dvalid <= 1'b0;
            mbgrant <= 1'b1;

            // as soon as RDATA begins, the slave/arbiter raises msplit
            wait (uut.state == uut.ADDR && uut.counter == SLAVE_MEM_ADDR_WIDTH-1);
            msplit <= 1'b1;
            @(posedge clk); // -> RDATA, samples msplit high -> next cycle SPLIT
            #1;

            wait (uut.state == uut.SPLIT);
            check_equal("mbreq stays asserted while parked in SPLIT", 1, mbreq);
            check_equal("mbgrant still held during SPLIT (arbiter's choice)", 1, mbgrant);

            // hold split for a few cycles ("slave" still busy)
            repeat (4) @(posedge clk);

            // arbiter/slave finish: msplit drops while mbgrant is (re)present
            msplit <= 1'b0;
            @(posedge clk); // master sees (!msplit && mbgrant) -> RDATA
            #1;
            check_equal("state == RDATA after split resume", uut.RDATA, uut.state);

            wait_dready(300);
            #1;

            check_equal("captured slave-select bits (split)", split_addr[15:12], cap_saddr);
            check_equal("captured local address (split)",     split_addr[11:0], cap_addr);
            check_equal("drdata after split resume", 8'h7E, drdata);

            @(posedge clk);
            mbgrant <= 1'b0;
        end

        // ---------------- Summary ---------------------------------------
        $display("\n=====================================================");
        $display(" RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("=====================================================");
        if (fail_count == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" *** %0d TEST(S) FAILED ***", fail_count);

        #(CLK_PERIOD*5);
        $finish;
    end

    // Safety timeout
    initial begin
        #200000;
        $display("[ERROR] Global testbench timeout - simulation hung");
        $finish;
    end

endmodule
