`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// flash_ctrl.v : load the save image at power-on, save it on request
//-----------------------------------------------------------------------------
// Owner   : Student D
// Storage : the Basys3 configuration flash (QSPI, used in 1-bit SPI mode).
//           The bitstream needs ~2.2 MB from address 0, so the saves live at
//           the top: slot A = 0x3E0000, slot B = 0x3F0000, each in its OWN
//           64 KB erase sector (erasing one slot can never touch the other).
//           A slot = the 126-byte image + CRC-16. Bytes 3/4 hold a sequence
//           number that goes up by one with every save.
// Boot    : dummy clocks (STARTUPE2 swallows the first USRCCLKO edges after
//           configuration) -> RDID 0x9F (no answer = no flash, play without
//           saves) -> RDSR 0x05 (block-protect bits set = no saves) ->
//           READ 0x03 both slots: magic "SL", version, CRC -> load the valid
//           slot with the newer sequence number into the image; none valid
//           -> factory defaults (persist_ctrl).
// Save    : wait until persist_ctrl is idle, copy the image to a page buffer
//           (a snapshot: the game may keep changing the image), into the
//           OLDER slot: WREN 0x06, sector erase 0xD8, poll RDSR until not
//           busy, WREN, page program 0x02 (128 bytes), poll, then READ it
//           back and compare. A power loss at any point leaves the other
//           slot intact, and a half-written slot fails its CRC at the next
//           boot, so the newest COMPLETE save always wins.
// Structure (Lecture 4): an upper FSM (boot / save steps) starts
//           transactions on a lower FSM (CS low, command, address, data,
//           CS high), which drives spi_byte.
//=============================================================================
module flash_ctrl #(
    parameter POLL_TIMEOUT = 32'd400_000_000      // 4 s
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       save_req,
    input  wire       persist_busy,
    output reg  [6:0] ra,
    input  wire [7:0] rd,
    output reg        we,
    output reg  [6:0] wa,
    output reg  [7:0] wd,
    output reg        c_defaults,
    output reg        load_done,
    output reg        flash_ok,
    output wire       saving,
    output reg        save_error,
    output reg        cs_n,
    output wire       sck,
    output wire       mosi,
    input  wire       miso
);
    localparam [23:0] SLOT_A = 24'h3E0000, SLOT_B = 24'h3F0000;

    // ---------------- SPI byte engine -------------------------------------
    reg        sb_start;
    reg  [7:0] sb_tx;
    wire [7:0] sb_rx;
    wire       sb_done, sb_busy;
    spi_byte u_spi (.clk(clk), .rst(rst), .start(sb_start), .tx(sb_tx), .rx(sb_rx), .done(sb_done),
                    .busy(sb_busy), .sck(sck), .mosi(mosi), .miso(miso));

    reg [7:0] page [0:127];                       // snapshot / program buffer (LUTRAM)
    reg [7:0] crc_lo_r;

    // ---------------- lower FSM: one transaction ---------------------------
    reg        t_go, t_addr_en, t_write, t_nocs;
    reg [7:0]  t_cmd, t_n;
    reg [23:0] t_addr;
    reg [7:0]  t_i;                               // data byte index
    reg        t_done, rx_valid;
    reg [7:0]  rx_byte;
    reg [7:0]  rx_idx;                            // index of rx_byte (t_i has moved on)
    localparam T_IDLE = 3'd0, T_CS = 3'd1, T_CMD = 3'd2, T_ADDR = 3'd3, T_DATA = 3'd4, T_END = 3'd5;
    reg [2:0]  ts;
    reg [1:0]  t_ab;                              // address byte counter
    reg [3:0]  t_wait;
    reg        t_wait_sb;                         // a byte is in flight

    always @(posedge clk) begin
        sb_start <= 1'b0; t_done <= 1'b0; rx_valid <= 1'b0;
        if (rst) begin
            ts <= T_IDLE; cs_n <= 1'b1; t_i <= 0; t_ab <= 0; t_wait <= 0; t_wait_sb <= 0;
            sb_tx <= 8'h00; rx_byte <= 0; rx_idx <= 0;
        end else case (ts)
            T_IDLE: if (t_go) begin
                cs_n <= t_nocs; t_wait <= 4'd0; ts <= T_CS;
            end
            T_CS: begin                               // CS set-up time
                t_wait <= t_wait + 4'd1;
                if (t_wait == 4'd3) begin sb_tx <= t_cmd; sb_start <= 1'b1; t_wait_sb <= 1'b1; ts <= T_CMD; end
            end
            T_CMD: if (sb_done) begin
                t_ab <= 2'd0; t_i <= 8'd0;
                if (t_addr_en) begin sb_tx <= t_addr[23:16]; sb_start <= 1'b1; ts <= T_ADDR; end
                else if (t_n != 0) begin sb_tx <= t_write ? page[0] : 8'h00; sb_start <= 1'b1; ts <= T_DATA; end
                else begin t_wait <= 4'd0; ts <= T_END; end
            end
            T_ADDR: if (sb_done) begin
                t_ab <= t_ab + 2'd1;
                if (t_ab == 2'd0)      begin sb_tx <= t_addr[15:8]; sb_start <= 1'b1; end
                else if (t_ab == 2'd1) begin sb_tx <= t_addr[7:0];  sb_start <= 1'b1; end
                else if (t_n != 0)     begin sb_tx <= t_write ? page[0] : 8'h00; sb_start <= 1'b1; ts <= T_DATA; end
                else begin t_wait <= 4'd0; ts <= T_END; end
            end
            T_DATA: if (sb_done) begin
                rx_valid <= ~t_write; rx_byte <= sb_rx; rx_idx <= t_i;
                if (t_i == t_n - 8'd1) begin t_wait <= 4'd0; ts <= T_END; end
                else begin
                    t_i <= t_i + 8'd1;
                    sb_tx <= t_write ? page[t_i[6:0] + 7'd1] : 8'h00;
                    sb_start <= 1'b1;
                end
            end
            T_END: begin                              // CS high and stay high a while
                cs_n <= 1'b1;
                t_wait <= t_wait + 4'd1;
                if (t_wait == 4'd15) begin t_done <= 1'b1; ts <= T_IDLE; end
            end
            default: ts <= T_IDLE;
        endcase
    end

    // ---------------- CRC of the stream ------------------------------------
    reg  [15:0] crc;
    reg  [7:0]  crc_d;
    wire [15:0] crc_n;
    crc16 u_crc (.crc_in(crc), .data(crc_d), .crc_out(crc_n));

    // ---------------- upper FSM: boot and save ------------------------------
    localparam U_DUMMY = 5'd0, U_RDID = 5'd1, U_RDSR0 = 5'd2, U_SCAN = 5'd3, U_CHOOSE = 5'd4,
               U_LOAD = 5'd5, U_DEF = 5'd6, U_READY = 5'd7, U_SNAP = 5'd8, U_WREN1 = 5'd9,
               U_ERASE = 5'd10, U_POLL1 = 5'd11, U_WREN2 = 5'd12, U_PROG = 5'd13, U_POLL2 = 5'd14,
               U_VERIFY = 5'd15, U_DONE = 5'd16, U_DEFW = 5'd17;
    reg [4:0]  us;
    reg        started;                           // transaction issued in this state
    reg        scan_b;                            // scanning slot B
    reg [7:0]  id0;
    reg        prot;
    reg        val_a, val_b, ok_scan, chosen_b, last_b;
    reg [15:0] seq_a, seq_b, last_seq, seq_scan, crc_rd;
    reg        pend;                              // save requested
    reg [7:0]  snap_i;
    reg [31:0] poll_cnt;
    reg        verify_bad;
    assign saving = (us >= U_SNAP) && (us <= U_DONE);

    wire [23:0] target = last_b ? SLOT_A : SLOT_B;  // always the older slot
    wire [15:0] new_seq = last_seq + 16'd1;
    wire [7:0]  snap_byte = (snap_i == 8'd3) ? new_seq[7:0] : (snap_i == 8'd4) ? new_seq[15:8] : rd;

    // start a transaction once per state (helper)
    task trans(input [7:0] cmd, input aen, input [23:0] addr, input [7:0] n, input wr, input nocs);
        begin
            if (!started && ts == T_IDLE) begin
                t_go <= 1'b1; t_cmd <= cmd; t_addr_en <= aen; t_addr <= addr; t_n <= n;
                t_write <= wr; t_nocs <= nocs; started <= 1'b1;
            end
        end
    endtask

    always @(posedge clk) begin
        t_go <= 1'b0; we <= 1'b0; c_defaults <= 1'b0;
        if (rst) begin
            us <= U_DUMMY; started <= 0; scan_b <= 0; id0 <= 0; prot <= 0;
            val_a <= 0; val_b <= 0; ok_scan <= 0; chosen_b <= 0; last_b <= 1'b1;
            seq_a <= 0; seq_b <= 0; last_seq <= 0; seq_scan <= 0; crc_rd <= 0;
            pend <= 0; snap_i <= 0; poll_cnt <= 0; verify_bad <= 0;
            load_done <= 0; flash_ok <= 0; save_error <= 0; ra <= 0; wa <= 0; wd <= 0;
            crc <= 16'hFFFF; crc_d <= 0;
            t_cmd <= 0; t_addr_en <= 0; t_addr <= 0; t_n <= 0; t_write <= 0; t_nocs <= 0;
        end else begin
            if (save_req) pend <= 1'b1;
            case (us)
                U_DUMMY: begin                        // 2 bytes of clocks with CS high
                    trans(8'hFF, 1'b0, 24'd0, 8'd1, 1'b0, 1'b1);
                    if (t_done) begin started <= 0; us <= U_RDID; end
                end
                U_RDID: begin
                    trans(8'h9F, 1'b0, 24'd0, 8'd3, 1'b0, 1'b0);
                    if (rx_valid && rx_idx == 0) id0 <= rx_byte;
                    if (t_done) begin started <= 0; us <= U_RDSR0; end
                end
                U_RDSR0: begin
                    trans(8'h05, 1'b0, 24'd0, 8'd1, 1'b0, 1'b0);
                    if (rx_valid) prot <= (rx_byte[4:2] != 3'b000);
                    if (t_done) begin
                        started <= 0;
                        if (id0 == 8'h00 || id0 == 8'hFF) us <= U_DEF;   // no flash answered
                        else begin us <= U_SCAN; scan_b <= 1'b0; crc <= 16'hFFFF; ok_scan <= 1'b1; end
                    end
                end
                U_SCAN: begin                         // read one slot, check it
                    trans(8'h03, 1'b1, scan_b ? SLOT_B : SLOT_A, 8'd128, 1'b0, 1'b0);
                    if (rx_valid) begin
                        // crc_n folds in the byte held in crc_d, so the CRC runs one
                        // byte behind the stream; U_CHOOSE folds in the last one
                        if (rx_idx < 8'd126) begin
                            crc_d <= rx_byte;
                            if (rx_idx != 8'd0) crc <= crc_n;
                        end
                        if (rx_idx == 8'd0 && rx_byte != 8'h53) ok_scan <= 1'b0;
                        if (rx_idx == 8'd1 && rx_byte != 8'h4C) ok_scan <= 1'b0;
                        if (rx_idx == 8'd2 && rx_byte != 8'h01) ok_scan <= 1'b0;
                        if (rx_idx == 8'd3) seq_scan[7:0]  <= rx_byte;
                        if (rx_idx == 8'd4) seq_scan[15:8] <= rx_byte;
                        if (rx_idx == 8'd126) crc_rd[15:8] <= rx_byte;
                        if (rx_idx == 8'd127) crc_rd[7:0]  <= rx_byte;
                    end
                    if (t_done) begin
                        started <= 0;
                        us <= U_CHOOSE;
                    end
                end
                U_CHOOSE: begin
                    // finish the CRC with the last data byte (crc_d = byte 125)
                    if (!scan_b) begin
                        val_a <= ok_scan && (crc_n == crc_rd); seq_a <= seq_scan;
                        scan_b <= 1'b1; crc <= 16'hFFFF; crc_d <= 8'h00; ok_scan <= 1'b1;
                        us <= U_SCAN;
                    end else begin
                        // B is newer if (seq_b - seq_a) is positive as a signed number
                        if (val_a && (ok_scan && crc_n == crc_rd) && $signed(seq_scan - seq_a) > 0)
                            begin chosen_b <= 1'b1; last_seq <= seq_scan; end
                        else if (val_a)
                            begin chosen_b <= 1'b0; last_seq <= seq_a; end
                        else
                            begin chosen_b <= 1'b1; last_seq <= seq_scan; end
                        val_b <= ok_scan && (crc_n == crc_rd);
                        us <= (val_a || (ok_scan && crc_n == crc_rd)) ? U_LOAD : U_DEF;
                    end
                end
                U_LOAD: begin
                    trans(8'h03, 1'b1, chosen_b ? SLOT_B : SLOT_A, 8'd126, 1'b0, 1'b0);
                    if (rx_valid) begin we <= 1'b1; wa <= rx_idx[6:0]; wd <= rx_byte; end
                    if (t_done) begin
                        started <= 0; last_b <= chosen_b;
                        flash_ok <= !prot; load_done <= 1'b1; us <= U_READY;
                    end
                end
                U_DEF: begin                          // no valid save: factory image
                    c_defaults <= 1'b1;
                    snap_i <= 8'd0;
                    us <= U_DEFW;
                end
                // persist_ctrl sees the command one clock later and is busy one
                // clock after that: wait 4 clocks before trusting persist_busy
                U_DEFW: if (snap_i != 8'd4) snap_i <= snap_i + 8'd1;
                else if (!persist_busy) begin
                    flash_ok <= (id0 != 8'h00 && id0 != 8'hFF) && !prot;
                    last_seq <= 16'd0; last_b <= 1'b1;
                    load_done <= 1'b1; us <= U_READY;
                end
                // ---------------- saving -----------------------------------
                U_READY: begin
                    snap_i <= 8'd0; ra <= 7'd0; crc <= 16'hFFFF;
                    if (pend && flash_ok && !persist_busy) begin pend <= 1'b0; us <= U_SNAP; end
                    else if (pend && !flash_ok) pend <= 1'b0;          // no flash: nothing to do
                end
                U_SNAP: begin
                    // ra is a register: at step k it holds k, so rd = image[k].
                    // Bytes 3/4 get the new sequence number; the CRC runs one
                    // byte behind (crc_d) like in U_SCAN.
                    snap_i <= snap_i + 8'd1;
                    ra <= snap_i[6:0] + 7'd1;
                    if (snap_i < 8'd126) begin
                        page[snap_i[6:0]] <= snap_byte;
                        crc_d <= snap_byte;
                        if (snap_i != 8'd0) crc <= crc_n;
                    end else if (snap_i == 8'd126) begin
                        // one write per clock keeps the page buffer a small LUTRAM
                        page[126] <= crc_n[15:8];
                        crc_lo_r  <= crc_n[7:0];
                    end else begin
                        page[127] <= crc_lo_r;
                        started <= 0; us <= U_WREN1;
                    end
                end
                U_WREN1: begin
                    trans(8'h06, 1'b0, 24'd0, 8'd0, 1'b0, 1'b0);
                    if (t_done) begin started <= 0; us <= U_ERASE; end
                end
                U_ERASE: begin
                    trans(8'hD8, 1'b1, target, 8'd0, 1'b0, 1'b0);
                    if (t_done) begin started <= 0; poll_cnt <= 0; us <= U_POLL1; end
                end
                U_POLL1, U_POLL2: begin               // RDSR until WIP = 0
                    poll_cnt <= poll_cnt + 32'd1;
                    trans(8'h05, 1'b0, 24'd0, 8'd1, 1'b0, 1'b0);
                    if (t_done) begin
                        started <= 0;
                        if (!rx_byte[0]) us <= (us == U_POLL1) ? U_WREN2 : U_VERIFY;
                        else if (poll_cnt > POLL_TIMEOUT) begin save_error <= 1'b1; us <= U_READY; end
                    end
                end
                U_WREN2: begin
                    trans(8'h06, 1'b0, 24'd0, 8'd0, 1'b0, 1'b0);
                    if (t_done) begin started <= 0; us <= U_PROG; end
                end
                U_PROG: begin
                    trans(8'h02, 1'b1, target, 8'd128, 1'b1, 1'b0);
                    if (t_done) begin started <= 0; poll_cnt <= 0; us <= U_POLL2; end
                end
                U_VERIFY: begin
                    trans(8'h03, 1'b1, target, 8'd128, 1'b0, 1'b0);
                    if (!started) verify_bad <= 1'b0;
                    if (rx_valid && rx_byte != page[rx_idx[6:0]]) verify_bad <= 1'b1;
                    if (t_done) begin started <= 0; us <= U_DONE; end
                end
                U_DONE: begin
                    if (verify_bad) save_error <= 1'b1;
                    else begin
                        save_error <= 1'b0;
                        last_b <= ~last_b; last_seq <= last_seq + 16'd1;
                    end
                    us <= U_READY;
                end
                default: us <= U_READY;
            endcase
        end
    end
endmodule
