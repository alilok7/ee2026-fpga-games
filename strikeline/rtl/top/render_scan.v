`timescale 1ns / 1ps
`include "strike_defs.vh"
// render_scan.v : walks every pixel of both screens once per frame
// Owner: Student B

module render_scan (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    output reg         scr,
    (* max_fanout = 64 *) output reg  [8:0]  px_x,
    (* max_fanout = 64 *) output reg  [7:0]  px_y,
    output reg         cap,
    output reg         we_v,
    output reg         we_o,
    output reg  [16:0] wa,
    output reg  [1:0]  wpar,
    output reg         done,
    output wire        busy_out
);

    reg        busy;
    reg [2:0]  cnt;
    reg [16:0] index;

    assign busy_out = busy;

    // End of a row and end of a picture, for each screen
    wire last_x = scr ? (px_x == 9'd95) : (px_x == 9'd319);
    wire last_y = scr ? (px_y == 8'd63) : (px_y == 8'd239);

    // ---------- Walk the VGA picture, then the OLED picture, 8 clocks per pixel ----------
    always @ (posedge clk) begin
        cap <= 1'b0;
        we_v <= 1'b0;
        we_o <= 1'b0;
        done <= 1'b0;
        if (rst) begin
            busy <= 1'b0;
            cnt <= 3'd0;
            index <= 17'd0;
            scr <= 1'b0;
            px_x <= 9'd0;
            px_y <= 8'd0;
            wa <= 17'd0;
            wpar <= 2'd0;
        end
        else if (!busy) begin
            if (start) begin
                busy <= 1'b1;
                cnt <= 3'd0;
                index <= 17'd0;
                scr <= 1'b0;
                px_x <= 9'd0;
                px_y <= 8'd0;
            end
        end
        else begin
            cnt <= cnt + 3'd1;
            // Pixel is held 8 clocks: compositor captures on clock 7, the buffer writes on clock 8
            if (cnt == 3'd6)
                cap <= 1'b1;
            if (cnt == 3'd7) begin
                wa <= index;
                wpar <= {px_y[0], px_x[0]};
                if (scr)
                    we_o <= 1'b1;
                else
                    we_v <= 1'b1;
                index <= index + 17'd1;
                if (!last_x)
                    px_x <= px_x + 9'd1;
                else begin
                    px_x <= 9'd0;
                    if (!last_y)
                        px_y <= px_y + 8'd1;
                    else begin
                        px_y <= 8'd0;
                        index <= 17'd0;
                        if (!scr)
                            scr <= 1'b1;
                        else begin
                            scr <= 1'b0;
                            busy <= 1'b0;
                            done <= 1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule
