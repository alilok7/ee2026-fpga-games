`timescale 1ns / 1ps
//=============================================================================
// tb_spi_byte.v : one SPI byte, mode 0 - loopback and timing checks
//-----------------------------------------------------------------------------
// MOSI is wired back to MISO (loopback), so the byte received must equal the
// byte sent. A small "slave" samples MOSI on every rising SCK edge, like the
// flash does. Checks: 8 SCK pulses, the slave sees the byte MSB first, MOSI
// never changes while SCK is high (mode 0), done is one clock, busy drops
// with done, SCK idles low, a start while busy is ignored, 65 clocks / byte.
//=============================================================================
module tb_spi_byte;
    reg clk = 0;
    always #5 clk = ~clk;                // 100 MHz
    reg rst = 1, start = 0;
    reg [7:0] tx = 0;
    wire [7:0] rx;
    wire done, busy, sck, mosi;
    spi_byte dut (.clk(clk), .rst(rst), .start(start), .tx(tx), .rx(rx), .done(done),
                  .busy(busy), .sck(sck), .mosi(mosi), .miso(mosi));   // loopback

    integer errors = 0;
    task check(input cond, input [8*64-1:0] msg);
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s", msg); errors = errors + 1; end
        end
    endtask

    // ---- the "slave": samples MOSI on the rising SCK edge ----
    reg [7:0] slave = 0;
    integer edges = 0, mosi_bad = 0, done_len = 0;
    always @(posedge sck) begin slave <= {slave[6:0], mosi}; edges = edges + 1; end
    always @(mosi) if (sck === 1'b1) mosi_bad = mosi_bad + 1;      // mode 0: only while SCK low
    always @(posedge clk) if (done) done_len = done_len + 1;

    integer t0, t1;
    task send(input [7:0] b);
        begin
            edges = 0; done_len = 0;
            @(posedge clk) begin start <= 1; tx <= b; end
            @(posedge clk) start <= 0;
            t0 = $time;
            // a second start while busy must be ignored
            @(posedge clk) begin start <= 1; tx <= 8'h00; end
            @(posedge clk) start <= 0;
            @(posedge done); t1 = $time;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst <= 0;
        repeat (4) @(posedge clk);
        check(sck == 0 && !busy, "after reset: SCK low, not busy");
        send(8'hA5);
        check(rx == 8'hA5,    "loopback: sent A5, received A5");
        check(slave == 8'hA5, "slave sampled A5 on the rising edges (MSB first)");
        check(edges == 8,     "exactly 8 SCK pulses");
        check(done_len == 1,  "done is a 1-clock pulse");
        check(!busy && sck == 0, "busy low and SCK low after the byte");
        check((t1 - t0) / 10 == 64, "64 clocks from start to done (8 bits x 8 clocks)");
        send(8'h3C);
        check(rx == 8'h3C && slave == 8'h3C && edges == 8, "second byte 3C (start while busy was ignored)");
        send(8'hFF);
        check(rx == 8'hFF, "byte FF");
        send(8'h00);
        check(rx == 8'h00, "byte 00");
        check(mosi_bad == 0, "MOSI never changed while SCK was high (mode 0)");
        if (errors == 0) $display("PASS tb_spi_byte: all checks");
        else             $display("FAIL tb_spi_byte: %0d errors", errors);
        $finish;
    end
endmodule
