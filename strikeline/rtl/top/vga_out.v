`timescale 1ns / 1ps
// vga_out.v : 640 x 480 @ 60 Hz VGA from a 320 x 240 frame buffer
// Owner: Student B

module vga_out (
    input  wire        clk,
    input  wire        rst,
    input  wire        we_v,
    input  wire        we_o,
    input  wire [16:0] wa,
    input  wire [15:0] wd,
    input  wire [1:0]  wpar,
    input  wire        render_busy,
    output wire        frame_start,
    input  wire [12:0] oled_index,
    output reg  [15:0] oled_data,
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,
    output reg         hsync,
    output reg         vsync
);

    // ---------- 1. Colours rounded to RGB333 with a 2 x 2 dither ----------
    wire [8:0] wd9;

    vga_dither u_dither (
        .wd(wd),
        .wpar(wpar),
        .wd9(wd9)
    );

    // ---------- 2. Frame buffers (tb_top and tb_screens read fb and fbo by name) ----------
    reg [8:0]  fb  [0:76799];
    reg [15:0] fbo [0:6143];
    reg [16:0] ra;
    reg [8:0]  rd;

    always @ (posedge clk) begin
        if (we_v)
            fb[wa] <= wd9;
        rd <= fb[ra];
    end

    always @ (posedge clk) begin
        if (we_o)
            fbo[wa[12:0]] <= wd;
        oled_data <= fbo[oled_index];
    end

    // ---------- 3. 640 x 480 @ 60 Hz counters ----------
    wire pe, vis, hs, vs;
    wire [9:0] h, v;

    vga_timing u_timing (
        .clk(clk),
        .rst(rst),
        .render_busy(render_busy),
        .pe(pe),
        .h(h),
        .v(v),
        .vis(vis),
        .hs(hs),
        .vs(vs),
        .frame_start(frame_start)
    );

    // ---------- 4. Address, then colour one pixel later, with the syncs delayed to match ----------
    reg vis_q, hs_q, vs_q;

    always @ (posedge clk) begin
        if (rst) begin
            ra <= 0;
            vis_q <= 0;
            hs_q <= 1;
            vs_q <= 1;
            vga_r <= 0;
            vga_g <= 0;
            vga_b <= 0;
            hsync <= 1;
            vsync <= 1;
        end
        else if (pe) begin
            // Address = row * 320 + column, and 320 = 256 + 64, so no multiply
            ra <= {v[8:1], 8'd0} + {2'b00, v[8:1], 6'd0} + {8'd0, h[9:1]};
            vis_q <= vis;
            hs_q <= hs;
            vs_q <= vs;
            hsync <= hs_q;
            vsync <= vs_q;
            if (vis_q) begin
                vga_r <= {rd[8:6], rd[8]};
                vga_g <= {rd[5:3], rd[5]};
                vga_b <= {rd[2:0], rd[2]};
            end
            else begin
                vga_r <= 4'd0;
                vga_g <= 4'd0;
                vga_b <= 4'd0;
            end
        end
    end
endmodule


// 25 MHz pixel enable, screen counters, sync signals and the frame start
module vga_timing (
    input  wire       clk,
    input  wire       rst,
    input  wire       render_busy,
    output wire       pe,
    output reg  [9:0] h,
    output reg  [9:0] v,
    output wire       vis,
    output wire       hs,
    output wire       vs,
    output reg        frame_start
);
    localparam [9:0] H_VISIBLE    = 10'd640;
    localparam [9:0] H_SYNC_START = 10'd656;
    localparam [9:0] H_SYNC_END   = 10'd752;
    localparam [9:0] H_LAST       = 10'd799;
    localparam [9:0] V_VISIBLE    = 10'd480;
    localparam [9:0] V_SYNC_START = 10'd490;
    localparam [9:0] V_SYNC_END   = 10'd492;
    localparam [9:0] V_LAST       = 10'd524;

    // Every 4th 100 MHz clock is one 25 MHz pixel
    reg [1:0] div;
    assign pe = (div == 2'd3);

    // Count across the line, then down the frame (800 x 525 in total)
    always @ (posedge clk) begin
        if (rst) begin
            div <= 2'd0;
            h <= 10'd0;
            v <= 10'd0;
        end
        else begin
            div <= div + 2'd1;
            if (pe) begin
                if (h == H_LAST) begin
                    h <= 10'd0;
                    if (v == V_LAST)
                        v <= 10'd0;
                    else
                        v <= v + 10'd1;
                end
                else
                    h <= h + 10'd1;
            end
        end
    end

    // Start drawing in the vertical blank, unless the last frame is still being drawn
    always @ (posedge clk) begin
        frame_start <= 1'b0;
        if (!rst && pe && h == 10'd0 && v == V_VISIBLE)
            frame_start <= !render_busy;
    end

    assign vis = (h < H_VISIBLE) && (v < V_VISIBLE);
    assign hs = !(h >= H_SYNC_START && h < H_SYNC_END);
    assign vs = !(v >= V_SYNC_START && v < V_SYNC_END);
endmodule


// RGB565 to RGB333, rounded by a 2 x 2 pattern so shading stays smooth
module vga_dither (
    input  wire [15:0] wd,
    input  wire [1:0]  wpar,
    output wire [8:0]  wd9
);
    // Threshold from the pixel position, so neighbours round differently
    wire [1:0] th = {wpar[1] ^ wpar[0], wpar[1]};

    // Keep the top 3 bits, and round up if the dropped bits beat the threshold
    function [2:0] round5;
        input [4:0] c;
        input [1:0] t;
        begin
            if (c[4:2] == 3'd7 || c[1:0] <= t)
                round5 = c[4:2];
            else
                round5 = c[4:2] + 3'd1;
        end
    endfunction

    function [2:0] round6;
        input [5:0] c;
        input [1:0] t;
        begin
            if (c[5:3] == 3'd7 || c[2:0] <= {t, 1'b0})
                round6 = c[5:3];
            else
                round6 = c[5:3] + 3'd1;
        end
    endfunction

    assign wd9 = {round5(wd[15:11], th), round6(wd[10:5], th), round5(wd[4:0], th)};
endmodule
