`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// persist_ctrl.v : every change to the save image goes through here
//-----------------------------------------------------------------------------
// Owner   : Student D
// Purpose : One writer = no write collisions. Callers fire 1-cycle commands;
//           each command type has its own "pending" flag and latched
//           arguments, and the FSM below serves the pending ones one at a
//           time as a short sequence of byte reads / writes (1 per clock).
//   ROLL     rolls[p][idx] = value, nroll[p] = idx + 1
//   HEADER   game in progress {valid, kind, player, frame}
//   CLEAR    all rolls = 15 ("not thrown"), counts 0, no game saved
//   STRIKE / SPARE   16-bit lifetime counter + 1 (read, add, write)
//   GAMEEND  games + 1; a Full game better than the best becomes the best
//   INSERT   new top-5 entry: find the first slot it beats, move the lower
//            entries down by one (from the bottom up, so nothing is
//            overwritten before it is copied), then write it
//   SETTINGS the 16-bit settings word
//   DEFAULTS factory image (first boot, no valid save, or "erase saves")
// Ports  : busy = something is pending or running (flash_ctrl waits for 0
//          before it takes a snapshot, so a save is always consistent).
//=============================================================================
module persist_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire        c_roll,
    input  wire        roll_p,
    input  wire [4:0]  roll_idx,
    input  wire [3:0]  roll_val,
    input  wire        c_hdr,
    input  wire        hdr_valid,
    input  wire [2:0]  hdr_kind,
    input  wire        hdr_player,
    input  wire [3:0]  hdr_frame,
    input  wire        c_clear,
    input  wire        c_strike,
    input  wire        c_spare,
    input  wire        c_gameend,
    input  wire        c_insert,
    input  wire        ins_quick,
    input  wire [8:0]  ins_score,
    input  wire [14:0] ins_name,         // 3 x 5-bit letters
    input  wire        c_settings,
    input  wire [15:0] set_value,
    input  wire        c_defaults,
    input  wire        gend_full,
    input  wire [8:0]  gend_score,
    // save image port
    output reg         we,
    output reg  [6:0]  wa,
    output reg  [7:0]  wd,
    output reg  [6:0]  ra,
    input  wire [7:0]  rd,
    output wire        busy
);
    // ---------------- pending flags + latched arguments ---------------------
    localparam N = 10;
    localparam P_DEF = 0, P_CLR = 1, P_ROLL = 2, P_HDR = 3, P_STRK = 4, P_SPAR = 5,
               P_GEND = 6, P_INS = 7, P_SET = 8;
    reg [N-1:0] pend;
    reg        a_p;  reg [4:0] a_idx; reg [3:0] a_val;
    reg        a_hv; reg [2:0] a_hk; reg a_hp; reg [3:0] a_hf;
    reg        a_iq; reg [8:0] a_is; reg [14:0] a_in;
    reg [15:0] a_set;
    reg        a_gf; reg [8:0] a_gs;

    // ---------------- sequencer --------------------------------------------
    localparam S_IDLE = 2'd0, S_RUN = 2'd1;
    reg [1:0] st;
    reg [3:0] job;                     // which pending flag is being served
    reg [7:0] step;                    // micro-step inside the job
    reg [7:0] t0, t1;                  // temporaries (read data)
    reg [2:0] pos, k;                  // INSERT: slot found / slot being moved
    reg [2:0] b;                       // byte inside an entry
    reg [2:0] isub;                    // INSERT sub-state
    // busy from the very clock a command arrives, so a caller that fires a
    // command and then waits for "not busy" can never slip in before it is
    // done (found by the screenshots: the rescore read the rolls too early)
    assign busy = (pend != 0) || (st != S_IDLE) || c_roll || c_hdr || c_clear || c_strike ||
                  c_spare || c_gameend || c_insert || c_settings || c_defaults;

    // default content of image byte a
    function [7:0] def_byte;
        input [6:0] a;
        begin
            if (a == `IM_MAGIC0)      def_byte = 8'h53;
            else if (a == `IM_MAGIC1) def_byte = 8'h4C;
            else if (a == `IM_VER)    def_byte = 8'h01;
            else if (a == `IM_SET_LO) def_byte = `SET_DEFAULT & 16'hFF;
            else if (a == `IM_SET_HI) def_byte = `SET_DEFAULT >> 8;
            else if (a >= `IM_ROLLS0 && a < `IM_NROLL0) def_byte = 8'h0F;
            else                      def_byte = 8'h00;
        end
    endfunction

    wire [6:0] tbl = a_iq ? `IM_TOPQ : `IM_TOPF;
    // address of byte bb of entry kk in the table being edited
    function [6:0] ent;
        input [2:0] kk, bb;
        ent = tbl + {kk, 2'b00} + {4'd0, kk} + {4'd0, bb};
    endfunction

    always @(posedge clk) begin
        we <= 1'b0;
        if (rst) begin
            pend <= 0; st <= S_IDLE; job <= 0; step <= 0; isub <= 0; t0 <= 0; t1 <= 0; pos <= 0; k <= 0; b <= 0;
            wa <= 0; wd <= 0; ra <= 0;
            a_p <= 0; a_idx <= 0; a_val <= 0; a_hv <= 0; a_hk <= 0; a_hp <= 0; a_hf <= 0;
            a_iq <= 0; a_is <= 0; a_in <= 0; a_set <= `SET_DEFAULT; a_gf <= 0; a_gs <= 0;
        end else begin
            // ---- accept commands (latched until served) ----
            if (c_defaults) pend[P_DEF] <= 1'b1;
            if (c_clear)    pend[P_CLR] <= 1'b1;
            if (c_roll)     begin pend[P_ROLL] <= 1'b1; a_p <= roll_p; a_idx <= roll_idx; a_val <= roll_val; end
            if (c_hdr)      begin pend[P_HDR] <= 1'b1; a_hv <= hdr_valid; a_hk <= hdr_kind; a_hp <= hdr_player; a_hf <= hdr_frame; end
            if (c_strike)   pend[P_STRK] <= 1'b1;
            if (c_spare)    pend[P_SPAR] <= 1'b1;
            if (c_gameend)  begin pend[P_GEND] <= 1'b1; a_gf <= gend_full; a_gs <= gend_score; end
            if (c_insert)   begin pend[P_INS] <= 1'b1; a_iq <= ins_quick; a_is <= ins_score; a_in <= ins_name; end
            if (c_settings) begin pend[P_SET] <= 1'b1; a_set <= set_value; end

            case (st)
                S_IDLE: begin
                    step <= 0; isub <= 3'd0;
                    // lowest pending flag first (DEFAULTS before anything else)
                    if      (pend[P_DEF])  begin job <= P_DEF;  st <= S_RUN; end
                    else if (pend[P_CLR])  begin job <= P_CLR;  st <= S_RUN; end
                    else if (pend[P_ROLL]) begin job <= P_ROLL; st <= S_RUN; end
                    else if (pend[P_HDR])  begin job <= P_HDR;  st <= S_RUN; end
                    else if (pend[P_STRK]) begin job <= P_STRK; st <= S_RUN; end
                    else if (pend[P_SPAR]) begin job <= P_SPAR; st <= S_RUN; end
                    else if (pend[P_GEND]) begin job <= P_GEND; st <= S_RUN; end
                    else if (pend[P_INS])  begin job <= P_INS;  st <= S_RUN; end
                    else if (pend[P_SET])  begin job <= P_SET;  st <= S_RUN; end
                end
                S_RUN: begin
                    step <= step + 8'd1;
                    case (job)
                        P_DEF: begin                              // 128 writes
                            we <= 1'b1; wa <= step[6:0]; wd <= def_byte(step[6:0]);
                            if (step == 8'd127) begin pend[P_DEF] <= 1'b0; st <= S_IDLE; end
                        end
                        P_CLR: begin                              // rolls, counts, game flag
                            we <= 1'b1;
                            if (step < 8'd42)       begin wa <= `IM_ROLLS0 + step[6:0]; wd <= 8'h0F; end
                            else if (step == 8'd42) begin wa <= `IM_NROLL0; wd <= 8'h00; end
                            else if (step == 8'd43) begin wa <= `IM_NROLL1; wd <= 8'h00; end
                            else begin
                                wa <= `IM_GVALID; wd <= 8'h00;
                                pend[P_CLR] <= 1'b0; st <= S_IDLE;
                            end
                        end
                        P_ROLL: begin
                            we <= 1'b1;
                            if (step == 0) begin
                                wa <= (a_p ? `IM_ROLLS1 : `IM_ROLLS0) + {2'b00, a_idx}; wd <= {4'd0, a_val};
                            end else begin
                                wa <= a_p ? `IM_NROLL1 : `IM_NROLL0; wd <= {3'd0, a_idx} + 8'd1;
                                pend[P_ROLL] <= 1'b0; st <= S_IDLE;
                            end
                        end
                        P_HDR: begin
                            we <= 1'b1;
                            case (step[1:0])
                                2'd0: begin wa <= `IM_GVALID;  wd <= {7'd0, a_hv}; end
                                2'd1: begin wa <= `IM_GKIND;   wd <= {5'd0, a_hk}; end
                                2'd2: begin wa <= `IM_GPLAYER; wd <= {7'd0, a_hp}; end
                                default: begin
                                    wa <= `IM_GFRAME; wd <= {4'd0, a_hf};
                                    pend[P_HDR] <= 1'b0; st <= S_IDLE;
                                end
                            endcase
                        end
                        P_STRK, P_SPAR, P_GEND: begin             // 16-bit increment
                            case (step)
                                8'd0: ra <= (job == P_STRK) ? `IM_STRK : (job == P_SPAR) ? `IM_SPAR : `IM_GAMES;
                                8'd1: begin t0 <= rd; ra <= ra + 7'd1; end
                                8'd2: begin
                                    t1 <= rd;
                                    we <= 1'b1; wa <= ra - 7'd1; wd <= t0 + 8'd1;
                                end
                                8'd3: begin
                                    we <= 1'b1; wa <= ra; wd <= t1 + ((t0 == 8'hFF) ? 8'd1 : 8'd0);
                                    if (job != P_GEND || !a_gf) begin pend[job] <= 1'b0; st <= S_IDLE; end
                                    else ra <= `IM_BEST;
                                end
                                8'd4: begin t0 <= rd; ra <= `IM_BEST + 7'd1; end   // best lo
                                8'd5: begin                                        // best hi
                                    t1 <= rd;
                                    if (a_gs > {rd[0], t0}) begin we <= 1'b1; wa <= `IM_BEST; wd <= a_gs[7:0]; end
                                end
                                default: begin
                                    if (a_gs > {t1[0], t0}) begin we <= 1'b1; wa <= `IM_BEST + 7'd1; wd <= {7'd0, a_gs[8]}; end
                                    pend[P_GEND] <= 1'b0; st <= S_IDLE;
                                end
                            endcase
                        end
                        P_INS: begin
                            // reads: the address is set in one clock, the data
                            // is used in the next (ra is a register)
                            case (isub)
                                3'd0: begin k <= 3'd0; ra <= ent(3'd0, 3'd1); isub <= 3'd1; end
                                3'd1: begin t1 <= rd; ra <= ent(k, 3'd0); isub <= 3'd2; end  // {valid, hi}
                                3'd2: begin                                                  // lo: compare
                                    if (!t1[7] || a_is > {t1[0], rd}) begin pos <= k; isub <= 3'd3; end
                                    else if (k == 3'd4) begin pend[P_INS] <= 1'b0; st <= S_IDLE; end
                                    else begin k <= k + 3'd1; ra <= ent(k + 3'd1, 3'd1); isub <= 3'd1; end
                                end
                                3'd3: begin                     // move entries 3..pos down one slot
                                    k <= 3'd3; b <= 3'd0; ra <= ent(3'd3, 3'd0);
                                    isub <= (pos == 3'd4) ? 3'd5 : 3'd4;
                                end
                                3'd4: begin                     // rd = byte b of entry k
                                    we <= 1'b1; wa <= ent(k + 3'd1, b); wd <= rd;
                                    if (b == 3'd4) begin
                                        b <= 3'd0;
                                        if (k == pos) isub <= 3'd5;
                                        else begin k <= k - 3'd1; ra <= ent(k - 3'd1, 3'd0); end
                                    end else begin
                                        b <= b + 3'd1; ra <= ent(k, b + 3'd1);
                                    end
                                end
                                default: begin                  // write the new entry at pos
                                    we <= 1'b1; wa <= ent(pos, b);
                                    case (b)
                                        3'd0: wd <= a_is[7:0];
                                        3'd1: wd <= {1'b1, 6'd0, a_is[8]};
                                        3'd2: wd <= {3'd0, a_in[14:10]};
                                        3'd3: wd <= {3'd0, a_in[9:5]};
                                        default: wd <= {3'd0, a_in[4:0]};
                                    endcase
                                    if (b == 3'd4) begin pend[P_INS] <= 1'b0; st <= S_IDLE; end
                                    else b <= b + 3'd1;
                                end
                            endcase
                        end
                        P_SET: begin
                            we <= 1'b1;
                            if (step == 0) begin wa <= `IM_SET_LO; wd <= a_set[7:0]; end
                            else begin wa <= `IM_SET_HI; wd <= a_set[15:8]; pend[P_SET] <= 1'b0; st <= S_IDLE; end
                        end
                        default: begin pend <= 0; st <= S_IDLE; end
                    endcase
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
