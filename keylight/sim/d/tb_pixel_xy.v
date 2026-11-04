`timescale 1ns / 1ps
//=============================================================================
// tb_pixel_xy.v : exhaustive check of D's divider-free x/y (and text grid)
//   For every pixel_index 0..6143: px_x == index % 96, px_y == index / 96,
//   and the text grid gives col == x / 6, fx == x % 6.
//=============================================================================
module tb_pixel_xy;
    reg clk = 0;
    reg [12:0] idx = 0;
    wire [6:0] x;
    wire [5:0] y;
    wire [3:0] col; wire [2:0] fx, row, fy, col2, fx2;
    pixel_xy dut (.clk(clk), .pixel_index(idx), .px_x(x), .px_y(y));
    text_grid g (.px_x(x), .px_y(y), .col(col), .fx(fx), .row(row), .fy(fy),
                 .col2(col2), .fx2(fx2));
    always #5 clk = ~clk;

    integer i, errors = 0;
    initial begin
        for (i = 0; i < 6144; i = i + 1) begin
            idx = i;
            @(posedge clk); @(posedge clk); #1;       // 2-stage pipeline
            if (x != i % 96 || y != i / 96) begin
                errors = errors + 1;
                if (errors < 5) $display("FAIL idx %0d -> x %0d y %0d", i, x, y);
            end
            if (col != (i % 96) / 6 || fx != (i % 96) % 6 || fx2 != ((i % 96) % 12) / 2) begin
                errors = errors + 1;
                if (errors < 5) $display("FAIL text grid at x %0d", i % 96);
            end
        end
        if (errors == 0) $display("PASS tb_pixel_xy: all 6144 pixels map correctly");
        else             $display("FAIL tb_pixel_xy: %0d errors", errors);
        $finish;
    end
endmodule
