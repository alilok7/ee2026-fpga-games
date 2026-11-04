`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// score_engine.v : ten-pin scoring from the list of rolls
//-----------------------------------------------------------------------------
// Owner   : Student D
// Rules   : frames 1-9: strike = 10 + next two balls, spare = 10 + next ball,
//           open = pins. Frame 10: up to 3 balls, its own pins only, a bonus
//           ball after a strike or spare. Max 300.
//           A frame's total is shown only once it is KNOWN (a strike waits
//           for its two bonus balls), exactly like a real scorecard.
// Method  : the rolls live in the save image (so a resumed game rescores
//           itself). After every roll (start) this FSM walks both players'
//           rolls, one read per clock, 4 clocks per frame (3 reads + 1
//           compute), ~100 clocks in total. Quick games start at frame 8
//           (start_frame = 7), frames before it stay blank.
// Outputs : one 28-bit word per (player, frame) in a 32-entry LUTRAM:
//           {known, running total (9 bits), 3 scorecard marks as glyph codes}
//           (frames 1-9 use marks 0 and 1): ' ' X / - or a digit. Every
//           frame word is rewritten once per rescore (blank before the start
//           frame), so the RAM never needs clearing.
//=============================================================================
module score_engine (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [3:0]  start_frame,
    output reg  [6:0]  ra,
    input  wire [7:0]  rd,
    input  wire [4:0]  card_addr,        // {player, frame} read by the scorecard
    output wire [27:0] card_word,        // {known, total[8:0], mark0, mark1, mark2}
    output wire [9:0]  ok0, ok1,
    output wire [8:0]  game0, game1,     // total of all known frames
    output reg         done
);
    localparam [5:0] G_SP = 6'd0, G_X = 6'd56, G_SL = 6'd15, G_DASH = 6'd13;
    function [5:0] gd;                     // single ball: '-' for 0, else digit (X for 10)
        input [3:0] v;
        gd = (v == 4'd0) ? G_DASH : (v == 4'd10) ? G_X : 6'd16 + {2'b00, v};
    endfunction

    reg [27:0] fr_mem [0:31];               // [{p, f}]
    reg        fr_we;
    reg [4:0]  fr_wa;
    reg [27:0] fr_wd;
    always @(posedge clk) if (fr_we) fr_mem[fr_wa] <= fr_wd;
    assign card_word = fr_mem[card_addr];
    reg [9:0] okr [0:1];
    reg [8:0] gt  [0:1];
    // the word of the frame being scored (blocking temporaries in S_CALC)
    reg [5:0] w_m0, w_m1, w_m2;
    reg [8:0] w_tot;
    reg       w_ok;
    assign ok0 = okr[0]; assign ok1 = okr[1];
    assign game0 = gt[0]; assign game1 = gt[1];

    localparam S_IDLE = 3'd0, S_N = 3'd1, S_R1 = 3'd2, S_R2 = 3'd3, S_R3 = 3'd4, S_CALC = 3'd5, S_NEXTP = 3'd6, S_F = 3'd7;
    reg [2:0] st;
    reg       p;
    reg [3:0] f;
    reg [4:0] idx, n;
    reg [3:0] r1, r2, r3;
    reg [8:0] cum;
    reg       known;                       // every frame so far is known
    wire [6:0] base = p ? `IM_ROLLS1 : `IM_ROLLS0;
    wire a1 = (idx < n), a2 = (idx + 5'd1 < n), a3 = (idx + 5'd2 < n);
    wire strike = a1 && (r1 == 4'd10);
    wire [4:0] s12 = r1 + r2;
    wire [4:0] s23 = r2 + r3;

    integer k;
    always @(posedge clk) begin
        done <= 1'b0; fr_we <= 1'b0;
        if (rst) begin
            st <= S_IDLE; p <= 0; f <= 0; idx <= 0; n <= 0; r1 <= 0; r2 <= 0; r3 <= 0;
            cum <= 0; known <= 0; ra <= 0;
            fr_we <= 0; fr_wa <= 0; fr_wd <= 0;
            okr[0] <= 0; okr[1] <= 0; gt[0] <= 0; gt[1] <= 0;
        end else begin
            case (st)
                S_IDLE: if (start) begin p <= 1'b0; ra <= `IM_NROLL0; st <= S_N; end
                S_N: begin                                     // roll count of player p
                    n <= (rd[4:0] > 5'd21) ? 5'd21 : rd[4:0];
                    idx <= 0; f <= 4'd0; cum <= 0; known <= 1'b1;
                    okr[p] <= 10'd0; gt[p] <= 9'd0;
                    st <= S_F;
                end
                S_F: begin                                     // frames before the start: blank
                    if (f < start_frame) begin
                        fr_we <= 1'b1; fr_wa <= {p, f}; fr_wd <= 28'd0;
                        f <= f + 4'd1;
                    end else begin
                        ra <= base;
                        st <= S_R1;
                    end
                end
                // the read address is set one clock before its data is used
                S_R1: begin r1 <= rd[3:0]; ra <= base + {2'b00, idx} + 7'd1; st <= S_R2; end
                S_R2: begin r2 <= rd[3:0]; ra <= base + {2'b00, idx} + 7'd2; st <= S_R3; end
                S_R3: begin r3 <= rd[3:0]; st <= S_CALC; end
                S_CALC: begin
                    w_m0 = G_SP; w_m1 = G_SP; w_m2 = G_SP; w_tot = 9'd0; w_ok = 1'b0;
                    if (f != 4'd9) begin
                        // ---------------- frames 1..9 ----------------
                        if (strike) begin
                            w_m1 = G_X;
                            if (a2 && a3) begin
                                cum <= cum + 9'd10 + r2 + r3;
                                w_tot = cum + 9'd10 + r2 + r3;
                                if (known) begin okr[p][f] <= 1'b1; w_ok = 1'b1; gt[p] <= cum + 9'd10 + r2 + r3; end
                            end else known <= 1'b0;
                            idx <= idx + 5'd1;
                        end else begin
                            if (a1) w_m0 = gd(r1);
                            if (a2) w_m1 = (s12 == 5'd10) ? G_SL : gd(r2);
                            if (a1 && a2 && s12 == 5'd10) begin
                                if (a3) begin
                                    cum <= cum + 9'd10 + r3;
                                    w_tot = cum + 9'd10 + r3;
                                    if (known) begin okr[p][f] <= 1'b1; w_ok = 1'b1; gt[p] <= cum + 9'd10 + r3; end
                                end else known <= 1'b0;
                            end else if (a1 && a2) begin
                                cum <= cum + s12;
                                w_tot = cum + s12;
                                if (known) begin okr[p][f] <= 1'b1; w_ok = 1'b1; gt[p] <= cum + s12; end
                            end else known <= 1'b0;
                            idx <= idx + 5'd2;
                        end
                    end else begin
                        // ---------------- frame 10 ----------------
                        if (a1) w_m0 = gd(r1);
                        if (a2) w_m1 = (r1 == 4'd10) ? gd(r2) : (s12 == 5'd10) ? G_SL : gd(r2);
                        if (a3) w_m2 = (r1 == 4'd10 && r2 != 4'd10) ?
                                              ((r2 + r3 == 5'd10) ? G_SL : gd(r3)) : gd(r3);
                        if ((a1 && a2 && r1 != 4'd10 && s12 < 5'd10) || a3) begin
                            cum <= cum + s12 + (a3 ? {5'd0, r3} : 9'd0);
                            w_tot = cum + s12 + (a3 ? {5'd0, r3} : 9'd0);
                            if (known) begin okr[p][f] <= 1'b1; w_ok = 1'b1; gt[p] <= cum + s12 + (a3 ? {5'd0, r3} : 9'd0); end
                        end
                    end
                    fr_we <= 1'b1; fr_wa <= {p, f}; fr_wd <= {w_ok, w_tot, w_m0, w_m1, w_m2};
                    if (f == 4'd9) st <= S_NEXTP;
                    else begin
                        f <= f + 4'd1;
                        ra <= base + {2'b00, idx} + ((strike) ? 7'd1 : 7'd2);
                        st <= S_R1;
                    end
                end
                S_NEXTP: begin
                    if (p) begin done <= 1'b1; st <= S_IDLE; end
                    else begin p <= 1'b1; ra <= `IM_NROLL1; st <= S_N; end
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
