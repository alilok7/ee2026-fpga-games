`timescale 1ns / 1ps
// gesture_features.v : turn a recorded swipe into a throw
// Owner: Student A
`include "strike_defs.vh"

module gesture_features (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [6:0]  wp,
    input  wire [7:0]  n_samples,
    input  wire [15:0] stance_x,
    input  wire [1:0]  spin_sens,
    output reg  [6:0]  rd_addr,
    input  wire [63:0] rd_data,
    output wire        busy,
    output reg         throw_valid,
    output reg  signed [15:0] throw_vy,
    output reg  signed [15:0] throw_vx,
    output reg  signed [`SPIN_W-1:0] throw_spin,
    output reg  [15:0] throw_x0,
    output reg  [7:0]  throw_mph10,
    output reg         reject,
    output reg  [1:0]  reject_msg,
    output reg  [2:0]  aim_level,
    output reg         aim_right
);
    localparam [16:0] TRIM_TH = 17'd3;

    reg  signed [16:0] multiply_a;
    reg  signed [16:0] multiply_b;
    wire signed [33:0] product;
    reg multiply_start;
    wire multiply_done;
    reg [4:0] multiply_return;
    gesture_multiply u_multiply (
        .clk(clk), .rst(rst), .start(multiply_start),
        .a(multiply_a), .b(multiply_b),
        .product(product), .done(multiply_done)
    );

    reg         dv_start;
    reg  [44:0] dv_num, dv_den;
    wire [44:0] dv_quo;
    wire        dv_done, dv_busy;
    div_seq #(.W(45)) u_div (.clk(clk), .rst(rst), .start(dv_start), .num(dv_num),
        .den(dv_den), .quo(dv_quo), .done(dv_done), .busy(dv_busy));

    reg [23:0] speed_rom [0:63];
    initial $readmemh("speed_curve.mem", speed_rom);

    wire signed [15:0] r_fx = rd_data[31:16];
    wire signed [15:0] r_ff = rd_data[15:0];

    localparam IDLE = 5'd0,  READ_START = 5'd1, READ_END = 5'd2, READ_WINDOW_END = 5'd3, READ_WINDOW_START = 5'd4,
               SELECT_MIDDLE = 5'd5,   READ_MIDDLE = 5'd6, MULTIPLY_MIDDLE_X = 5'd7,   MULTIPLY_MIDDLE_F = 5'd8,  SAVE_PRODUCT = 5'd9,
               SAVE_CROSS = 5'd10,   SAVE_TOTALS = 5'd11,  CHECK_SWIPE = 5'd12, WAIT_AIM = 5'd13, MULTIPLY_AIM = 5'd14,
               MULTIPLY_X_SQUARED = 5'd15, SAVE_AIM = 5'd16, SAVE_X_SQUARED = 5'd17,  SAVE_CHORD_SQUARED = 5'd18, DIVIDE_SPIN = 5'd19,
               WAIT_SPIN = 5'd20, OUTPUT_THROW = 5'd21, TRIM_START = 5'd22, TRIM_READ = 5'd23, TRIM_FINISH = 5'd24, TRIM_STEP = 5'd25, TRIM_NEXT = 5'd26, MULTIPLY_WAIT = 5'd27, MULTIPLY_F_SQUARED = 5'd28;
    reg [4:0] state;
    assign busy = (state != IDLE);

    reg [6:0]  first_addr;
    reg [7:0]  sample_count, sample_index, last_window, first_move, last_move;
    reg        motion_found;
    reg signed [15:0] start_x, start_f, end_x, end_f, window_end;
    reg signed [16:0] peak;
    reg signed [15:0] previous_x, previous_f;
    reg signed [16:0] middle_x, middle_f;
    reg signed [33:0] middle_cross;
    reg [32:0] chord_squared;
    reg [5:0]  speed_index;
    reg [8:0]  aim_ratio;
    reg [15:0] speed;

    reg  signed [16:0] total_x, total_f;
    reg  [16:0] sideways;
    wire signed [16:0] delta_x = end_x - start_x;
    wire signed [16:0] delta_f = end_f - start_f;
    reg [16:0] abs_x;
    always @(*) begin
        if (delta_x[16]) begin
            abs_x = -delta_x;
        end else begin
            abs_x = delta_x;
        end
    end
    wire signed [16:0] window_motion = window_end - r_ff;

    reg  signed [15:0] sample_x, sample_f;
    reg         moving;
    wire signed [16:0] step_x = sample_x - previous_x;
    wire signed [16:0] step_f = sample_f - previous_f;
    wire [17:0] step_size = (step_x[16] ? -step_x : step_x) + (step_f[16] ? -step_f : step_f);

    reg [33:0] abs_cross;
    always @(*) begin
        if (middle_cross[33]) begin
            abs_cross = -middle_cross;
        end else begin
            abs_cross = middle_cross;
        end
    end
    // turn * 256 = 6 * |S| / L^2 * 256 = 1536 * |S| / L^2   (1536 = 1024 + 512)
    wire [44:0] spin_num = {1'b0, abs_cross, 10'd0} + {2'b00, abs_cross, 9'd0};

    reg [8:0] spin_turn;
    reg [8:0] spin_above_deadzone;
    reg [8:0] scaled_spin;
    reg [4:0] spin_magnitude;
    always @(*) begin
        if (dv_quo > 256) spin_turn = 256;
        else spin_turn = dv_quo[8:0];
        if (spin_turn > 8) spin_above_deadzone = spin_turn - 9'd8;
        else spin_above_deadzone = 0;
        scaled_spin = 0;
        case (spin_sens)
            0: scaled_spin = spin_above_deadzone >> 2;
            1: scaled_spin = spin_above_deadzone >> 1;
            2: scaled_spin = spin_above_deadzone;
            3: scaled_spin = spin_above_deadzone >> 3;
        endcase
        if (scaled_spin > 31) spin_magnitude = 31;
        else spin_magnitude = scaled_spin[4:0];
    end

    always @(posedge clk) begin
        throw_valid <= 1'b0;
        reject <= 1'b0;
        dv_start <= 1'b0;
        multiply_start <= 0;
        if (rst) begin
            state <= IDLE;
            rd_addr <= 0;
            multiply_return <= IDLE;
            multiply_a <= 0;
            multiply_b <= 0;
            throw_vy <= 0;
            throw_vx <= 0;
            throw_spin <= 0;
            throw_x0 <= `W_LANE_CX;
            throw_mph10 <= 0;
            reject_msg <= 0;
            aim_level <= 0;
            aim_right <= 0;
            first_addr <= 0;
            sample_count <= 0;
            sample_index <= 0;
            last_window <= 0;
            first_move <= 0;
            last_move <= 0;
            motion_found <= 0;
            start_x <= 0;
            start_f <= 0;
            end_x <= 0;
            end_f <= 0;
            window_end <= 0;
            peak <= 0;
            previous_x <= 0;
            previous_f <= 0;
            middle_x <= 0;
            middle_f <= 0;
            middle_cross <= 0;
            chord_squared <= 0;
            speed_index <= 0;
            aim_ratio <= 0;
            speed <= 0;
            dv_num <= 0;
            dv_den <= 0;
            total_x <= 0;
            total_f <= 0;
            sideways <= 0;
        end else begin
            case (state)
                IDLE: if (start && n_samples >= 2 && n_samples <= 128) begin
                    first_addr    <= wp - n_samples[6:0];
                    sample_count       <= n_samples;
                    rd_addr <= wp - n_samples[6:0];
                    throw_x0 <= stance_x;
                    state <= TRIM_START;
                end

                TRIM_START: begin
                    previous_x <= r_fx;
                    previous_f <= r_ff;
                    sample_index <= 8'd1;
                    motion_found <= 1'b0;
                    first_move <= 8'd1;
                    last_move <= 8'd1;
                    rd_addr <= first_addr + 7'd1;
                    state <= TRIM_READ;
                end
                TRIM_READ: begin
                    sample_x <= r_fx;
                    sample_f <= r_ff;
                    state <= TRIM_STEP;
                end
                TRIM_STEP: begin
                    moving <= (step_size >= TRIM_TH);
                    previous_x <= sample_x;
                    previous_f <= sample_f;
                    state  <= TRIM_NEXT;
                end
                TRIM_NEXT: begin
                    state  <= TRIM_READ;
                    if (moving) begin
                        if (!motion_found) first_move <= sample_index;
                        motion_found <= 1'b1;
                        last_move <= sample_index;
                    end
                    if (sample_index == sample_count - 8'd1) state <= TRIM_FINISH;
                    else begin
                        sample_index <= sample_index + 8'd1;
                        rd_addr <= first_addr + sample_index[6:0] + 7'd1;
                    end
                end
                TRIM_FINISH: begin
                    if (!motion_found) begin
                        reject <= 1'b1;
                        reject_msg <= `GM_FASTER;
                        state <= IDLE;
                    end else begin
                        first_addr    <= first_addr + first_move[6:0] - 7'd1;
                        sample_count       <= last_move - first_move + 8'd2;
                        rd_addr <= first_addr + first_move[6:0] - 7'd1;
                        state <= READ_START;
                    end
                end
                READ_START: begin
                    start_x <= r_fx;
                    start_f <= r_ff;
                    rd_addr <= first_addr + sample_count[6:0] - 7'd1;
                    state <= READ_END;
                end
                READ_END: begin
                    end_x <= r_fx;
                    end_f <= r_ff;
                    peak <= 17'sd0;
                    sample_index    <= sample_count - 8'd1;
                    if ((sample_count < 8'd17)) begin
                        last_window <= 8'd16;
                    end else begin
                        if ((sample_count > 8'd41)) begin
                            last_window <= sample_count - 8'd25;
                        end else begin
                            last_window <= 8'd16;
                        end
                    end
                    if (sample_count < 8'd17) begin
                        peak <= r_ff - start_f;
                        rd_addr <= first_addr + 7'd1;
                        state <= SELECT_MIDDLE;
                    end else begin
                        rd_addr <= first_addr + sample_count[6:0] - 7'd1;
                        state <= READ_WINDOW_END;
                    end
                end

                READ_WINDOW_END: begin
                    window_end <= r_ff;
                    rd_addr <= first_addr + sample_index[6:0] - 7'd16;
                    state <= READ_WINDOW_START;
                end
                READ_WINDOW_START: begin
                    if (window_motion > peak) peak <= window_motion;
                    if (sample_index == last_window) begin
                        rd_addr <= first_addr + 7'd1;
                        state <= SELECT_MIDDLE;
                    end else begin
                        sample_index <= sample_index - 8'd1;
                        rd_addr <= first_addr + sample_index[6:0] - 7'd1;
                        state <= READ_WINDOW_END;
                    end
                end

                SELECT_MIDDLE: begin
                    rd_addr <= first_addr + ((sample_count - 1'b1) >> 1);
                    state <= READ_MIDDLE;
                end
                READ_MIDDLE: begin
                    middle_x <= r_fx - start_x;
                    middle_f <= r_ff - start_f;
                    state <= MULTIPLY_MIDDLE_X;
                end
                MULTIPLY_MIDDLE_X: begin
                    multiply_a <= middle_x;
                    multiply_b <= delta_f;
                    multiply_start <= 1;
                    multiply_return <= SAVE_PRODUCT;
                    state <= MULTIPLY_WAIT;
                end
                MULTIPLY_MIDDLE_F: begin
                    multiply_a <= middle_f;
                    multiply_b <= delta_x;
                    multiply_start <= 1;
                    multiply_return <= SAVE_CROSS;
                    state <= MULTIPLY_WAIT;
                end
                SAVE_PRODUCT: begin
                    middle_cross <= product;
                    state <= MULTIPLY_MIDDLE_F;
                end
                SAVE_CROSS: begin
                    middle_cross <= middle_cross - product;
                    state <= SAVE_TOTALS;
                end

                SAVE_TOTALS: begin
                    total_x <= delta_x;
                    total_f <= delta_f;
                    sideways <= abs_x;
                    state <= CHECK_SWIPE;
                end
                CHECK_SWIPE: begin
                    if ((peak > 17'sd511)) begin
                        speed_index <= 6'd63;
                    end else begin
                        speed_index <= peak[8:3];
                    end
                    if (total_f <= 0 || sideways > total_f) begin
                        reject <= 1'b1;
                        reject_msg <= `GM_FORWARD;
                        state <= IDLE;
                    end else if (total_f < 17'sd32 || peak < 17'sd32) begin
                        reject <= 1'b1;
                        reject_msg <= `GM_FASTER;
                        state <= IDLE;
                    end else begin
                        dv_num <= {20'd0, sideways, 8'd0};
                        dv_den <= {28'd0, total_f};
                        dv_start <= 1'b1;
                        state <= WAIT_AIM;
                    end
                end
                WAIT_AIM: begin
                    speed      <= speed_rom[speed_index][23:8];
                    throw_mph10 <= speed_rom[speed_index][7:0];
                    if (dv_done) begin
                        if ((dv_quo > 40'd256)) begin
                            aim_ratio <= 9'd230;
                        end else begin
                            if ((dv_quo > 40'd26)) begin
                                aim_ratio <= dv_quo[8:0] - 9'd26;
                            end else begin
                                aim_ratio <= 9'd0;
                            end
                        end
                        state <= MULTIPLY_AIM;
                    end
                end
                MULTIPLY_AIM: begin
                    multiply_a <= {1'b0, speed};
                    multiply_b <= {8'd0, aim_ratio};
                    multiply_start <= 1;
                    multiply_return <= SAVE_AIM;
                    state <= MULTIPLY_WAIT;
                end
                MULTIPLY_X_SQUARED: begin
                    multiply_a <= total_x;
                    multiply_b <= total_x;
                    multiply_start <= 1;
                    multiply_return <= SAVE_X_SQUARED;
                    state <= MULTIPLY_WAIT;
                end
                SAVE_AIM: begin
                    if (total_x[16]) begin
                        throw_vx <= -$signed(product[28:13]);
                    end else begin
                        throw_vx <= $signed(product[28:13]);
                    end
                    if ((aim_ratio[8:5] > 4'd7)) begin
                        aim_level <= 3'd7;
                    end else begin
                        aim_level <= aim_ratio[7:5];
                    end
                    aim_right <= ~total_x[16] && (aim_ratio != 0);
                    state <= MULTIPLY_X_SQUARED;
                end
                SAVE_X_SQUARED: begin
                    chord_squared <= product[32:0];
                    state <= MULTIPLY_F_SQUARED;
                end
                SAVE_CHORD_SQUARED: begin
                    chord_squared <= chord_squared + product[32:0];
                    state <= DIVIDE_SPIN;
                end
                MULTIPLY_F_SQUARED: begin
                    multiply_a <= total_f;
                    multiply_b <= total_f;
                    multiply_start <= 1;
                    multiply_return <= SAVE_CHORD_SQUARED;
                    state <= MULTIPLY_WAIT;
                end
                MULTIPLY_WAIT: begin
                    if (multiply_done) state <= multiply_return;
                end
                DIVIDE_SPIN: begin
                    dv_num   <= spin_num;
                    if ((chord_squared == 0)) begin
                        dv_den <= 40'd1;
                    end else begin
                        dv_den <= chord_squared;
                    end
                    dv_start <= 1'b1;
                    state <= WAIT_SPIN;
                end
                WAIT_SPIN: if (dv_done) begin
                    state <= OUTPUT_THROW;
                    if (middle_cross[33]) begin
                        throw_spin <= -$signed({1'b0, spin_magnitude});
                    end else begin
                        throw_spin <= $signed({1'b0, spin_magnitude});
                    end
                end
                OUTPUT_THROW: begin
                    throw_vy    <= speed;
                    throw_valid <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
