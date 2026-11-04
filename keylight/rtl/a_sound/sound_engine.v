`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// sound_engine.v : KeyLight synthesiser  (VERTICAL-SLICE VERSION)
//-----------------------------------------------------------------------------
// Owner   : Student A
// Status  : Phase 2 slice = ONE square-wave DDS voice with a linear decay.
//           Phase 3 replaces the inside with 4 voices, ADSR, 4 instruments,
//           the SFX ROM and the metronome; the PORTS stay the same.
// Purpose : Direct Digital Synthesis. A 24-bit phase accumulator adds the
//           note's increment every audio sample (48.828 kHz). The top bit of
//           the phase is a square wave at
//               f_out = inc * 48828.125 / 2^24
//           so any pitch is just a different increment from note_rom.
// Ports
//   ev_valid/ev_note/ev_vel   note-on event (MIDI note, velocity 1..3)
//   sfx_valid/sfx_id          sound effects (ignored in the slice)
//   settings                  volume (and later instrument)
//   mute                      sw[1]
//   sample                    8-bit unsigned audio sample, 128 = silence
//   scope_sample              same value, for B's Free Play scope
//   voice_active[3:0]         bit 0 = the slice voice is sounding
//=============================================================================
module sound_engine (
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      tick_sample,
    input  wire                      tick_1ms,
    input  wire                      ev_valid,
    input  wire [6:0]                ev_note,
    input  wire [1:0]                ev_vel,
    input  wire                      sfx_valid,
    input  wire [3:0]                sfx_id,
    input  wire [`KL_SETTINGS_W-1:0] settings,
    input  wire                      mute,
    output reg  [7:0]                sample,
    output wire [7:0]                scope_sample,
    output wire [3:0]                voice_active
);
    // ---- voice state -------------------------------------------------------
    reg  [6:0]  note;
    reg  [23:0] phase;
    reg  [7:0]  amp;              // envelope level, 0 = silent
    reg         decay_div;        // amp drops by 1 every 2 ms -> ~0.5 s note
    wire [23:0] inc;

    note_rom u_rom (.note(note), .inc(inc));

    always @(posedge clk) begin
        if (rst) begin
            note      <= 7'd0;
            phase     <= 24'd0;
            amp       <= 8'd0;
            decay_div <= 1'b0;
        end else begin
            if (ev_valid) begin                       // note-on: retrigger
                note  <= ev_note;
                phase <= 24'd0;
                amp   <= (ev_vel == `KL_VEL_SOFT) ? 8'd150 : 8'd255;
            end else if (tick_1ms) begin              // linear decay
                decay_div <= ~decay_div;
                if (decay_div && amp != 8'd0) amp <= amp - 8'd1;
            end
            if (tick_sample) phase <= phase + inc;
        end
    end

    // ---- volume and output -------------------------------------------------
    // level = amp * (volume + 1) / 8, then the square wave swings +-level/2
    // around 128.
    wire [2:0]  vol   = settings[`KL_SET_VOLUME];
    wire [10:0] scaled = amp * ({1'b0, vol} + 4'd1);  // 8b x 4b, max 2040
    wire [7:0]  level  = scaled[10:3];
    wire [7:0]  half   = level >> 1;

    always @(posedge clk) begin
        if (rst)
            sample <= 8'd128;
        else if (tick_sample)
            sample <= (mute || amp == 8'd0) ? 8'd128
                    : (phase[23] ? 8'd128 + half : 8'd128 - half);
    end

    assign scope_sample = sample;
    assign voice_active = {3'b000, amp != 8'd0};

    // Unused in the slice (kept so the port list is final).
    wire unused_ok = &{1'b0, sfx_valid, sfx_id};
endmodule
