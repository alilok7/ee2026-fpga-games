`timescale 1ns / 1ps
//=============================================================================
// note_table.v : the 24-slot active-note table and everything that edits it
//-----------------------------------------------------------------------------
// Owner   : Student C
// Purpose : Holds the notes that are on (or about to come on) screen.
//           Each slot = {valid, missed, lane, note, hit_ms, len_ms}.
//           ONE controller FSM owns the table, so there is only one writer.
//           Its jobs, in priority order, each a scan over the 24 slots:
//             FRAME  (tick_frame) work out each note's y position on screen
//                    and each lane's "time to next note" for the LED guides
//             JUDGE  (a lane was struck) find the EARLIEST pending note in
//                    that lane inside the Good window -> Perfect/Good/stray
//             MISS   (every ms) pending notes past the Good window -> Miss;
//                    missed notes that have left the screen are freed
//             LOAD   (otherwise) copy the loader's next event into a free
//                    slot once it is within LOOKAHEAD ms of its hit time
//           One scan = 25 clocks = 0.25 us, tiny next to a millisecond, so
//           strikes on all 8 lanes at once are all judged within 2 us.
// Screen  : y_bottom = 54 - ((hit_ms - song_ms) >>> speed_shift)
//           height   = max(3, (len_ms >> speed_shift) - 1), capped at 40
//           Shifts, not division: speed_shift 4 means 16 ms per pixel.
// Limits  : 24 notes inside the 4 s look-ahead (e.g. 16ths at 360 BPM).
//           If the table is full the loader simply waits.
//=============================================================================
module note_table #(
    parameter N         = 24,
    parameter LOOKAHEAD = 20'd4000,
    parameter LAG_MS    = 20'd5        // debounce delay of a strike
) (
    input  wire          clk,
    input  wire          clr,
    input  wire          tick_1ms,
    input  wire          tick_frame,
    input  wire [19:0]   song_ms,
    input  wire          paused,
    input  wire [7:0]    perf_w,
    input  wire [7:0]    good_w,
    input  wire [2:0]    speed_shift,
    input  wire [7:0]    lane_strike,
    // from note_loader
    input  wire          evt_valid,
    input  wire [2:0]    evt_lane,
    input  wire [6:0]    evt_note,
    input  wire [19:0]   evt_hit,
    input  wire [15:0]   evt_len,
    output reg           evt_take,
    // judgement events (one per clock at most)
    output reg           j_valid,
    output reg  [1:0]    j_type,        // 0 Perfect, 1 Good, 2 Miss, 3 stray
    output reg  [2:0]    j_lane,
    output reg  [6:0]    j_note,
    output wire          empty,
    // render snapshot (updated during FRAME, i.e. between OLED frames)
    output reg  [N-1:0]  r_vis,
    output reg  [N-1:0]  r_missed,
    output reg  [3*N-1:0] r_lane,
    output reg  [8*N-1:0] r_top,        // signed y of the bar's top row
    output reg  [8*N-1:0] r_bot,        // signed y of the bar's bottom row
    output reg  [8*11-1:0] lane_dt      // per lane ms to next note, 2047 = none
);
    localparam [1:0] J_PERFECT = 2'd0, J_GOOD = 2'd1, J_MISS = 2'd2, J_STRAY = 2'd3;
    localparam [2:0] S_IDLE = 3'd0, S_FRAME = 3'd1, S_JUDGE = 3'd2, S_APPLY = 3'd3,
                     S_MISS = 3'd4, S_FCOMMIT = 3'd5;
    localparam signed [9:0] HIT_Y = 10'sd54;

    // ---------------- slot storage -------------------------------------------
    reg [N-1:0] s_valid, s_missed;
    reg [2:0]   s_lane [0:N-1];
    reg [6:0]   s_note [0:N-1];
    reg [19:0]  s_hit  [0:N-1];
    reg [15:0]  s_len  [0:N-1];

    reg [2:0]  state;
    reg [4:0]  i;                     // scan index
    reg        frame_req, miss_req;
    reg [7:0]  strike_pend;
    reg [2:0]  jl;                    // lane being judged
    reg        best_found;
    reg [4:0]  best_i;
    reg [19:0] best_hit;
    reg [7:0]  best_abs;
    reg [10:0] lane_min [0:7];
    integer    k;

    assign empty = (s_valid == {N{1'b0}});

    // ---------------- scan pipeline -------------------------------------------
    // A scan visits one slot per clock in TWO stages, so no single clock has
    // to do "pick 1 of 24 slots + subtract + shift + compare" (too slow for
    // 10 ns):
    //   stage 0 (index i):  read slot i into c_* and pre-compute the two time
    //                       differences
    //   stage 1 (index ci): everything else, on registers only
    // A scan therefore runs i = 0..N; stage 1 works whenever i != 0.
    reg  [4:0]  ci;
    reg         c_valid, c_missed;
    reg  [2:0]  c_lane;
    reg  [6:0]  c_note;
    reg  [19:0] c_hit;
    reg  [15:0] c_len;
    reg  signed [20:0] d_judge;      // strike time - hit time   (>0 = late)
    reg  signed [20:0] d_to_hit;     // hit time - now           (>0 = still coming)
    wire [19:0] t_now = song_ms - LAG_MS;                     // strike time
    always @(posedge clk) begin                               // stage 0
        ci       <= i;
        c_valid  <= s_valid[i];
        c_missed <= s_missed[i];
        c_lane   <= s_lane[i];
        c_note   <= s_note[i];
        c_hit    <= s_hit[i];
        c_len    <= s_len[i];
        d_judge  <= $signed({1'b0, t_now}) - $signed({1'b0, s_hit[i]});
        d_to_hit <= $signed({1'b0, s_hit[i]}) - $signed({1'b0, song_ms});
    end

    // stage 1 arithmetic for slot ci
    wire [20:0] d_abs   = d_judge[20] ? -d_judge : d_judge;
    wire        in_good = (d_abs <= {13'd0, good_w});
    wire signed [20:0] dy_full  = d_to_hit >>> speed_shift;  // pixels above the line
    // clamp so the bar maths fits in 10 bits; anything beyond is off-screen
    wire signed [9:0]  dy  = (dy_full > 21'sd200) ? 10'sd200 :
                             (dy_full < -21'sd200) ? -10'sd200 : dy_full[9:0];
    wire signed [9:0]  ybot = HIT_Y - dy;
    wire [15:0] len_px = c_len >> speed_shift;
    wire [5:0]  h      = (len_px < 16'd4) ? 6'd3 : (len_px > 16'd41) ? 6'd40 : len_px[5:0] - 6'd1;
    wire signed [9:0]  ytop = ybot - $signed({4'd0, h}) + 10'sd1;
    wire        on_scr = (ybot >= 10'sd10) && (ytop <= 10'sd63);
    wire [10:0] dt_ms  = d_to_hit[20] ? 11'd0 :
                         (d_to_hit > 21'sd2047) ? 11'd2047 : d_to_hit[10:0];
    // clamp to the 8-bit signed range the renderer uses
    wire [7:0]  ybot8 = (ybot > 10'sd127) ? 8'sd127 : (ybot < -10'sd128) ? -8'sd128 : ybot[7:0];
    wire [7:0]  ytop8 = (ytop > 10'sd127) ? 8'sd127 : (ytop < -10'sd128) ? -8'sd128 : ytop[7:0];

    // lowest free slot (priority encoder)
    reg  [4:0] free_i;
    reg        free_ok;
    always @(*) begin
        free_ok = 1'b0;
        free_i  = 5'd0;
        for (k = N - 1; k >= 0; k = k - 1)
            if (!s_valid[k]) begin
                free_ok = 1'b1;
                free_i  = k[4:0];
            end
    end

    // lowest pending strike lane
    reg [2:0] next_lane;
    always @(*) begin
        next_lane = 3'd0;
        for (k = 7; k >= 0; k = k - 1)
            if (strike_pend[k]) next_lane = k[2:0];
    end

    // natural note of a lane, for strays (the switch still plays its note)
    function [6:0] lane_note;
        input [2:0] l;
        case (l)
            3'd0: lane_note = 7'd60; 3'd1: lane_note = 7'd62; 3'd2: lane_note = 7'd64;
            3'd3: lane_note = 7'd65; 3'd4: lane_note = 7'd67; 3'd5: lane_note = 7'd69;
            3'd6: lane_note = 7'd71; default: lane_note = 7'd72;
        endcase
    endfunction

    // ---------------- the controller FSM -------------------------------------
    always @(posedge clk) begin
        evt_take <= 1'b0;
        j_valid  <= 1'b0;
        if (clr) begin
            state <= S_IDLE; i <= 5'd0;
            s_valid <= {N{1'b0}}; s_missed <= {N{1'b0}};
            frame_req <= 1'b0; miss_req <= 1'b0; strike_pend <= 8'd0;
            r_vis <= {N{1'b0}}; r_missed <= {N{1'b0}};
            r_lane <= {3*N{1'b0}}; r_top <= {8*N{1'b0}}; r_bot <= {8*N{1'b0}};
            lane_dt <= {8{11'd2047}};
            j_type <= 2'd0; j_lane <= 3'd0; j_note <= 7'd0; jl <= 3'd0;
            best_found <= 1'b0; best_i <= 5'd0; best_hit <= 20'd0; best_abs <= 8'd0;
            for (k = 0; k < 8; k = k + 1) lane_min[k] <= 11'd2047;
        end else begin
            // requests are remembered until served
            if (tick_frame) frame_req <= 1'b1;
            if (tick_1ms)   miss_req  <= 1'b1;
            strike_pend <= strike_pend | (paused ? 8'd0 : lane_strike);

            case (state)
            S_IDLE: begin
                if (frame_req) begin
                    frame_req <= 1'b0;
                    for (k = 0; k < 8; k = k + 1) lane_min[k] <= 11'd2047;
                    state <= S_FRAME;
                end else if (strike_pend != 8'd0) begin
                    jl          <= next_lane;
                    strike_pend <= (strike_pend & ~(8'd1 << next_lane)) |
                                   (paused ? 8'd0 : lane_strike);
                    best_found  <= 1'b0;
                    state       <= S_JUDGE;
                end else if (miss_req) begin
                    miss_req <= 1'b0;
                    state    <= S_MISS;
                end else if (evt_valid && !evt_take && free_ok &&
                             (evt_hit <= song_ms + LOOKAHEAD)) begin
                    // !evt_take: the loader drops evt_valid one clock after
                    // our take pulse, so never load in the cycle right after.
                    s_valid[free_i]  <= 1'b1;            // LOAD (one clock)
                    s_missed[free_i] <= 1'b0;
                    s_lane[free_i]   <= evt_lane;
                    s_note[free_i]   <= evt_note;
                    s_hit[free_i]    <= evt_hit;
                    s_len[free_i]    <= evt_len;
                    evt_take         <= 1'b1;
                end
            end

            S_FRAME: begin                        // position + LED data for slot ci
                if (i != 5'd0) begin
                    r_vis[ci]          <= c_valid && on_scr;
                    r_missed[ci]       <= c_missed;
                    r_lane[3*ci +: 3]  <= c_lane;
                    r_top[8*ci +: 8]   <= ytop8;
                    r_bot[8*ci +: 8]   <= ybot8;
                    if (c_valid && !c_missed && dt_ms < lane_min[c_lane])
                        lane_min[c_lane] <= dt_ms;
                end
                if (i == N) begin i <= 5'd0; state <= S_FCOMMIT; end
                else        i <= i + 5'd1;
            end

            S_FCOMMIT: begin                      // all slots seen: publish LED data
                for (k = 0; k < 8; k = k + 1) lane_dt[11*k +: 11] <= lane_min[k];
                state <= S_IDLE;
            end

            S_JUDGE: begin                        // earliest pending note in lane jl
                if (i != 5'd0 && c_valid && !c_missed && c_lane == jl && in_good &&
                    (!best_found || c_hit < best_hit)) begin
                    best_found <= 1'b1;
                    best_i     <= ci;
                    best_hit   <= c_hit;
                    best_abs   <= d_abs[7:0];
                end
                if (i == N) begin i <= 5'd0; state <= S_APPLY; end
                else        i <= i + 5'd1;
            end

            S_APPLY: begin
                j_valid <= 1'b1;
                j_lane  <= jl;
                if (best_found) begin
                    j_type           <= (best_abs <= perf_w) ? J_PERFECT : J_GOOD;
                    j_note           <= s_note[best_i];
                    s_valid[best_i]  <= 1'b0;           // hit notes vanish
                end else begin
                    j_type <= J_STRAY;
                    j_note <= lane_note(jl);
                end
                state <= S_IDLE;
            end

            S_MISS: begin
                if (i != 5'd0) begin
                    if (c_valid && !c_missed && !d_judge[20] && d_abs > {13'd0, good_w}) begin
                        s_missed[ci] <= 1'b1;           // passed the window: Miss
                        j_valid <= 1'b1;
                        j_type  <= J_MISS;
                        j_lane  <= c_lane;
                        j_note  <= c_note;
                    end else if (c_valid && c_missed && d_to_hit[20] &&
                                 (-d_to_hit) > 21'sd1500) begin
                        s_valid[ci] <= 1'b0;            // long gone: free it
                    end
                end
                if (i == N) begin i <= 5'd0; state <= S_IDLE; end
                else        i <= i + 5'd1;
            end

            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
