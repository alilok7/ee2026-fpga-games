`timescale 1ns / 1ps
module reset_gen #(parameter HOLD_CYCLES = 1_000_000, parameter COUNT_W = 20) (
    input wire clk, soft_req,
    (* max_fanout = 40 *) output reg rst = 1,
    output reg por_rst = 1
);
    reg [COUNT_W-1:0] por_count = 20'd0;
    reg [COUNT_W-1:0] reset_count = 20'd0;

    always @(posedge clk) begin
        if (por_rst) begin
            if (por_count == HOLD_CYCLES - 1) por_rst <= 0;
            else por_count <= por_count + 1'b1;
        end
        if (soft_req) begin
            rst <= 1;
            reset_count <= 0;
        end else if (rst) begin
            if (reset_count == HOLD_CYCLES - 1) rst <= 0;
            else reset_count <= reset_count + 1'b1;
        end
    end
endmodule
