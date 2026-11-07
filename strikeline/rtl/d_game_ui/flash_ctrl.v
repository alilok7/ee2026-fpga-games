`timescale 1ns / 1ps
`include "strike_defs.vh"
// flash_ctrl.v : load the save image from flash at power-on, save it on request
// Student D. Slots at 0x3E0000 / 0x3F0000; the newest valid one (seq + CRC) wins.
// Upper FSM (boot / save steps) -> lower FSM (one transaction) -> spi_byte.
module flash_ctrl #(
    parameter POLL_TIMEOUT = 32'd400_000_000      // 4 s at 100 MHz (testbench: shorter)
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       save_req,
    input  wire       persist_busy,
    output reg  [6:0] ra,               // save image read port 0
    input  wire [7:0] rd,
    output reg        we,
    output reg  [6:0] wa,
    output reg  [7:0] wd,
    output reg        c_defaults,
    output reg        load_done,
    output reg        flash_ok,         // flash present and writable
    output wire       saving,
    output reg        save_error,
    output reg        cs_n,             // QspiCSn
    output wire       sck,
    output wire       mosi,             // QspiDB[0]
    input  wire       miso              // QspiDB[1]
);
    localparam [23:0] SLOT_A = 24'h3E0000, SLOT_B = 24'h3F0000;

    // spi_byte: the lowest submachine
    reg        sb_start;
    reg  [7:0] sb_tx;
    wire [7:0] sb_rx;
    wire       sb_done, sb_busy;
    // the byte engine
    spi_byte u_spi (.clk(clk), .rst(rst), .start(sb_start), .tx(sb_tx), .rx(sb_rx), .done(sb_done),
                    .busy(sb_busy), .sck(sck), .mosi(mosi), .miso(miso));

    // snapshot to program (LUT-RAM)
    reg [7:0] page [0:127];

    // LOWER FSM: one transaction  (CS low, cmd, [3 address bytes], [n data], CS high)
    reg        t_go;
    reg  [7:0] t_cmd;                   // command byte
    reg        t_addr_en;
    reg [23:0] t_addr;
    reg  [7:0] t_n;                     // number of data bytes (0..128)
    reg        t_write;
    reg        t_nocs;
    reg        t_done;
    reg        rx_valid;
    reg  [7:0] rx_byte;                 //   ... this byte
    reg  [7:0] rx_idx;

    localparam T_IDLE = 3'd0, T_CS = 3'd1, T_CMD = 3'd2, T_ADDR = 3'd3, T_DATA = 3'd4, T_END = 3'd5;
    // lower FSM state + its counters
    reg [2:0] ts, ts_next;
    reg [3:0] t_wait;
    reg [1:0] t_ab;                     // counter: address byte 0..2
    reg [7:0] t_i;                      // counter: data byte

    // next-state logic
    always @(*) begin
        ts_next = ts;
        case (ts)
            T_IDLE: if (t_go) ts_next = T_CS;
            T_CS:   if (t_wait == 4'd3) ts_next = T_CMD;
            T_CMD:  if (sb_done) ts_next = t_addr_en ? T_ADDR : (t_n != 0) ? T_DATA : T_END;
            T_ADDR: if (sb_done && t_ab == 2'd2) ts_next = (t_n != 0) ? T_DATA : T_END;
            T_DATA: if (sb_done && t_i == t_n - 8'd1) ts_next = T_END;
            T_END:  if (t_wait == 4'd15) ts_next = T_IDLE;
            default: ts_next = T_IDLE;
        endcase
    end

    // state register + datapath
    always @(posedge clk) begin
        if (rst) begin
            ts <= T_IDLE; cs_n <= 1'b1; t_wait <= 0; t_ab <= 0; t_i <= 0;
            sb_start <= 0; sb_tx <= 8'h00; t_done <= 0; rx_valid <= 0; rx_byte <= 0; rx_idx <= 0;
        end else begin
            ts <= ts_next;
            sb_start <= 1'b0; t_done <= 1'b0; rx_valid <= 1'b0;      // pulses
            case (ts)
                T_IDLE: if (t_go) begin cs_n <= t_nocs; t_wait <= 4'd0; end
                T_CS: begin                                          // CS set-up time
                    t_wait <= t_wait + 4'd1;
                    if (t_wait == 4'd3) begin sb_tx <= t_cmd; sb_start <= 1'b1; end
                end
                T_CMD: if (sb_done) begin
                    t_ab <= 2'd0; t_i <= 8'd0;
                    if (t_addr_en)     begin sb_tx <= t_addr[23:16]; sb_start <= 1'b1; end
                    else if (t_n != 0) begin sb_tx <= t_write ? page[0] : 8'h00; sb_start <= 1'b1; end
                    else               t_wait <= 4'd0;
                end
                T_ADDR: if (sb_done) begin
                    t_ab <= t_ab + 2'd1;
                    if (t_ab == 2'd0)      begin sb_tx <= t_addr[15:8]; sb_start <= 1'b1; end
                    else if (t_ab == 2'd1) begin sb_tx <= t_addr[7:0];  sb_start <= 1'b1; end
                    else if (t_n != 0)     begin sb_tx <= t_write ? page[0] : 8'h00; sb_start <= 1'b1; end
                    else                   t_wait <= 4'd0;
                end
                T_DATA: if (sb_done) begin
                    rx_valid <= ~t_write; rx_byte <= sb_rx; rx_idx <= t_i;
                    if (t_i == t_n - 8'd1) t_wait <= 4'd0;
                    else begin
                        t_i <= t_i + 8'd1;
                        sb_tx <= t_write ? page[t_i[6:0] + 7'd1] : 8'h00;    // next byte
                        sb_start <= 1'b1;
                    end
                end
                T_END: begin                                         // CS high, stay high a while
                    cs_n <= 1'b1;
                    t_wait <= t_wait + 4'd1;
                    if (t_wait == 4'd15) t_done <= 1'b1;
                end
                default: ;
            endcase
        end
    end

    // CRC of the byte stream (one byte behind: crc_d is the byte waiting)
    reg  [15:0] crc;
    reg  [7:0]  crc_d;
    wire [15:0] crc_n;
    crc16 u_crc (.crc_in(crc), .data(crc_d), .crc_out(crc_n));

    // UPPER FSM: boot and save steps
    localparam U_DUMMY = 5'd0,  U_RDID = 5'd1,   U_RDSR0 = 5'd2,  U_SCAN = 5'd3,  U_CHOOSE = 5'd4,
               U_LOAD  = 5'd5,  U_DEF  = 5'd6,   U_READY = 5'd7,  U_SNAP = 5'd8,  U_WREN1  = 5'd9,
               U_ERASE = 5'd10, U_POLL1 = 5'd11, U_WREN2 = 5'd12, U_PROG = 5'd13, U_POLL2  = 5'd14,
               U_VERIFY = 5'd15, U_DONE = 5'd16, U_DEFW = 5'd17;
    // upper FSM state and its registers
    reg [4:0]  us, us_next;

    reg        started;
    reg        scan_b;
    reg [7:0]  id0;
    reg        prot;                    // block-protect bits were set
    reg        ok_scan;
    reg        val_a, val_b;            // slot A / B is valid
    reg        chosen_b;                // load slot B (else A)
    reg        last_b;
    reg [15:0] seq_a, seq_scan, last_seq, crc_rd;
    reg        pend;                    // a save was requested
    reg [7:0]  snap_i;                  // counter: byte being copied
    reg [7:0]  crc_lo_r;
    reg [2:0]  def_wait;
    reg [31:0] poll_cnt;                // counter: timeout while polling
    reg        verify_bad;

    assign saving = (us >= U_SNAP) && (us <= U_DONE);

    wire [23:0] target    = last_b ? SLOT_A : SLOT_B;        // always the OLDER slot
    wire [15:0] new_seq   = last_seq + 16'd1;
    wire [7:0]  snap_byte = (snap_i == 8'd3) ? new_seq[7:0] : (snap_i == 8'd4) ? new_seq[15:8] : rd;
    wire        slot_ok   = ok_scan && (crc_n == crc_rd);    // the slot just read is valid
    wire        no_flash  = (id0 == 8'h00) || (id0 == 8'hFF);
    // slot B is newer if (seq_b - seq_a) is a positive signed number (works across wrap-round)
    wire [15:0] seq_diff  = seq_scan - seq_a;
    wire        b_newer   = !seq_diff[15] && (seq_diff != 16'd0);

    // transaction table: which transaction each state needs (output logic)
    reg        tr_need, tr_aen, tr_wr, tr_nocs;
    reg [7:0]  tr_cmd, tr_n;
    reg [23:0] tr_addr;
    always @(*) begin
        tr_need = 1'b1; tr_aen = 1'b0; tr_wr = 1'b0; tr_nocs = 1'b0;
        tr_cmd = 8'h00; tr_n = 8'd0; tr_addr = 24'd0;
        case (us)
            U_DUMMY:          begin tr_cmd = 8'hFF; tr_n = 8'd1; tr_nocs = 1'b1; end       // clocks only
            U_RDID:           begin tr_cmd = 8'h9F; tr_n = 8'd3; end                       // read ID
            U_RDSR0,
            U_POLL1, U_POLL2: begin tr_cmd = 8'h05; tr_n = 8'd1; end                       // read status
            U_SCAN:           begin tr_cmd = 8'h03; tr_aen = 1'b1; tr_addr = scan_b ? SLOT_B : SLOT_A; tr_n = 8'd128; end
            U_LOAD:           begin tr_cmd = 8'h03; tr_aen = 1'b1; tr_addr = chosen_b ? SLOT_B : SLOT_A; tr_n = 8'd126; end
            U_WREN1, U_WREN2: begin tr_cmd = 8'h06; end                                    // write enable
            U_ERASE:          begin tr_cmd = 8'hD8; tr_aen = 1'b1; tr_addr = target; end   // 64 KB erase
            U_PROG:           begin tr_cmd = 8'h02; tr_aen = 1'b1; tr_addr = target; tr_n = 8'd128; tr_wr = 1'b1; end
            U_VERIFY:         begin tr_cmd = 8'h03; tr_aen = 1'b1; tr_addr = target; tr_n = 8'd128; end
            default:          tr_need = 1'b0;                                              // no transaction
        endcase
    end
    wire issue = tr_need && !started && (ts == T_IDLE);      // start it once per state

    // next-state logic
    always @(*) begin
        us_next = us;
        case (us)
            U_DUMMY:  if (t_done) us_next = U_RDID;
            U_RDID:   if (t_done) us_next = U_RDSR0;
            U_RDSR0:  if (t_done) us_next = no_flash ? U_DEF : U_SCAN;
            U_SCAN:   if (t_done) us_next = U_CHOOSE;
            U_CHOOSE: if (!scan_b) us_next = U_SCAN;                                  // now slot B
                      else         us_next = (val_a || slot_ok) ? U_LOAD : U_DEF;
            U_LOAD:   if (t_done) us_next = U_READY;
            U_DEF:    us_next = U_DEFW;
            U_DEFW:   if (def_wait == 3'd4 && !persist_busy) us_next = U_READY;
            U_READY:  if (pend && flash_ok && !persist_busy) us_next = U_SNAP;
            U_SNAP:   if (snap_i == 8'd127) us_next = U_WREN1;
            U_WREN1:  if (t_done) us_next = U_ERASE;
            U_ERASE:  if (t_done) us_next = U_POLL1;
            U_POLL1,
            U_POLL2:  if (t_done) begin
                          if (!rx_byte[0])               us_next = (us == U_POLL1) ? U_WREN2 : U_VERIFY;  // WIP = 0
                          else if (poll_cnt > POLL_TIMEOUT) us_next = U_READY;                       // give up
                      end
            U_WREN2:  if (t_done) us_next = U_PROG;
            U_PROG:   if (t_done) us_next = U_POLL2;
            U_VERIFY: if (t_done) us_next = U_DONE;
            U_DONE:   us_next = U_READY;
            default:  us_next = U_READY;
        endcase
    end

    // state register + datapath
    always @(posedge clk) begin
        if (rst) begin
            us <= U_DUMMY; started <= 0; scan_b <= 0; id0 <= 0; prot <= 0;
            ok_scan <= 0; val_a <= 0; val_b <= 0; chosen_b <= 0; last_b <= 1'b1;
            seq_a <= 0; seq_scan <= 0; last_seq <= 0; crc_rd <= 0;
            pend <= 0; snap_i <= 0; crc_lo_r <= 0; def_wait <= 0; poll_cnt <= 0; verify_bad <= 0;
            load_done <= 0; flash_ok <= 0; save_error <= 0; c_defaults <= 0;
            ra <= 0; we <= 0; wa <= 0; wd <= 0; crc <= 16'hFFFF; crc_d <= 0;
            t_go <= 0; t_cmd <= 0; t_addr_en <= 0; t_addr <= 0; t_n <= 0; t_write <= 0; t_nocs <= 0;
        end else begin
            us <= us_next;
            t_go <= 1'b0; we <= 1'b0; c_defaults <= 1'b0;            // pulses

            // start this state's transaction (once), latch its details
            if (issue) begin
                t_go <= 1'b1; t_cmd <= tr_cmd; t_addr_en <= tr_aen; t_addr <= tr_addr;
                t_n <= tr_n; t_write <= tr_wr; t_nocs <= tr_nocs;
            end
            if (t_done)     started <= 1'b0;                         // ready for the next one
            else if (issue) started <= 1'b1;

            if (save_req) pend <= 1'b1;                              // remember the request

            case (us)
                U_RDID:  if (rx_valid && rx_idx == 8'd0) id0 <= rx_byte;
                U_RDSR0: begin
                    if (rx_valid) prot <= (rx_byte[4:2] != 3'b000);  // BP2..BP0
                    if (t_done && !no_flash) begin scan_b <= 1'b0; crc <= 16'hFFFF; ok_scan <= 1'b1; end
                end
                U_SCAN: if (rx_valid) begin
                    if (rx_idx < 8'd126) begin
                        crc_d <= rx_byte;                            // fold in next clock
                        if (rx_idx != 8'd0) crc <= crc_n;            // fold in the previous byte
                    end
                    if (rx_idx == 8'd0 && rx_byte != 8'h53) ok_scan <= 1'b0;   // 'S'
                    if (rx_idx == 8'd1 && rx_byte != 8'h4C) ok_scan <= 1'b0;   // 'L'
                    if (rx_idx == 8'd2 && rx_byte != 8'h01) ok_scan <= 1'b0;   // version
                    if (rx_idx == 8'd3)   seq_scan[7:0]  <= rx_byte;
                    if (rx_idx == 8'd4)   seq_scan[15:8] <= rx_byte;
                    if (rx_idx == 8'd126) crc_rd[15:8]   <= rx_byte;
                    if (rx_idx == 8'd127) crc_rd[7:0]    <= rx_byte;
                end
                U_CHOOSE: begin                                      // crc_n now includes byte 125
                    if (!scan_b) begin                               // slot A checked
                        val_a <= slot_ok; seq_a <= seq_scan;
                        scan_b <= 1'b1; crc <= 16'hFFFF; crc_d <= 8'h00; ok_scan <= 1'b1;
                    end else begin                                   // slot B checked: choose
                        if (val_a && slot_ok && b_newer) begin chosen_b <= 1'b1; last_seq <= seq_scan; end
                        else if (val_a)                  begin chosen_b <= 1'b0; last_seq <= seq_a;    end
                        else                             begin chosen_b <= 1'b1; last_seq <= seq_scan; end
                        val_b <= slot_ok;
                    end
                end
                U_LOAD: begin                                        // copy the slot into the image
                    if (rx_valid) begin we <= 1'b1; wa <= rx_idx[6:0]; wd <= rx_byte; end
                    if (t_done) begin last_b <= chosen_b; flash_ok <= !prot; load_done <= 1'b1; end
                end
                U_DEF: begin c_defaults <= 1'b1; def_wait <= 3'd0; end
                // wait 4 clocks for persist_ctrl to see DEFAULTS before trusting persist_busy
                U_DEFW: begin
                    if (def_wait != 3'd4) def_wait <= def_wait + 3'd1;
                    else if (!persist_busy) begin
                        flash_ok <= !no_flash && !prot;
                        last_seq <= 16'd0; last_b <= 1'b1; load_done <= 1'b1;
                    end
                end
                // saving
                U_READY: begin
                    snap_i <= 8'd0; ra <= 7'd0; crc <= 16'hFFFF;
                    if (pend && flash_ok && !persist_busy) pend <= 1'b0;   // start the save
                    else if (pend && !flash_ok)            pend <= 1'b0;   // no flash: nothing to do
                end
                U_SNAP: begin
                    // copy image[i] into the page (bytes 3/4 = new seq), CRC one byte behind
                    snap_i <= snap_i + 8'd1;
                    ra <= snap_i[6:0] + 7'd1;
                    if (snap_i < 8'd126) begin
                        page[snap_i[6:0]] <= snap_byte;
                        crc_d <= snap_byte;
                        if (snap_i != 8'd0) crc <= crc_n;
                    end else if (snap_i == 8'd126) begin
                        page[126] <= crc_n[15:8];                    // CRC high byte
                        crc_lo_r  <= crc_n[7:0];
                    end else begin
                        page[127] <= crc_lo_r;                       // CRC low byte
                    end
                end
                U_ERASE, U_PROG: if (t_done) poll_cnt <= 32'd0;
                U_POLL1, U_POLL2: begin
                    poll_cnt <= poll_cnt + 32'd1;
                    if (t_done && rx_byte[0] && poll_cnt > POLL_TIMEOUT) save_error <= 1'b1;
                end
                U_VERIFY: begin                                      // read back and compare
                    if (!started) verify_bad <= 1'b0;
                    if (rx_valid && rx_byte != page[rx_idx[6:0]]) verify_bad <= 1'b1;
                end
                U_DONE: begin
                    if (verify_bad) save_error <= 1'b1;
                    else begin
                        save_error <= 1'b0;
                        last_b <= ~last_b; last_seq <= last_seq + 16'd1;
                    end
                end
                default: ;
            endcase
        end
    end
endmodule
