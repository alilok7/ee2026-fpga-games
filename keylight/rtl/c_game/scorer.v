`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// scorer.v : score, combo, multiplier, accuracy and grade
//-----------------------------------------------------------------------------
// Owner   : Student C
// Purpose : Consumes one judgement per clock from note_table.
//             Perfect 100, Good 50, Miss 0, times the combo multiplier
//             x1, x2 from 10, x3 from 30, x4 from 50 (combo after the hit)
//             Miss or stray strike -> combo back to 0.
//           A separate 0..9 counter tells us "every 10th combo" without a
//           modulo; it drives the milestone sound and the 5-LED combo meter.
//           At the end (finish pulse): accuracy % = (2P + G) * 100 / (2N)
//           on the sequential divider, then the grade.
//           x100 = x64 + x32 + x4, shifts and adds only.
//=============================================================================
module scorer (
    input  wire        clk,
    input  wire        clr,
    input  wire        j_valid,
    input  wire [1:0]  j_type,            // 0 P, 1 G, 2 Miss, 3 stray
    input  wire        finish,
    output reg  [19:0] score,
    output reg  [8:0]  combo,
    output reg  [8:0]  maxcombo,
    output reg  [8:0]  n_perfect,
    output reg  [8:0]  n_good,
    output reg  [8:0]  n_miss,
    output reg  [2:0]  mult,
    output reg  [2:0]  combo_tens,        // 0..5, one LED per 10 combo
    output reg         milestone,
    output reg         res_valid,
    output reg  [6:0]  res_acc,
    output reg  [2:0]  res_grade
);
    localparam [19:0] MAX_SCORE = 20'd999_999;

    reg  [3:0]  rem10;
    wire        is_hit   = j_valid && (j_type == 2'd0 || j_type == 2'd1);
    wire        is_break = j_valid && (j_type == 2'd2 || j_type == 2'd3);
    wire [8:0]  combo_n  = combo + 9'd1;
    wire [2:0]  mult_n   = (combo_n >= 9'd50) ? 3'd4 : (combo_n >= 9'd30) ? 3'd3 :
                           (combo_n >= 9'd10) ? 3'd2 : 3'd1;
    reg  [9:0]  points;
    always @(*) begin
        case ({j_type[0], mult_n})            // j_type[0]: 0 = Perfect, 1 = Good
            {1'b0, 3'd1}: points = 10'd100;   {1'b1, 3'd1}: points = 10'd50;
            {1'b0, 3'd2}: points = 10'd200;   {1'b1, 3'd2}: points = 10'd100;
            {1'b0, 3'd3}: points = 10'd300;   {1'b1, 3'd3}: points = 10'd150;
            {1'b0, 3'd4}: points = 10'd400;   default:      points = 10'd200;
        endcase
    end
    wire [20:0] score_sum = score + points;

    // ---- end of song: accuracy via the sequential divider ----
    wire [9:0]  hits2   = {n_perfect, 1'b0} + {1'b0, n_good};                 // 2P + G
    wire [16:0] num     = {hits2, 6'b0} + {1'b0, hits2, 5'b0} + {5'b0, hits2, 2'b0};
    wire [9:0]  total   = n_perfect + n_good + n_miss;                        // N
    wire [9:0]  den     = {total[8:0], 1'b0};                                 // 2N
    reg         div_start, waiting;
    wire [16:0] quot;
    wire        div_done;
    divider_seq #(.WN(17), .WD(10)) u_div (
        .clk(clk), .rst(clr), .start(div_start), .num(num), .den(den),
        .quot(quot), .done(div_done));

    wire [6:0] acc_q = (quot > 17'd100) ? 7'd100 : quot[6:0];

    always @(posedge clk) begin
        milestone <= 1'b0;
        res_valid <= 1'b0;
        div_start <= 1'b0;
        if (clr) begin
            score <= 20'd0; combo <= 9'd0; maxcombo <= 9'd0;
            n_perfect <= 9'd0; n_good <= 9'd0; n_miss <= 9'd0;
            mult <= 3'd1; combo_tens <= 3'd0; rem10 <= 4'd0;
            res_acc <= 7'd0; res_grade <= `KL_GRADE_D; waiting <= 1'b0;
        end else begin
            if (is_hit) begin
                combo <= combo_n;
                mult  <= mult_n;
                if (combo_n > maxcombo) maxcombo <= combo_n;
                score <= (score_sum > MAX_SCORE) ? MAX_SCORE : score_sum[19:0];
                if (j_type == 2'd0) n_perfect <= n_perfect + 9'd1;
                else                n_good    <= n_good + 9'd1;
                if (rem10 == 4'd9) begin                     // every 10th hit in a row
                    rem10     <= 4'd0;
                    milestone <= 1'b1;
                    if (combo_tens != 3'd5) combo_tens <= combo_tens + 3'd1;
                end else begin
                    rem10 <= rem10 + 4'd1;
                end
            end else if (is_break) begin
                combo      <= 9'd0;
                mult       <= 3'd1;
                rem10      <= 4'd0;
                combo_tens <= 3'd0;
                if (j_type == 2'd2) n_miss <= n_miss + 9'd1;
            end

            if (finish) begin
                if (total == 10'd0) begin                    // nothing to judge
                    res_acc   <= 7'd0;
                    res_grade <= `KL_GRADE_D;
                    res_valid <= 1'b1;
                end else begin
                    div_start <= 1'b1;
                    waiting   <= 1'b1;
                end
            end
            if (waiting && div_done) begin
                waiting   <= 1'b0;
                res_acc   <= acc_q;
                res_grade <= (acc_q >= 7'd95) ? `KL_GRADE_S : (acc_q >= 7'd90) ? `KL_GRADE_A :
                             (acc_q >= 7'd80) ? `KL_GRADE_B : (acc_q >= 7'd70) ? `KL_GRADE_C :
                                                                                 `KL_GRADE_D;
                res_valid <= 1'b1;
            end
        end
    end
endmodule
