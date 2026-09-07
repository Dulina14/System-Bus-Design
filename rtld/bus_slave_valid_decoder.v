`timescale 1ns/1ps

// Converts a two-bit slave number into one valid signal per slave.
module bus_slave_valid_decoder (
    input  wire [1:0] slave_select,
    input  wire       enable,
    output reg        slave1_valid,
    output reg        slave2_valid,
    output reg        slave3_valid
);

    always @(*) begin
        slave1_valid = 1'b0;
        slave2_valid = 1'b0;
        slave3_valid = 1'b0;

        if (enable) begin
            case (slave_select)
                2'd0: slave1_valid = 1'b1;
                2'd1: slave2_valid = 1'b1;
                2'd2: slave3_valid = 1'b1;
                default: begin
                    slave1_valid = 1'b0;
                    slave2_valid = 1'b0;
                    slave3_valid = 1'b0;
                end
            endcase
        end
    end

endmodule
