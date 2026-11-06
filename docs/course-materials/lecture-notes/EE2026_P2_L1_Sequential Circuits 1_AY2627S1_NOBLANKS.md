## EE2026 Digital Design

SEQUENTIAL LOGIC : FLIP-FLOPS

Chua Dingjuan elechuad@nus.edu.sg

## Module Lecture Structure

## Contents

## Part 1 (Combinational Logic)

- Number systems + Verilog
- Boolean Algebra and logic gates + Verilog
- Gate-level design and minimization + Verilog
- Combinational logic blocks and design + Verilog

## Part 2 (Sequential Logic)

- Introduction to Sequential Logic - Flip-flops + Verilog
- Counters + Verilog
- Combining combinational/sequential building blocks + Verilog
- Finite State Machine Design + Modeling of FSMs in Verilog

## SEQUENTIAL CIRCUITS - I

©COPYRIGHT CHUA DINGJUAN. ALL RIGHTS RESERVED.

## Design a circuit to do this &gt;&gt;

When the button is pushed :

- 1) Turn On the light if it is Off
- 2) Turn Off the light if it is On

<!-- image -->

<!-- image -->

0

## What is missing?

- 1) Remembering the previous state of the bulb MEMORY
- 2) Responding to an input EVENT (cf. input value)

<!-- image -->

<!-- image -->

## Sequential Logic Circuits?

## Combinational Logic Circuits:

- o Outputs depend on current inputs

## Sequential Logic Circuits:

<!-- image -->

- o Outputs depend on current and previous inputs Memory!
- o Requires separation of previous, current, future : states
- o 2 Types of sequential circuits:

| Synchronous                                                            | Asynchronous                           |
|------------------------------------------------------------------------|----------------------------------------|
| Clocked: need a clock input                                            | Unclocked                              |
| Responds to inputs at discrete time instants governed by a clock input | Responds whenever input signals change |

<!-- image -->

The simplest memory element has two stable states :

Flip-Flop (FF)  it can store 1 bit of information

Most basic FF : Set-Reset (SR) Flip-flop / Latch

Implemented with NOR / NAND gates

<!-- image -->

| S                     | R                     | Output                | Q+                    |
|-----------------------|-----------------------|-----------------------|-----------------------|
| 0                     | 0                     |                       |                       |
| 0                     | 1                     |                       |                       |
| 1                     | 0                     |                       |                       |
| 1                     | 1                     |                       |                       |
| 0 0 is the rest state | 0 0 is the rest state | 0 0 is the rest state | 0 0 is the rest state |

## SR Flip-flop (FF)

|   S |   R | Output Q   |
|-----|-----|------------|
|   0 |   0 |            |
|   0 |   1 | Q = 0      |
|   1 |   0 |            |
|   1 |   1 |            |

|   A |   B |   NOR |
|-----|-----|-------|
|   0 |   0 |     1 |
|   0 |   1 |     0 |
|   1 |   0 |     0 |
|   1 |   1 |     0 |

<!-- image -->

<!-- image -->

## SR Flip-flop (FF)

|   S |   R | Output Q   |
|-----|-----|------------|
|   0 |   0 |            |
|   0 |   1 | Q = 0      |
|   1 |   0 | Q = 1      |
|   1 |   1 |            |

|   A |   B |   NOR |
|-----|-----|-------|
|   0 |   0 |     1 |
|   0 |   1 |     0 |
|   1 |   0 |     0 |
|   1 |   1 |     0 |

<!-- image -->

<!-- image -->

## SR Flip-flop (FF)

|   S |   R | Output Q   |
|-----|-----|------------|
|   0 |   0 |            |
|   0 |   1 | Q = 0      |
|   1 |   0 | Q = 1      |
|   1 |   1 |            |

|   A |   B |   NOR |
|-----|-----|-------|
|   0 |   0 |     1 |
|   0 |   1 |     0 |
|   1 |   0 |     0 |
|   1 |   1 |     0 |

<!-- image -->

<!-- image -->

## SR Flip-flop (FF)

|   S |   R | Output Q      |
|-----|-----|---------------|
|   0 |   0 | Hold, Q + = Q |
|   0 |   1 | Q = 0         |
|   1 |   0 | Q = 1         |
|   1 |   1 |               |

|   A |   B |   NOR |
|-----|-----|-------|
|   0 |   0 |     1 |
|   0 |   1 |     0 |
|   1 |   0 |     0 |
|   1 |   1 |     0 |

<!-- image -->

<!-- image -->

## SR Flip-flop (FF)

|   S | R   | Output Q   |
|-----|-----|------------|
|   0 | 0   | Hold       |
|   0 | Q = | 1 0        |
|   1 | 0   | Q = 1      |
|   1 | 1   | Invalid    |

|   A |   B |   NOR |
|-----|-----|-------|
|   0 |   0 |     1 |
|   0 |   1 |     0 |
|   1 |   0 |     0 |
|   1 |   1 |     0 |

<!-- image -->

<!-- image -->

<!-- image -->

The simplest memory element has two stable states :

Flip-Flop (FF)  it can store 1 bit of information

Most basic FF : Set-Reset (SR) Flip-flop / Latch

Implemented with NOR / NAND gates

<!-- image -->

| S                     | R                     | Output                | Q+                    |
|-----------------------|-----------------------|-----------------------|-----------------------|
| 0 0                   | Hold                  | Q                     |                       |
| 1                     | Clear                 | 0                     | 0                     |
| 1 0                   | Set                   | 1                     |                       |
| 1                     | Invalid               | Invalid               | 1                     |
| 0 0 is the rest state | 0 0 is the rest state | 0 0 is the rest state | 0 0 is the rest state |

<!-- image -->

## SR Flip-flop (FF)

- o FF can record and store transient events.
- o Switching is not instantaneous propagation delays

<!-- image -->

| S                     | R                     | Output                |
|-----------------------|-----------------------|-----------------------|
| 0                     | 0 Hold                |                       |
| 0                     | 1 Clear               |                       |
| 1                     | 0 Set                 |                       |
| 1                     | 1 Invalid             |                       |
| 0 0 is the rest state | 0 0 is the rest state | 0 0 is the rest state |

<!-- formula-not-decoded -->

2) If S→ while R = 0 ⇒ Q = 1, Q = 0, i.e., the event (S going high) is recorded and stored as Q = 1.

## Assume R=0 :

<!-- image -->

## A Simple Application…

<!-- image -->

<!-- image -->

<!-- image -->

<!-- image -->

<!-- image -->

- (a) Output of typical mechanical switch
- (b) Debounced switch output signal
- oMechanical switches bounce before settling down which may cause problems as inputs.
- o Switch debouncing is a common use of S-R FFs.

<!-- image -->

| S                     | R                     | Output                |
|-----------------------|-----------------------|-----------------------|
| 0                     | 0 Hold                |                       |
| 0                     | 1 Clear               |                       |
| 1                     | 0 Set                 |                       |
| 1                     | Invalid               | 1                     |
| 0 0 is the rest state | 0 0 is the rest state | 0 0 is the rest state |

## A Simple Application…

<!-- image -->

| S                     | R                     | Output                |
|-----------------------|-----------------------|-----------------------|
| 0                     | 0 Hold                |                       |
| 0                     | 1 Clear               |                       |
| 1                     | 0 Set                 |                       |
| 1                     | 1 Invalid             |                       |
| 0 0 is the rest state | 0 0 is the rest state | 0 0 is the rest state |

<!-- image -->

<!-- image -->

## JK Flip Flop

<!-- image -->

The JK FF is based on SR with 2 improvements : clock &amp; toggle

condensed characteristic table

<!-- image -->

## The JK FF is a synchronous circuit:

characteristic table

| CLK   |   J |   K |   Q |   Q + |
|-------|-----|-----|-----|-------|
| ↑     |   0 |   0 |   0 |     0 |
| ↑     |   0 |   0 |   1 |     1 |
| ↑     |   0 |   1 |   0 |     0 |
| ↑     |   0 |   1 |   1 |     0 |
| ↑     |   1 |   0 |   0 |     1 |
| ↑     |   1 |   0 |   1 |     1 |
| ↑     |   1 |   1 |   0 |     1 |
| ↑     |   1 |   1 |   1 |     0 |

- o Clock input is a controlling input. It specifies when circuit read inputs / change outputs.
- o Synchronous circuits respond only at the active clock edges i.e., LOW→HIGH, HIGH→LOW transitions rising
- o At any other time, changing inputs have no effect on the output.

<!-- image -->

<!-- image -->

<!-- image -->



## Respond @ Active Clock Edges

<!-- image -->

- o When inputs don't change FF outputs don't change.
- o If inputs change FF output changes state only at active clock edge.

## FF Timing Parameters

<!-- image -->

t setup : minimum time before the active clock edge by which FF inputs must be stable.

t hold : minimum time inputs must be stable after active clock edge

t pHL :

t pLH :

time taken for FF output to change state from High to Low.

time taken for FF output to change state from Low to High.

What happens if inputs change state right at the active clock transition? Answer: output is unpredictable

Thus, input changes must meet required setup &amp; hold times of device == Operating Speed of device

[http://www.ti.com/product/SN74LS107A](http://www.ti.com/product/SN74LS107A)

<!-- image -->

## So how fast can this device run?

<!-- image -->

- 1) The clock frequency on the Basys 3 development board is 100MHz! Will the 74107 chip work at this clock speed?

No! tpd ranges from 16ns to 40ns, exceeding one clock period.

- 2) Assuming that a flip-flop only has tpd = 20ns, what is the maximum clock speed it can run at?

fclk, max = 1/20ns = 50MHz This is a theoretical limit. In

```
tclk, min = 20ns, practice, it would be much lower!
```

## Commercially Available JK FFs

74'107 with asynchronous clear

<!-- image -->

74'109 with direct set &amp; direct clear

<!-- image -->

<!-- image -->

| CLK   | CLR   | J   | K   | Q +   |
|-------|-------|-----|-----|-------|
| X     | L     | X   | X   | L     |
| ↓     | H     | L   | L   | Q     |
| ↓     | H     | L   | H   | L     |
| ↓     | H     | H   | L   | H     |
| ↓     | H     | H   | H   |       |

| CLK   | PR   | CLR   | J   | K   | Q +         |
|-------|------|-------|-----|-----|-------------|
| X     | L    | H     | X   | X   | H           |
| X     | H    | L     | X   | X   | L           |
| X     | L    | L     | X   | X   | not allowed |
| ↓     | H    | H     | L   | L   | Q           |
| ↓     | H    | H     | L   | H   | L           |
| ↓     | H    | H     | H   | L   | H           |
| ↓     | H    | H     | H   | H   | �Q          |

## Other Flip-Flops…

<!-- image -->

<!-- image -->

Since T Flip-flops are easy to construct from other FFs, they are not often used commercially.

## Verilog for Sequential Logic

## In previous labs and lectures…

- o module
- owire (net) , reg
- o Logic gates (~, &amp;, |, ^ )
- o Operators : +, -, ? :, { }
- o Dataflow
- o Continuous Assignments : assign
- o Behavioural
- o Procedural Assignments : always @ (*)
- o Blocking (=) and Non-Blocking (&lt;=)
- o Structural modeling

## Verilog Time! - D-FF

<!-- image -->

## Verilog Time! - D-FF

<!-- image -->

<!-- image -->

always @ (posedge \_\_) ↑

↑

always @ (negedge \_\_)

```
module dff ( input d, clk, output reg q);
```

Anything assigned in an always block must be declared as type reg

always @ (posedge clk)

Conceptually, the always block runs once when sensitivity list changes value. posedge captures the 0 1 change in clk.

If posedge / negedge is used in the sensitivity list, ALL signals must be used with posedge / negedge.

begin

q = d;

end

endmodule

## Blocking &amp; Non-blocking

Verilog supports two types of assignments within

<!-- image -->

- = blocking assignment
- o Sequential evaluation
- o Immediate assignment

```
always @ (*) begin x = y; z = ~x; end 1) Evaluate y, assign result to x 2) Evaluate ~x, assign result to z
```

| Behaviour         |   x |   y |   z |
|-------------------|-----|-----|-----|
| Initial Condition |   0 |   0 |   1 |
| y changes         |   0 |   1 |   1 |
| x = y             |   1 |   1 |   1 |
| z = ~x            |   1 |   1 |   0 |

## always

<!-- image -->

- &lt;= non-blocking asignment
- o Sequential evaluation
- o Deferred assignment

```
always @ (*) begin x <= y; z <= ~x; end 1) Evaluate y, defer assignment 2) Evaluate ~x, defer assignment 3) Assign x and z with new values
```

| Behaviour         |   x |   y |   z | Deferred   |
|-------------------|-----|-----|-----|------------|
| Initial Condition |   0 |   0 |   1 |            |
| y changes         |   0 |   1 |   1 |            |
| x <= y            |   0 |   1 |   1 | x <= 1     |
| z <= ~x           |   0 |   1 |   1 | z <= 1     |
| Assignment        |   1 |   1 |   1 | Page 25    |

## Example

```
module example(input [2:0] A, output reg [2:0] V, Z, W);
```

always @ (A) begin

```
V = A | 3'b001; Z <= V | 3'b100; W = Z; 1 2 3
```

end endmodule

| Behaviour         |   A |   V |   Z |   W | Deferred   |
|-------------------|-----|-----|-----|-----|------------|
| Initial Condition | 000 | 001 | 101 | 000 |            |
| A changes         | 010 | 001 | 101 | 000 |            |
| Stmt 1            | 010 | 011 | 101 | 000 |            |
| Stmt 2            | 010 | 011 | 101 | 000 | Z<=111     |
| Stmt 3            | 010 | 011 | 101 | 101 |            |
| Assignment        | 010 | 011 | 111 | 101 |            |

## An event occurs on A at simulation t :

- o Stmt 1 is executed and V is assigned immediately
- o Stmt 2 is executed and defer assignment to Z
- o Stmt 3 is executed using old value of Z.
- o Z is assigned.

## Verilog Time! - D-FF

```
CLK D Q+ ↑ 0 0 ↑ 1 1 D Q module dff ( input d, clk, output reg q); always @ (posedge __) always @ (negedge __) always @ (posedge clk) begin end ↑ ↑ q <= d; or q = d; Both are correct!
```

endmodule

## Two D Flip-Flops…

<!-- image -->

| Behaviour FFs CLK          | D      | q1 q2 0 0 Q +   |
|----------------------------|--------|-----------------|
| Reset st ↑                 | edge 0 | 0               |
| @ 1 rising @ 2 nd rising ↑ | edge 1 | 1 0 1 1 1       |

<!-- image -->

Assume initial outputs of FFs is '0' and D1 is '1'.

| Behaviour              |   Q1 |   Q2 |
|------------------------|------|------|
|                        |    0 |    0 |
| After 1 st rising edge |    1 |    0 |
| After 2 nd rising edge |    1 |    1 |

## Two D Flip-Flops… and Verilog!

<!-- image -->

| Behaviour              |   Q1 |   Q2 |
|------------------------|------|------|
|                        |    0 |    0 |
| After 1 st rising edge |    1 |    0 |
| After 2 nd rising edge |    1 |    1 |

```
always @ (posedge clk) begin q1 = d1; q2 = q1;
```

## end

| Behaviour              |   Q1 |   Q2 |
|------------------------|------|------|
|                        |    0 |    0 |
| After 1 st rising edge |    1 |    1 |
| After 2 nd rising edge |    1 |    1 |

```
always @ (posedge clk) begin q1 <= d1; q2 <= q1;
```

## end

| Behaviour              |   Q1 |   Q2 |
|------------------------|------|------|
|                        |    0 |    0 |
| After 1 st rising edge |    1 |    0 |
| After 2 nd rising edge |    1 |    1 |

## Discussion Example

```
always @ (posedge clk) begin q1 = d1; q2 = q1; end
```

<!-- image -->

```
always @ (posedge clk) begin q1 <= d1; q2 <= q1;
```

end

<!-- image -->

## Discussion Example

module ff(input clk,

```
d1,d2, output reg q1); always @ (posedge clk) begin q1 <= d1; end always @ (posedge clk) begin q1 <= d2; end endmodule
```

<!-- image -->

<!-- image -->

[DRC MDRV-1] Multiple Driver Nets: Net

q1\_OBUF has multiple drivers: q1\_reg/Q, and q1\_reg\_\_0/Q.

## Discussion Example

```
module ff(input clk, d1,d2, output reg q1); always @ (posedge clk) begin q1 <= d1; end always @ (posedge clk) begin q2 <= d2; end
```

endmodule

<!-- image -->

## Discussion Example

```
module ff(input clk, d1,d2, output reg q1); always @ (posedge clk) begin x = ~d1; q1 <= x; end
```

endmodule

<!-- image -->

## Basic Guidelines…

#1: When modeling sequential logic, use nonblocking assignments.

#2: When modeling simple combinational logic, use continuous assignments (assign).

#3: When modeling complex combinational logic, use blocking assignments in an always block.

#3: When modeling both sequential and combinational logic within the same always block, use nonblocking assignments.

#4: Do not mix blocking and nonblocking assignments in the same always block.

#5: Do not make assignments to the same variable from more than one always block.

## Discussion Example

Given the circuit diagram below, complete the timing diagram below by filling in Q and Q. Assume that the initial value of Q is '0' and include all propagation delays.

<!-- image -->

## Summary

- o SR Flip Flop &amp; Applications
- o JK Flip Flop
- o FF Timing Parameters
- o Commercial JK Flip Flops
- o Verilog description of D Flip Flop
- o Blocking and Non-blocking procedural assignments
- oModeling of multiple D Flip-flops

## FFs on Artix-7 FPGA

## D Flip-Flop… in Vivado?

## Verilog Code

```
module dff1 (input d,clk, output reg q); always @ (posedge clk) begin q <= d; end endmodule
```

## Vivado RTL Schematic

<!-- image -->

## Vivado Synthesized Schematic

<!-- image -->

D Flip-Flop with Clock Enable and Synchronous Reset

## FDXX Primitives in 7series FPGA

D Flip-Flop with Clock Enable and Asynchronous Clear D Flip-Flop with Clock Enable and Asynchronous Preset

<!-- image -->

<!-- image -->

D Flip-Flop with Clock Enable and Asynchronous Clear D Flip-Flop with Clock Enable and Asynchronous Preset

<!-- image -->

<!-- image -->

## Try this!

assign is used for

In continuous assignments, the code is executed

The code in the always block is executed when ο

always is used for

&lt;= is a

endmodule Is always paired with

The sensitivity list follows the

Code in always block is executed

<!-- image -->