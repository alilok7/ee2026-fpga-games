`timescale 1ns / 1ps
`include "strike_defs.vh"
// persist_ctrl.v : the only module that writes the save image during a game
// Student D. Each 1-clock command sets a pending flag; the FSM serves them one
// at a time (one read or write per clock). busy = something pending or running.
module persist_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire        c_roll,           // ---- from C turn_fsm ----
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
    input  wire        c_gameend,        // ---- from game_fsm ----
    input  wire        c_insert,
    input  wire        ins_quick,
    input  wire [8:0]  ins_score,
    input  wire [14:0] ins_name,         // 3 letters x 5 bits (0 = A)
    input  wire        c_settings,
    input  wire [15:0] set_value,
    input  wire        c_defaults,
    input  wire        gend_full,
    input  wire [8:0]  gend_score,
    output reg         we,               // ---- save image port 1 ----
    output reg  [6:0]  wa,
    output reg  [7:0]  wd,
    output reg  [6:0]  ra,
    input  wire [7:0]  rd,
    output wire        busy
);
    // pending flags + the arguments latched with them
    parameter P_DEF = 0, P_CLR = 1, P_ROLL = 2, P_HDR = 3, P_STRK = 4, P_SPAR = 5,
              P_GEND = 6, P_INS = 7, P_SET = 8;
    reg [8:0]  pend;
    reg        a_p;  reg [4:0] a_idx; reg [3:0] a_val;                 // ROLL
    reg        a_hv; reg [2:0] a_hk;  reg a_hp; reg [3:0] a_hf;        // HEADER
    reg        a_iq; reg [8:0] a_is;  reg [14:0] a_in;                 // INSERT
    reg [15:0] a_set;                                                  // SETTINGS
    reg        a_gf; reg [8:0] a_gs;                                   // GAMEEND

    // states
    parameter S_IDLE      = 4'd0,
              S_DEF       = 4'd1,
              S_CLR       = 4'd2,     // 45 writes
              S_ROLL      = 4'd3,     // 2 writes
              S_HDR       = 4'd4,     // 4 writes
              S_STRK      = 4'd5,
              S_SPAR      = 4'd6,
              S_GEND      = 4'd7,
              S_BEST      = 4'd8,
              S_INS_FIND  = 4'd9,     // INSERT: start at entry 0
              S_INS_RDHI  = 4'd10,
              S_INS_CMP   = 4'd11,    //         read score lo, compare
              S_INS_SHIFT = 4'd12,
              S_INS_MOVE  = 4'd13,
              S_INS_WRITE = 4'd14,    //         write the new entry at pos
              S_SET       = 4'd15;    // 2 writes
    reg [3:0] state, nextstate;

    // datapath registers
    reg [7:0] step;
    reg [7:0] t0, t1;                 // bytes read
    reg [2:0] k;
    reg [2:0] pos;
    reg [2:0] b;

    // busy from the very clock a command arrives
    assign busy = (pend != 0) || (state != S_IDLE) || c_roll || c_hdr || c_clear || c_strike ||
                  c_spare || c_gameend || c_insert || c_settings || c_defaults;

    // top-5 entry addresses: entry e starts at tbl + 5e (= {e,2'b00} + e)
    wire [6:0] tbl      = a_iq ? `IM_TOPQ : `IM_TOPF;
    wire [6:0] base_k   = tbl + {2'b00, k, 2'b00} + {4'd0, k};       // entry k
    wire [6:0] base_k1  = base_k + 7'd5;                             // entry k+1
    wire [6:0] base_km1 = base_k - 7'd5;                             // entry k-1
    wire [6:0] base_pos = tbl + {2'b00, pos, 2'b00} + {4'd0, pos};   // entry pos
    // does the new score beat entry k? (empty entry: valid bit = 0 -> yes)
    wire beats = !t1[7] || (a_is > {t1[0], rd});

    // factory value of image byte "step" (combinational)
    reg [7:0] def_byte;
    always @(*) begin
        if      (step[6:0] == `IM_MAGIC0) def_byte = 8'h53;                    // 'S'
        else if (step[6:0] == `IM_MAGIC1) def_byte = 8'h4C;                    // 'L'
        else if (step[6:0] == `IM_VER)    def_byte = 8'h01;
        else if (step[6:0] == `IM_SET_LO) def_byte = `SET_DEFAULT & 16'hFF;
        else if (step[6:0] == `IM_SET_HI) def_byte = `SET_DEFAULT >> 8;
        else if (step[6:0] >= `IM_ROLLS0 && step[6:0] < `IM_NROLL0) def_byte = 8'h0F;  // not thrown
        else                              def_byte = 8'h00;
    end

    // next-state logic
    always @(*) begin
        nextstate = state;
        case (state)
            S_IDLE: begin                     // lowest pending flag first
                if      (pend[P_DEF])  nextstate = S_DEF;
                else if (pend[P_CLR])  nextstate = S_CLR;
                else if (pend[P_ROLL]) nextstate = S_ROLL;
                else if (pend[P_HDR])  nextstate = S_HDR;
                else if (pend[P_STRK]) nextstate = S_STRK;
                else if (pend[P_SPAR]) nextstate = S_SPAR;
                else if (pend[P_GEND]) nextstate = S_GEND;
                else if (pend[P_INS])  nextstate = S_INS_FIND;
                else if (pend[P_SET])  nextstate = S_SET;
            end
            S_DEF:       if (step == 8'd127) nextstate = S_IDLE;
            S_CLR:       if (step == 8'd44)  nextstate = S_IDLE;
            S_ROLL:      if (step == 8'd1)   nextstate = S_IDLE;
            S_HDR:       if (step == 8'd3)   nextstate = S_IDLE;
            S_STRK,
            S_SPAR:      if (step == 8'd3)   nextstate = S_IDLE;
            S_GEND:      if (step == 8'd3)   nextstate = a_gf ? S_BEST : S_IDLE;
            S_BEST:      if (step == 8'd2)   nextstate = S_IDLE;
            S_INS_FIND:  nextstate = S_INS_RDHI;
            S_INS_RDHI:  nextstate = S_INS_CMP;
            S_INS_CMP:   if (beats)          nextstate = S_INS_SHIFT;
                         else if (k == 3'd4) nextstate = S_IDLE;           // beats nobody
                         else                nextstate = S_INS_RDHI;       // try entry k+1
            S_INS_SHIFT: nextstate = (pos == 3'd4) ? S_INS_WRITE : S_INS_MOVE;  // last place: nothing to move
            S_INS_MOVE:  if (b == 3'd4 && k == pos) nextstate = S_INS_WRITE;
            S_INS_WRITE: if (b == 3'd4)      nextstate = S_IDLE;
            S_SET:       if (step == 8'd1)   nextstate = S_IDLE;
            default:     nextstate = S_IDLE;
        endcase
    end

    // state register
    always @(posedge clk) begin
        if (rst) state <= S_IDLE;
        else     state <= nextstate;
    end

    // datapath: reads, writes, flags
    always @(posedge clk) begin
        if (rst) begin
            pend <= 0; step <= 0; t0 <= 0; t1 <= 0; k <= 0; pos <= 0; b <= 0;
            we <= 0; wa <= 0; wd <= 0; ra <= 0;
            a_p <= 0; a_idx <= 0; a_val <= 0; a_hv <= 0; a_hk <= 0; a_hp <= 0; a_hf <= 0;
            a_iq <= 0; a_is <= 0; a_in <= 0; a_set <= `SET_DEFAULT; a_gf <= 0; a_gs <= 0;
        end else begin
            we   <= 1'b0;                                        // write only when set below
            step <= (nextstate != state) ? 8'd0 : step + 8'd1;   // restart in every new state

            case (state)
                S_DEF: begin                                     // byte "step" = factory value
                    we <= 1'b1; wa <= step[6:0]; wd <= def_byte;
                    if (step == 8'd127) pend[P_DEF] <= 1'b0;
                end
                S_CLR: begin
                    we <= 1'b1;
                    if (step < 8'd42)       begin wa <= `IM_ROLLS0 + step[6:0]; wd <= 8'h0F; end
                    else if (step == 8'd42) begin wa <= `IM_NROLL0; wd <= 8'h00; end
                    else if (step == 8'd43) begin wa <= `IM_NROLL1; wd <= 8'h00; end
                    else begin wa <= `IM_GVALID; wd <= 8'h00; pend[P_CLR] <= 1'b0; end
                end
                S_ROLL: begin
                    we <= 1'b1;
                    if (step == 8'd0) begin
                        wa <= (a_p ? `IM_ROLLS1 : `IM_ROLLS0) + {2'b00, a_idx}; wd <= {4'd0, a_val};
                    end else begin
                        wa <= a_p ? `IM_NROLL1 : `IM_NROLL0; wd <= {3'd0, a_idx} + 8'd1;
                        pend[P_ROLL] <= 1'b0;
                    end
                end
                S_HDR: begin
                    we <= 1'b1;
                    case (step[1:0])
                        2'd0: begin wa <= `IM_GVALID;  wd <= {7'd0, a_hv}; end
                        2'd1: begin wa <= `IM_GKIND;   wd <= {5'd0, a_hk}; end
                        2'd2: begin wa <= `IM_GPLAYER; wd <= {7'd0, a_hp}; end
                        default: begin wa <= `IM_GFRAME; wd <= {4'd0, a_hf}; pend[P_HDR] <= 1'b0; end
                    endcase
                end
                S_STRK, S_SPAR, S_GEND: begin                    // 16-bit counter + 1
                    // ra is a register: the byte it points at is in rd one clock later
                    case (step)
                        8'd0: ra <= (state == S_STRK) ? `IM_STRK : (state == S_SPAR) ? `IM_SPAR : `IM_GAMES;
                        8'd1: begin t0 <= rd; ra <= ra + 7'd1; end                   // low byte
                        8'd2: begin t1 <= rd; we <= 1'b1; wa <= ra - 7'd1; wd <= t0 + 8'd1; end
                        default: begin                                               // high byte + carry
                            we <= 1'b1; wa <= ra; wd <= t1 + ((t0 == 8'hFF) ? 8'd1 : 8'd0);
                            if (state == S_STRK) pend[P_STRK] <= 1'b0;
                            if (state == S_SPAR) pend[P_SPAR] <= 1'b0;
                            if (state == S_GEND) begin
                                if (a_gf) ra <= `IM_BEST;                            // go on to S_BEST
                                else      pend[P_GEND] <= 1'b0;
                            end
                        end
                    endcase
                end
                S_BEST: begin
                    case (step)
                        8'd0: begin t0 <= rd; ra <= `IM_BEST + 7'd1; end            // best lo
                        8'd1: begin                                                  // best hi
                            t1 <= rd;
                            if (a_gs > {rd[0], t0}) begin we <= 1'b1; wa <= `IM_BEST; wd <= a_gs[7:0]; end
                        end
                        default: begin
                            if (a_gs > {t1[0], t0}) begin we <= 1'b1; wa <= `IM_BEST + 7'd1; wd <= {7'd0, a_gs[8]}; end
                            pend[P_GEND] <= 1'b0;
                        end
                    endcase
                end
                // INSERT into a top-5 table
                S_INS_FIND: begin k <= 3'd0; ra <= tbl + 7'd1; end           // entry 0, byte 1
                S_INS_RDHI: begin t1 <= rd; ra <= base_k; end                 // t1 = {valid, bit 8}; next: lo
                S_INS_CMP: begin
                    if (beats)          pos <= k;                             // found the place
                    else if (k == 3'd4) pend[P_INS] <= 1'b0;                  // not in the top 5
                    else begin k <= k + 3'd1; ra <= base_k1 + 7'd1; end       // entry k+1, byte 1
                end
                S_INS_SHIFT: begin k <= 3'd3; b <= 3'd0; ra <= tbl + 7'd15; end   // entry 3, byte 0
                S_INS_MOVE: begin                                 // rd = byte b of entry k
                    we <= 1'b1; wa <= base_k1 + {4'd0, b}; wd <= rd;          // -> same byte of entry k+1
                    if (b == 3'd4) begin
                        b <= 3'd0;
                        if (k != pos) begin k <= k - 3'd1; ra <= base_km1; end // next entry up
                    end else begin
                        b <= b + 3'd1; ra <= base_k + {4'd0, b} + 7'd1;
                    end
                end
                S_INS_WRITE: begin                                // the new entry, byte b
                    we <= 1'b1; wa <= base_pos + {4'd0, b};
                    case (b)
                        3'd0: wd <= a_is[7:0];                    // score low byte
                        3'd1: wd <= {1'b1, 6'd0, a_is[8]};        // valid + score bit 8
                        3'd2: wd <= {3'd0, a_in[14:10]};          // 1st letter
                        3'd3: wd <= {3'd0, a_in[9:5]};            // 2nd letter
                        default: wd <= {3'd0, a_in[4:0]};         // 3rd letter
                    endcase
                    if (b == 3'd4) pend[P_INS] <= 1'b0;
                    else           b <= b + 3'd1;
                end
                S_SET: begin
                    we <= 1'b1;
                    if (step == 8'd0) begin wa <= `IM_SET_LO; wd <= a_set[7:0]; end
                    else begin wa <= `IM_SET_HI; wd <= a_set[15:8]; pend[P_SET] <= 1'b0; end
                end
                default: ;                                        // S_IDLE: nothing to do
            endcase

            // accept new commands (after the case, so "set" beats "clear")
            if (c_defaults) pend[P_DEF] <= 1'b1;
            if (c_clear)    pend[P_CLR] <= 1'b1;
            if (c_roll)     begin pend[P_ROLL] <= 1'b1; a_p <= roll_p; a_idx <= roll_idx; a_val <= roll_val; end
            if (c_hdr)      begin pend[P_HDR] <= 1'b1; a_hv <= hdr_valid; a_hk <= hdr_kind; a_hp <= hdr_player; a_hf <= hdr_frame; end
            if (c_strike)   pend[P_STRK] <= 1'b1;
            if (c_spare)    pend[P_SPAR] <= 1'b1;
            if (c_gameend)  begin pend[P_GEND] <= 1'b1; a_gf <= gend_full; a_gs <= gend_score; end
            if (c_insert)   begin pend[P_INS] <= 1'b1; a_iq <= ins_quick; a_is <= ins_score; a_in <= ins_name; end
            if (c_settings) begin pend[P_SET] <= 1'b1; a_set <= set_value; end
        end
    end
endmodule
