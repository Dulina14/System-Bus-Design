`timescale 1ns/1ps

// Two-input combinational multiplexer used to select one of the two masters.
module bus_mux2 #(
    parameter WIDTH = 1
) (
    input  wire [WIDTH-1:0] data0,
    input  wire [WIDTH-1:0] data1,
    input  wire             select,
    output wire [WIDTH-1:0] data_out
);

    assign data_out = select ? data1 : data0;

endmodule
