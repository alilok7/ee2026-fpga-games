`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// score_engine.v : ten-pin scoring from the list of rolls
//-----------------------------------------------------------------------------
// Owner   : Student C (v3.5 team split; before: Student D)
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
// The RAM keeps its lower-case name fr_mem: tb_top reads it.
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
    output wire [8:0]  game0, game1,     // total of all known frames (official)
    output wire [8:0]  prov0, prov1,     // provisional: strikes/spares count the bonus balls thrown so far
    output reg         done
);

    // ---------- 1. Scorecard glyphs ----------
    localparam [5:0] G_SP   = 6'd0;
    localparam [5:0] G_X    = 6'd56;
    localparam [5:0] G_SL   = 6'd15;
    localparam [5:0] G_DASH = 6'd13;

    // single ball: '-' for 0, else digit (X for 10)
    function [5:0] BALL_GLYPH;
        input [3:0] V;
        BALL_GLYPH = (V == 4'd0)  ? G_DASH :
                     (V == 4'd10) ? G_X    :
                                    6'd16 + {2'b00, V};
    endfunction

    // ---------- 2. Frame RAM and totals ----------
    reg [27:0] fr_mem [0:31];               // [{player, frame}]
    reg        FRAME_WE;
    reg [4:0]  FRAME_WA;
    reg [27:0] FRAME_WD;
    always @ (posedge clk)
        if (FRAME_WE)
            fr_mem[FRAME_WA] <= FRAME_WD;
    assign card_word = fr_mem[card_addr];

    reg [9:0] OK    [0:1];                  // per frame: total known
    reg [8:0] TOTAL [0:1];                  // official totals
    reg [8:0] PROV  [0:1];                  // provisional totals
    assign ok0   = OK[0];
    assign ok1   = OK[1];
    assign game0 = TOTAL[0];
    assign game1 = TOTAL[1];
    assign prov0 = PROV[0];
    assign prov1 = PROV[1];

    // ---------- 3. States and walk registers ----------
    localparam [2:0] S_IDLE  = 3'd0;
    localparam [2:0] S_N     = 3'd1;
    localparam [2:0] S_R1    = 3'd2;
    localparam [2:0] S_R2    = 3'd3;
    localparam [2:0] S_R3    = 3'd4;
    localparam [2:0] S_CALC  = 3'd5;
    localparam [2:0] S_NEXTP = 3'd6;
    localparam [2:0] S_F     = 3'd7;

    reg [2:0] STATE;
    reg       P;                            // player being scored
    reg [3:0] F;                            // frame being scored
    reg [4:0] IDX, N;                       // first roll of frame F, rolls thrown
    reg [3:0] R1, R2, R3;                   // rolls IDX, IDX+1, IDX+2
    reg       A1, A2, A3;                   // ... and whether they exist
    reg [8:0] CUM;                          // running total
    reg [8:0] PV;                           // provisional running total
    reg       KNOWN;                        // every frame so far is known
    wire [6:0] BASE   = P ? `IM_ROLLS1 : `IM_ROLLS0;
    wire       STRIKE = A1 && (R1 == 4'd10);
    wire [4:0] S12    = R1 + R2;

    // the word of frame F (blocking temporaries in S_CALC)
    reg [5:0] W_M0, W_M1, W_M2;
    reg [8:0] W_ADD;                        // points of frame F, once complete
    reg       W_DONE;                       // frame F complete (its bonus balls thrown)
    reg [8:0] W_TOT;
    reg       W_OK;
    reg [4:0] W_PV;                         // points of frame F so far

    // ---------- 4. FSM ----------
    always @ (posedge clk) begin
        done <= 1'b0;
        FRAME_WE <= 1'b0;
        if (rst) begin
            STATE <= S_IDLE; P <= 0; F <= 0; IDX <= 0; N <= 0; R1 <= 0; R2 <= 0; R3 <= 0;
            CUM <= 0; KNOWN <= 0; ra <= 0;
            FRAME_WE <= 0; FRAME_WA <= 0; FRAME_WD <= 0;
            OK[0] <= 0; OK[1] <= 0; TOTAL[0] <= 0; TOTAL[1] <= 0; PROV[0] <= 0; PROV[1] <= 0; PV <= 0;
        end
        else begin
            case (STATE)
                S_IDLE: begin
                    if (start) begin
                        P <= 1'b0;
                        ra <= `IM_NROLL0;
                        STATE <= S_N;
                    end
                end

                S_N: begin                                     // roll count of player P
                    N <= (rd[4:0] > 5'd21) ? 5'd21 : rd[4:0];
                    IDX <= 0;
                    F <= 4'd0;
                    CUM <= 0;
                    KNOWN <= 1'b1;
                    OK[P] <= 10'd0;
                    TOTAL[P] <= 9'd0;
                    PV <= 9'd0;
                    STATE <= S_F;
                end

                S_F: begin                                     // frames before the start: blank
                    if (F < start_frame) begin
                        FRAME_WE <= 1'b1;
                        FRAME_WA <= {P, F};
                        FRAME_WD <= 28'd0;
                        F <= F + 4'd1;
                    end
                    else begin
                        ra <= BASE;
                        STATE <= S_R1;
                    end
                end

                // the read address is set one clock before its data is used
                S_R1: begin R1 <= rd[3:0]; ra <= BASE + {2'b00, IDX} + 7'd1; STATE <= S_R2; end
                S_R2: begin R2 <= rd[3:0]; ra <= BASE + {2'b00, IDX} + 7'd2; STATE <= S_R3; end
                S_R3: begin
                    R3 <= rd[3:0];
                    A1 <= (IDX < N);
                    A2 <= (IDX + 5'd1 < N);
                    A3 <= (IDX + 5'd2 < N);
                    STATE <= S_CALC;
                end

                S_CALC: begin
                    W_M0 = G_SP;
                    W_M1 = G_SP;
                    W_M2 = G_SP;
                    if (F != 4'd9 && STRIKE) begin                         // strike
                        W_M1   = G_X;
                        W_ADD  = 9'd10 + R2 + R3;
                        W_DONE = A2 && A3;
                        W_PV   = 5'd10 + (A2 ? {1'b0, R2} : 5'd0) + (A3 ? {1'b0, R3} : 5'd0);
                    end
                    else if (F != 4'd9) begin                              // spare or open
                        if (A1)
                            W_M0 = BALL_GLYPH(R1);
                        if (A2)
                            W_M1 = (S12 == 5'd10) ? G_SL : BALL_GLYPH(R2);
                        if (A1 && A2 && S12 == 5'd10) begin
                            W_ADD  = 9'd10 + R3;
                            W_DONE = A3;
                        end
                        else begin
                            W_ADD  = S12;
                            W_DONE = A1 && A2;
                        end
                        W_PV = (A1 ? {1'b0, R1} : 5'd0) + (A2 ? {1'b0, R2} : 5'd0) +
                               ((A1 && A2 && S12 == 5'd10 && A3) ? {1'b0, R3} : 5'd0);
                    end
                    else begin                                             // frame 10
                        if (A1)
                            W_M0 = BALL_GLYPH(R1);
                        if (A2)
                            W_M1 = (R1 == 4'd10)  ? BALL_GLYPH(R2) :
                                   (S12 == 5'd10) ? G_SL :
                                                    BALL_GLYPH(R2);
                        if (A3)
                            W_M2 = (R1 == 4'd10 && R2 != 4'd10) ?
                                   ((R2 + R3 == 5'd10) ? G_SL : BALL_GLYPH(R3)) :
                                   BALL_GLYPH(R3);
                        W_ADD  = S12 + (A3 ? {5'd0, R3} : 9'd0);
                        W_DONE = (A1 && A2 && R1 != 4'd10 && S12 < 5'd10) || A3;
                        W_PV   = (A1 ? {1'b0, R1} : 5'd0) + (A2 ? {1'b0, R2} : 5'd0) + (A3 ? {1'b0, R3} : 5'd0);
                    end

                    // a complete frame adds to the total; it is official if all before it are
                    W_TOT = W_DONE ? CUM + W_ADD : 9'd0;
                    W_OK  = W_DONE && KNOWN;
                    if (W_DONE)
                        CUM <= W_TOT;
                    else
                        KNOWN <= 1'b0;
                    if (W_OK) begin
                        OK[P][F] <= 1'b1;
                        TOTAL[P] <= W_TOT;
                    end

                    // provisional: counts the bonus balls thrown so far
                    PV <= PV + {4'd0, W_PV};
                    if (F == 4'd9)
                        PROV[P] <= PV + {4'd0, W_PV};

                    FRAME_WE <= 1'b1;
                    FRAME_WA <= {P, F};
                    FRAME_WD <= {W_OK, W_TOT, W_M0, W_M1, W_M2};
                    if (F == 4'd9)
                        STATE <= S_NEXTP;
                    else begin
                        F <= F + 4'd1;
                        IDX <= IDX + (STRIKE ? 5'd1 : 5'd2);
                        ra <= BASE + {2'b00, IDX} + (STRIKE ? 7'd1 : 7'd2);
                        STATE <= S_R1;
                    end
                end

                S_NEXTP: begin
                    if (P) begin
                        done <= 1'b1;
                        STATE <= S_IDLE;
                    end
                    else begin
                        P <= 1'b1;
                        ra <= `IM_NROLL1;
                        STATE <= S_N;
                    end
                end

                default: STATE <= S_IDLE;
            endcase
        end
    end
endmodule
