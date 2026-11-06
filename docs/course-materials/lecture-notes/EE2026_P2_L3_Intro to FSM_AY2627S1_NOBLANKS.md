## FSM 1 : Intro to Finite State Machines

©COPYRIGHT CHUA DINGJUAN. ALL RIGHTS RESERVED.

## What is a FSM?

- o FSM : Finite State Machine
- o Synchronous Machine with "states" of operation
- o At each active clock edge, combinational logic computes outputs and next state,

as a function of inputs and present state

<!-- image -->

## Mealy and Moore

## Moore vs Mealy FSMs : Different Output Generation

- o Mealy machine: output is a function of a present state &amp; inputs.
- o Moore machine: output is a function of a present state only.

<!-- image -->

<!-- image -->

## Structure

## State Memory

- o set of n FFs store current state of machine; up to 2 n states.
- o FFs can be J-K or D, but D FFs simpler (1 input vs. 2 inputs for J-K FFs)

## Next State Logic

- o combinational circuit which decides the next state of the machine based on current state and inputs:

```
Next state = f (inputs, current state)
```

## Output logic

- o combinational circuit which creates the output Moore : outputs depend on current state outputs = g (current state) Mealy : outputs depend on the current state &amp; inputs outputs = g (inputs, current state)

## Traffic Problem…

<!-- image -->

At a busy intersection on campus…

Students from the Law faculty are burying their heads in their books and are not looking where they are going.

Students from the Business faculty are occupied on their phones and aren't looking at where they're going either….

<!-- image -->

## Traffic Problem…

<!-- image -->

<!-- image -->

## Design a FSM to control the traffic lights!

- 1) Sensors T B and T L are TRUE when students are present. False otherwise.
- 2) Control traffic lights L L , L B to be green, yellow, red.
- 3) Reset to Green on Law Ave and Red on Business St.

<!-- image -->

L B

## Every 5 sec, check the traffic and decide what to do!

- If the lights on Business St. are green and there's no traffic, the lights turn yellow for 5 secs. After that, they turn red and Law Ave. lights turn green.
- So on, so forth.
- If there is traffic, lights do not change.

T B

Street A SYSTEMATIC PROCEDURE TO GO FROM

<!-- image -->

IDEA  IMPLEMENTATION

## Step 1 : State Transition Diagram

- o Block Diagram of Desired System
- o Design State Transition Diagram to represent FSM

<!-- image -->

<!-- image -->

<!-- image -->

## Moore State Transition Diagrams

<!-- image -->

- o Circles represent states.
* Each state specifies values for all outputs (Moore)
- o Arcs represents transitions between states.
* Labels  input that triggers the transition.
* Transitions take place on the active edge of the clock.
- o Arc from outer space indicates initial state upon reset
- oWithin each state, for any combination of input values, there's exactly one applicable arc.

## Step 1 : State Transition Diagram

- o Block Diagram of Desired System
- o Design State Transition Diagram to represent FSM

<!-- image -->

<!-- image -->

<!-- image -->

## Step 2 : Next State Table

1. From STD, find the number of states
2. Number of bits / FFs required = ?\_ to go through these states
3. State Assignment
4. Next State Table

| State   |   S 1 S 0 |
|---------|-----------|
| S0      |        00 |
| S1      |        01 |
| S2      |        10 |
| S3      |        11 |

|                                 |                                 |                                 |                                 |
|---------------------------------|---------------------------------|---------------------------------|---------------------------------|
| Current State Inputs Next State | Current State Inputs Next State | Current State Inputs Next State | Current State Inputs Next State |
| S                               | T L                             | T B                             | S+                              |
| S0                              | 0                               | X                               | S1                              |
| S0                              | 1                               | X                               | S0                              |
| S1                              | X                               | X                               | S2                              |
| S2                              | X                               | 0                               | S3                              |
| S2                              | X                               | 1                               | S2                              |
| S3                              | X                               | X                               | S0                              |

<!-- image -->

## Step 2 : Next State Table

## 5. State Generator Circuit

| Current State Inputs Next State   | Current State Inputs Next State   | Current State Inputs Next State   | Current State Inputs Next State   | Current State Inputs Next State   | Current State Inputs Next State   |
|-----------------------------------|-----------------------------------|-----------------------------------|-----------------------------------|-----------------------------------|-----------------------------------|
| S 1                               | S 0                               | T L                               | T B                               | S 1 +                             | S 0 +                             |
| 0                                 | 0                                 | 0                                 | X                                 | 0                                 | 1                                 |
| 0                                 | 0                                 | 1                                 | X                                 | 0                                 | 0                                 |
| 0                                 | 1                                 | X                                 | X                                 | 1                                 | 0                                 |
| 1                                 | 0                                 | X                                 | 0                                 | 1                                 | 1                                 |
| 1                                 | 0                                 | X                                 | 1                                 | 1                                 | 0                                 |
| 1                                 | 1                                 | X                                 | X                                 | 0                                 | 0                                 |

<!-- formula-not-decoded -->

<!-- formula-not-decoded -->

<!-- image -->

## Next State Animation

S0

| Current State Inputs Next State   | Current State Inputs Next State   | Current State Inputs Next State   | Current State Inputs Next State   | Current State Inputs Next State   | Current State Inputs Next State   | Current State Inputs Next State   |
|-----------------------------------|-----------------------------------|-----------------------------------|-----------------------------------|-----------------------------------|-----------------------------------|-----------------------------------|
| S 1                               | S 0                               | T L                               | T B                               | S 1 +                             | S 0 +                             |                                   |
| 0                                 | 0                                 | 0                                 | X                                 | 0                                 | 1                                 | S1                                |

0

0

0

1

1 X T L =0, T B =1

X

X

0

0

1

0

1

0

X

0

1

1

1

0

X

1

1

0

1

1

X

X

0

0

<!-- image -->

## Next State Animation

S1

| Current State   | Current State   | Inputs   | Inputs   | Next State   | Next State   |
|-----------------|-----------------|----------|----------|--------------|--------------|
| S 1             | S 0             | T L      | T B      | S 1 +        | S 0 +        |
| 0               | 0               | 0        | X        | 0            | 1            |
| 0               | 0               | 1        | X        | 0            | 0            |
| 0               | 1               | X        | X        | 1            | 0            |

1

0

1

0

X 0 T L =0, T B =0

X

1

1

1

1

0

1

1

X

X

0

0

<!-- image -->

S2

## Step 3 : Output Logic

## 1. Output Truth Table

S0

|   Current State - S 1 |   Current State - S 0 |   Outputs - L L1 |   Outputs - L L0 |   Outputs - L B1 |   Outputs - L B0 |
|-----------------------|-----------------------|------------------|------------------|------------------|------------------|
|                     0 |                     0 |                0 |                0 |                1 |                0 |
|                     0 |                     1 |                0 |                1 |                1 |                0 |
|                     1 |                     0 |                1 |                0 |                0 |                0 |
|                     1 |                     1 |                1 |                0 |                0 |                1 |

| Output   |   L 1 L 0 |
|----------|-----------|
| Green    |        00 |
| Yellow   |        01 |
| Red      |        10 |

<!-- formula-not-decoded -->

<!-- formula-not-decoded -->

<!-- image -->

## Ta-Dah!

<!-- image -->

<!-- image -->

<!-- image -->

CLK

Reset

TL

TB

State

LL

LB

S0

S0

S0

S1

S2

S2

S3

S0

Green Green Green Yellow Red Red Red Green

Red Red Red Red Green Green Yellow Red

## Timing Diagram

RST

SO

T=1

T\_= 0

LL: green S1

LL: yellow

LB:red LB : red

S3

L: red

LB: yellow

B

T

B

= 0

二

1

L: red

S2

LB : green

## Verilog~! - Code Structure

<!-- image -->

## FSM in Verilog

<!-- image -->

```
module fsm(input clk, … , output … … ); reg __ state, nextstate;
```

parameter is used to define constants within a module, improving code readability.

```
always @ (*) case (state)
```

```
S0 : nextstate = S1; S1 : nextstate = S0; endcase
```

Next State Combinational Logic : (*) code is triggered whenever any input changes combinational logic.

case represents next state table.

```
always @ (posedge clk, posedge reset) if (reset) state <= S0; else state <= nextstate;
```

```
Sequential Logic :
```

Use &lt;= to infer flip-flops. Is this Sync or Async reset?

Output Logic : Use assign to infer combinational logic.

```
assign y = ( state == S0 );
```

endmodule

```
Equality Comparison : a == b evaluates to 1 if a equals b.
```

```
parameter S0 = 2'b00; parameter S1 = 2'b01;
```

## FSM Traffic Controller in Verilog

```
module traffic (input clk, reset, TL, TB, output [1:0] LL, LB); reg [1:0] state, nextstate; parameter S0 = 2'b00, S1 = 2'b01, S2 = 2'b10, S3 = 2'b11; parameter green = 2'b00, yellow= 2'b01, red= 2'b10; always @ (*) begin case (state) S0: nextstate = TL ? S0 : S1; S1: nextstate = S2; S2: nextstate = TB ? S2 : S3; S3: nextstate = S0; endcase end
```

```
Page 20 always@(posedge clk, posedge reset) begin if (reset) state <= S0; else state <= nextstate; end //What's the diff between these //2 ways of coding output logic ? assign LL = {state[1], ~state[1] & state[0]}; assign LB = (state== S0 || state== S1) ? red : ( (state == S2) ? green : yellow ); endmodule RST T=1 TL= 0 SO S1 LL: green LL: yellow LB:red LB:red S3 TB = 0 S2 LL: red L: red LB: yellow LB : green
```

## Traffic Controller

- o Check the waveforms in the timing diagram below…

Are they correct?

<!-- image -->

<!-- image -->

## Vivado : fsm\_extraction

<!-- image -->

- INFERENCE of FSMs in Vivado
- Built-in FSM encoding strategies to for optimization

## Possible Encoding Strategies :

- Auto
- One-Hot
- Gray State
- Johnson State
- Sequential State

https://www.xilinx.com/support/documentation/sw\_manuals/xilinx2017\_1/ug901-vivadosynthesis.pdf