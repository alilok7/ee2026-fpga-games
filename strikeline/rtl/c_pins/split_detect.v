`timescale 1ns / 1ps
//=============================================================================
// split_detect.v : is the leave a split?
//-----------------------------------------------------------------------------
// Owner   : Student C
// Rule    : a split = the head pin (pin 1) is down AND the standing pins form
//           two or more groups that do not touch. "Touch" = neighbours in
//           the triangle (12 in apart), from an adjacency ROM made by
//           tools/gen_tables.py. So 7-10, 4-6, 5-7, 3-10 (baby split) are
//           splits; 4-5, 2-4-5-8 (bucket), 3-6-10 are not.
// Method  : flood fill from the lowest-numbered standing pin, one step per
//           clock:  reach = reach | (neighbours of reach & standing)
//           until nothing changes (at most 4 steps: no two pins in the
//           triangle are more than 3 steps apart). Any standing pin outside
//           `reach` is a second group.
//=============================================================================
module split_detect (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [9:0] standing,
    output reg        split,
    output reg        done
);
    reg [9:0] adj_rom [0:9];
    initial $readmemh("pin_adj.mem", adj_rom);

    reg [9:0] stand, reach;
    reg       busy;

    // neighbours of every pin already reached (OR of their ROM rows)
    reg [9:0] nb;
    integer k;
    always @(*) begin
        nb = 10'd0;
        for (k = 0; k < 10; k = k + 1)
            if (reach[k]) nb = nb | adj_rom[k];
    end
    wire [9:0] grow = reach | (nb & stand);

    // lowest standing pin (start of the fill)
    reg [9:0] first;
    always @(*) begin
        first = 10'd0;
        for (k = 9; k >= 0; k = k - 1)
            if (standing[k]) first = 10'd1 << k;
    end

    // number of standing pins >= 2  <=>  more than one bit set
    wire two_plus = (stand & (stand - 10'd1)) != 10'd0;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            busy <= 1'b0; stand <= 0; reach <= 0; split <= 1'b0;
        end else if (start) begin
            stand <= standing;
            reach <= first;
            busy  <= 1'b1;
        end else if (busy) begin
            if (grow == reach) begin                 // fill finished
                busy  <= 1'b0;
                done  <= 1'b1;
                split <= !stand[0] && two_plus && ((stand & ~reach) != 10'd0);
            end else begin
                reach <= grow;
            end
        end
    end
endmodule
