//=============================================================================
// bcd_fns.vh : combinational binary -> BCD (include INSIDE a module)
//-----------------------------------------------------------------------------
// Owner   : Student D
// "Double dabble" unrolled: for every input bit, add 3 to each BCD digit
// that is >= 5, then shift left one bit and bring in the next input bit.
// (bin2bcd.v does the same one bit per clock; here a renderer needs the
// digits of a value at the current pixel, so it is unrolled into logic.)
//=============================================================================
function [11:0] bcd9;              // 0..511 -> 3 digits
    input [8:0] v;
    integer i;
    reg [11:0] b;
    begin
        b = 12'd0;
        for (i = 8; i >= 0; i = i - 1) begin
            if (b[3:0]  >= 5) b[3:0]  = b[3:0]  + 4'd3;
            if (b[7:4]  >= 5) b[7:4]  = b[7:4]  + 4'd3;
            if (b[11:8] >= 5) b[11:8] = b[11:8] + 4'd3;
            b = {b[10:0], v[i]};
        end
        bcd9 = b;
    end
endfunction
function [19:0] bcd16;             // 0..65535 -> 5 digits
    input [15:0] v;
    integer i;
    reg [19:0] b;
    begin
        b = 20'd0;
        for (i = 15; i >= 0; i = i - 1) begin
            if (b[3:0]   >= 5) b[3:0]   = b[3:0]   + 4'd3;
            if (b[7:4]   >= 5) b[7:4]   = b[7:4]   + 4'd3;
            if (b[11:8]  >= 5) b[11:8]  = b[11:8]  + 4'd3;
            if (b[15:12] >= 5) b[15:12] = b[15:12] + 4'd3;
            if (b[19:16] >= 5) b[19:16] = b[19:16] + 4'd3;
            b = {b[18:0], v[i]};
        end
        bcd16 = b;
    end
endfunction
