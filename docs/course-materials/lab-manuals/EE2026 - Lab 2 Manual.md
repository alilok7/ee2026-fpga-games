## OVERVIEW:

A combinational circuit is one where the outputs depend only on the current inputs. In this lab, we will be designing some combinational circuits that are able to perform addition.

## The pre-requisite for this lab requires one to be able to:

- Create a Verilog project and design source in Vivado.
- Create a testbench to simulate the design source.
- Generate the RTL schematic and the synthesised circuit schematic of the design source.
- Map and implement a design on the Basys 3 development board.

## This lab will cover the following:

- Designing a one-bit full adder circuit using the dataflow modelling method.
- Designing a two-bit parallel adder circuit using the structural modelling method.

## Tasks for this lab include:

- Designing the Verilog code of a one-bit full adder.
- Designing, simulating and implementing a four-bit parallel adder on the FPGA.
- Understanding a 1-bit two-to-one multiplexer.

## GRADED PRACTICE TASK [CANVAS SUBMISSION REQUIRED]:

The Graded Practice Task for lab 2 (GPT-2) is required to be started during your lab session and preferably reach near completion during the lab session.

Details for GPT-2 are available at the end of this lab manual.

## EE2026: DIGITAL DESIGN Academic Year 2026-2027, Semester 1

## LAB 2: Combinational Circuits in Verilog

## ONE-BIT-FULL ADDER:

Consider the binary addition shown in Figure 2.1. To design a circuit that would perform the addition of two one-bit values, the circuit would need to have three input bits and two output bits.

Figure 2.1: Binary Addition and functional block diagram of the one-bit full adder

<!-- image -->

Such a circuit is called a one-bit full adder. It adds two bits (A, B) and the carry (Cin) from a previous stage of addition, and produces a sum (S) and a carry (Cout), as illustrated through a truth table in Figure 2.2. By simplifying the truth table, the Boolean expressions for S and Cout can be obtained.

Figure 2.2: Truth table and boolean expressions of the one-bit full adder

<!-- image -->

Note: A half adder, in contrast to a full adder, does not involve a carry input. Thus, for a half adder, 𝑆 = 𝐴⨁𝐵, and 𝐶௢௨௧ = 𝐴𝐵

## UNDERSTANDING | TASK 1

Using the dataflow method, complete the Verilog code for the one-bit full adder. Verify that the RTL schematic is as shown.

## Verilog skeleton code for the one-bit-full adder:

```
module my_full_adder(input A, B, CIN, output S, COUT); assign S = assign COUT =
```

## endmodule

## RTL schematic for the one-bit full adder:

<!-- image -->

RTL\_XOR

## TWO-BIT FULL ADDER:

By cascading one-bit full adder blocks, the one-bit adder can be reused and parallel adders that add multiple bits can be created through the structural modelling method. A two-bit ripple-carry adder is illustrated in Figure 2.3.

Figure 2.3: Functional block diagram of the two-bit ripple-carry adder

<!-- image -->

With the code for a one-bit full adder, a new module is created and two full adder blocks (fa0, fa1) are instantiated. By specifying the inputs and outputs to these blocks, the connection C1 between them is made. Note that the order of signals during instantiation should respect the order in which they were declared in the one-bit full adder module my\_full\_adder.

This approach to hardware description is called structural modelling, whereby a more abstract module (for example, my\_2\_bit\_adder) is built from simpler components describing gate-level hardware (such as my\_full\_adder).

## Verilog code for two-bit ripple-carry adder, using structural modelling:

```
module my_2_bit_adder(input [1:0] A, input [1:0] B, input C0, output [1:0] S, output C2); wire C1; my_full_adder fa0 (A[0], B[0], C0, S[0], C1); my_full_adder fa1 (A[1], B[1], C1, S[1], C2);
```

endmodule

## [Note] Two-bit port declaration for A, B, S:

Instead of having multiple input and output ports (A1, A0, B1, B0, S1, S0), multi-bit vector ports are defined.

Example:

input [5:0] room

Input port name is room, with size of 6 bits.

room[5] refers to the MSB.

room[0] refers to the LSB.

## RTL schematic for the two-bit ripple-carry adder:

<!-- image -->

## FOUR-BIT FULL ADDER:

The functional block diagram of a four-bit ripple-carry adder is shown in Figure 2.4.

Figure 2.4: Functional block diagram of a four-bit ripple-carry adder

<!-- image -->

## UNDERSTANDING | TASK 2

Start by adding a new design source for the four-bit full adder.

1. By using the structural modelling method, design a four-bit ripple-carry adder.
2. Generate the RTL schematic and check that connections between the blocks are correct.
3. Simulate your code with the following three sets of input values, and check that the simulation outputs are correct:

<!-- image -->

## [Note] Brief guidelines for multi-bit vector ports in the testbench:

-  The port size should be indicated when declaring the signals. Inputs to the module being tested are declared using reg, whereas outputs from the module being tested are declared using wire: reg [3:0] A; wire [3:0] S;
-  The parameters for the module being tested do not need the port size of the signals:
-  The testbench stimuli for multi-bit vector ports can be written as:
- A = 4'b0011; B = 4'b0011; CARRY\_IN = 1'b0;
4. Generate the bitstream of your code for the FPGA, using appropriate switches and LEDs on the Basys 3 development board to represent the inputs and outputs.

```
my_4_bit_adder module_alias (A, B, CARRY_IN, S, CARRY_OUT);
```

## UNDERSTANDING | TASK 3

When there are many possible input values involved, consider the usage of LLM / AI tools to help with generating an exhaustive testbench. As example, for the adder created in UNDERSTANDING | TASK 2, the total amount of bits for the all the input ports is 9 bits. Thus, there are 2 9 (Equivalent to 512) test cases that covers all valid possibilities.

## Example of Prompt (Exhaustive Testbench)

This is the module declaration of my Verilog code describing a combinational 4-bit adder.

module my\_4\_bit\_adder (input [3:0] A, B, input CARRY\_IN, output [3:0] S, output CARRY\_OUT);

Generate a simple Verilog exhaustive testbench.

For the specific test values in UNDERSTANDING | TASK 2, it is also possible to indicate them.

## Example of Prompt (Specific Values)

This is the module declaration of my Verilog code describing a combinational 4-bit adder.

module my\_4\_bit\_adder (input [3:0] A, B, input CARRY\_IN, output [3:0] S, output CARRY\_OUT);

Generate a simple Verilog testbench, applying the following test cases in sequence with #10 delay between each test case :

```
A = 4'b0011; B=4'b0011; CARRY_IN=0; A = 4'b1011; B=4'b0111; CARRY_IN =0; A = 4'b1111; B=4'b1111; CARRY_IN =0;
```

From the generated codes, you may notice new Verilog keywords that you have not seen before.

What do you think they are for? Are they necessary?

Hint: Look in the console window, as well as the duration of your simulation.

## 1-BIT TWO-TO-ONE MULTIPLEXER:

A multiplexer (MUX) is a combinational circuit that connects one of its input signals to the output, based on the control signal. A simple 1-bit two-to-one mux, with inputs A, B, control signal S, and output Z, is illustrated as a functional block diagram, together with its simplified truth table, in Figure 2.5.

|   S | Z   |
|-----|-----|
|   0 | A   |
|   1 | B   |

Figure 2.5: Functional block diagram and truth table of a 1-bit two-to-one multiplexer

<!-- image -->

## UNDERSTANDING | TASK 4

A quick way to implement the Verilog code for a 1-bit two-to-one multiplexer is using the conditional syntax:

condition ? expression1 : expression2;

Notice in the schematic, how the code is automatically recognised as a MUX.

Verilog code for 1-bit two-to-one mux, using the dataflow method

```
module my_2_to_1_mux (input A, B, S, output Z);
```

assign Z = S ? B : A; // assign B to Z if S = 1 or assign A to Z if S = 0;

## endmodule

RTL schematic for the 1-bit two-to-one mux

<!-- image -->

## BEFORE STARTING ON GPT-2:

Each student has a personalised requirement based on student matriculation number. Carefully write down and use your exact number, as mistakes in the student matriculation number are not accepted. Appeals due to wrong number used for your personalised requirement will be rejected.

<!-- image -->

|    |   7 th Rightmost Number | 6 th Rightmost Number   | 5 th Rightmost Number   | 4 th Rightmost Number   | 3 rd Rightmost Number   | 2 nd Rightmost Number   | 1 st Rightmost Number   | Rightmost Alphabet   |
|----|-------------------------|-------------------------|-------------------------|-------------------------|-------------------------|-------------------------|-------------------------|----------------------|
| A  |                       0 |                         |                         |                         |                         |                         |                         |                      |

Students are required to carefully read all the GPT-2 requirements, and to enhance their understanding by looking at the example.

Marks are given for using your correct student matriculation number, and grading is done only once. Re-submissions, late submissions, or updates, even if very simple or minor, are not accepted after the grading.

## GRADED PRACTICE TASK 2 (GPT-2)

There is NO bitstream involved in GPT-2. All the requirements are to be shown in simulation only.

## IMPORTANT CHARACTERS

In GPT-2, these are the important characters to note from your student matriculation number:

- The 2 nd rightmost numerical value of your student matriculation number (Initialisation, subtask B)
- The 3 rd rightmost numerical value of your student matriculation number (Subtask A)

## INITIALISATION

In the previous lab, we had used one bit signal to control each LED / segment / anode.

<!-- image -->

From this lab onwards, it is compulsory to use multi-bits vectors to give values to the segments and anodes.

Do not separate the 7 segments and decimal point on the segment displays. Instead, they need to be combined as an 8 bit-signal.

Each bit within an 8-bit signal must control the segments in this exact order: {DP, G, F, E, D, C, B, A} Each bit within a 4-bit signal must control the anodes in this exact order: {AN3, AN2, AN1, AN0}

## For example:

- A value of 8'b11111011 to the 8-bit signal turns on segment C.
- A value of 4'b0111 to the 4-bit signal turns on AN3.

When the program starts, the seven segment displays must show the following patterns exactly, based on the 2 nd rightmost numerical value of your student matriculation number:

<!-- image -->

## SUBTASK A (Structural modelling)

Based on the 3 rd rightmost numerical value of your student matriculation number, create two separate parallel adders as indicated in the table below:

|   3 rd Rightmost Numerical Value | Required parallel adders. Each one of these parallel adders must be made up of multiple 1-bit adders   | Required parallel adders. Each one of these parallel adders must be made up of multiple 1-bit adders   |
|----------------------------------|--------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|
|                                0 | 2-bit parallel adder                                                                                   | 3-bit parallel adder                                                                                   |
|                                1 | 3-bit parallel adder                                                                                   | 2-bit parallel adder                                                                                   |
|                                2 | 2-bit parallel adder                                                                                   | 4-bit parallel adder                                                                                   |
|                                3 | 4-bit parallel adder                                                                                   | 2-bit parallel adder                                                                                   |
|                                4 | 3-bit parallel adder                                                                                   | 4-bit parallel adder                                                                                   |
|                                5 | 4-bit parallel adder                                                                                   | 3-bit parallel adder                                                                                   |
|                                6 | 3-bit parallel adder                                                                                   | 5-bit parallel adder                                                                                   |
|                                7 | 5-bit parallel adder                                                                                   | 3-bit parallel adder                                                                                   |
|                                8 | 2-bit parallel adder                                                                                   | 5-bit parallel adder                                                                                   |
|                                9 | 5-bit parallel adder                                                                                   | 2-bit parallel adder                                                                                   |

Following that, make use of both parallel adders to create a "single complete n-bit parallel adder" with inputs A and B, and output DR. The bits given to the "single complete n-bit parallel adder" must be divided between the two parallel adders as follows:

|   3 rd Rightmost Numerical Value | Most significant bits of the complete adder must use the following adder   | Least significant bits of the complete adder must use the following adder   | n-bit input A, or Input B, of the complete adder   | n-bit output DR of the complete adder   |
|----------------------------------|----------------------------------------------------------------------------|-----------------------------------------------------------------------------|----------------------------------------------------|-----------------------------------------|
|                                0 | 2-bit parallel adder                                                       | 3-bit parallel adder                                                        | 5 bits                                             | 5 bits                                  |
|                                1 | 3-bit parallel adder                                                       | 2-bit parallel adder                                                        | 5 bits                                             | 5 bits                                  |
|                                2 | 2-bit parallel adder                                                       | 4-bit parallel adder                                                        | 6 bits                                             | 6 bits                                  |
|                                3 | 4-bit parallel adder                                                       | 2-bit parallel adder                                                        | 6 bits                                             | 6 bits                                  |
|                                4 | 3-bit parallel adder                                                       | 4-bit parallel adder                                                        | 7 bits                                             | 7 bits                                  |
|                                5 | 4-bit parallel adder                                                       | 3-bit parallel adder                                                        | 7 bits                                             | 7 bits                                  |
|                                6 | 3-bit parallel adder                                                       | 5-bit parallel adder                                                        | 8 bits                                             | 8 bits                                  |
|                                7 | 5-bit parallel adder                                                       | 3-bit parallel adder                                                        | 8 bits                                             | 8 bits                                  |
|                                8 | 2-bit parallel adder                                                       | 5-bit parallel adder                                                        | 7 bits                                             | 7 bits                                  |
|                                9 | 5-bit parallel adder                                                       | 2-bit parallel adder                                                        | 7 bits                                             | 7 bits                                  |

For the module dealing with the Least significant bits: There is no carry in, but there is a carry out. For the module dealing with the Most significant bits: There is a carry in, but there is no carry out.

The block diagram for the "single complete n-bit parallel adder" is as illustrated below:

<!-- image -->

## SUBTASK B (Manipulation and usage of multi-bits vectors)

When a certain pushbutton is pressed, the anodes of seven segment displays from the INITIALISATION part must be inverted. When that same pushbutton is released, the anodes of the seven displays must revert to how they were in the INITILISATION part.

The pushbutton to use is dependent on the 2 nd rightmost numerical value of your student matriculation number, as indicated in the table below:

| 2 nd Rightmost Numerical Value   | Pushbutton to use   |
|----------------------------------|---------------------|
| 0 , 5                            | BTNU (Up)           |
| 1 , 6                            | BTNR (Right)        |
| 2 , 7                            | BTND (Down)         |
| 3 , 8                            | BTNL (Left)         |
| 4 , 9                            | BTNC (Centre)       |

<!-- image -->

The result from the "single complete n-bit parallel adder" of SUBTASK A is called the default result (DR) and is to be shown by default on the LEDs of the Basys 3 development board. However, when the user presses and hold the pushbutton indicated at the start of this SUBTASK B, it is required to have another alternate n-bit result (AR) shown on the LEDs of the Basys 3 development board, instead of the n-bit default result (DR). That alternate n-bit result is dependent on the 2 nd rightmost numerical value of your student matriculation number, as shown in the table below:

|   2 nd Rightmost Numerical Value | Alternate result (AR)                   | Further details                            |
|----------------------------------|-----------------------------------------|--------------------------------------------|
|                                0 | 3 least significant bits of DR inverted | The other bits are not inverted            |
|                                1 | DR divided by 2                         | Ignore the decimal point of S (Round down) |
|                                2 | DR multiplied by 8                      | Ignore bits that exceed the size of S      |
|                                3 | 2 most significant bits of DR inverted  | The other bits are not inverted            |
|                                4 | DR divided by 4                         | Ignore the decimal point of S (Round down) |
|                                5 | DR multiplied by 2                      | Ignore bits that exceed the size of S      |
|                                6 | 4 least significant bits of DR inverted | The other bits are not inverted            |
|                                7 | DR divided by 8                         | Ignore the decimal point of S (Round down) |
|                                8 | DR multiplied by 4                      | Ignore bits that exceed the size of S      |
|                                9 | 3 most significant bits of DR inverted  | The other bits are not inverted            |

Avoid the usage of shift operators while trying to complete this subtask B.

## Hints:

- To get the AR, consider:
- o The usage of specific bits from the output DR of SUBTASK A
- o Replacing certain bits with zeros
- o Concatenating bits
- Use a multiplexor to determine whether DR or AR goes to the output S of the digital device

Arithmetic operators for addition, subtraction, multiplication, and division are NOT ALLOWED anywhere for GPT-2. No marks are given if arithmetic operators (+ , - , * , / ) are used

## SUBTASK C (Making the Single Digital Device)

Combine the INITIALISATION, SUBTASK A, and SUBTASK B together, such that the digital device to be implemented on the Basys3 development board only have these 6 ports, with the names and sizes of each port exactly as indicated in the figure on the right (Exactly 6 ports / 6 rows of waveforms must be present in the simulation of SUBTASK D also).

## SUBTASK D (Simulation and Report)

A gentle reminder that there is no bitstream involved in GPT-2. Instead, the digital device created in SUBTASK C is to be tested in simulation only. Fill in Table 1 below with the values obtained from your simulation, while carefully noting the following:

- Requirements / Examples are in blue characters, and these blue characters must be deleted in your submission.
- Values highlighted in light yellow are fixed and must be as indicated in the table. (Keep the highlight in your submission).
- All values for A, B, pb, S, an, and seg must be written in unsigned decimal type in the table (Example: 4'd0, 8'd0 etc.).
- 'n' should be replaced with your personalised value, and it is normal for bits to be truncated in case your personalised 'n' value is too small to fit in all the bits (These extra bits are ignored, and you do not need to deal with them).

Table 1: Table for 10 Simulation Sets

| Time of Update (ns)                                                                                                                                                                                                                                           | Input A                                                                                                                                                                                                                                                       | Input B                                                                                                                                                                                                                                                       | Pushbutton pb                                                                                                                                                                                                                                                 | Output S                                                                                                                                                                                                                                                      | Output an                                                                                                                                                                                                                                                     | Output seg                                                                                                                                                                                                                                                    |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 0 ns                                                                                                                                                                                                                                                          | n'd0                                                                                                                                                                                                                                                          | n'd0                                                                                                                                                                                                                                                          | 1'd0                                                                                                                                                                                                                                                          | n'd0                                                                                                                                                                                                                                                          | (Eg: 4'd6)                                                                                                                                                                                                                                                    | (Eg: 8'd183)                                                                                                                                                                                                                                                  |
| 20 ns                                                                                                                                                                                                                                                         | n'd0                                                                                                                                                                                                                                                          | n'd0                                                                                                                                                                                                                                                          | 1'd1                                                                                                                                                                                                                                                          | (Eg: n'd234)                                                                                                                                                                                                                                                  | (Eg: 4'd6)                                                                                                                                                                                                                                                    | (Eg: 8'd183)                                                                                                                                                                                                                                                  |
| 40 ns                                                                                                                                                                                                                                                         | n'd0                                                                                                                                                                                                                                                          | n'd255                                                                                                                                                                                                                                                        | 1'd1                                                                                                                                                                                                                                                          | (Eg: n'd234)                                                                                                                                                                                                                                                  | (Eg: 4'd6)                                                                                                                                                                                                                                                    | (Eg: 8'd183)                                                                                                                                                                                                                                                  |
| 60 ns                                                                                                                                                                                                                                                         | n'd2                                                                                                                                                                                                                                                          | n'd255                                                                                                                                                                                                                                                        | 1'd0 …                                                                                                                                                                                                                                                        | (Eg: n'd234)                                                                                                                                                                                                                                                  | (Eg: 4'd6)                                                                                                                                                                                                                                                    | (Eg: 8'd183)                                                                                                                                                                                                                                                  |
| Simulate more sets of values (6 simulation sets with values chosen by you are required. The previous 4 rows of simulation sets do not count towards your chosen 6 simulation sets. Hence, 10 different simulation sets in total must be present in the table) | Simulate more sets of values (6 simulation sets with values chosen by you are required. The previous 4 rows of simulation sets do not count towards your chosen 6 simulation sets. Hence, 10 different simulation sets in total must be present in the table) | Simulate more sets of values (6 simulation sets with values chosen by you are required. The previous 4 rows of simulation sets do not count towards your chosen 6 simulation sets. Hence, 10 different simulation sets in total must be present in the table) | Simulate more sets of values (6 simulation sets with values chosen by you are required. The previous 4 rows of simulation sets do not count towards your chosen 6 simulation sets. Hence, 10 different simulation sets in total must be present in the table) | Simulate more sets of values (6 simulation sets with values chosen by you are required. The previous 4 rows of simulation sets do not count towards your chosen 6 simulation sets. Hence, 10 different simulation sets in total must be present in the table) | Simulate more sets of values (6 simulation sets with values chosen by you are required. The previous 4 rows of simulation sets do not count towards your chosen 6 simulation sets. Hence, 10 different simulation sets in total must be present in the table) | Simulate more sets of values (6 simulation sets with values chosen by you are required. The previous 4 rows of simulation sets do not count towards your chosen 6 simulation sets. Hence, 10 different simulation sets in total must be present in the table) |

A single unedited screenshot (PrintScreen/Windows snipping tool) of the simulation waveform pattern from the Vivado simulation window must be obtained and then pasted on a 1-page landscape A4-size below the table for 10 simulation sets.

The single unedited screenshot must compulsorily meet these criteria, and requires you to know how to manipulate the visualisation of the simulation waveforms in Vivado, to be given marks:

- All 10 test cases are clearly readable from the waveforms, and they exactly match the values indicated in Table 1.
- The radix of the waveforms must be selected as "Unsigned Decimal".
- No 'X' or 'Z' values in any of the waveforms (These indicate unknown or high impedance values).
- There are exactly 6 rows of waveform, and they should not be expanded (No need to see the individual bits).

## REPORT LAYOUT REQUIREMENTS:

- (1) Name and matriculation number at the top of the single page A4 size landscape document.
- (2) The filled-up Table 1 with 10 different simulation sets is next.
- (3) The single and clearly readable screenshot of the waveform that matches the values in Table 1 is next.
- (4) Not allowed to have more than 1-page landscape A4-size. Anything found beyond the 1-page is ignored.

<!-- image -->

<!-- image -->

seg

## SUGGESTIONS

- Complete the MUX task and understand the purpose of MUX before working on GPT-2.
- The following will be taught in subsequent labs, and are thus not necessary in lab 2:
- o if-else functions (Instead, use something similar to the MUX task)
- o always blocks (Instead, use dataflow and structural modelling)
- o shift operators (Instead, make clever use of the multi-bits vector manipulation)
- Bitstream generation for the Basys3 is not required for GPT-2, but you are encouraged to practice it!

## EXAMPLE OF GPT-2 BEHAVIOUR:

The example here is the implemented behaviour of GPT-2 for ease of visualisation.

You are not required to implement GPT-2 using a bitstream. Instead, only the simulation part is graded.

If your student matriculation number is A0159089Y, then:

2 nd rightmost numerical value:

3 rd rightmost numerical value:

8 (Initialisation and subtask B depends on this number)

0 (Subtask A depends on this number)

## INITIALISATION

<!-- image -->

## SUBTASK A

| Matric. Value = 0   | 2-bit parallel adder   | 3-bit parallel adder   | 5 bits   | 5 bits   |
|---------------------|------------------------|------------------------|----------|----------|

<!-- image -->

## SUBTASK B

<!-- image -->

| Matric. Value = 8   | DR multiplied by 4   | Ignore bits that exceed the size of S   |
|---------------------|----------------------|-----------------------------------------|

## ADDITIONAL EXAMPLES FOR SUBTASK B

## Assuming 6 Bits System

<!-- image -->

## CANVAS SUBMISSION INSTRUCTIONS

- Ensure that your simulation can run BEFORE archiving your Vivado workspace for CANVAS upload. Bitstream is not required.
- It is compulsory to archive your project in a compressed form without any saved simulation waveforms. Follow the instructions given in the pdf: "Archive Project in Vivado 2025.2". The archive size should not exceed 5 MB in size for GPT-2. If the archive size exceeds, ensure that there is no ".sim" folder in your Vivado project folder before archiving.
- After following the instructions in "Archive Project in Vivado 2025.2", rename your project archive as indicated in the appendix of this lab manual.
- Separately from the project archive, the single PDF report of 1 A4-size page is to be named as indicated in the appendix of this lab manual. The report layout and requirements should be as described in SUBTASK D.
- Upload to CANVAS EE2026 -&gt; Assignments -&gt; Lab 2 -&gt; GPT-2 (On-Time).
- Download your CANVAS archive after uploading. Click and drag the single folder within that archive to desktop, and then open the Vivado project (.xpr) in that extracted folder to see if it can be opened. You can ignore "out-of-date" warnings. Check if you can also run your simulation correctly. No project file and no working simulation is equivalent to losing all marks.
- GPT-2 is recommended to be mostly completed within the lab session itself and uploaded within a few hours of the lab. You are however allowed to upload to CANVAS without penalties before Monday 7 th September 2026, 6:00 A.M. Avoid planning to upload during the additional grace period of 2 hours. (Grace period is for last-minute cases, such as due to slow internet, wrong uploads etc.)
- The late submission folder closes 1 week after the original deadline. Late submissions are not graded if submissions are found in the on-time folder. Do not submit in the late submission folder if you have already submitted in the on-time folder, as it will be ignored and only the on-time submission will be graded. The late submission folder will be located at: CANVAS EE2026 -&gt; Assignments -&gt; Lab 2 -&gt; GPT-2 Submission (Late).
- Re-submissions, late submissions, or updates, even if very simple or minor, are not accepted after your original submission has been graded.
- Submissions through emails, file sharing programs, or links, are not accepted. Submissions must be officially submitted to, and downloadable from, Canvas in the correct on-time or late folder.

## Plagiarism is penalised with a 100% penalty for all SOURCES and RECIPIENTS

All past and future submissions, and marks, will be reviewed in greater detail, for any person found to have plagiarised

ALL THE SUBMISSION INSTRUCTIONS LISTED ABOVE WILL AFFECT YOUR GRADES!

\_ \_ \_ \_ \_ \_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_ \_

## GRADING PROCESS

- Submissions not following all the CANVAS SUBMISSION INSTRUCTIONS (listed above) will not be graded immediately, and they will instead be reviewed towards the end of the semester. You will not be able to see your submission results during the lab sessions in such situations.

## APPENDIX (COMPULSORY renaming just before CANVAS upload):

It is compulsory to rename your project archive and PDF report, just before the CANVAS upload, as listed in the table below.

Do not change any other part of the naming. Simply copy the naming from the table below and paste it while renaming your project archive and PDF report. Then upload these 2 items to CANVAS after the renaming. Penalties will be incurred if your submission cannot be found according to the exact naming template below.

CANVAS may automatically add a suffix (Example. "-1", "-2", "-3" etc.) at the end of the filename if you submit multiple files. That is acceptable and we will grade the latest file submitted within that on-time folder.

| Archive Naming (.xpr.zip and .zip accepted)                       | PDF Report Naming                                               |
|-------------------------------------------------------------------|-----------------------------------------------------------------|
| GPT2_AARON CHIN JIN HAO_163_Archive                               | GPT2_AARON CHIN JIN HAO_163_Report                              |
| GPT2_ADI RAMANLAL_033_Archive                                     | GPT2_ADI RAMANLAL_033_Report                                    |
| GPT2_ADVAIT BAGRI_209_Archive                                     | GPT2_ADVAIT BAGRI_209_Report                                    |
| GPT2_AHMED IMAAD_686_Archive                                      | GPT2_AHMED IMAAD_686_Report                                     |
| GPT2_ALYCIA YAK SHI YI_246_Archive                                | GPT2_ALYCIA YAK SHI YI_246_Report                               |
| GPT2_AMBAR_974_Archive                                            | GPT2_AMBAR_974_Report                                           |
| GPT2_ANDREW CHONG KIAN WEI_019_Archive                            | GPT2_ANDREW CHONG KIAN WEI_019_Report                           |
| GPT2_ANDREW YAP ZI ZEN_117_Archive                                | GPT2_ANDREW YAP ZI ZEN_117_Report                               |
| GPT2_ARNAV PARAG SALKADE_052_Archive                              | GPT2_ARNAV PARAG SALKADE_052_Report                             |
| GPT2_ARORA JITISHA_189_Archive                                    | GPT2_ARORA JITISHA_189_Report                                   |
| GPT2_ARUN PANCHAPAKESAN IYER_842_Archive                          | GPT2_ARUN PANCHAPAKESAN IYER_842_Report                         |
| GPT2_ATHARVA REGE_841_Archive                                     | GPT2_ATHARVA REGE_841_Report                                    |
| GPT2_BALAKRISHNAN SHRIKKANTH_980_Archive                          | GPT2_BALAKRISHNAN SHRIKKANTH_980_Report                         |
| GPT2_BARANIKUMAR SARITHA PADMA_345_Archive                        | GPT2_BARANIKUMAR SARITHA PADMA_345_Report                       |
| GPT2_BETTS DANIEL ANZHE_421_Archive                               | GPT2_BETTS DANIEL ANZHE_421_Report                              |
| GPT2_BHAO TANUSH_706_Archive                                      | GPT2_BHAO TANUSH_706_Report                                     |
| GPT2_BI JIALIN_083_Archive                                        | GPT2_BI JIALIN_083_Report                                       |
| GPT2_BODAPATI VAMSHI KRISHNA_405_Archive                          | GPT2_BODAPATI VAMSHI KRISHNA_405_Report                         |
| GPT2_BRYAN CHUA XIANG YU_710_Archive                              | GPT2_BRYAN CHUA XIANG YU_710_Report                             |
| GPT2_CAI YI HANG_455_Archive                                      | GPT2_CAI YI HANG_455_Report                                     |
| GPT2_CHAN CHEE HENG_721_Archive                                   | GPT2_CHAN CHEE HENG_721_Report                                  |
| GPT2_CHANG YICHUN_522_Archive                                     | GPT2_CHANG YICHUN_522_Report                                    |
| GPT2_CHANG ZI SHYAN SHERWIN_293_Archive                           | GPT2_CHANG ZI SHYAN SHERWIN_293_Report                          |
| GPT2_CHEN HOK LEONG_601_Archive                                   | GPT2_CHEN HOK LEONG_601_Report                                  |
| GPT2_CHEN ZHENONG_159_Archive                                     | GPT2_CHEN ZHENONG_159_Report                                    |
| GPT2_CHEW WAI JUN EVAN_524_Archive                                | GPT2_CHEW WAI JUN EVAN_524_Report                               |
| GPT2_CHIA MING HENG TITUS_200_Archive                             | GPT2_CHIA MING HENG TITUS_200_Report                            |
| GPT2_CHUA CHOON HSIANG_727_Archive                                | GPT2_CHUA CHOON HSIANG_727_Report                               |
| GPT2_CHUA JINGHAO_532_Archive                                     | GPT2_CHUA JINGHAO_532_Report                                    |
| GPT2_DARREN TOH QING HONG_467_Archive                             | GPT2_DARREN TOH QING HONG_467_Report                            |
| GPT2_DONGJIN SHIN_719_Archive                                     | GPT2_DONGJIN SHIN_719_Report                                    |
| GPT2_DOUGLAS ETHAN KWOK_301_Archive                               | GPT2_DOUGLAS ETHAN KWOK_301_Report                              |
| GPT2_DUONG NGHIEP HOANG_675_Archive                               | GPT2_DUONG NGHIEP HOANG_675_Report                              |
| GPT2_EETHAN ZHANG YOU JIE_514_Archive                             | GPT2_EETHAN ZHANG YOU JIE_514_Report                            |
| GPT2_ELYSSA TJIN YI JING_142_Archive                              | GPT2_ELYSSA TJIN YI JING_142_Report                             |
| GPT2_ENZO HO_460_Archive                                          | GPT2_ENZO HO_460_Report                                         |
| GPT2_ERNEST GOH CHIN WEE_869_Archive                              | GPT2_ERNEST GOH CHIN WEE_869_Report                             |
| GPT2_EUGENE QUEK_592_Archive                                      | GPT2_EUGENE QUEK_592_Report                                     |
| GPT2_GABRIEL YU YAO SOON_978_Archive                              | GPT2_GABRIEL YU YAO SOON_978_Report                             |
| GPT2_GAN SIM RU DAYNA_051_Archive                                 | GPT2_GAN SIM RU DAYNA_051_Report                                |
| GPT2_GANGADHAR NANDI GAUTHAM_850_Archive                          | GPT2_GANGADHAR NANDI GAUTHAM_850_Report                         |
| GPT2_GARG DIVYANSH_042_Archive GPT2_GARG SANCHIT AMIT_679_Archive | GPT2_GARG DIVYANSH_042_Report GPT2_GARG SANCHIT AMIT_679_Report |

| GPT2_GLAENNFJORD MILLA LINNEA _gl_Archive                                   | GPT2_GLAENNFJORD MILLA LINNEA _gl_Report                                  |
|-----------------------------------------------------------------------------|---------------------------------------------------------------------------|
| GPT2_GLENNON PHUA QING XUN_609_Archive                                      | GPT2_GLENNON PHUA QING XUN_609_Report                                     |
| GPT2_GOH ROU HUI ASHLEY_439_Archive                                         | GPT2_GOH ROU HUI ASHLEY_439_Report                                        |
| GPT2_GOPINATHAN MAIYURI_060_Archive                                         | GPT2_GOPINATHAN MAIYURI_060_Report                                        |
| GPT2_GUPTA TANMAY_349_Archive                                               | GPT2_GUPTA TANMAY_349_Report                                              |
| GPT2_HAN QIZE_320_Archive                                                   | GPT2_HAN QIZE_320_Report                                                  |
| GPT2_HAN ZHONG DING_590_Archive                                             | GPT2_HAN ZHONG DING_590_Report                                            |
| GPT2_HENG YONG HEN_977_Archive                                              | GPT2_HENG YONG HEN_977_Report                                             |
| GPT2_HEU YU HUI_290_Archive                                                 | GPT2_HEU YU HUI_290_Report                                                |
| GPT2_HUANG SHANGYI_564_Archive                                              | GPT2_HUANG SHANGYI_564_Report                                             |
| GPT2_IAN LEE JIAYI_769_Archive                                              | GPT2_IAN LEE JIAYI_769_Report                                             |
| GPT2_IFTIKHAR YUHAN BIN IRZAD _693_Archive                                  | GPT2_IFTIKHAR YUHAN BIN IRZAD _693_Report                                 |
| GPT2_ISAAC GOH YONG CHEE_412_Archive                                        | GPT2_ISAAC GOH YONG CHEE_412_Report                                       |
| GPT2_JAIN TANMAY_216_Archive                                                | GPT2_JAIN TANMAY_216_Report                                               |
| GPT2_JANG SEOK KEON_036_Archive                                             | GPT2_JANG SEOK KEON_036_Report                                            |
| GPT2_JAVIER LEE RUI YANG_587_Archive                                        | GPT2_JAVIER LEE RUI YANG_587_Report                                       |
| GPT2_JEREMIAH JAMES_493_Archive                                             | GPT2_JEREMIAH JAMES_493_Report                                            |
| GPT2_JORDAN RIATONO_175_Archive                                             | GPT2_JORDAN RIATONO_175_Report                                            |
| GPT2_JOSEFSSON CARL OSCAR WILL_j_Archive                                    | GPT2_JOSEFSSON CARL OSCAR WILL_j_Report                                   |
| GPT2_KANG KIAT YANG_549_Archive                                             | GPT2_KANG KIAT YANG_549_Report                                            |
| GPT2_KANNI KUMARAN SRISURAJ_081_Archive                                     | GPT2_KANNI KUMARAN SRISURAJ_081_Report                                    |
| GPT2_KARAN BONTHA_031_Archive                                               | GPT2_KARAN BONTHA_031_Report                                              |
| GPT2_KARTHIK SIVASUBRAMANIAN_056_Archive                                    | GPT2_KARTHIK SIVASUBRAMANIAN_056_Report                                   |
| GPT2_KARTIKEYAN RONITH_987_Archive                                          | GPT2_KARTIKEYAN RONITH_987_Report                                         |
| GPT2_KARUNANITHI NAVIN ANAND_370_Archive                                    | GPT2_KARUNANITHI NAVIN ANAND_370_Report                                   |
| GPT2_KAUSHAL RAJESH_862_Archive                                             | GPT2_KAUSHAL RAJESH_862_Report                                            |
| GPT2_KHOO KAI JUN_957_Archive                                               | GPT2_KHOO KAI JUN_957_Report                                              |
| GPT2_KIM DOYEON_415_Archive                                                 | GPT2_KIM DOYEON_415_Report                                                |
| GPT2_KIM TAEEUN_919_Archive                                                 | GPT2_KIM TAEEUN_919_Report                                                |
| GPT2_KOH KA HOW_373_Archive                                                 | GPT2_KOH KA HOW_373_Report                                                |
| GPT2_KOH LI WEI OLIVER_592_Archive                                          | GPT2_KOH LI WEI OLIVER_592_Report                                         |
| GPT2_KOTHARI AADI_808_Archive                                               | GPT2_KOTHARI AADI_808_Report                                              |
| GPT2_KRONHAMN OSCAR LUDVIG_kr_Archive                                       | GPT2_KRONHAMN OSCAR LUDVIG_kr_Report                                      |
| GPT2_KUMARESAN KUGAPRYAN_993_Archive                                        | GPT2_KUMARESAN KUGAPRYAN_993_Report                                       |
| GPT2_KYLE LEE YAO YU_663_Archive GPT2_LAM LOK SANG MATTHEW LUCA_294_Archive | GPT2_KYLE LEE YAO YU_663_Report GPT2_LAM LOK SANG MATTHEW LUCA_294_Report |
| GPT2_LAM YAP TING_341_Archive                                               | GPT2_LAM YAP TING_341_Report                                              |
| GPT2_LAU ZHE WEN_969_Archive                                                | GPT2_LAU ZHE WEN_969_Report                                               |
| GPT2_LAW SHAO CHONG_761_Archive                                             | GPT2_LAW SHAO CHONG_761_Report                                            |
| GPT2_LEE CHANG FENG_463_Archive                                             | GPT2_LEE CHANG                                                            |
| GPT2_LEE CHEONG WENG JUSTIN_211_Archive                                     | FENG_463_Report GPT2_LEE CHEONG WENG JUSTIN_211_Report                    |
| GPT2_LEE EE XUAN_562_Archive                                                | GPT2_LEE EE XUAN_562_Report                                               |
| GPT2_LEE KWAN TZE_762_Archive                                               | GPT2_LEE KWAN TZE_762_Report                                              |
| GPT2_LEE PEI LING_692_Archive                                               | GPT2_LEE PEI                                                              |
| GPT2_LEE ZHON CHEN_758_Archive                                              | LING_692_Report GPT2_LEE ZHON CHEN_758_Report                             |
| GPT2_LEON MATTHEW WEI_323_Archive                                           | GPT2_LEON MATTHEW WEI_323_Report                                          |
| GPT2_LEROY KOH_782_Archive                                                  | GPT2_LEROY KOH_782_Report                                                 |
| GPT2_LEW YIK CHIN_716_Archive                                               | GPT2_LEW YIK CHIN_716_Report                                              |
| GPT2_LI MEIYI_500_Archive                                                   | GPT2_LI MEIYI_500_Report                                                  |
| GPT2_LI YI AN_037_Archive                                                   | GPT2_LI YI AN_037_Report                                                  |
| GPT2_LIAO YIRAN_844_Archive                                                 | GPT2_LIAO YIRAN_844_Report                                                |
| GPT2_LIM CI ANN ALOYSIUS_771_Archive GPT2_LIM JI YONG_851_Archive           | GPT2_LIM CI ANN ALOYSIUS_771_Report GPT2_LIM JI YONG_851_Report           |

| GPT2_LIM JING RUN_884_Archive                                                  | GPT2_LIM JING RUN_884_Report                                                 |
|--------------------------------------------------------------------------------|------------------------------------------------------------------------------|
| GPT2_LIM JUN ZHAN_890_Archive                                                  | GPT2_LIM JUN ZHAN_890_Report                                                 |
| GPT2_LIM SHAU SHEE_975_Archive                                                 | GPT2_LIM SHAU SHEE_975_Report                                                |
| GPT2_LIM SI HAN GAVIN_446_Archive                                              | GPT2_LIM SI HAN GAVIN_446_Report                                             |
| GPT2_LIM ZI JING_395_Archive                                                   | GPT2_LIM ZI JING_395_Report                                                  |
| GPT2_LIU BOREN LAWRENCE_737_Archive                                            | GPT2_LIU BOREN LAWRENCE_737_Report                                           |
| GPT2_LOK WEI XIONG_376_Archive                                                 | GPT2_LOK WEI XIONG_376_Report                                                |
| GPT2_LOKE JING JIE EVAN_701_Archive                                            | GPT2_LOKE JING JIE EVAN_701_Report                                           |
| GPT2_LOKHANDWALA ALIASGAR_001_Archive                                          | GPT2_LOKHANDWALA ALIASGAR_001_Report                                         |
| GPT2_LOO ZHONG EN SAMUEL_434_Archive                                           | GPT2_LOO ZHONG EN SAMUEL_434_Report                                          |
| GPT2_LOUISA CHUNG YU_654_Archive                                               | GPT2_LOUISA CHUNG YU_654_Report                                              |
| GPT2_LOW YI JIE SHERYL_847_Archive                                             | GPT2_LOW YI JIE SHERYL_847_Report                                            |
| GPT2_LYU JINHAN_276_Archive                                                    | GPT2_LYU JINHAN_276_Report                                                   |
| GPT2_MADHU KUMAR ANANNYA_082_Archive                                           | GPT2_MADHU KUMAR ANANNYA_082_Report                                          |
| GPT2_MADNANI KHUSHI_069_Archive                                                | GPT2_MADNANI KHUSHI_069_Report                                               |
| GPT2_MANDE NEIL ASHVINIKUMAR_848_Archive                                       | GPT2_MANDE NEIL ASHVINIKUMAR_848_Report                                      |
| GPT2_MANOJ AMIT_044_Archive                                                    | GPT2_MANOJ AMIT_044_Report                                                   |
| GPT2_MARCUS LEE WEI_368_Archive                                                | GPT2_MARCUS LEE WEI_368_Report                                               |
| GPT2_MARCUS LIM_380_Archive                                                    | GPT2_MARCUS LIM_380_Report                                                   |
| GPT2_MIRA KIM FABE_490_Archive                                                 | GPT2_MIRA KIM FABE_490_Report                                                |
| GPT2_MOON JOONCHUL_280_Archive                                                 | GPT2_MOON JOONCHUL_280_Report                                                |
| GPT2_MOON SI HO_044_Archive                                                    | GPT2_MOON SI HO_044_Report                                                   |
| GPT2_MUHAMMAD ASYRAF BIN ABDUL_606_Archive                                     | GPT2_MUHAMMAD ASYRAF BIN ABDUL_606_Report                                    |
| GPT2_MUHAMMAD HAZIQ BIN ABDUL _198_Archive                                     | GPT2_MUHAMMAD HAZIQ BIN ABDUL _198_Report                                    |
| GPT2_MUN JIA HAO_276_Archive                                                   | GPT2_MUN JIA HAO_276_Report                                                  |
| GPT2_MUTHUMANIKANTAN PAVITHRA_472_Archive                                      | GPT2_MUTHUMANIKANTAN PAVITHRA_472_Report                                     |
| GPT2_NANDHINI NACHIAPPAN_089_Archive                                           | GPT2_NANDHINI NACHIAPPAN_089_Report                                          |
| GPT2_NATARAJAN SRINIVASAN_636_Archive                                          | GPT2_NATARAJAN SRINIVASAN_636_Report                                         |
| GPT2_NATHAN BONG NENG QUAN_650_Archive                                         | GPT2_NATHAN BONG NENG QUAN_650_Report                                        |
| GPT2_NEHRU KABILLAN_803_Archive                                                | GPT2_NEHRU KABILLAN_803_Report                                               |
| GPT2_NEO KUANG YI JAYDEN_533_Archive                                           | GPT2_NEO KUANG YI JAYDEN_533_Report                                          |
| GPT2_NG YEE SUNG_664_Archive GPT2_NG ZHI HAO CLEMENT_642_Archive               | GPT2_NG YEE SUNG_664_Report GPT2_NG ZHI HAO CLEMENT_642_Report               |
| GPT2_NG ZHI HOU_719_Archive                                                    | GPT2_NG ZHI HOU_719_Report                                                   |
| GPT2_NG ZI LE_452_Archive                                                      | GPT2_NG ZI LE_452_Report                                                     |
| GPT2_NGUYEN DUC KHOA_243_Archive                                               | GPT2_NGUYEN DUC KHOA_243_Report                                              |
| GPT2_NGUYEN TAN KIET_449_Archive                                               | GPT2_NGUYEN TAN KIET_449_Report                                              |
| GPT2_ONG JUNYIN JUSTIN_114_Archive                                             | GPT2_ONG JUNYIN JUSTIN_114_Report                                            |
| GPT2_ONG LI KIAT ISAAC_158_Archive                                             | GPT2_ONG LI KIAT ISAAC_158_Report                                            |
| GPT2_ONG MING YU_773_Archive                                                   | GPT2_ONG MING YU_773_Report                                                  |
| GPT2_OOI WEN YUE_036_Archive                                                   | GPT2_OOI WEN YUE_036_Report                                                  |
| GPT2_PAI SHASHANK LALITKUMAR_208_Archive                                       | GPT2_PAI SHASHANK LALITKUMAR_208_Report                                      |
| GPT2_PAN QI YUAN KEVIN_471_Archive                                             | GPT2_PAN QI YUAN KEVIN_471_Report                                            |
| GPT2_PATEL SIDDHARTH BUNTYBHAI_689_Archive                                     | GPT2_PATEL SIDDHARTH BUNTYBHAI_689_Report                                    |
| GPT2_PEMMASANI PRABAKARAN RASH_248_Archive                                     | GPT2_PEMMASANI PRABAKARAN RASH_248_Report                                    |
| GPT2_PENG BOHAO_755_Archive                                                    | GPT2_PENG BOHAO_755_Report                                                   |
| GPT2_PLOGNER OSKAR NILS ALFRED__Archive                                        | GPT2_PLOGNER OSKAR NILS ALFRED__Report                                       |
| GPT2_RAJASEKARAN KRITHIKA_539_Archive                                          | GPT2_RAJASEKARAN KRITHIKA_539_Report                                         |
| GPT2_RAMESH GOKUL SAI_662_Archive                                              | GPT2_RAMESH GOKUL SAI_662_Report                                             |
| GPT2_RAVI DEEPAK_148_Archive                                                   | GPT2_RAVI DEEPAK_148_Report                                                  |
| GPT2_REYAS MOHIDEEN FAWAZ_413_Archive                                          | GPT2_REYAS MOHIDEEN FAWAZ_413_Report                                         |
| GPT2_REYES JUSTIN NOEL DOTIMAS_680_Archive GPT2_ROYSTON CHEW YI DE_430_Archive | GPT2_REYES JUSTIN NOEL DOTIMAS_680_Report GPT2_ROYSTON CHEW YI DE_430_Report |

| GPT2_RUBENNISHWARAAN KARUPPIAH_691_Archive                                           | GPT2_RUBENNISHWARAAN KARUPPIAH_691_Report                           |
|--------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| GPT2_RYAN PRIYANK SUNJAI DHAS_098_Archive                                            | GPT2_RYAN PRIYANK SUNJAI DHAS_098_Report                            |
| GPT2_RYAN VERNADOS_024_Archive                                                       | GPT2_RYAN VERNADOS_024_Report                                       |
| GPT2_SAM LEE HUEY SAMANTHA_617_Archive                                               | GPT2_SAM LEE HUEY SAMANTHA_617_Report                               |
| GPT2_SAMPATHAWADUGE NILANA IMA_372_Archive                                           | GPT2_SAMPATHAWADUGE NILANA IMA_372_Report                           |
| GPT2_SELVAM ANAND_304_Archive                                                        | GPT2_SELVAM ANAND_304_Report                                        |
| GPT2_SELVASINGH OLIVER JOSEPH_070_Archive                                            | GPT2_SELVASINGH OLIVER JOSEPH_070_Report                            |
| GPT2_SEOW CHENG SI_802_Archive                                                       | GPT2_SEOW CHENG SI_802_Report                                       |
| GPT2_SHEN YUNCONG_412_Archive                                                        | GPT2_SHEN YUNCONG_412_Report                                        |
| GPT2_SHUKLA ATHARVA_251_Archive                                                      | GPT2_SHUKLA ATHARVA_251_Report                                      |
| GPT2_SINGARAM KARTHIKEYAN_091_Archive                                                | GPT2_SINGARAM KARTHIKEYAN_091_Report                                |
| GPT2_SPENCER TING TIEW YU_254_Archive                                                | GPT2_SPENCER TING TIEW YU_254_Report                                |
| GPT2_SRIRAM ANUPAMA_775_Archive                                                      | GPT2_SRIRAM ANUPAMA_775_Report                                      |
| GPT2_STEFAN CHOO BIN HAO_098_Archive                                                 | GPT2_STEFAN CHOO BIN HAO_098_Report                                 |
| GPT2_STEVEN MARCUS KHOO TENG E_978_Archive                                           | GPT2_STEVEN MARCUS KHOO TENG E_978_Report                           |
| GPT2_SUA ISAAC_138_Archive                                                           | GPT2_SUA ISAAC_138_Report                                           |
| GPT2_TAN BOON LEONG_443_Archive                                                      | GPT2_TAN BOON LEONG_443_Report                                      |
| GPT2_TAN JIN XIANG_014_Archive                                                       | GPT2_TAN JIN XIANG_014_Report                                       |
| GPT2_TAN KAI SHENG_237_Archive                                                       | GPT2_TAN KAI SHENG_237_Report                                       |
| GPT2_TAN SWEE KIAT_110_Archive                                                       | GPT2_TAN SWEE KIAT_110_Report                                       |
| GPT2_TAN YONG XIANG_557_Archive                                                      | GPT2_TAN YONG XIANG_557_Report                                      |
| GPT2_TAN YU JUN_046_Archive                                                          | GPT2_TAN YU JUN_046_Report                                          |
| GPT2_TEE REN WEY_983_Archive                                                         | GPT2_TEE REN WEY_983_Report                                         |
| GPT2_THAM YOU JIE_411_Archive                                                        | GPT2_THAM YOU JIE_411_Report                                        |
| GPT2_THOW JIA LE CALEB_252_Archive                                                   | GPT2_THOW JIA LE CALEB_252_Report                                   |
| GPT2_TIFFANY HENG_973_Archive                                                        | GPT2_TIFFANY HENG_973_Report                                        |
| GPT2_TIU SHENG YANG_815_Archive                                                      | GPT2_TIU SHENG YANG_815_Report                                      |
| GPT2_TOH JIAN BIN_754_Archive                                                        | GPT2_TOH JIAN BIN_754_Report                                        |
| GPT2_TOH SIEW HEAN_512_Archive                                                       | GPT2_TOH SIEW HEAN_512_Report                                       |
| GPT2_TRAN HOANG KHANG_579_Archive                                                    | GPT2_TRAN HOANG KHANG_579_Report                                    |
| GPT2_TRICIA LIM ZI NING_575_Archive                                                  | GPT2_TRICIA LIM ZI NING_575_Report                                  |
| GPT2_TRIPATHI ANOUSHKA_062_Archive                                                   | GPT2_TRIPATHI ANOUSHKA_062_Report                                   |
| GPT2_TRISTAN LAU YUE SHEN_950_Archive GPT2_TRUONG PHI HUNG_402_Archive               | GPT2_TRISTAN LAU YUE SHEN_950_Report                                |
|                                                                                      | GPT2_TRUONG PHI HUNG_402_Report                                     |
| GPT2_VISHWAK NATTAMAI_645_Archive                                                    | GPT2_VISHWAK NATTAMAI_645_Report                                    |
| GPT2_VISHWANATH ANNANYA_037_Archive                                                  | GPT2_VISHWANATH ANNANYA_037_Report                                  |
| GPT2_VITO BENEDICT HALIM_783_Archive                                                 | GPT2_VITO BENEDICT HALIM_783_Report                                 |
| GPT2_VIVEKAN KATHIRAVAN_236_Archive                                                  | GPT2_VIVEKAN KATHIRAVAN_236_Report                                  |
| GPT2_VUPPU NAGARAJAN YUVEN RAA_686_Archive GPT2_WAHLGREN HANNA CHRISTINA__ch_Archive | GPT2_VUPPU NAGARAJAN YUVEN RAA_686_Report                           |
|                                                                                      | GPT2_WAHLGREN HANNA CHRISTINA__ch_Report                            |
| GPT2_WANG QICHEN_536_Archive                                                         | GPT2_WANG QICHEN_536_Report                                         |
| GPT2_WILL CHIN JUN YU_806_Archive                                                    | GPT2_WILL CHIN JUN YU_806_Report GPT2_WONG WEI LUN_308_Report       |
| GPT2_WONG WEI LUN_308_Archive                                                        |                                                                     |
| GPT2_XANDER LIM_790_Archive                                                          | GPT2_XANDER LIM_790_Report                                          |
| GPT2_XU RUIJIE_009_Archive                                                           | GPT2_XU RUIJIE_009_Report                                           |
| GPT2_YEW SU YI_674_Archive                                                           | GPT2_YEW SU YI_674_Report                                           |
| GPT2_YONG CHUAN ONN_697_Archive                                                      | GPT2_YONG CHUAN ONN_697_Report                                      |
| GPT2_YU YIFAN_811_Archive                                                            | GPT2_YU YIFAN_811_Report                                            |
| GPT2_YUE WEI AN JOSHUA_221_Archive GPT2_ZEPH TANG ZHENKAI_461_Archive                | GPT2_YUE WEI AN JOSHUA_221_Report GPT2_ZEPH TANG ZHENKAI_461_Report |
| GPT2_ZHAO ZEYU_093_Archive                                                           | GPT2_ZHAO ZEYU_093_Report                                           |
| GPT2_ZOE TAY HUI EN_198_Archive                                                      | GPT2_ZOE TAY HUI                                                    |
| GPT2_ZOU YUYANG_145_Archive                                                          | EN_198_Report GPT2_ZOU YUYANG_145_Report                            |

-------------------------------------------------------------------------------------

## FINAL CHECKLIST FOR GPT-2:

Grading is done only once. Re-grading due to not meeting the checklist below are not accepted.

- [ ] □ I have used the exact and correct numbers from my student matriculation number.

- [ ] □ I have named the submitted archive, and pdf report, according to the given template.

- [ ] □ The submitted archive is less than 5 MB (Delete ".sim" folder if more than 5 MB. Penalty of up to 10% apply if ≥5 MB).

- [ ] □ I confirm that the two separate submissions (archive, and report) are the correct / latest versions.

- [ ] □ I have downloaded both (archive, and report) submissions and confirmed that they were properly uploaded to canvas.

- [ ] □ I confirm that the grader can run the simulation without errors.

- [ ] □ I have carefully verified that the report layout and requirements listed in SUBTASK D have been followed.