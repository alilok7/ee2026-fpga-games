`timescale 1ns / 1ps
//=============================================================================
// flash_model.v : behavioural SPI NOR flash for the flash_ctrl testbench
//-----------------------------------------------------------------------------
// Owner : Student D
// Mode 0 (sample MOSI on rising SCK, drive MISO after falling SCK).
// Commands: 9F RDID (01 02 15), 05 RDSR (bit0 WIP, bit1 WEL), 06 WREN,
//           03 READ, D8 64 KB sector erase, 02 page program.
// Only the two save sectors (0x3E and 0x3F) are stored (256 bytes each);
// everything else reads 0xFF. Program can only clear bits (real NOR flash),
// so programming without an erase first is caught by the read-back.
// Erase / program need WEL (set by WREN) and keep WIP busy for a while.
// power_cut(): aborts a busy erase/program leaving the sector half done.
//=============================================================================
module flash_model #(
    parameter ERASE_CLKS = 3000,
    parameter PROG_CLKS  = 800
) (
    input  wire clk,                  // only to time WIP
    input  wire cs_n,
    input  wire sck,
    input  wire mosi,
    output reg  miso,
    input  wire present               // 0 = no flash on the bus (MISO stuck low)
);
    reg [7:0] sa [0:255];             // sector 0x3E, offsets 0..255
    reg [7:0] sb [0:255];             // sector 0x3F
    reg       wel = 0;
    integer   busy = 0;
    integer   pending_kind = 0;       // 1 erase, 2 program
    reg [7:0] pending_sec;
    reg [7:0] pbuf [0:255];
    integer   pcount, pdone_n, paddr_lo;   // pcount counts bytes now, pdone_n = latched count

    integer k;
    initial begin
        for (k = 0; k < 256; k = k + 1) begin sa[k] = 8'hFF; sb[k] = 8'hFF; end
        miso = 1'b0;
    end

    always @(posedge clk) if (busy > 0) begin
        busy = busy - 1;
        if (busy == 0) finish_op;
    end

    task finish_op;
        integer i;
        begin
            if (pending_kind == 1) begin
                for (i = 0; i < 256; i = i + 1)
                    if (pending_sec == 8'h3E) sa[i] = 8'hFF; else if (pending_sec == 8'h3F) sb[i] = 8'hFF;
            end else if (pending_kind == 2) begin
                for (i = 0; i < pdone_n; i = i + 1)
                    if (pending_sec == 8'h3E) sa[(paddr_lo + i) & 255] = sa[(paddr_lo + i) & 255] & pbuf[i];
                    else if (pending_sec == 8'h3F) sb[(paddr_lo + i) & 255] = sb[(paddr_lo + i) & 255] & pbuf[i];
            end
            pending_kind = 0;
            wel = 0;
        end
    endtask

    // power loss in the middle of an erase / program: half of the work done
    task power_cut;
        integer i;
        begin
            if (pending_kind == 1) begin
                for (i = 0; i < 128; i = i + 1)
                    if (pending_sec == 8'h3E) sa[i] = 8'hFF; else sb[i] = 8'hFF;
            end else if (pending_kind == 2) begin
                for (i = 0; i < pdone_n / 2; i = i + 1)
                    if (pending_sec == 8'h3E) sa[(paddr_lo + i) & 255] = sa[(paddr_lo + i) & 255] & pbuf[i];
                    else sb[(paddr_lo + i) & 255] = sb[(paddr_lo + i) & 255] & pbuf[i];
            end
            pending_kind = 0; busy = 0; wel = 0;
        end
    endtask

    function [7:0] rd_byte(input [23:0] a);
        rd_byte = (a[23:16] == 8'h3E && a[15:8] == 0) ? sa[a[7:0]] :
                  (a[23:16] == 8'h3F && a[15:8] == 0) ? sb[a[7:0]] : 8'hFF;
    endfunction

    // ---- SPI slave -----------------------------------------------------------
    reg [7:0]  in_sh, out_sh, cmd;
    integer    bitn, byten;
    reg [23:0] addr;

    always @(negedge cs_n) begin
        bitn = 0; byten = 0; cmd = 8'h00; out_sh = 8'h00; pcount = 0;
    end

    always @(posedge cs_n) begin                   // command ends
        if (busy == 0 && wel) begin
            if (cmd == 8'hD8 && byten >= 4) begin
                pending_kind = 1; pending_sec = addr[23:16]; busy = ERASE_CLKS;
            end else if (cmd == 8'h02 && byten >= 5) begin
                pending_kind = 2; pending_sec = addr[23:16]; paddr_lo = addr[7:0]; pdone_n = pcount; busy = PROG_CLKS;
            end
        end
    end

    always @(posedge sck) if (!cs_n) begin
        in_sh = {in_sh[6:0], mosi};
        bitn = bitn + 1;
        if (bitn == 8) begin
            bitn = 0;
            if (byten == 0) begin
                cmd = in_sh;
                if (cmd == 8'h06 && busy == 0) wel = 1;
            end else if (byten <= 3 && (cmd == 8'h03 || cmd == 8'hD8 || cmd == 8'h02)) begin
                addr = {addr[15:0], in_sh};
            end else if (cmd == 8'h02 && byten > 3) begin
                pbuf[pcount] = in_sh; pcount = pcount + 1;
            end
            byten = byten + 1;
            // next byte to send
            case (cmd)
                8'h9F:   out_sh = (byten == 1) ? 8'h01 : (byten == 2) ? 8'h02 : 8'h15;
                8'h05:   out_sh = {6'd0, wel, (busy > 0)};
                8'h03:   if (byten >= 4) begin out_sh = rd_byte(addr); addr = addr + 1; end
                default: out_sh = 8'h00;
            endcase
        end
    end

    always @(negedge sck) if (!cs_n) begin
        miso <= present ? out_sh[7 - bitn] : 1'b0;
    end
endmodule
