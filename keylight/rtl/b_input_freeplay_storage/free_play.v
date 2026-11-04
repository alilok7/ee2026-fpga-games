`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// free_play.v : Free Play piano  (VERTICAL-SLICE VERSION)
//-----------------------------------------------------------------------------
// Owner   : Student B
// Status  : Slice = the 13-key piano plays notes and lights the on-screen
//           keys. Phase 3 adds note names, the scope, the recorder,
//           playback and MY SONG; the ports for those are already here.
// Purpose : Every key strike becomes a note-on event for A. Several keys
//           struck in the same clock (a chord) are queued in `pend` and sent
//           one per clock, so no note is lost.
//           Each key has a glow timer (ms) for the on-screen key and LED.
// Screen  : lower half = piano. White key k spans x = 12k+1 .. 12k+10;
//           a black key is 7 px wide, centred on the line between two
//           white keys. Range checks only.
//=============================================================================
module free_play (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  tick_1ms,
    input  wire [`KL_MODE_W-1:0] mode,
    input  wire [12:0]           key_strike,
    input  wire                  octave_up,
    input  wire [6:0]            px_x,
    input  wire [5:0]            px_y,
    output reg  [15:0]           px_color,
    output reg                   ev_valid,
    output reg  [6:0]            ev_note,
    output wire [1:0]            ev_vel,
    output reg  [15:0]           led_req,
    output wire [23:0]           seg_glyphs,
    output wire [3:0]            seg_dp,
    output wire [3:0]            seg_blink,
    output wire                  rec_exists
);
    localparam [7:0] GLOW_MS = 8'd250;
    wire active = (mode == `KL_MODE_FREE);

    // ---- strike queue -> note events ---------------------------------------
    reg  [12:0] pend;
    reg  [3:0]  first;                       // lowest pending key
    integer k;
    always @(*) begin
        first = 4'd0;
        for (k = 12; k >= 0; k = k - 1) if (pend[k]) first = k[3:0];
    end
    always @(posedge clk) begin
        ev_valid <= 1'b0;
        ev_note  <= 7'd0;
        if (rst || !active) begin
            pend <= 13'd0;
        end else begin
            pend <= (pend & ~((pend != 13'd0) ? (13'd1 << first) : 13'd0)) | key_strike;
            if (pend != 13'd0) begin
                ev_valid <= 1'b1;
                ev_note  <= `KL_MIDI_C4 + {3'd0, first} + (octave_up ? 7'd12 : 7'd0);
            end
        end
    end
    assign ev_vel = `KL_VEL_NORMAL;

    // ---- glow timers --------------------------------------------------------
    reg [7:0] glow [0:12];
    always @(posedge clk) begin
        for (k = 0; k < 13; k = k + 1) begin
            if (rst || !active)            glow[k] <= 8'd0;
            else if (key_strike[k])        glow[k] <= GLOW_MS;
            else if (tick_1ms && glow[k] != 8'd0) glow[k] <= glow[k] - 8'd1;
        end
    end

    // ---- piano renderer -------------------------------------------------------
    // white key index (0..7) -> chromatic key, and the lane palette colour
    wire [12:0] p43 = px_x * 6'd43;
    wire [2:0]  wk  = p43[11:9];                                   // x / 12
    wire [6:0]  lx  = px_x - ({1'b0, wk, 3'b000} + {2'b00, wk, 2'b00});
    reg  [3:0]  w_chrom;
    always @(*) begin
        case (wk)
            3'd0: w_chrom = 4'd0;  3'd1: w_chrom = 4'd2;  3'd2: w_chrom = 4'd4;
            3'd3: w_chrom = 4'd5;  3'd4: w_chrom = 4'd7;  3'd5: w_chrom = 4'd9;
            3'd6: w_chrom = 4'd11; default: w_chrom = 4'd12;
        endcase
    end
    // a black key sits on the boundary after white keys C, D, F, G, A
    wire       has_black_r = (wk != 3'd2) && (wk != 3'd6) && (wk != 3'd7);   // right edge
    wire       has_black_l = (wk != 3'd0) && (wk != 3'd3) && (wk != 3'd7);   // left edge
    wire       in_black    = (px_y >= 6'd28) && (px_y <= 6'd46) &&
                             ((has_black_r && lx >= 7'd9) || (has_black_l && lx <= 7'd2));
    wire [3:0] b_chrom     = (lx >= 7'd9) ? w_chrom + 4'd1 : w_chrom - 4'd1;
    wire [2:0] b_lane      = (lx >= 7'd9) ? wk : wk - 3'd1;            // sharp = lower natural

    wire [15:0] w_col, b_col;
    note_palette u_pw (.lane(wk),     .dark(1'b0), .color(w_col));
    note_palette u_pb (.lane(b_lane), .dark(1'b1), .color(b_col));

    always @(*) begin
        px_color = `KL_BLACK;
        if (px_y >= 6'd28 && px_y <= 6'd55) begin
            if (in_black)
                px_color = (glow[b_chrom] != 8'd0) ? b_col : 16'h2104;
            else if (lx >= 7'd1 && lx <= 7'd10)
                px_color = (glow[w_chrom] != 8'd0) ? w_col : 16'hDEFB;
        end
    end

    // ---- LEDs: the LED above a struck switch glows while its note rings -------
    always @(*) begin
        led_req = 16'h0000;
        led_req[15] = glow[0]  != 0;  led_req[14] = glow[2]  != 0;  led_req[13] = glow[4] != 0;
        led_req[12] = glow[5]  != 0;  led_req[11] = glow[7]  != 0;  led_req[10] = glow[9] != 0;
        led_req[9]  = glow[11] != 0;  led_req[8]  = glow[12] != 0;
        led_req[7]  = glow[1]  != 0;  led_req[6]  = glow[3]  != 0;  led_req[5]  = glow[6] != 0;
        led_req[4]  = glow[8]  != 0;  led_req[3]  = glow[10] != 0;
    end

    // "FrEE" on the 7-seg; MY SONG not available until the recorder exists
    assign seg_glyphs = {6'd15, 6'd27, 6'd14, 6'd14};
    assign seg_dp     = 4'b0000;
    assign seg_blink  = 4'b0000;
    assign rec_exists = 1'b0;
endmodule
