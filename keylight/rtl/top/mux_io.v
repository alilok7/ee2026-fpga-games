`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// mux_io.v : who owns the LEDs, 7-seg and sound bus in each mode
//-----------------------------------------------------------------------------
// Owner (Q&A) : Student B
// Purpose     : Each part produces REQUESTS (led_req, seg glyphs, note
//               events); this module picks one owner per mode, like a
//               multiplexer whose select is the mode:
//                 Play -> C,  Free Play -> B,  everything else -> D.
//               The three status LEDs are global: led[2] recording,
//               led[1] muted, led[0] paused.
//               Note events: Play -> C, Free -> B (Learn -> D later).
//               Sound effects: C's in Play, D's (UI sounds) otherwise.
//=============================================================================
module mux_io (
    input  wire [`KL_MODE_W-1:0] mode,
    input  wire                  muted,
    input  wire                  paused,
    input  wire                  recording,
    // LED requests
    input  wire [15:0]           led_c,
    input  wire [15:0]           led_b,
    input  wire [15:0]           led_d,
    // 7-seg requests
    input  wire [23:0]           seg_g_c, seg_g_b, seg_g_d,
    input  wire [3:0]            seg_dp_c, seg_dp_b, seg_dp_d,
    input  wire [3:0]            seg_bl_c, seg_bl_b, seg_bl_d,
    // sound requests
    input  wire                  ev_v_c, ev_v_b, ev_v_d,
    input  wire [6:0]            ev_n_c, ev_n_b, ev_n_d,
    input  wire [1:0]            ev_l_c, ev_l_b, ev_l_d,
    input  wire                  sfx_v_c, sfx_v_d,
    input  wire [3:0]            sfx_i_c, sfx_i_d,
    // to the board / sound engine
    output reg  [15:0]           led,
    output reg  [23:0]           seg_glyphs,
    output reg  [3:0]            seg_dp,
    output reg  [3:0]            seg_blink,
    output reg                   ev_valid,
    output reg  [6:0]            ev_note,
    output reg  [1:0]            ev_vel,
    output reg                   sfx_valid,
    output reg  [3:0]            sfx_id
);
    wire in_play = (mode == `KL_MODE_PLAY);
    wire in_free = (mode == `KL_MODE_FREE);
    wire in_lrn  = (mode == `KL_MODE_LEARN);

    always @(*) begin
        // LEDs and 7-seg
        if (in_play) begin
            led = led_c; seg_glyphs = seg_g_c; seg_dp = seg_dp_c; seg_blink = seg_bl_c;
        end else if (in_free) begin
            led = led_b; seg_glyphs = seg_g_b; seg_dp = seg_dp_b; seg_blink = seg_bl_b;
        end else begin
            led = led_d; seg_glyphs = seg_g_d; seg_dp = seg_dp_d; seg_blink = seg_bl_d;
        end
        led[2] = recording;
        led[1] = muted;
        led[0] = paused && (in_play || in_lrn);

        // note events
        if (in_play)      begin ev_valid = ev_v_c; ev_note = ev_n_c; ev_vel = ev_l_c; end
        else if (in_free) begin ev_valid = ev_v_b; ev_note = ev_n_b; ev_vel = ev_l_b; end
        else if (in_lrn)  begin ev_valid = ev_v_d; ev_note = ev_n_d; ev_vel = ev_l_d; end
        else              begin ev_valid = 1'b0;   ev_note = 7'd0;   ev_vel = 2'd0;   end

        // sound effects
        if (in_play) begin sfx_valid = sfx_v_c; sfx_id = sfx_i_c; end
        else         begin sfx_valid = sfx_v_d; sfx_id = sfx_i_d; end
    end
endmodule
