`timescale 1ns / 1ps
//=============================================================================
// results_latch.v : keep the last song's results and their decimal digits
//-----------------------------------------------------------------------------
// Owner   : Student D
// Purpose : C emits the results bundle for ONE cycle (res_valid). We latch
//           it, then run the shared bin2bcd converter over the six numbers
//           one after another (a tiny sequencer), so the Results screen can
//           draw digits straight from registers.
// Ports
//   res_*      bundle from C's scorer (see keylight_defs.vh)
//   *_bcd      decimal digits for the screen, digit 0 in the low nibble
//   score      binary score kept for the high-score compare
//=============================================================================
module results_latch (
    input  wire        clk,
    input  wire        rst,
    input  wire        res_valid,
    input  wire [19:0] res_score,
    input  wire [8:0]  res_perfect,
    input  wire [8:0]  res_good,
    input  wire [8:0]  res_miss,
    input  wire [8:0]  res_maxcombo,
    input  wire [6:0]  res_acc,
    input  wire [2:0]  res_grade,
    output reg  [19:0] score,
    output reg  [2:0]  grade,
    output reg  [23:0] score_bcd,
    output reg  [11:0] perf_bcd,
    output reg  [11:0] good_bcd,
    output reg  [11:0] miss_bcd,
    output reg  [11:0] max_bcd,
    output reg  [11:0] acc_bcd
);
    reg  [8:0]  perfect, good, miss, maxc;
    reg  [6:0]  acc;
    reg  [2:0]  idx;          // which number is being converted (0..5), 7 = idle
    reg         start;
    reg  [19:0] cvt_in;
    wire [23:0] cvt_out;
    wire        cvt_done;

    bin2bcd #(.W(20), .D(6)) u_bcd (
        .clk(clk), .rst(rst), .start(start), .bin(cvt_in),
        .bcd(cvt_out), .done(cvt_done));

    // value to convert for each step
    always @(*) begin
        case (idx)
            3'd0:    cvt_in = score;
            3'd1:    cvt_in = {11'd0, perfect};
            3'd2:    cvt_in = {11'd0, good};
            3'd3:    cvt_in = {11'd0, miss};
            3'd4:    cvt_in = {11'd0, maxc};
            default: cvt_in = {13'd0, acc};
        endcase
    end

    always @(posedge clk) begin
        start <= 1'b0;
        if (rst) begin
            idx <= 3'd7;
            {score, grade, perfect, good, miss, maxc, acc} <= 0;
            {score_bcd, perf_bcd, good_bcd, miss_bcd, max_bcd, acc_bcd} <= 0;
        end else if (res_valid) begin
            score <= res_score;   grade <= res_grade;
            perfect <= res_perfect; good <= res_good; miss <= res_miss;
            maxc <= res_maxcombo; acc <= res_acc;
            idx   <= 3'd0;
            start <= 1'b1;
        end else if (cvt_done && idx != 3'd7) begin
            case (idx)
                3'd0: score_bcd <= cvt_out;
                3'd1: perf_bcd  <= cvt_out[11:0];
                3'd2: good_bcd  <= cvt_out[11:0];
                3'd3: miss_bcd  <= cvt_out[11:0];
                3'd4: max_bcd   <= cvt_out[11:0];
                default: acc_bcd <= cvt_out[11:0];
            endcase
            if (idx == 3'd5) idx <= 3'd7;
            else begin
                idx   <= idx + 3'd1;
                start <= 1'b1;
            end
        end
    end
endmodule
