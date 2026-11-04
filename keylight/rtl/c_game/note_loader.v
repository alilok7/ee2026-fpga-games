`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// note_loader.v : walks the chart and turns steps into milliseconds
//-----------------------------------------------------------------------------
// Owner   : Student C
// Purpose : Reads the header (step_ms, event count) and the LAST event (to
//           know the song length for the progress bar), then hands events
//           to the note table one at a time.
//               hit_ms = start_step * step_ms + lead_ms
//               len_ms = len_steps  * step_ms
//           lead_ms = 32 steps (2 bars of count-in) = step_ms << 5.
//           Both products use ONE multiplier (mul_a * step_ms), used in
//           different FSM states -> one DSP block for the whole loader.
// Chart port timing: address is registered here, the ROM registers it again,
//           so data is read 2 states after the address is set (_WAIT state).
// Ports
//   start          1-cycle pulse: begin a new song
//   hdr_valid      header/step_ms/lead_ms/total_ms are valid
//   evt_*          next event, held while evt_valid until evt_take
//   done           every event has been handed over
//=============================================================================
module note_loader (
    input  wire                    clk,
    input  wire                    clr,
    input  wire                    start,
    output reg  [`KL_CHART_AW-1:0] chart_addr,
    input  wire [`KL_CHART_DW-1:0] chart_data,
    output reg                     hdr_valid,
    output reg  [9:0]              step_ms,
    output reg  [19:0]             lead_ms,
    output reg  [19:0]             total_ms,
    output reg                     evt_valid,
    output reg  [2:0]              evt_lane,
    output reg  [6:0]              evt_note,
    output reg  [19:0]             evt_hit,
    output reg  [15:0]             evt_len,
    input  wire                    evt_take,
    output reg                     done
);
    localparam S_IDLE = 4'd0,  S_H_WAIT = 4'd1, S_H_READ = 4'd2, S_L_WAIT = 4'd3,
               S_L_READ = 4'd4, S_L_MUL = 4'd5,  S_E_WAIT = 4'd6, S_E_READ = 4'd7,
               S_E_MUL1 = 4'd8, S_E_MUL2 = 4'd9, S_PRESENT = 4'd10, S_DONE = 4'd11;

    reg  [3:0]  state;
    reg  [8:0]  count, idx;
    reg  [11:0] mul_a;
    reg  [5:0]  len_steps;
    wire [21:0] prod = mul_a * step_ms;              // the shared multiplier

    // Lane of a note: white keys map to themselves, a sharp goes to the lane
    // of the natural below it (C#->C, D#->D, F#->F, G#->G, A#->A).
    function [2:0] lane_of;
        input [6:0] note;
        reg   [6:0] k;
        begin
            k = (note < 7'd60) ? 7'd0 : (note > 7'd72) ? 7'd12 : note - 7'd60;
            case (k)
                7'd0, 7'd1:  lane_of = 3'd0;
                7'd2, 7'd3:  lane_of = 3'd1;
                7'd4:        lane_of = 3'd2;
                7'd5, 7'd6:  lane_of = 3'd3;
                7'd7, 7'd8:  lane_of = 3'd4;
                7'd9, 7'd10: lane_of = 3'd5;
                7'd11:       lane_of = 3'd6;
                default:     lane_of = 3'd7;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (clr) begin
            state <= S_IDLE;
            chart_addr <= 9'd0;
            {hdr_valid, evt_valid, done} <= 3'b000;
            step_ms <= 10'd0; lead_ms <= 20'd0; total_ms <= 20'd0;
            count <= 9'd0; idx <= 9'd0; mul_a <= 12'd0; len_steps <= 6'd0;
            evt_lane <= 3'd0; evt_note <= 7'd0; evt_hit <= 20'd0; evt_len <= 16'd0;
        end else begin
            case (state)
                S_IDLE: if (start) begin
                    chart_addr <= 9'd0;                       // header
                    state      <= S_H_WAIT;
                end
                S_H_WAIT: state <= S_H_READ;
                S_H_READ: begin
                    step_ms <= chart_data[`KL_HDR_STEPMS];
                    lead_ms <= {5'd0, chart_data[`KL_HDR_STEPMS], 5'b0};   // x 32
                    count   <= chart_data[`KL_HDR_COUNT];
                    if (chart_data[`KL_HDR_COUNT] == 9'd0) begin
                        total_ms  <= {5'd0, chart_data[`KL_HDR_STEPMS], 5'b0};
                        hdr_valid <= 1'b1;
                        state     <= S_DONE;
                    end else begin
                        chart_addr <= chart_data[`KL_HDR_COUNT];   // last event
                        state      <= S_L_WAIT;
                    end
                end
                S_L_WAIT: state <= S_L_READ;
                S_L_READ: begin
                    mul_a <= {1'b0, chart_data[`KL_EV_START]} + {6'd0, chart_data[`KL_EV_LEN]};
                    state <= S_L_MUL;
                end
                S_L_MUL: begin
                    total_ms   <= prod[19:0] + lead_ms;          // end of last note
                    hdr_valid  <= 1'b1;
                    idx        <= 9'd1;
                    chart_addr <= 9'd1;
                    state      <= S_E_WAIT;
                end
                S_E_WAIT: state <= S_E_READ;
                S_E_READ: begin
                    if (chart_data[`KL_EV_NOTE] == 7'd0 || idx > count) begin
                        state <= S_DONE;                          // end marker
                    end else begin
                        evt_note  <= chart_data[`KL_EV_NOTE];
                        evt_lane  <= lane_of(chart_data[`KL_EV_NOTE]);
                        mul_a     <= {1'b0, chart_data[`KL_EV_START]};
                        len_steps <= chart_data[`KL_EV_LEN];
                        state     <= S_E_MUL1;
                    end
                end
                S_E_MUL1: begin
                    evt_hit <= prod[19:0] + lead_ms;
                    mul_a   <= {6'd0, len_steps};
                    state   <= S_E_MUL2;
                end
                S_E_MUL2: begin
                    evt_len   <= prod[15:0];
                    evt_valid <= 1'b1;
                    state     <= S_PRESENT;
                end
                S_PRESENT: if (evt_take) begin
                    evt_valid  <= 1'b0;
                    idx        <= idx + 9'd1;
                    chart_addr <= idx + 9'd1;
                    state      <= S_E_WAIT;
                end
                default: done <= 1'b1;                            // S_DONE
            endcase
        end
    end
endmodule
