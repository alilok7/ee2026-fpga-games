## SEQUENTIAL CIRCUITS - II

©COPYRIGHT CHUA DINGJUAN. ALL RIGHTS RESERVED.

## Counters

Asynchronous : Circuit elements do not get the clock input simultaneously Synchronous Counters: Circuit elements get the clock input simultaneously

## Ripple Counter (Asynchronous):

<!-- image -->

## Counters : Mod - X

- o Each FF successively halves the input clock frequency
- o The 4-bit counter counts from 0000 (0) → 1111(15)
- 16 distinct count states ⇒called a mod-16 counter
- o N x FFs connected this way will have 2 N states ⇒mod-2 N

How to obtain a counter with mod-X &lt; 2 N ?

1. Use FFs with CLR functions
2. Assume counter starts from 0
3. Identify FFs that will be in HIGH state when count = X
4. Feed those FFs outputs to a NAND gate
5. Connect NAND gate output to asynchronous CLR

| CLK   | CLR   | J   | K   | Q +   |
|-------|-------|-----|-----|-------|
| X     | L     | X   | X   | L     |
| ↓     | H     | L   | L   | Q     |
| ↓     | H     | L   | H   | L     |
| ↓     | H     | H   | L   | H     |
| ↓     | H     | H   | H   | Q     |

## Count Down Ripple Counter…

To count down : connect complements of FF outputs to clock inputs of succeeding FFs

CBA

<!-- image -->

<!-- image -->

## t pd  limiting frequency

- o Ripple counters are very easy to implement
- o But they have a major drawback they cannot operate beyond a limiting frequency
- o Due to propagation delays of the FFs in the chain adding up:
1. Clock input FF 1 : t 0
2. Clock input FF 2 : t 0 + ∆tpd
3. Clock input FF 3 : t 0 + 2*∆tpd
4. Clock input FF N : t 0 + (n - 1) * ∆tpd
- the nth FF changes state at n* ∆t after t 0

<!-- image -->

<!-- image -->

## For proper operation:

Tclock ≥ ( n*∆tpd )

fmax ≤ 1 / ( n*∆tpd )

<!-- image -->

## Synchronous (Parallel) Counters

## Mod-16 Synchronous Parallel Counter :

<!-- image -->

- o Since all FFs are triggered simultaneously by the clock, this counter can operate at higher frequencies.
- o Critical Path Delay = ∆tpd (FF) + ∆tpd (AND)
- o Operating frequency is irrespective of the number of FFs
- o Disadvantages? - more gates

B toggles when A = 1

C toggles when AB = 1

D toggles when ABC = 1

<!-- image -->

|   Count | D   | C   | B   | A   |
|---------|-----|-----|-----|-----|
|       0 | 0   | 0   | 0   | 0   |
|       1 | 0   | 0   | 0   | 1   |
|       2 | 0   | 0   | 1   | 0   |
|       3 | 0   | 0   | 1   | 1   |
|       4 | 0   | 1   | 0   | 0   |
|       5 | 0   | 1   | 0   | 1   |
|       6 | 0   | 1   | 1   | 0   |
|       7 | 0   | 1   | 1   | 1   |
|       8 | 1   | 0   | 0   | 0   |
|       9 | 1   | 0   | 0   | 1   |
|      10 | 1   | 0   | 1   | 0   |
|      11 | 1   | 0   | 1   | 1   |
|      12 | 1   | 1   | 0   | 0   |
|      13 | 1   | 1   | 0   | 1   |
|      14 | 1   | 1   | 1   | 0   |
|      15 | 1   | 1   | 1   | 1   |
|       0 | 0   | 0   | 0   | 0   |
|         | c   | o   | n   | t   |

'1'

'1'

J

A

CLK

\_

K A

J B

CLK

\_

K B

J C

CLK

\_

K C

J D

CLK

\_

K D

0 1 0 1 0 1 0 1 0 1 0 1

t PD,FF

0 0 1 1 0 0 1 1 0 0 1 1

t PD,FF + t PD,AND

0 0 0 0 1 1 1 1 0 0 0 0

0 0 0 0 0 0 0 0 1 1 1 1

Page 9

0 1 2 3 4 5 6 7 8 9 10 11

## Counting Down…

What about a count down mod-16 counter ?

<!-- image -->

B toggles when

C toggles when

D toggles when

|   Count | D   | C   | B   | A   |
|---------|-----|-----|-----|-----|
|       0 | 0   | 0   | 0   | 0   |
|       1 | 0   | 0   | 0   | 1   |
|       2 | 0   | 0   | 1   | 0   |
|       3 | 0   | 0   | 1   | 1   |
|       4 | 0   | 1   | 0   | 0   |
|       5 | 0   | 1   | 0   | 1   |
|       6 | 0   | 1   | 1   | 0   |
|       7 | 0   | 1   | 1   | 1   |
|       8 | 1   | 0   | 0   | 0   |
|       9 | 1   | 0   | 0   | 1   |
|      10 | 1   | 0   | 1   | 0   |
|      11 | 1   | 0   | 1   | 1   |
|      12 | 1   | 1   | 0   | 0   |
|      13 | 1   | 1   | 0   | 1   |
|      14 | 1   | 1   | 1   | 0   |
|      15 | 1   | 1   | 1   | 1   |
|       0 | 0   | 0   | 0   | 0   |
|         | c   | o   | n   | t   |

## Up/Down Synchronous Counters

<!-- image -->

<!-- formula-not-decoded -->

<!-- formula-not-decoded -->

## Example (D Flip-Flops)

## Mod-8 Count-Up Counter Using D-FFs:

<!-- image -->

| CLK   |   D |   Q + |
|-------|-----|-------|
| ↓     |   0 |     0 |
| ↓     |   1 |     1 |

| Count   | C   | B   | A   |
|---------|-----|-----|-----|
| 0       | 0   | 0   | 0   |
| 1       | 0   | 0   | 1   |
| 2       | 0   | 1   | 0   |
| 3       | 0   | 1   | 1   |
| 4       | 1   | 0   | 0   |
| 5       | 1   | 0   | 1   |
| 6       | 1   | 1   | 0   |
| 7       | 1   | 1   | 1   |
| 0       | 0   | 0   | 0   |
| c       | o   | n   | t   |

CLK D Q +

↑

0

0

↑

1

<!-- image -->

## Synchronous Counters (DFF)

<!-- image -->

## Counter Animation - 1

<!-- image -->

## Counter Animation - 2

<!-- image -->

## Counter Animation - 3

<!-- image -->

## Counter Animation - 4

<!-- image -->

## Verilog for Synchronous Counters

## Mod-8 Counter in Verilog

```
module mod8( input clk, output reg [2:0] q); wire [2:0] d; reg [2:0] q = 0; always @ (posedge clk) begin q <= d; end assign d[0] = ~q[0]; assign d[1] = q[0] ^ q[1]; assign d[2] = q[0]&q[1]&~q[2] | ~q[1]&q[2] | ~q[0]&q[2]; endmodule Dc = ABC+BC +ĀC DB = AB + AB = A ⊕ B DA =A D D A A -O>CLK A QB D B CLK -B Dc Qc D C CLK č
```

## Mod-8 Counter in Verilog

<!-- image -->

```
module mod8( input clk, output reg [2:0] q); initial begin q = 3'b000; end always @ (posedge clk) begin q <= q + 1; end endmodule 000 111 001 110 010 101 011 100
```

<!-- image -->

```
initial begin q = 3′b000; end always @ (posedge clk) begin <= q + 1; q
```

<!-- image -->

Page 58

<!-- image -->

## Critical Paths in Vivado?

## You can find the critical paths in your design via timing reports:

- 1) Navigate to Implemented Design → Report Timing Summary.
- 2) Key metrics: WNS (Worst Negative Slack), WHS (Worst Hold Slack), TNS (Total Negative Slack).

Timing slack is the difference between the time your signal arrives at a register (reg), versus the time it needs to arrive to meet timing requirements. (Slack = Required Time - Arrival Time)

- o Positive Slack: Signal arrives early (meets timing).
- o Negative Slack: Signal arrives late (violates timing, needs fixing).

<!-- image -->

<!-- image -->

eg. If a signal needs to arrive by 10ns but arrives at 9ns, slack is +1ns (good). If it arrives at 11ns, slack is -1ns (bad).

<!-- image -->

```
Setup Worst Negative Slack (WNS): 7.777 ns Total Negative Slack (TNS): 0.000 ns Number of Failing Endpoints: 0 Total Number of Endpoints: 3 All user specified timing constraints are met.
```

## What if #bits = 32?

<!-- image -->

```
clk initial begin q = 3′b000; end always @ (posedge clk) begin q 7 q + 1; end
```

<!-- image -->

## What happens if #bits increase?

<!-- image -->

## Setup

Worst Negative Slack (WNS): 6.861 ns

Total Negative Slack (TNS):

0.000 ns

Number of Failing Endpoints: 0

Total Number of Endpoints:

32

All user specified timing constraints are met.

## Mod-5 Counter in Verilog

```
module mod5( input clk, clr, output reg [2:0] q); initial begin q = 3'b000; end always @ (posedge clk, posedge clr) begin end
```

<!-- image -->

```
q <= (q == 3'b100) ? 3'b000 : q + 1; endmodule 000 010 011 100 001
```

## Last Slide!

- o Incrementing / Counting is easy in Verilog! COUNT &lt;= COUNT + 1;
- oWhat about the following features?
- o Positive / Negative clock edge triggered
- o Counting Up / Counting Down
- omod-X Counters
- o Synchronous / Asynchronous Resets
- o Synchronous / Asynchronous Presets

```
module counter(input clear, clk, output reg [3:0] q); always @ (posedge clk) begin q <= clear ? (q - 1) : 4'b0000; end endmodule oWhat counter does this code describe? 1. Positive/Negative Edge clock triggered? 2. Asynchronous / Synchronous Clear? 3. Count Up / Down Counter ?
```