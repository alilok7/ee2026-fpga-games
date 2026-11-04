`timescale 1ns / 1ps
//=============================================================================
// note_palette.v : the single note-colour palette (one visual language)
//-----------------------------------------------------------------------------
// Owner (Q&A) : Student D
// Purpose     : Lanes (C), piano keys (B), the Learn piano-roll (D) and the
//               title animation all colour a note the same way:
//               C red, D orange, E yellow, F green, G cyan, A blue,
//               B violet, C5 pink. Sharps use the lower natural, darkened.
//               Pure combinational lookup - instantiate where needed.
// Ports
//   lane      0..7 = C4 D4 E4 F4 G4 A4 B4 C5
//   dark      1 = darker shade (sharps, lane backgrounds)
//   color     RGB565
// Darkening: halve each channel. In RGB565 that is (c >> 1) with the bit
//   that would spill from one channel into the next cleared:
//   mask 0x7BEF = 0111 1011 1110 1111.
//=============================================================================
module note_palette (
    input  wire [2:0]  lane,
    input  wire        dark,
    output wire [15:0] color
);
    reg [15:0] base;
    always @(*) begin
        case (lane)
            3'd0: base = 16'hF800;   // C  red      (255,   0,   0)
            3'd1: base = 16'hFD20;   // D  orange   (255, 165,   0)
            3'd2: base = 16'hFFE0;   // E  yellow   (255, 255,   0)
            3'd3: base = 16'h07E0;   // F  green    (  0, 255,   0)
            3'd4: base = 16'h07FF;   // G  cyan     (  0, 255, 255)
            3'd5: base = 16'h2B3F;   // A  blue     ( 40, 100, 255)
            3'd6: base = 16'hA1FF;   // B  violet   (160,  60, 255)
            default: base = 16'hFB56;// C5 pink     (255, 105, 180)
        endcase
    end
    assign color = dark ? ((base >> 1) & 16'h7BEF) : base;
endmodule
