`timescale 1ns / 1ps
// replay_buffer.v : instant replay of the last throw, in slow motion
// Owner: Student A
`include "strike_defs.vh"

module replay_buffer (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [`GS_W-1:0] game_state,
    input  wire        start,
    input  wire        fast,
    input  wire        stop,
    input  wire        ball_vis_in,
    input  wire [15:0] ball_x_in,
    input  wire [15:0] ball_y_in,
    input  wire [5:0]  angle_in,
    input  wire signed [10:0] cam_in,
    input  wire [239:0] pins_in,
    output reg         active,
    output reg         done,
    output reg         ball_vis,
    output reg  [15:0] ball_x,
    output reg  [15:0] ball_y,
    output reg  [5:0]  angle,
    output reg  signed [10:0] cam,
    output reg  [239:0] pins
);
    reg [35:0] ram [0:2047];
    reg        write_enable;
    reg [10:0] write_address, read_address;
    reg [35:0] write_data, read_data;
    always @(posedge clk) begin
        if (write_enable) ram[write_address] <= write_data;
        read_data <= ram[read_address];
    end

    wire [287:0] snapshot = {14'd0, ball_vis_in, ball_x_in[11:6], ball_y_in[15:6], angle_in, cam_in, pins_in};
    wire recording = (game_state == `GS_ROLL) || (game_state == `GS_PINACTION) || (game_state == `GS_SETTLE);

    reg [7:0]  write_slot;
    reg [8:0]  count;
    reg [3:0]  write_word;
    reg        write_active;
    reg [287:0] write_bits;
    reg        was_recording;

    localparam IDLE = 2'd0, WAIT_FRAME = 2'd1, READ_WORDS = 2'd2;
    reg [1:0]  play_state;
    reg [7:0]  read_slot;
    reg [8:0]  frames_left;
    reg [3:0]  read_word;
    reg        half_speed;
    reg [287:0] frame_bits;
    wire [287:0] complete_frame = {read_data, frame_bits[287:36]};

    always @(posedge clk) begin
        write_enable <= 1'b0;
        done <= 1'b0;
        if (rst) begin
            write_slot <= 0;
            count <= 0;
            write_word <= 0;
            write_active <= 0;
            write_bits <= 0;
            was_recording <= 0;
            play_state <= IDLE;
            read_slot <= 0;
            frames_left <= 0;
            read_word <= 0;
            half_speed <= 0;
            frame_bits <= 0;
            active <= 0;
            write_address <= 0;
            read_address <= 0;
            write_data <= 0;
            ball_vis <= 0;
            ball_x <= 0;
            ball_y <= 0;
            angle <= 0;
            cam <= 0;
            pins <= 0;
        end else begin
            was_recording <= recording;
            if (recording && !was_recording) count <= 0;
            if (recording && tick_frame && !write_active && !active) begin
                write_bits <= snapshot;
                write_word <= 0;
                write_active <= 1;
            end
            if (write_active) begin
                write_enable <= 1'b1;
                write_address <= {write_slot, write_word[2:0]};
                write_data <= write_bits[35:0];
                write_bits <= write_bits >> 36;
                write_word <= write_word + 4'd1;
                if (write_word == 4'd7) begin
                    write_active <= 0;
                    write_slot <= write_slot + 8'd1;
                    if (count != 9'd256) count <= count + 9'd1;
                end
            end

            case (play_state)
                IDLE: if (start && count != 0) begin
                    active <= 1;
                    read_slot <= write_slot - count[7:0];
                    frames_left <= count;
                    half_speed <= 0;
                    play_state <= WAIT_FRAME;
                end else if (start) done <= 1'b1;
                WAIT_FRAME: if (stop) begin
                    active <= 0;
                    done <= 1'b1;
                    play_state <= IDLE;
                end else if (tick_frame) begin
                    half_speed <= ~half_speed;
                    if (!half_speed || fast) begin
                        if (frames_left == 0) begin
                            active <= 0;
                            done <= 1'b1;
                            play_state <= IDLE;
                        end
                        else begin
                            read_word <= 0;
                            read_address <= {read_slot, 3'd0};
                            play_state <= READ_WORDS;
                        end
                    end
                end
                READ_WORDS: begin
                    read_word <= read_word + 4'd1;
                    read_address <= {read_slot, read_word[2:0] + 3'd1};
                    if (read_word != 0) frame_bits <= {read_data, frame_bits[287:36]};
                    if (read_word == 4'd8) begin
                        pins     <= complete_frame[239:0];
                        cam      <= complete_frame[250:240];
                        play_state <= WAIT_FRAME;
                        read_slot <= read_slot + 8'd1;
                        frames_left <= frames_left - 9'd1;
                        ball_vis <= complete_frame[273];
                        ball_x <= {4'd0, complete_frame[272:267], 6'd32};
                        ball_y <= {complete_frame[266:257], 6'd32};
                        angle    <= complete_frame[256:251];
                    end
                end
                default: play_state <= IDLE;
            endcase
        end
    end
endmodule
