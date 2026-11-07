`timescale 1ns / 1ps

module timebase #(
    parameter MS_DIV   = 100_000,
    parameter PHYS_DIV = 97_656,
    parameter SMP_DIV  = 500_000,
    parameter MS_W = 17,
    parameter PHYS_W = 17,
    parameter SMP_W = 19
) (
    input  wire clk,
    input  wire rst,
    input  wire paused,
    input  wire slowmo,
    input  wire frame_done,
    output reg  tick_1ms,
    output reg  tick_game,
    output reg  tick_sample,
    output reg  tick_phys,
    output reg  tick_frame,
    output wire clk6p25m
);

    reg [3:0] div16 = 4'd0;
    always @(posedge clk) div16 <= div16 + 4'd1;
    assign clk6p25m = div16[3];

    reg [MS_W-1:0] ms_count;
    reg [PHYS_W-1:0] phys_count;
    reg [SMP_W-1:0] sample_count;
    reg [1:0] game_slow_count;
    reg [1:0] phys_slow_count;

    always @(posedge clk) begin
        tick_1ms <= 0;
        tick_game <= 0;
        tick_sample <= 0;
        tick_phys <= 0;
        tick_frame <= 0;

        if (rst) begin
            ms_count <= 0;
            phys_count <= 0;
            sample_count <= 0;
            game_slow_count <= 0;
            phys_slow_count <= 0;
        end else begin
            tick_frame <= frame_done;

            if (ms_count == MS_DIV - 1) begin
                ms_count <= 0;
                tick_1ms <= 1;
                game_slow_count <= game_slow_count + 1'b1;
                if (!paused) begin
                    if (!slowmo) tick_game <= 1;
                    else if (game_slow_count == 0) tick_game <= 1;
                end
            end else begin
                ms_count <= ms_count + 1;
            end

            if (sample_count == SMP_DIV - 1) begin
                sample_count <= 0;
                if (!paused) tick_sample <= 1;
            end else begin
                sample_count <= sample_count + 1;
            end

            if (phys_count == PHYS_DIV - 1) begin
                phys_count <= 0;
                phys_slow_count <= phys_slow_count + 1'b1;
                if (!paused) begin
                    if (!slowmo) tick_phys <= 1;
                    else if (phys_slow_count == 0) tick_phys <= 1;
                end
            end else begin
                phys_count <= phys_count + 1;
            end
        end
    end
endmodule
