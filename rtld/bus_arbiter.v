`timescale 1ns/1ps

// Fixed-priority arbiter for two masters and three slaves.
// Master 1 has priority when both masters request an idle bus.
// Slave 3 is the only split-capable slave.
module bus_arbiter (
    input  wire clk,
    input  wire reset_n,

    input  wire master1_request,
    input  wire master2_request,

    input  wire slave1_ready,
    input  wire slave2_ready,
    input  wire split_slave_ready,
    input  wire split_request,

    output wire master1_grant,
    output wire master2_grant,
    output wire selected_master,
    output reg  master1_split,
    output reg  master2_split,
    output reg  split_resume
);

    localparam [1:0] STATE_IDLE = 2'd0,
                     STATE_M1   = 2'd1,
                     STATE_M2   = 2'd2;

    localparam [1:0] OWNER_NONE = 2'd0,
                     OWNER_M1   = 2'd1,
                     OWNER_M2   = 2'd2;

    reg [1:0] state;
    reg [1:0] next_state;
    reg [1:0] split_owner;

    wire all_slaves_ready;
    wire normal_slaves_ready;

    assign all_slaves_ready    = slave1_ready & slave2_ready & split_slave_ready;
    assign normal_slaves_ready = slave1_ready & slave2_ready;

    assign master1_grant  = (state == STATE_M1);
    assign master2_grant  = (state == STATE_M2);
    assign selected_master = (state == STATE_M2);

    // Decide which master owns the next bus cycle.
    always @(*) begin
        next_state = state;

        case (state)
            STATE_IDLE: begin
                if (split_owner != OWNER_NONE) begin
                    if (!split_request) begin
                        // A completed split transaction is resumed before a new one.
                        if ((split_owner == OWNER_M1) && master1_request)
                            next_state = STATE_M1;
                        else if ((split_owner == OWNER_M2) && master2_request)
                            next_state = STATE_M2;
                        else
                            next_state = STATE_IDLE;
                    end
                    else begin
                        // While Slave 3 is busy, the other master may use Slaves 1 or 2.
                        if ((split_owner == OWNER_M1) && master2_request && normal_slaves_ready)
                            next_state = STATE_M2;
                        else if ((split_owner == OWNER_M2) && master1_request && normal_slaves_ready)
                            next_state = STATE_M1;
                        else
                            next_state = STATE_IDLE;
                    end
                end
                else if (master1_request && all_slaves_ready) begin
                    next_state = STATE_M1;
                end
                else if (master2_request && all_slaves_ready) begin
                    next_state = STATE_M2;
                end
                else begin
                    next_state = STATE_IDLE;
                end
            end

            STATE_M1: begin
                if (!master1_request)
                    next_state = STATE_IDLE;
                else if ((split_owner == OWNER_NONE) && split_request)
                    next_state = STATE_IDLE;
                else
                    next_state = STATE_M1;
            end

            STATE_M2: begin
                if (!master2_request)
                    next_state = STATE_IDLE;
                else if ((split_owner == OWNER_NONE) && split_request)
                    next_state = STATE_IDLE;
                else
                    next_state = STATE_M2;
            end

            default: next_state = STATE_IDLE;
        endcase
    end

    // State and split bookkeeping use the assignment-required asynchronous reset.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= STATE_IDLE;
            split_owner   <= OWNER_NONE;
            master1_split <= 1'b0;
            master2_split <= 1'b0;
            split_resume  <= 1'b0;
        end
        else begin
            state        <= next_state;
            split_resume <= 1'b0; // default: split_resume is a one-clock pulse

            // Cancel a saved split if its master abandons the request.
            if ((split_owner == OWNER_M1) && !master1_request) begin
                split_owner   <= OWNER_NONE;
                master1_split <= 1'b0;
            end
            else if ((split_owner == OWNER_M2) && !master2_request) begin
                split_owner   <= OWNER_NONE;
                master2_split <= 1'b0;
            end
            // Record a new split against the master that currently owns the bus.
            else if ((state == STATE_M1) && (split_owner == OWNER_NONE) && split_request) begin
                split_owner   <= OWNER_M1;
                master1_split <= 1'b1;
            end
            else if ((state == STATE_M2) && (split_owner == OWNER_NONE) && split_request) begin
                split_owner   <= OWNER_M2;
                master2_split <= 1'b1;
            end
            // When the split slave is ready, restore the interrupted owner.
            else if ((state == STATE_IDLE) &&
                     (split_owner == OWNER_M1) &&
                     !split_request && master1_request &&
                     (next_state == STATE_M1)) begin
                split_owner   <= OWNER_NONE;
                master1_split <= 1'b0;
                split_resume  <= 1'b1;
            end
            else if ((state == STATE_IDLE) &&
                     (split_owner == OWNER_M2) &&
                     !split_request && master2_request &&
                     (next_state == STATE_M2)) begin
                split_owner   <= OWNER_NONE;
                master2_split <= 1'b0;
                split_resume  <= 1'b1;
            end
        end
    end

endmodule
