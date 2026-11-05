`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// score_engine.v - ten-pin bowling scores from the list of rolls
//-----------------------------------------------------------------------------
// Owner   : Student D
// Rules   : frames 1-9: strike = 10 + next two balls, spare = 10 + next ball,
//           open frame = the pins knocked down. Frame 10: up to 3 balls, a
//           bonus ball after a strike or spare. Maximum 300.
//           A frame's total is only shown when it is KNOWN (a strike must
//           wait for its two bonus balls), like a real scorecard.
// How     : The rolls are stored in the save image (21 per player, 15 = not
//           thrown yet). After every ball the turn FSM pulses `start`, and
//           for each player this module:
//             1. reads how many rolls there are       (S_COUNT)
//             2. copies the 21 rolls into roll[]      (S_LOAD, 1 per clock)
//             3. writes blank words for the frames before start_frame
//                (Quick game starts at frame 8)       (S_BLANK)
//             4. scores one frame per clock           (S_FRAME)
//           then does the same for player 2 and pulses `done`.
//           FSM style as in Lecture 3/4: a state register, a next-state
//           block, and a separate datapath (the registers below).
// Output  : one 28-bit word per (player, frame), kept in fr_mem:
//           {known, running total (9 bits), mark0, mark1, mark2}
//           marks are seg/scorecard character codes: ' ' X / - or a digit.
//=============================================================================
module score_engine (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [3:0]  start_frame,
    output reg  [6:0]  ra,               // read address into the save image
    input  wire [7:0]  rd,               // data at ra (comes one clock later)
    input  wire [4:0]  card_addr,        // {player, frame} wanted by the scorecard
    output wire [27:0] card_word,
    output wire [9:0]  ok0, ok1,         // which frames are known
    output wire [8:0]  game0, game1,     // official totals (known frames only)
    output wire [8:0]  prov0, prov1,     // provisional totals (bonus balls so far)
    output reg         done
);
    // ---- character codes for the marks ------------------------------------
    localparam [5:0] G_SP = 6'd0, G_X = 6'd56, G_SL = 6'd15, G_DASH = 6'd13;

    // one ball as a mark: '-' for 0, X for 10, otherwise the digit
    function [5:0] ball_mark;
        input [3:0] v;
        begin
            if (v == 0)
                ball_mark = G_DASH;
            else if (v == 10)
                ball_mark = G_X;
            else
                ball_mark = 6'd16 + v;
        end
    endfunction

    // ---- the frame words (small RAM) --------------------------------------
    reg [27:0] fr_mem [0:31];            // address = {player, frame}
    reg        fr_we;
    reg [4:0]  fr_wa;
    reg [27:0] fr_wd;
    always @(posedge clk) begin
        if (fr_we == 1)
            fr_mem[fr_wa] <= fr_wd;
    end
    assign card_word = fr_mem[card_addr];

    // ---- results for each player ------------------------------------------
    reg [9:0] ok_p0,   ok_p1;
    reg [8:0] game_p0, game_p1;
    reg [8:0] prov_p0, prov_p1;
    assign ok0 = ok_p0;     assign ok1 = ok_p1;
    assign game0 = game_p0; assign game1 = game_p1;
    assign prov0 = prov_p0; assign prov1 = prov_p1;

    // ---- FSM states ---------------------------------------------------------
    localparam S_IDLE  = 3'd0,
               S_COUNT = 3'd1,
               S_LOAD  = 3'd2,
               S_BLANK = 3'd3,
               S_FRAME = 3'd4,
               S_NEXT  = 3'd5;
    reg [2:0] state, next_state;

    // ---- datapath registers -------------------------------------------------
    reg       p;                         // player being scored (0 or 1)
    reg [4:0] n;                         // number of rolls this player has
    reg [4:0] i;                         // load counter 0..20
    reg [3:0] roll [0:20];               // this player's rolls
    reg [3:0] f;                         // frame 0..9
    reg [4:0] idx;                       // first roll of frame f
    reg [8:0] cum;                       // running total
    reg       known;                     // every frame so far is known
    reg [8:0] pv;                        // running provisional total

    wire [6:0] base = (p == 1) ? `IM_ROLLS1 : `IM_ROLLS0;

    // =========================================================================
    // 1. next state
    // =========================================================================
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:  if (start == 1) next_state = S_COUNT;
            S_COUNT: next_state = S_LOAD;
            S_LOAD:  if (i == 20) next_state = S_BLANK;
            S_BLANK: if (f >= start_frame) next_state = S_FRAME;
            S_FRAME: if (f == 9) next_state = S_NEXT;
            S_NEXT:  if (p == 1) next_state = S_IDLE; else next_state = S_COUNT;
            default: next_state = S_IDLE;
        endcase
    end

    // =========================================================================
    // 2. state register
    // =========================================================================
    always @(posedge clk) begin
        if (rst == 1)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // =========================================================================
    // 3. score of frame f (combinational)
    // =========================================================================
    // the three balls that can count for this frame
    wire [3:0] r1 = roll[idx];
    wire [3:0] r2 = roll[idx + 1];
    wire [3:0] r3 = roll[idx + 2];
    // have they been thrown yet?
    wire a1 = (idx     < n);
    wire a2 = (idx + 1 < n);
    wire a3 = (idx + 2 < n);
    wire [4:0] r12 = r1 + r2;

    reg [5:0] m0, m1, m2;                // the marks
    reg       complete;                  // this frame's score is known
    reg [4:0] pts;                       // this frame's points (with bonus)
    reg [4:0] prov_pts;                  // this frame's provisional points
    reg [4:0] next_idx;                  // first roll of the next frame

    always @(*) begin
        m0 = G_SP; m1 = G_SP; m2 = G_SP;
        complete = 0;
        pts      = 0;
        prov_pts = 0;
        next_idx = idx + 2;

        if (f != 9) begin
            // ---------------- frames 1 to 9 ----------------
            if (a1 == 1 && r1 == 10) begin
                // strike: X, points = 10 + next two balls
                m1       = G_X;
                next_idx = idx + 1;
                if (a2 == 1 && a3 == 1) begin
                    complete = 1;
                    pts      = 10 + r2 + r3;
                end
                prov_pts = 10;
                if (a2 == 1) prov_pts = prov_pts + r2;
                if (a3 == 1) prov_pts = prov_pts + r3;
            end
            else begin
                if (a1 == 1) m0 = ball_mark(r1);
                if (a2 == 1) begin
                    if (r12 == 10) m1 = G_SL;
                    else           m1 = ball_mark(r2);
                end

                if (a1 == 1 && a2 == 1 && r12 == 10) begin
                    // spare: points = 10 + next ball
                    if (a3 == 1) begin
                        complete = 1;
                        pts      = 10 + r3;
                    end
                end
                else if (a1 == 1 && a2 == 1) begin
                    // open frame
                    complete = 1;
                    pts      = r12;
                end

                if (a1 == 1) prov_pts = prov_pts + r1;
                if (a2 == 1) prov_pts = prov_pts + r2;
                if (a1 == 1 && a2 == 1 && r12 == 10 && a3 == 1) prov_pts = prov_pts + r3;
            end
        end
        else begin
            // ---------------- frame 10 ----------------
            if (a1 == 1) m0 = ball_mark(r1);
            if (a2 == 1) begin
                if (r1 == 10)       m1 = ball_mark(r2);   // X then anything
                else if (r12 == 10) m1 = G_SL;            // spare
                else                m1 = ball_mark(r2);
            end
            if (a3 == 1) begin
                if (r1 == 10 && r2 != 10 && r2 + r3 == 10) m2 = G_SL;  // X 7 /
                else                                       m2 = ball_mark(r3);
            end

            // finished: open frame after 2 balls, or all 3 balls thrown
            if ((a1 == 1 && a2 == 1 && r1 != 10 && r12 < 10) || a3 == 1) begin
                complete = 1;
                pts      = r12;
                if (a3 == 1) pts = pts + r3;
            end

            if (a1 == 1) prov_pts = prov_pts + r1;
            if (a2 == 1) prov_pts = prov_pts + r2;
            if (a3 == 1) prov_pts = prov_pts + r3;
        end
    end

    wire [8:0] frame_total = complete ? (cum + pts) : 9'd0;
    wire       frame_ok    = complete && known;

    // =========================================================================
    // 4. datapath: what each state does
    // =========================================================================
    always @(posedge clk) begin
        done  <= 0;
        fr_we <= 0;
        if (rst == 1) begin
            p <= 0; n <= 0; i <= 0; f <= 0; idx <= 0;
            cum <= 0; known <= 0; pv <= 0; ra <= 0;
            fr_wa <= 0; fr_wd <= 0;
            ok_p0 <= 0; ok_p1 <= 0; game_p0 <= 0; game_p1 <= 0; prov_p0 <= 0; prov_p1 <= 0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    if (start == 1) begin
                        p  <= 0;
                        ra <= `IM_NROLL0;               // number of rolls, player 1
                    end
                end

                S_COUNT: begin                          // rd = number of rolls
                    if (rd > 21) n <= 21;
                    else         n <= rd[4:0];
                    i     <= 0;
                    f     <= 0;
                    idx   <= 0;
                    cum   <= 0;
                    known <= 1;
                    pv    <= 0;
                    if (p == 0) begin ok_p0 <= 0; game_p0 <= 0; end
                    else        begin ok_p1 <= 0; game_p1 <= 0; end
                    ra <= base;                         // first roll
                end

                S_LOAD: begin                           // rd = roll i
                    roll[i] <= rd[3:0];
                    ra      <= base + i + 1;
                    i       <= i + 1;
                end

                S_BLANK: begin                          // frames before the start
                    if (f < start_frame) begin
                        fr_we <= 1;
                        fr_wa <= {p, f};
                        fr_wd <= 28'd0;
                        f     <= f + 1;
                    end
                end

                S_FRAME: begin
                    // write this frame's word
                    fr_we <= 1;
                    fr_wa <= {p, f};
                    fr_wd <= {frame_ok, frame_total, m0, m1, m2};

                    // running totals
                    if (complete == 1)
                        cum <= cum + pts;
                    if (complete == 0)
                        known <= 0;
                    if (frame_ok == 1) begin
                        if (p == 0) begin ok_p0[f] <= 1; game_p0 <= cum + pts; end
                        else        begin ok_p1[f] <= 1; game_p1 <= cum + pts; end
                    end
                    pv <= pv + prov_pts;
                    if (f == 9) begin
                        if (p == 0) prov_p0 <= pv + prov_pts;
                        else        prov_p1 <= pv + prov_pts;
                    end

                    // next frame
                    f   <= f + 1;
                    idx <= next_idx;
                end

                S_NEXT: begin
                    if (p == 1) begin
                        done <= 1;
                    end
                    else begin
                        p  <= 1;
                        ra <= `IM_NROLL1;               // number of rolls, player 2
                    end
                end

                default: ;
            endcase
        end
    end
endmodule
