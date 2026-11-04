`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// swipe_lab_plot.v : draws the last swipe into a bitmap for the Swipe Lab
//-----------------------------------------------------------------------------
// Owner   : Student A
// Purpose : Shows the algorithm at work: the raw mouse path (grey staircase,
//           40 Hz packets) and the 4-tap filtered path (yellow, smooth).
//           After a swipe in the Swipe Lab (start):
//             CLEAR  write 0 to all 4096 pixels of a 64 x 64 x 2-bit block RAM
//             EXTENT one pass over the ring: ext = max(2|dx|, |df|) from the
//                    first sample, then the smallest shift s with ext >> s <= 56
//                    (auto-zoom by a power of two: no divider)
//             PLOT   each sample at x = 32 + dx >> s, y = 60 - df >> s
//                    (raw = 1, then filtered = 2 on top)
//           ~4300 clocks, once per swipe. The renderer reads the RAM with the
//           pixel position (1-clock read, inside the video timing window).
//=============================================================================
module swipe_lab_plot (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [5:0]  wp,
    input  wire [6:0]  n_samples,
    output reg  [5:0]  rd_addr,
    input  wire [63:0] rd_data,
    output wire        busy,
    input  wire [11:0] px_addr,          // {y[5:0], x[5:0]} from the renderer
    output reg  [1:0]  px_data
);
    reg [1:0] bmp [0:4095];
    reg        bw;
    reg [11:0] ba;
    reg [1:0]  bd;
    always @(posedge clk) begin
        if (bw) bmp[ba] <= bd;
        px_data <= bmp[px_addr];
    end

    // the ring data is registered (timing): rq = sample at the address of the
    // previous clock, so each loop issues address i and processes point i-1
    reg [63:0] rq;
    always @(posedge clk) rq <= rd_data;
    wire signed [15:0] r_sx = rq[63:48], r_sf = rq[47:32];
    wire signed [15:0] r_fx = rq[31:16], r_ff = rq[15:0];

    localparam S_IDLE = 3'd0, S_CLR = 3'd1, S_ORG = 3'd2, S_EXT = 3'd3, S_SH = 3'd4, S_RAW = 3'd5, S_FIL = 3'd6, S_ORGW = 3'd7;
    reg [2:0]  st;
    reg [12:0] i;
    reg [5:0]  base;
    reg [6:0]  n;
    reg signed [15:0] x0, f0;
    reg [16:0] ext;
    reg [2:0]  sh;
    assign busy = (st != S_IDLE);

    // distance from the first sample (raw or filtered), for the extent pass
    wire signed [16:0] ddx_r = r_sx - x0, ddf_r = r_sf - f0;
    wire signed [16:0] ddx_f = r_fx - x0, ddf_f = r_ff - f0;
    function [16:0] ab; input signed [16:0] v; ab = v[16] ? -v : v; endfunction
    wire [16:0] e_r = ((ab(ddx_r) << 1) > ab(ddf_r)) ? (ab(ddx_r) << 1) : ab(ddf_r);
    wire [16:0] e_f = ((ab(ddx_f) << 1) > ab(ddf_f)) ? (ab(ddx_f) << 1) : ab(ddf_f);

    // screen position of a point (and whether it is inside the 64 x 64 box)
    wire signed [16:0] ddx = (st == S_RAW) ? ddx_r : ddx_f;
    wire signed [16:0] ddf = (st == S_RAW) ? ddf_r : ddf_f;
    reg  signed [16:0] ddx1, ddf1;               // stage 1 (registered)
    reg  [16:0] e1;                               // (unused, kept for reset list)
    reg  [16:0] ar, af, br, bf;                   // stage-1 absolute offsets
    wire [16:0] e2r = ((ar << 1) > af) ? (ar << 1) : af;
    wire [16:0] e2f = ((br << 1) > bf) ? (br << 1) : bf;
    reg         v1;
    wire signed [16:0] pxs = 17'sd32 + (ddx1 >>> sh);
    wire signed [16:0] pys = 17'sd60 - (ddf1 >>> sh);
    wire inside = (pxs >= 0) && (pxs <= 63) && (pys >= 0) && (pys <= 63);

    always @(posedge clk) begin
        bw <= 1'b0;
        if (rst) begin
            st <= S_IDLE; i <= 0; base <= 0; n <= 0; x0 <= 0; f0 <= 0; ext <= 0; sh <= 0;
            ddx1 <= 0; ddf1 <= 0; e1 <= 0; v1 <= 0; ar <= 0; af <= 0; br <= 0; bf <= 0;
            rd_addr <= 0; ba <= 0; bd <= 0;
        end else case (st)
            S_IDLE: if (start) begin
                base <= wp - n_samples[5:0]; n <= n_samples; i <= 0; st <= S_CLR;
            end
            S_CLR: begin
                bw <= 1'b1; ba <= i[11:0]; bd <= 2'd0;
                i <= i + 13'd1;
                if (i == 13'd4095) begin rd_addr <= base; st <= S_ORGW; end
            end
            S_ORGW: st <= S_ORG;                 // rq catches up with rd_addr
            S_ORG: begin                         // first sample = origin
                x0 <= r_fx; f0 <= r_ff; ext <= 17'd1; i <= 0; rd_addr <= base;
                st <= S_EXT;
            end
            // loops: clock i issues address i, rq holds point i-1, and the
            // registered stage-1 values (v1) belong to point i-2 (timing)
            S_EXT: begin
                // 3 stages: clock i issues address i; rq = point i-1;
                // stage 1 registers its 4 absolute offsets; stage 2 (point i-2)
                // takes max(2|dx|, |df|) of raw and filtered and updates ext
                v1 <= (i != 0) && (i[6:0] <= n);
                ar <= ab(ddx_r); af <= ab(ddf_r); br <= ab(ddx_f); bf <= ab(ddf_f);
                if (v1) begin
                    if (e2r > ext && e2r >= e2f) ext <= e2r;
                    else if (e2f > ext)          ext <= e2f;
                end
                i <= i + 13'd1;
                rd_addr <= base + i[5:0] + 6'd1;
                if (i[6:0] == n + 7'd1) begin v1 <= 1'b0; st <= S_SH; end
            end
            S_SH: begin                          // smallest shift that fits
                sh <= (ext <= 17'd56)   ? 3'd0 : (ext <= 17'd112)  ? 3'd1 : (ext <= 17'd224)  ? 3'd2 :
                      (ext <= 17'd448)  ? 3'd3 : (ext <= 17'd896)  ? 3'd4 : (ext <= 17'd1792) ? 3'd5 :
                      (ext <= 17'd3584) ? 3'd6 : 3'd7;
                i <= 0; rd_addr <= base; st <= S_RAW;
            end
            S_RAW, S_FIL: begin
                v1 <= (i != 0) && (i[6:0] <= n);
                ddx1 <= ddx; ddf1 <= ddf;
                if (v1 && inside) begin bw <= 1'b1; ba <= {pys[5:0], pxs[5:0]}; bd <= (st == S_RAW) ? 2'd1 : 2'd2; end
                i <= i + 13'd1;
                rd_addr <= base + i[5:0] + 6'd1;
                if (i[6:0] == n + 7'd1) begin
                    i <= 0; rd_addr <= base; v1 <= 1'b0;
                    st <= (st == S_RAW) ? S_FIL : S_IDLE;
                end
            end
            default: st <= S_IDLE;
        endcase
    end
endmodule
