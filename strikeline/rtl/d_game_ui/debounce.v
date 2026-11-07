`timescale 1ns / 1ps
// debounce.v : stable-count debouncer for ONE already-synchronised input
// Owner: Student A
module debounce #(parameter N_MS = 5, parameter W = 4) (
    input wire clk, rst, tick_1ms, din,
    output reg level, toggled
);
    (* ASYNC_REG = "TRUE" *) reg sync1, sync2;
    reg [W-1:0] count;
    reg [1:0] startup;

    always @(posedge clk) begin
        sync1 <= din;
        sync2 <= sync1;
    end

    always @(posedge clk) begin
        toggled <= 0;
        if (rst) begin
            level <= 0;
            count <= 0;
            startup <= 0;
        end else if (startup != 3) begin
            startup <= startup + 1'b1;
            count <= 0;
            if (startup == 2) level <= sync2;
        end else if (sync2 == level) begin
            count <= 0;
        end else if (tick_1ms) begin
            if (count == N_MS - 1) begin
                level <= sync2;
                toggled <= 1;
                count <= 0;
            end else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
