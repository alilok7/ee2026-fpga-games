`timescale 1ns / 1ps
//=============================================================================
// vga_out.v - 640 x 480 @ 60 Hz VGA from a 320 x 240 frame buffer (v3, v3.2)
//-----------------------------------------------------------------------------
// Owner (Q&A) : Student D (integration)
// Timing  : the standard 640 x 480 mode, 25 MHz pixel clock made as a clock
//           ENABLE (every 4th clock of 100 MHz, the same tick idea as
//           timebase): 800 clocks per line (640 visible, front porch 16, sync
//           96, back porch 48), 525 lines (480, 10, 2, 33). Both syncs are
//           active low.
// Picture : (v3.2) each logical pixel is shown as 2 x 2 screen pixels, so the
//           read address is (v / 2) * 320 + h / 2 = (v/2) * 256 + (v/2) * 64 + h/2.
// Buffer  : ONE 320 x 240 x 9 bit block RAM (RGB 3:3:3, 512 colours): two of
//           them would not fit in the Basys3's block RAM next to the rest of
//           the game. render_scan starts drawing in the vertical blank and
//           draws a row faster than the monitor shows one, so the picture
//           never tears (render_scan.v). The 9-bit width is the RAM's native
//           4K x 9 shape, so the third bit of blue costs nothing.
//           Colours arrive as RGB565 and are rounded to 3:3:3 with a 2 x 2
//           ordered dither on the logical pixel (wpar), so shading stays
//           smooth; on the way out 3 bits become the DAC's 4 (c, c[2]).
//           The OLED buffer (96 x 64 x 16) is here too; Oled_Display reads
//           it through pixel_index.
//=============================================================================
module vga_out (
    input  wire        clk,
    input  wire        rst,
    // renderer side
    input  wire        we_v,
    input  wire        we_o,
    input  wire [16:0] wa,
    input  wire [15:0] wd,
    input  wire [1:0]  wpar,             // {y[0], x[0]} of the pixel written
    input  wire        render_busy,      // a frame is still being drawn
    output reg         frame_start,      // 1-cycle: start drawing the next frame
    // OLED side
    input  wire [12:0] oled_index,
    output reg  [15:0] oled_data,
    // VGA connector
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,
    output reg         hsync,
    output reg         vsync
);
    // ---------------- RGB565 -> RGB333 with a 2 x 2 ordered dither -------------
    // Bayer thresholds 0 2 / 3 1 (in quarters of a step)
    wire [1:0] bth = {wpar[1] ^ wpar[0], wpar[1]};
    function [2:0] q5;                         // 5 -> 3 bits
        input [4:0] c; input [1:0] t;
        begin
            if (c[4:2] == 3'd7 || c[1:0] <= t) q5 = c[4:2];
            else                               q5 = c[4:2] + 3'd1;
        end
    endfunction
    function [2:0] q6;                         // 6 -> 3 bits
        input [5:0] c; input [1:0] t;
        begin
            if (c[5:3] == 3'd7 || c[2:0] <= {t, 1'b0}) q6 = c[5:3];
            else                                     q6 = c[5:3] + 3'd1;
        end
    endfunction
    wire [8:0] wd9 = {q5(wd[15:11], bth), q6(wd[10:5], bth), q5(wd[4:0], bth)};

    // ---------------- frame buffers --------------------------------------------
    reg [8:0]  fb  [0:76799];
    reg [15:0] fbo [0:6143];
    reg [16:0] ra;
    reg [8:0]  rd;
    always @(posedge clk) begin
        if (we_v) fb[wa] <= wd9;
        rd <= fb[ra];
    end
    always @(posedge clk) begin
        if (we_o) fbo[wa[12:0]] <= wd;
        oled_data <= fbo[oled_index];
    end

    // ---------------- 25 MHz enable, counters ------------------------------------
    reg [1:0] div;
    wire pe = (div == 2'd3);
    reg [9:0] h, v;
    always @(posedge clk) begin
        if (rst) begin div <= 2'd0; h <= 10'd0; v <= 10'd0; end
        else begin
            div <= div + 2'd1;
            if (pe) begin
                if (h == 10'd799) begin
                    h <= 10'd0;
                    v <= (v == 10'd524) ? 10'd0 : v + 10'd1;
                end else h <= h + 10'd1;
            end
        end
    end

    // ---------------- frame start at the start of the vertical blank -----------
    always @(posedge clk) begin
        frame_start <= 1'b0;
        if (!rst && pe && h == 10'd0 && v == 10'd480)
            frame_start <= !render_busy;
    end

    // ---------------- pipeline: address -> RAM -> colour, syncs delayed to match --
    wire       vis = (h < 10'd640) && (v < 10'd480);
    reg        vis_d;
    reg        hs_d, vs_d;
    always @(posedge clk) begin
        if (rst) begin
            ra <= 0; vis_d <= 0; hs_d <= 1; vs_d <= 1;
            vga_r <= 0; vga_g <= 0; vga_b <= 0; hsync <= 1; vsync <= 1;
        end else if (pe) begin
            // stage 1: this screen pixel's buffer address
            ra    <= {v[8:1], 8'd0} + {2'b00, v[8:1], 6'd0} + {8'd0, h[9:1]};
            vis_d <= vis;
            hs_d  <= !(h >= 10'd656 && h < 10'd752);
            vs_d  <= !(v >= 10'd490 && v < 10'd492);
            // stage 2 (one pixel later): the colour read at that address
            hsync <= hs_d;
            vsync <= vs_d;
            if (vis_d) begin
                vga_r <= {rd[8:6], rd[8]};
                vga_g <= {rd[5:3], rd[5]};
                vga_b <= {rd[2:0], rd[2]};
            end else begin
                vga_r <= 4'd0; vga_g <= 4'd0; vga_b <= 4'd0;
            end
        end
    end
endmodule
