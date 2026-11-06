`timescale 1ns / 1ps
`include "strike_defs.vh"
// backdrop_render.v : the far end of the alley: ceiling, masking unit, curtain
// Owner: Student B

module backdrop_render (
    input  wire        clk,
    input  wire        fp,
    input  wire [8:0]  hx,
    input  wire [7:0]  hy,
    input  wire [7:0]  rp_mu,
    input  wire [7:0]  rp_bw,
    input  wire [15:0] mu_step,
    input  wire [7:0]  frame_cnt,
    input  wire        neon,
    output wire [15:0] color,
    output wire        en,
    output wire [6:0]  sign_row,
    output wire        sign_ok
);

    // ---------- 1. Rows of the panel and curtain this frame ----------
    wire signed [9:0] mt, mb, bw, lr;

    backdrop_rows u_rows (
        .clk(clk),
        .rp_mu(rp_mu),
        .rp_bw(rp_bw),
        .mt(mt),
        .mb(mb),
        .bw(bw),
        .lr(lr),
        .sign_row(sign_row),
        .sign_ok(sign_ok)
    );

    // ---------- 2. Position across the row, one step per pixel ----------
    wire [23:0] u;

    backdrop_step u_step (
        .clk(clk),
        .hx(hx),
        .mu_step(mu_step),
        .u(u)
    );

    // ---------- 3. Colour of this pixel ----------
    backdrop_color u_color (
        .fp(fp),
        .hy(hy),
        .frame_cnt(frame_cnt),
        .neon(neon),
        .mt(mt),
        .mb(mb),
        .bw(bw),
        .lr(lr),
        .u(u),
        .color(color),
        .en(en)
    );
endmodule


// Screen rows of the masking unit and curtain, from their size r
module backdrop_rows (
    input  wire        clk,
    input  wire [7:0]  rp_mu,
    input  wire [7:0]  rp_bw,
    output reg  signed [9:0] mt,
    output reg  signed [9:0] mb,
    output reg  signed [9:0] bw,
    output reg  signed [9:0] lr,
    output reg  [6:0]  sign_row,
    output reg         sign_ok
);
    // Top and bottom of the panel relative to the horizon, as fractions of r
    wire [15:0] r95 = {rp_mu, 6'd0} + {1'b0, rp_mu, 5'd0} - {8'd0, rp_mu};
    wire [15:0] r85 = {rp_mu, 6'd0} + {2'b00, rp_mu, 4'd0} + {4'd0, rp_mu, 2'b00} + {8'd0, rp_mu};

    always @ (posedge clk) begin
        mt <= 10'sd60 - $signed({2'b00, r95[15:8]});
        mb <= 10'sd60 + $signed({2'b00, r85[15:8]});
        bw <= 10'sd60 + $signed({2'b00, rp_bw});
        lr <= mb - ((mb - mt) >>> 2);
        sign_row <= ((mt + mb) < 0) ? 7'd0 : (((mt + mb) >>> 2) > 10'sd119) ? 7'd119 : ((mt + mb) >>> 2);
        sign_ok <= (mb - mt) >= 10'sd24;
    end
endmodule


// Running lane position across the row, so no multiply is needed per pixel
module backdrop_step (
    input  wire        clk,
    input  wire [8:0]  hx,
    input  wire [15:0] mu_step,
    output reg  [23:0] u
);
    reg [8:0] hx_q;
    wire [23:0] u0 = 24'h008000 - ({8'd0, mu_step} << 7) - ({8'd0, mu_step} << 5);

    always @ (posedge clk) begin
        hx_q <= hx;
        if (hx != hx_q)
            u <= (hx == 9'd0) ? u0 : u + {8'd0, mu_step};
    end
endmodule


// Ceiling, panel with its trim and lights, and the folded curtain
module backdrop_color (
    input  wire        fp,
    input  wire [7:0]  hy,
    input  wire [7:0]  frame_cnt,
    input  wire        neon,
    input  wire signed [9:0] mt,
    input  wire signed [9:0] mb,
    input  wire signed [9:0] bw,
    input  wire signed [9:0] lr,
    input  wire [23:0] u,
    output reg  [15:0] color,
    output reg         en
);
    wire [3:0] frac = u[15:12];
    wire [2:0] lane = u[18:16];
    wire signed [9:0] y = $signed({2'b00, hy});

    // Panel colours for the wood and neon themes
    wire [15:0] c_panel = neon ? 16'h300C : 16'h5800;
    wire [15:0] c_pan2  = neon ? 16'h2009 : 16'h4000;
    wire [15:0] c_trim  = neon ? `C_CYAN : 16'hC5A0;
    wire [15:0] c_div   = neon ? 16'h1006 : 16'h2800;
    wire [15:0] c_ceil  = (y < mt - 10'sd12) ? 16'h0841 : 16'h1082;

    // Lamp colours: steady white on wood, cycling on neon
    reg [15:0] c_lamp;
    always @ (*) begin
        case (neon ? (lane + frame_cnt[6:4]) : 3'd7)
            3'd0:    c_lamp = `C_MAGENTA;
            3'd1:    c_lamp = `C_CYAN;
            3'd2:    c_lamp = `C_YELLOW;
            3'd3:    c_lamp = 16'h07E0;
            3'd4:    c_lamp = 16'hFD20;
            3'd5:    c_lamp = 16'h841F;
            3'd6:    c_lamp = 16'hF81F;
            default: c_lamp = 16'hFF9C;
        endcase
    end

    // A lamp and its glow in the middle of each lane section
    wire lamp = (y >= lr - 10'sd1) && (y <= lr + 10'sd1) && (frac >= 4'd6) && (frac <= 4'd9);
    wire glow = (y >= lr - 10'sd3) && (y <= lr + 10'sd3) && (frac >= 4'd5) && (frac <= 4'd10);

    // Top to bottom: ceiling, trim and panel, then the curtain
    always @ (*) begin
        en = 1'b0;
        color = `C_BLACK;
        if (fp && y < bw) begin
            en = 1'b1;
            if (y < mt)
                color = (y >= mt - 10'sd2) ? c_trim : c_ceil;
            else if (y <= mb) begin
                if (y <= mt + 10'sd1 || y >= mb - 10'sd1)
                    color = c_trim;
                else if (lamp)
                    color = c_lamp;
                else if (glow)
                    color = neon ? 16'h500F : 16'h9A40;
                else if (frac == 4'd0)
                    color = c_div;
                else
                    color = (y > lr) ? c_pan2 : c_panel;
            end
            else
                color = u[13] ? 16'h0841 : ((u[12] ^ u[11]) ? 16'h0020 : 16'h1082);
        end
    end
endmodule
