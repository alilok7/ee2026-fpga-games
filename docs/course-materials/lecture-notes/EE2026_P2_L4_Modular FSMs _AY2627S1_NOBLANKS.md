## FSM 2 : Finite State Machines

©COPYRIGHT CHUA DINGJUAN. ALL RIGHTS RESERVED.

## Let's Try This Out…

<!-- image -->

Bob is stressed out as he has too many deadlines and isn't sleeping enough! He has decided to develop a FSM to regulate his time between sleeping and studying.

- oWhen he is idle, there are two actions he can do next : SLEEP or STUDY.
- o To prevent exhaustion, he buys a body exhaustion sensor and checks it every hour. When he is exhausted, the sensor output EX will be TRUE.
- oWhen he is exhausted, he should sleep (SLEEP is TRUE). When he is not exhausted, he should study (STUDY is TRUE).
- o Implement his FSM using D Flip Flops and gates.

## Step 1 : Block Diagram, STD

<!-- image -->

## Step 2 : Next State Table

## State Transition Diagram

<!-- image -->

## Current State Input Next State

个

| S 1 S 0   |   EX | S 1 +S 0 +   |
|-----------|------|--------------|
| 0 0       |    0 | 1 0          |
| 0 0       |    1 | 0 1          |
| 0 1       |    0 | 1 0          |
| 0 1       |    1 | 0 1          |
| 1 0       |    0 | 1 0          |
| 1 0       |    1 | 0 1          |

<!-- image -->

<!-- image -->

个

| S     |   EX | S+    |
|-------|------|-------|
| IDLE  |    0 | STUDY |
| IDLE  |    1 | SLEEP |
| SLEEP |    0 | STUDY |
| SLEEP |    1 | SLEEP |
| STUDY |    0 | STUDY |
| STUDY |    1 | SLEEP |

<!-- image -->

个

| State   |   S 1 S 0 |
|---------|-----------|
| IDLE    |        00 |
| SLEEP   |        01 |
| STUDY   |        10 |

## Step 2 : Next State Table

| S 1 S 0   |   EX | S 1 +S 0 +   |
|-----------|------|--------------|
| 0 0       |    0 | 1 0          |
| 0 0       |    1 | 0 1          |
| 0 1       |    0 | 1 0          |
| 0 1       |    1 | 0 1          |
| 1 0       |    0 | 1 0          |
| 1 0       |    1 | 0 1          |

<!-- image -->

<!-- formula-not-decoded -->

<!-- image -->

<!-- image -->

<!-- formula-not-decoded -->

<!-- formula-not-decoded -->

*Minimum area vs minimum risk implementations

## Step 2 : Next State Table

If the state assignments were to change, would the next state logic change?

<!-- image -->

Yes, it could! S State assignments are one of the ways e FSMs. to optimize

## Step 3 : Output Logic

<!-- image -->

| State   |   S 1 S 0 |
|---------|-----------|
| IDLE    |        00 |
| SLEEP   |        01 |
| STUDY   |        10 |

| S 1 S 0   |   Sleep |   Study |
|-----------|---------|---------|
| 0 0       |       0 |       0 |
| 0 1       |       1 |       0 |
| 1 0       |       0 |       1 |

<!-- formula-not-decoded -->

<!-- image -->

## Changing Sleep Time…

<!-- image -->

Bob has decided that he is sleep state for too long and has decided to fix his sleep time to 5 hours.

How can we modify his state transition diagram?

<!-- image -->

EX = 0

## Modular Design of FSMs

Designing complex FSMs is often easier if they can be broken down into simpler FSMs that interact.

<!-- image -->

## Modular Design of State Machines

<!-- image -->

- Main machine : executes main algorithm, controls the submachines &amp; get the job done. Commands &amp; gets feedback signals from submachines.
- Submachines respond to external inputs &amp; commands from main machine. Can give outputs as well as feedback to the main machine.
- Common examples of submachines are counters, shift registers, etc.
- Sometimes the main machine is called the controller and the submachines are called controlled circuit elements or architectural elements.
- Trick here is to modularize appropriately, and pick suitable components for the submachines that simplify the design problem.

## Modularizing…

What is a natural submachine that we can use?

<!-- image -->

What inputs would you provide? What outputs would you want?

## Mod-5 Counter

<!-- image -->

Done = 1 when count = 4

## Mod-X Counter

Done = 1 when count = (X-1)

<!-- image -->

## Modified FSM

<!-- image -->

<!-- image -->

## Timing Diagram:

<!-- image -->

<!-- image -->