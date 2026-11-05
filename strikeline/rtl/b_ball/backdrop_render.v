`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// backdrop_render.v - the far end of the alley in the 3-D view: ceiling, masking unit, curtain
//-----------------------------------------------------------------------------
// Owner   : Student B
// Purpose : (v3.5) In v3.4 everything above the floor was a fixed band at the
//           horizon, as if it were infinitely far away, so when the camera
//           rolled toward the pins the edges of the lane and an empty strip
//           showed behind the rack. Here the far end is built from two
//           upright planes at their real distance, so they grow with the pins:
//             masking unit : the panel that hides the pinsetter, at 700 in,
//                            from 34 to 70 in above the lane, across all lanes,
//                            with a trim, lane dividers and a light over each lane
//             back curtain : black, folded, at 790 in, from the pit floor up
//             ceiling      : above the panel
// Geometry: the camera is 51 in above the lane (that is why one inch is r / 51
//           px on screen row 60 + r). An upright plane at distance d is
//           r = 2K / d (persp_proj computes it once per frame, rp_*), and a
//           point h inches up on it is on row 60 + r - h * r / 51:
//             panel top (70 in)    60 - 0.373 r  ~  60 - (r * 95) >> 8
//             panel bottom (34 in) 60 + 0.333 r  ~  60 + (r * 85) >> 8
//             curtain foot (0 in)  60 + r
// Across  : the panel faces the camera, so a lane (64 in on it) is the same
//           number of pixels everywhere on it. persp_proj gives the step in
//           lanes per pixel (mu_step, Q16); a running sum u steps across each
//           row as render_scan walks it (no multiply per pixel):
//             u = 0.5 + (x - 160) * step  ->  lane = u[23:16], place in it = u[15:0]
// No DSP attribute here (DSPs are all in use); everything is shifts, adds and
// compares.
//=============================================================================
module backdrop_render (
    input  wire        clk,
    input  wire        fp,               // this pixel is in the 3-D view
    input  wire [8:0]  hx,               // 320 x 240 pixel
    input  wire [7:0]  hy,
    input  wire [7:0]  rp_mu,            // size of the masking unit plane (r)
    input  wire [7:0]  rp_bw,            // size of the back curtain plane (r)
    input  wire [15:0] mu_step,          // lanes per pixel on the panel, Q16
    input  wire [7:0]  frame_cnt,
    input  wire        neon,
    output reg  [15:0] color,
    output reg         en,
    output reg  [6:0]  sign_row,         // the panel's middle row, 160 x 120 grid (for the sign)
    output reg         sign_ok           // the panel is tall enough for the 5-row sign
);
    // ---------------- rows of this frame (registered) ----------------------
    wire [15:0] r95 = {rp_mu, 6'd0} + {1'b0, rp_mu, 5'd0} - {8'd0, rp_mu};          // r * 95
    wire [15:0] r85 = {rp_mu, 6'd0} + {2'b00, rp_mu, 4'd0} + {4'd0, rp_mu, 2'b00} + {8'd0, rp_mu}; // r * 85
    reg  signed [9:0] mt, mb, bw;        // panel top, panel bottom, curtain foot
    reg  signed [9:0] lr;                // the row of the lights (a quarter up from the bottom)
    always @(posedge clk) begin
        mt <= 10'sd60 - $signed({2'b00, r95[15:8]});
        mb <= 10'sd60 + $signed({2'b00, r85[15:8]});
        bw <= 10'sd60 + $signed({2'b00, rp_bw});
        lr <= mb - ((mb - mt) >>> 2);
        sign_row <= ((mt + mb) < 0) ? 7'd0 : (((mt + mb) >>> 2) > 10'sd119) ? 7'd119 : ((mt + mb) >>> 2);
        // 5 rows of 160 x 120 text = 10 rows here, plus the trims and the lights
        sign_ok  <= (mb - mt) >= 10'sd24;
    end

    // ---------------- across: running lane coordinate --------------------------
    reg  [8:0]  hx_d;
    reg  [23:0] u;
    wire [23:0] u0 = 24'h008000 - ({8'd0, mu_step} << 7) - ({8'd0, mu_step} << 5);   // 0.5 - 160 step
    always @(posedge clk) begin
        hx_d <= hx;
        if (hx != hx_d) u <= (hx == 9'd0) ? u0 : u + {8'd0, mu_step};
    end
    wire [3:0] frac = u[15:12];          // 16ths of a lane
    wire [2:0] lane = u[18:16];

    // ---------------- colours ---------------------------------------------------
    wire signed [9:0] y = $signed({2'b00, hy});
    wire [15:0] c_panel = neon ? 16'h300C : 16'h5800;
    wire [15:0] c_pan2  = neon ? 16'h2009 : 16'h4000;            // lower half, a little darker
    wire [15:0] c_trim  = neon ? `C_CYAN : 16'hC5A0;
    wire [15:0] c_div   = neon ? 16'h1006 : 16'h2800;
    wire [15:0] c_ceil  = (y < mt - 10'sd12) ? 16'h0841 : 16'h1082;
    // a light over each lane: warm white; in the neon theme it cycles colour
    reg  [15:0] c_lamp;
    always @(*) begin
        case (neon ? (lane + frame_cnt[6:4]) : 3'd7)
            3'd0: c_lamp = `C_MAGENTA; 3'd1: c_lamp = `C_CYAN;   3'd2: c_lamp = `C_YELLOW;
            3'd3: c_lamp = 16'h07E0;  3'd4: c_lamp = 16'hFD20;  3'd5: c_lamp = 16'h841F;
            3'd6: c_lamp = 16'hF81F;  default: c_lamp = 16'hFF9C;
        endcase
    end
    wire lamp = (y >= lr - 10'sd1) && (y <= lr + 10'sd1) && (frac >= 4'd6) && (frac <= 4'd9);
    wire glow = (y >= lr - 10'sd3) && (y <= lr + 10'sd3) && (frac >= 4'd5) && (frac <= 4'd10);

    always @(*) begin
        en = 1'b0; color = `C_BLACK;
        if (fp && y < bw) begin
            en = 1'b1;
            if (y < mt)                                   color = (y >= mt - 10'sd2) ? c_trim : c_ceil;
            else if (y <= mb) begin                       // the masking unit
                if (y <= mt + 10'sd1 || y >= mb - 10'sd1) color = c_trim;
                else if (lamp)                            color = c_lamp;
                else if (glow)                            color = neon ? 16'h500F : 16'h9A40;
                else if (frac == 4'd0)                    color = c_div;
                else                                      color = (y > lr) ? c_pan2 : c_panel;
            end else                                      // the curtain behind the pit
                color = u[13] ? 16'h0841 : ((u[12] ^ u[11]) ? 16'h0020 : 16'h1082);
        end
    end
endmodule
