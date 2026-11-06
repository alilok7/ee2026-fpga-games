`timescale 1ns / 1ps
// pixel_xy.v : pixel_index -> (x, y). Not used since v3
// Owner: Student B

// Not used since v3: nothing instantiates this module
module pixel_xy (
    input  wire        clk,
    input  wire [12:0] pixel_index,
    output reg  [6:0]  px_x,
    output reg  [5:0]  px_y
);
    reg [12:0] index;

    always @ (posedge clk) begin
        index <= pixel_index;
    end

    // y = (index / 32) / 3, and n / 3 = (n * 171) >> 9, so no divider is needed
    wire [7:0]  n    = index[12:5];
    wire [15:0] prod = n * 8'd171;
    wire [5:0]  y    = prod[14:9];
    wire [12:0] y96  = {y, 6'b0} + {1'b0, y, 5'b0};
    wire [12:0] x    = index - y96;

    always @ (posedge clk) begin
        px_y <= y;
        px_x <= x[6:0];
    end
endmodule
