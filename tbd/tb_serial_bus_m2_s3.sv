`timescale 1ns/1ps

module tb_serial_bus_m2_s3;

    localparam ADDR_WIDTH = 16;
    localparam DATA_WIDTH = 8;
    localparam SLAVE_MEM_ADDR_WIDTH = 12;
    localparam DEVICE_ADDR_WIDTH = ADDR_WIDTH - SLAVE_MEM_ADDR_WIDTH;

    reg clk;
    reg reset_n;

    reg  m1_wdata;
    reg  m1_mode;
    reg  m1_mvalid;
    reg  m1_breq;
    wire m1_rdata;
    wire m1_svalid;
    wire m1_bgrant;
    wire m1_ack;
    wire m1_split;

    reg  m2_wdata;
    reg  m2_mode;
    reg  m2_mvalid;
    reg  m2_breq;
    wire m2_rdata;
    wire m2_svalid;
    wire m2_bgrant;
    wire m2_ack;
    wire m2_split;

    reg  s1_rdata;
    reg  s1_svalid;
    reg  s1_ready;
    wire s1_wdata;
    wire s1_mode;
    wire s1_mvalid;

    reg  s2_rdata;
    reg  s2_svalid;
    reg  s2_ready;
    wire s2_wdata;
    wire s2_mode;
    wire s2_mvalid;

    reg  s3_rdata;
    reg  s3_svalid;
    reg  s3_ready;
    reg  s3_split;
    wire s3_wdata;
    wire s3_mode;
    wire s3_mvalid;

    wire split_grant;

    integer error_count;
    integer bit_index;

    serial_bus_m2_s3 #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SLAVE_MEM_ADDR_WIDTH(SLAVE_MEM_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),

        .m1_rdata(m1_rdata),
        .m1_wdata(m1_wdata),
        .m1_mode(m1_mode),
        .m1_mvalid(m1_mvalid),
        .m1_svalid(m1_svalid),
        .m1_breq(m1_breq),
        .m1_bgrant(m1_bgrant),
        .m1_ack(m1_ack),
        .m1_split(m1_split),

        .m2_rdata(m2_rdata),
        .m2_wdata(m2_wdata),
        .m2_mode(m2_mode),
        .m2_mvalid(m2_mvalid),
        .m2_svalid(m2_svalid),
        .m2_breq(m2_breq),
        .m2_bgrant(m2_bgrant),
        .m2_ack(m2_ack),
        .m2_split(m2_split),

        .s1_rdata(s1_rdata),
        .s1_wdata(s1_wdata),
        .s1_mode(s1_mode),
        .s1_mvalid(s1_mvalid),
        .s1_svalid(s1_svalid),
        .s1_ready(s1_ready),

        .s2_rdata(s2_rdata),
        .s2_wdata(s2_wdata),
        .s2_mode(s2_mode),
        .s2_mvalid(s2_mvalid),
        .s2_svalid(s2_svalid),
        .s2_ready(s2_ready),

        .s3_rdata(s3_rdata),
        .s3_wdata(s3_wdata),
        .s3_mode(s3_mode),
        .s3_mvalid(s3_mvalid),
        .s3_svalid(s3_svalid),
        .s3_ready(s3_ready),
        .s3_split(s3_split),

        .split_grant(split_grant)
    );

    always #5 clk = ~clk;

    task automatic check_condition;
        input condition;
        input [8*100-1:0] message;
        begin
            if (!condition) begin
                error_count = error_count + 1;
                $display("FAIL @ %0t: %0s", $time, message);
            end
            else begin
                $display("PASS @ %0t: %0s", $time, message);
            end
        end
    endtask

    task automatic request_bus;
        input integer master_number;
        begin
            @(negedge clk);
            if (master_number == 1)
                m1_breq = 1'b1;
            else
                m2_breq = 1'b1;

            @(posedge clk);
            #1;
            if (master_number == 1)
                check_condition(m1_bgrant && !m2_bgrant,
                                "Master 1 receives the bus grant");
            else
                check_condition(m2_bgrant && !m1_bgrant,
                                "Master 2 receives the bus grant");
        end
    endtask

    task automatic release_bus;
        input integer master_number;
        begin
            @(negedge clk);
            if (master_number == 1)
                m1_breq = 1'b0;
            else
                m2_breq = 1'b0;

            @(posedge clk);
            #1;
            check_condition(!m1_bgrant && !m2_bgrant,
                            "Bus returns to the idle state");
        end
    endtask

    task automatic send_device_id;
        input integer master_number;
        input [DEVICE_ADDR_WIDTH-1:0] device_id;
        input expected_ack;
        begin
            for (bit_index = 0; bit_index < DEVICE_ADDR_WIDTH; bit_index = bit_index + 1) begin
                @(negedge clk);
                if (master_number == 1) begin
                    m1_wdata  = device_id[bit_index];
                    m1_mvalid = 1'b1;
                end
                else begin
                    m2_wdata  = device_id[bit_index];
                    m2_mvalid = 1'b1;
                end
                @(posedge clk);
                #1;
            end

            if (master_number == 1) begin
                check_condition(m1_ack == expected_ack,
                                "Master 1 receives the expected address acknowledgement");
                check_condition(!m2_ack,
                                "Inactive Master 2 does not receive Master 1 acknowledgement");
            end
            else begin
                check_condition(m2_ack == expected_ack,
                                "Master 2 receives the expected address acknowledgement");
                check_condition(!m1_ack,
                                "Inactive Master 1 does not receive Master 2 acknowledgement");
            end

            // The protocol has a low-valid separator between device ID and
            // local slave address.
            @(negedge clk);
            if (master_number == 1)
                m1_mvalid = 1'b0;
            else
                m2_mvalid = 1'b0;

            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_selected_slave;
        input integer master_number;
        input integer slave_number;
        input serial_bit;
        begin
            @(negedge clk);

            if (slave_number == 1)
                s1_ready = 1'b0;
            else if (slave_number == 2)
                s2_ready = 1'b0;
            else
                s3_ready = 1'b0;

            if (master_number == 1) begin
                m1_wdata  = serial_bit;
                m1_mode   = 1'b1;
                m1_mvalid = 1'b1;
            end
            else begin
                m2_wdata  = serial_bit;
                m2_mode   = 1'b1;
                m2_mvalid = 1'b1;
            end

            #1;
            check_condition((s1_wdata == serial_bit) &&
                            (s2_wdata == serial_bit) &&
                            (s3_wdata == serial_bit),
                            "Selected master serial data is broadcast to all slaves");
            check_condition(s1_mode && s2_mode && s3_mode,
                            "Selected master write mode is broadcast to all slaves");

            case (slave_number)
                1: check_condition(s1_mvalid && !s2_mvalid && !s3_mvalid,
                                   "Only Slave 1 valid is asserted");
                2: check_condition(!s1_mvalid && s2_mvalid && !s3_mvalid,
                                   "Only Slave 2 valid is asserted");
                3: check_condition(!s1_mvalid && !s2_mvalid && s3_mvalid,
                                   "Only Slave 3 valid is asserted");
            endcase

            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_slave_response;
        input integer master_number;
        input integer slave_number;
        input response_bit;
        begin
            @(negedge clk);
            case (slave_number)
                1: begin s1_rdata = response_bit; s1_svalid = 1'b1; end
                2: begin s2_rdata = response_bit; s2_svalid = 1'b1; end
                3: begin s3_rdata = response_bit; s3_svalid = 1'b1; end
            endcase

            #1;
            if (master_number == 1) begin
                check_condition(m1_svalid && (m1_rdata == response_bit),
                                "Selected slave response reaches Master 1");
                check_condition(!m2_svalid,
                                "Slave response is hidden from inactive Master 2");
            end
            else begin
                check_condition(m2_svalid && (m2_rdata == response_bit),
                                "Selected slave response reaches Master 2");
                check_condition(!m1_svalid,
                                "Slave response is hidden from inactive Master 1");
            end
        end
    endtask

    task automatic finish_slave_transaction;
        input integer master_number;
        input integer slave_number;
        begin
            @(negedge clk);
            if (master_number == 1)
                m1_mvalid = 1'b0;
            else
                m2_mvalid = 1'b0;

            case (slave_number)
                1: begin s1_svalid = 1'b0; s1_ready = 1'b1; end
                2: begin s2_svalid = 1'b0; s2_ready = 1'b1; end
                3: begin s3_svalid = 1'b0; s3_ready = 1'b1; end
            endcase

            @(posedge clk);
            #1;
            check_condition(!s1_mvalid && !s2_mvalid && !s3_mvalid,
                            "All slave-valid outputs clear after transaction completion");
        end
    endtask

    initial begin
        clk = 1'b0;
        reset_n = 1'b0;
        error_count = 0;

        m1_wdata = 1'b0;
        m1_mode = 1'b0;
        m1_mvalid = 1'b0;
        m1_breq = 1'b0;

        m2_wdata = 1'b0;
        m2_mode = 1'b0;
        m2_mvalid = 1'b0;
        m2_breq = 1'b0;

        s1_rdata = 1'b0;
        s1_svalid = 1'b0;
        s1_ready = 1'b1;

        s2_rdata = 1'b0;
        s2_svalid = 1'b0;
        s2_ready = 1'b1;

        s3_rdata = 1'b0;
        s3_svalid = 1'b0;
        s3_ready = 1'b1;
        s3_split = 1'b0;

        // Reset is asserted before a clock edge, proving asynchronous reset.
        #2;
        check_condition(!m1_bgrant && !m2_bgrant &&
                        !m1_split && !m2_split && !split_grant,
                        "Asynchronous reset clears arbiter outputs");
        check_condition(!s1_mvalid && !s2_mvalid && !s3_mvalid,
                        "Asynchronous reset disables all slave paths");

        @(negedge clk);
        reset_n = 1'b1;

        // Test 1: fixed priority when both masters request together.
        @(negedge clk);
        m1_breq = 1'b1;
        m2_breq = 1'b1;
        @(posedge clk);
        #1;
        check_condition(m1_bgrant && !m2_bgrant,
                        "Master 1 wins simultaneous requests");
        @(negedge clk);
        m1_breq = 1'b0;
        m2_breq = 1'b0;
        @(posedge clk);
        #1;

        // Test 2: Master 1 selects Slave 1 and receives its response.
        request_bus(1);
        send_device_id(1, 4'd0, 1'b1);
        check_selected_slave(1, 1, 1'b1);
        check_slave_response(1, 1, 1'b1);
        finish_slave_transaction(1, 1);
        release_bus(1);

        // Test 3: Master 2 selects Slave 2 and receives its response.
        request_bus(2);
        send_device_id(2, 4'd1, 1'b1);
        check_selected_slave(2, 2, 1'b0);
        check_slave_response(2, 2, 1'b1);
        finish_slave_transaction(2, 2);
        release_bus(2);

        // Test 4: invalid device ID is rejected without enabling a slave.
        request_bus(1);
        send_device_id(1, 4'd3, 1'b0);
        check_condition(!s1_mvalid && !s2_mvalid && !s3_mvalid,
                        "Invalid device ID does not enable any slave");
        release_bus(1);

        // Test 5: Master 1 is split by Slave 3.
        request_bus(1);
        send_device_id(1, 4'd2, 1'b1);
        check_selected_slave(1, 3, 1'b1);

        @(negedge clk);
        m1_mvalid = 1'b0;
        s3_split = 1'b1;
        @(posedge clk);
        #1;
        check_condition(m1_split && !m2_split,
                        "Split is recorded against Master 1");
        check_condition(!m1_bgrant && !m2_bgrant,
                        "Split releases the shared bus");

        // Master 2 uses normal Slave 1 while Slave 3 is still split.
        request_bus(2);
        send_device_id(2, 4'd0, 1'b1);
        check_selected_slave(2, 1, 1'b0);
        finish_slave_transaction(2, 1);
        release_bus(2);

        // Slave 3 finishes its delayed work; Master 1 must resume first.
        @(negedge clk);
        s3_split = 1'b0;
        @(posedge clk);
        #1;
        check_condition(m1_bgrant && !m2_bgrant,
                        "Interrupted Master 1 regains the bus");
        check_condition(split_grant && !m1_split,
                        "split_grant pulses and clears Master 1 split status");

        @(posedge clk);
        #1;
        check_condition(!split_grant,
                        "split_grant is exactly one clock cycle wide");

        s3_rdata = 1'b1;
        s3_svalid = 1'b1;
        #1;
        check_condition(m1_svalid && m1_rdata,
                        "Resumed Slave 3 response is routed to Master 1");

        @(negedge clk);
        s3_svalid = 1'b0;
        s3_ready = 1'b1;
        @(posedge clk);
        #1;
        release_bus(1);

        // Test 6: the symmetric case, Master 2 is split and Master 1 proceeds.
        s3_ready = 1'b1;
        request_bus(2);
        send_device_id(2, 4'd2, 1'b1);
        check_selected_slave(2, 3, 1'b0);

        @(negedge clk);
        m2_mvalid = 1'b0;
        s3_split = 1'b1;
        @(posedge clk);
        #1;
        check_condition(m2_split && !m1_split,
                        "Split is recorded against Master 2");
        check_condition(!m1_bgrant && !m2_bgrant,
                        "Master 2 split releases the shared bus");

        request_bus(1);
        release_bus(1);

        @(negedge clk);
        s3_split = 1'b0;
        @(posedge clk);
        #1;
        check_condition(m2_bgrant && !m1_bgrant,
                        "Interrupted Master 2 regains the bus");
        check_condition(split_grant && !m2_split,
                        "split_grant pulses and clears Master 2 split status");

        @(posedge clk);
        #1;
        check_condition(!split_grant,
                        "Master 2 split_grant is one clock cycle wide");

        @(negedge clk);
        s3_ready = 1'b1;
        @(posedge clk);
        #1;
        release_bus(2);

        // Test 7: assert reset between rising edges while a grant is active.
        request_bus(2);
        #2;
        reset_n = 1'b0;
        #1;
        check_condition(!m1_bgrant && !m2_bgrant,
                        "Mid-cycle asynchronous reset immediately removes grants");
        check_condition(!m1_split && !m2_split && !split_grant,
                        "Mid-cycle asynchronous reset clears split state");
        check_condition(!s1_mvalid && !s2_mvalid && !s3_mvalid,
                        "Mid-cycle asynchronous reset disables slave routing");

        m2_breq = 1'b0;
        @(negedge clk);
        reset_n = 1'b1;

        repeat (2) @(posedge clk);

        if (error_count == 0) begin
            $display("\n========================================");
            $display("ALL MEMBER 2 TESTS PASSED");
            $display("========================================\n");
        end
        else begin
            $display("\n========================================");
            $display("MEMBER 2 TESTS FAILED: %0d error(s)", error_count);
            $display("========================================\n");
            $fatal(1);
        end

        $finish;
    end

    initial begin
        $dumpfile("tb_serial_bus_m2_s3.vcd");
        $dumpvars(0, tb_serial_bus_m2_s3);
    end

    // Prevent a protocol error from hanging the simulation forever.
    initial begin
        #10000;
        $fatal(1, "Simulation timeout");
    end

endmodule
