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

    // ---------- 1. Neighbour table ----------
    reg [9:0] ADJ_ROM [0:9];
    initial $readmemh("pin_adj.mem", ADJ_ROM);

    reg [9:0] STAND, REACH;
    reg       BUSY;

    // ---------- 2. Next step of the fill ----------
    // neighbours of every pin already reached (OR of their ROM rows)
    reg [9:0] NEIGHBOURS;
    integer k;
    always @ (*) begin
        NEIGHBOURS = 10'd0;
        for (k = 0; k < 10; k = k + 1)
            if (REACH[k])
                NEIGHBOURS = NEIGHBOURS | ADJ_ROM[k];
    end
    wire [9:0] GROW = REACH | (NEIGHBOURS & STAND);

    // lowest standing pin (start of the fill)
    reg [9:0] FIRST;
    always @ (*) begin
        FIRST = 10'd0;
        for (k = 9; k >= 0; k = k - 1)
            if (standing[k])
                FIRST = 10'd1 << k;
    end

    // number of standing pins >= 2  <=>  more than one bit set
    wire TWO_PLUS = (STAND & (STAND - 10'd1)) != 10'd0;

    // ---------- 3. Fill, one step per clock ----------
    always @ (posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            BUSY <= 1'b0;
            STAND <= 0;
            REACH <= 0;
            split <= 1'b0;
        end
        else if (start) begin
            STAND <= standing;
            REACH <= FIRST;
            BUSY <= 1'b1;
        end
        else if (BUSY) begin
            if (GROW == REACH) begin                 // fill finished
                BUSY <= 1'b0;
                done <= 1'b1;
                split <= !STAND[0] && TWO_PLUS && ((STAND & ~REACH) != 10'd0);
            end
            else
                REACH <= GROW;
        end
    end
endmodule
