`timescale 1ns/1ps

// Standalone DE0-Nano diagnostic wrapper for the Member 2 interconnect.
//
// Controls:
//   KEY[0]  : asynchronous active-low reset
//   KEY[1]  : start one diagnostic transaction (active-low pushbutton)
//   SW[0]   : requested master, 0 = Master 1, 1 = Master 2
//   SW[1]   : request both masters initially to demonstrate M1 priority
//   SW[3:2] : device ID, 0 = S1, 1 = S2, 2 = split S3, 3 = invalid
//
// Latched LED result (cleared by reset or the next start):
//   LED[0]  : Master 1 received the grant
//   LED[1]  : Master 2 received the grant
//   LED[2]  : Slave 1 was selected
//   LED[3]  : Slave 2 was selected
//   LED[4]  : Slave 3 was selected
//   LED[5]  : address acknowledgement observed
//   LED[6]  : split observed
//   LED[7]  : diagnostic transaction completed
module member2_de0_nano_top (
    input  wire       CLOCK_50,
    input  wire [1:0] KEY,
    input  wire [3:0] SW,
    output wire [7:0] LED
);

    wire reset_n;
    assign reset_n = KEY[0];

    // Synchronize KEY[1] and create one pulse when it is pressed.
    reg start_meta;
    reg start_sync;
    reg start_previous;
    wire start_pulse;

    assign start_pulse = start_previous & ~start_sync;

    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (!reset_n) begin
            start_meta     <= 1'b1;
            start_sync     <= 1'b1;
            start_previous <= 1'b1;
        end
        else begin
            start_meta     <= KEY[1];
            start_sync     <= start_meta;
            start_previous <= start_sync;
        end
    end

    localparam [3:0] CTRL_IDLE          = 4'd0,
                     CTRL_REQUEST       = 4'd1,
                     CTRL_SEND_ID       = 4'd2,
                     CTRL_WAIT_ACK      = 4'd3,
                     CTRL_SEND_PAYLOAD  = 4'd4,
                     CTRL_WAIT_RESPONSE = 4'd5,
                     CTRL_DONE          = 4'd6;

    reg [3:0] controller_state;
    reg [2:0] serial_bit_count;
    reg [4:0] ack_timeout;
    reg [1:0] requested_device;
    reg requested_master;
    reg request_both;
    reg active_master;

    reg m1_wdata;
    reg m1_mode;
    reg m1_mvalid;
    reg m1_breq;
    wire m1_rdata;
    wire m1_svalid;
    wire m1_bgrant;
    wire m1_ack;
    wire m1_split;

    reg m2_wdata;
    reg m2_mode;
    reg m2_mvalid;
    reg m2_breq;
    wire m2_rdata;
    wire m2_svalid;
    wire m2_bgrant;
    wire m2_ack;
    wire m2_split;

    wire [3:0] device_id;
    assign device_id = {2'b00, requested_device};

    // Drive one selected master. During CTRL_REQUEST, SW[1] can request both
    // masters so that the fixed Master 1 priority is visible on the LEDs.
    always @(*) begin
        m1_wdata  = 1'b0;
        m1_mode   = 1'b0; // diagnostic transaction is a read
        m1_mvalid = 1'b0;
        m1_breq   = 1'b0;

        m2_wdata  = 1'b0;
        m2_mode   = 1'b0;
        m2_mvalid = 1'b0;
        m2_breq   = 1'b0;

        if (controller_state == CTRL_REQUEST) begin
            if (request_both) begin
                m1_breq = 1'b1;
                m2_breq = 1'b1;
            end
            else if (requested_master) begin
                m2_breq = 1'b1;
            end
            else begin
                m1_breq = 1'b1;
            end
        end
        else if ((controller_state != CTRL_IDLE) &&
                 (controller_state != CTRL_DONE)) begin
            if (active_master)
                m2_breq = 1'b1;
            else
                m1_breq = 1'b1;
        end

        if (controller_state == CTRL_SEND_ID) begin
            if (active_master) begin
                m2_wdata  = device_id[serial_bit_count];
                m2_mvalid = 1'b1;
            end
            else begin
                m1_wdata  = device_id[serial_bit_count];
                m1_mvalid = 1'b1;
            end
        end
        else if (controller_state == CTRL_SEND_PAYLOAD) begin
            // One local-address bit is sufficient for the routing diagnostic.
            if (active_master) begin
                m2_wdata  = 1'b1;
                m2_mvalid = 1'b1;
            end
            else begin
                m1_wdata  = 1'b1;
                m1_mvalid = 1'b1;
            end
        end
    end

    // Simple synthesizable slave-response models used only by this diagnostic
    // top. The final assignment top replaces these with the teammate's slaves.
    localparam [2:0] SLAVE_IDLE         = 3'd0,
                     SLAVE_DELAY        = 3'd1,
                     SLAVE_SPLIT_DELAY  = 3'd2,
                     SLAVE_WAIT_RESUME  = 3'd3,
                     SLAVE_RESPOND      = 3'd4;

    reg [2:0] slave_model_state;
    reg [1:0] active_slave;
    reg [4:0] response_delay;

    reg s1_rdata;
    reg s1_svalid;
    reg s1_ready;
    wire s1_wdata;
    wire s1_mode;
    wire s1_mvalid;

    reg s2_rdata;
    reg s2_svalid;
    reg s2_ready;
    wire s2_wdata;
    wire s2_mode;
    wire s2_mvalid;

    reg s3_rdata;
    reg s3_svalid;
    reg s3_ready;
    reg s3_split;
    wire s3_wdata;
    wire s3_mode;
    wire s3_mvalid;

    wire split_grant;

    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (!reset_n) begin
            slave_model_state <= SLAVE_IDLE;
            active_slave      <= 2'd0;
            response_delay    <= 5'd0;
            s1_rdata          <= 1'b0;
            s1_svalid         <= 1'b0;
            s1_ready          <= 1'b1;
            s2_rdata          <= 1'b0;
            s2_svalid         <= 1'b0;
            s2_ready          <= 1'b1;
            s3_rdata          <= 1'b0;
            s3_svalid         <= 1'b0;
            s3_ready          <= 1'b1;
            s3_split          <= 1'b0;
        end
        else begin
            s1_svalid <= 1'b0;
            s2_svalid <= 1'b0;
            s3_svalid <= 1'b0;

            case (slave_model_state)
                SLAVE_IDLE: begin
                    response_delay <= 5'd0;

                    if (s1_mvalid) begin
                        active_slave      <= 2'd0;
                        s1_ready          <= 1'b0;
                        slave_model_state <= SLAVE_DELAY;
                    end
                    else if (s2_mvalid) begin
                        active_slave      <= 2'd1;
                        s2_ready          <= 1'b0;
                        slave_model_state <= SLAVE_DELAY;
                    end
                    else if (s3_mvalid) begin
                        active_slave      <= 2'd2;
                        s3_ready          <= 1'b0;
                        s3_split          <= 1'b1;
                        slave_model_state <= SLAVE_SPLIT_DELAY;
                    end
                end

                SLAVE_DELAY: begin
                    if (response_delay == 5'd6) begin
                        if (active_slave == 2'd0) begin
                            s1_rdata  <= 1'b1;
                            s1_svalid <= 1'b1;
                        end
                        else begin
                            s2_rdata  <= 1'b0;
                            s2_svalid <= 1'b1;
                        end
                        slave_model_state <= SLAVE_RESPOND;
                    end
                    else begin
                        response_delay <= response_delay + 1'b1;
                    end
                end

                SLAVE_SPLIT_DELAY: begin
                    if (response_delay == 5'd12) begin
                        s3_split          <= 1'b0;
                        response_delay    <= 5'd0;
                        slave_model_state <= SLAVE_WAIT_RESUME;
                    end
                    else begin
                        response_delay <= response_delay + 1'b1;
                    end
                end

                SLAVE_WAIT_RESUME: begin
                    if (split_grant) begin
                        s3_rdata          <= 1'b1;
                        s3_svalid         <= 1'b1;
                        slave_model_state <= SLAVE_RESPOND;
                    end
                end

                SLAVE_RESPOND: begin
                    if (active_slave == 2'd0)
                        s1_ready <= 1'b1;
                    else if (active_slave == 2'd1)
                        s2_ready <= 1'b1;
                    else
                        s3_ready <= 1'b1;

                    slave_model_state <= SLAVE_IDLE;
                end

                default: slave_model_state <= SLAVE_IDLE;
            endcase
        end
    end

    reg [1:0] granted_master_latched;
    reg [2:0] selected_slave_latched;
    reg acknowledgement_latched;
    reg split_latched;
    reg completed_latched;

    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (!reset_n) begin
            controller_state          <= CTRL_IDLE;
            serial_bit_count          <= 3'd0;
            ack_timeout               <= 5'd0;
            requested_device          <= 2'd0;
            requested_master          <= 1'b0;
            request_both              <= 1'b0;
            active_master             <= 1'b0;
            granted_master_latched    <= 2'b00;
            selected_slave_latched    <= 3'b000;
            acknowledgement_latched  <= 1'b0;
            split_latched             <= 1'b0;
            completed_latched         <= 1'b0;
        end
        else begin
            if (m1_split || m2_split)
                split_latched <= 1'b1;

            if (s1_mvalid)
                selected_slave_latched <= 3'b001;
            else if (s2_mvalid)
                selected_slave_latched <= 3'b010;
            else if (s3_mvalid)
                selected_slave_latched <= 3'b100;

            case (controller_state)
                CTRL_IDLE: begin
                    serial_bit_count <= 3'd0;
                    ack_timeout      <= 5'd0;

                    if (start_pulse) begin
                        requested_device         <= SW[3:2];
                        requested_master         <= SW[0];
                        request_both             <= SW[1];
                        granted_master_latched   <= 2'b00;
                        selected_slave_latched   <= 3'b000;
                        acknowledgement_latched <= 1'b0;
                        split_latched            <= 1'b0;
                        completed_latched        <= 1'b0;
                        controller_state         <= CTRL_REQUEST;
                    end
                end

                CTRL_REQUEST: begin
                    if (m1_bgrant) begin
                        active_master          <= 1'b0;
                        granted_master_latched <= 2'b01;
                        serial_bit_count       <= 3'd0;
                        controller_state       <= CTRL_SEND_ID;
                    end
                    else if (m2_bgrant) begin
                        active_master          <= 1'b1;
                        granted_master_latched <= 2'b10;
                        serial_bit_count       <= 3'd0;
                        controller_state       <= CTRL_SEND_ID;
                    end
                end

                CTRL_SEND_ID: begin
                    if (serial_bit_count == 3'd3) begin
                        serial_bit_count <= 3'd0;
                        ack_timeout      <= 5'd0;
                        controller_state <= CTRL_WAIT_ACK;
                    end
                    else begin
                        serial_bit_count <= serial_bit_count + 1'b1;
                    end
                end

                CTRL_WAIT_ACK: begin
                    if ((!active_master && m1_ack) || (active_master && m2_ack)) begin
                        acknowledgement_latched <= 1'b1;
                        controller_state        <= CTRL_SEND_PAYLOAD;
                    end
                    else if (ack_timeout == 5'd20) begin
                        // Device ID 3 intentionally follows this path.
                        completed_latched <= 1'b1;
                        controller_state  <= CTRL_DONE;
                    end
                    else begin
                        ack_timeout <= ack_timeout + 1'b1;
                    end
                end

                CTRL_SEND_PAYLOAD: begin
                    controller_state <= CTRL_WAIT_RESPONSE;
                end

                CTRL_WAIT_RESPONSE: begin
                    if ((!active_master && m1_svalid) ||
                        (active_master && m2_svalid)) begin
                        completed_latched <= 1'b1;
                        controller_state  <= CTRL_DONE;
                    end
                end

                CTRL_DONE: begin
                    controller_state <= CTRL_IDLE;
                end

                default: controller_state <= CTRL_IDLE;
            endcase
        end
    end

    serial_bus_m2_s3 #(
        .ADDR_WIDTH(16),
        .DATA_WIDTH(8),
        .SLAVE_MEM_ADDR_WIDTH(12)
    ) interconnect (
        .clk(CLOCK_50),
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

    assign LED[0] = granted_master_latched[0];
    assign LED[1] = granted_master_latched[1];
    assign LED[2] = selected_slave_latched[0];
    assign LED[3] = selected_slave_latched[1];
    assign LED[4] = selected_slave_latched[2];
    assign LED[5] = acknowledgement_latched;
    assign LED[6] = split_latched;
    assign LED[7] = completed_latched;

endmodule
