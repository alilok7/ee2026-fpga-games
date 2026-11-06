`timescale 1ns / 1ps
`include "strike_defs.vh"
// ball_trace.v : the path of the last ball, for the minimap
// Owner: Student B

module ball_trace (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire        clear,
    input  wire [`BP_W-1:0] ball_phase,
    input  wire [15:0] ball_x,
    input  wire [15:0] ball_y,
    input  wire [5:0]  rd_row,
    output wire [3:0]  rd_data
);

    // ---------- 1. Ball position to minimap row and column ----------
    wire [23:0] by_m = ball_y[15:6] * 14'd1366;
    wire [5:0]  row = (ball_y[15:6] > 10'd767) ? 6'd63 : by_m[19:14];
    wire [6:0]  xi = (ball_x[15:6] < 10'd9) ? 7'd0 : ball_x[12:6] - 7'd9;
    wire [12:0] xm = xi * 6'd43;
    wire [2:0]  col = (xm[10:8] > 3'd6) ? 3'd7 : xm[10:8] + 3'd1;
    wire moving = (ball_phase != `BP_IDLE) && (ball_phase != `BP_PIT);

    // ---------- 2. A new throw clears the memory, one entry per clock ----------
    reg [6:0] clr;
    always @ (posedge clk) begin
        if (rst || clear)
            clr <= 7'd64;
        else if (clr != 0)
            clr <= clr - 7'd1;
    end

    // ---------- 3. Path memory, one entry per minimap row ----------
    reg [3:0] row_mem [0:63];
    wire       we = (clr != 0) || (tick_frame && moving);
    wire [5:0] wa = (clr != 0) ? clr[5:0] - 6'd1 : row;
    wire [3:0] wd = (clr != 0) ? 4'd0 : {1'b1, col};

    always @ (posedge clk) begin
        if (we)
            row_mem[wa] <= wd;
    end

    assign rd_data = row_mem[rd_row];
endmodule
