## LAB VENUE:

## DIGITAL ELECTRONICS LAB @ E4-03-07

## LAB SCHEDULE:

| Attend your official lab session. Swapping is not allowed. - Week   | Attend your official lab session. Swapping is not allowed. - Activity   | Attend your official lab session. Swapping is not allowed. - Graded Component (60%)   |
|---------------------------------------------------------------------|-------------------------------------------------------------------------|---------------------------------------------------------------------------------------|
| Week 1 10 Aug 2026                                                  | No Scheduled Lab                                                        |                                                                                       |
| Week 2 17 Aug 2026                                                  | No Scheduled Lab                                                        |                                                                                       |
| Week 3 24 Aug 2026                                                  | Lab 1: Introduction to Vivado                                           | Practice Task (2%) Recommended to complete task in lab 1                              |
| Week 4 31 Aug 2026                                                  | Lab 2: Combinational Circuits                                           | Practice Task (4%) Recommended to complete task in lab 2                              |
| Week 5 7 Sep 2026                                                   | Lab 3: Progress Checkpoint 1/3                                          | Progression Test (Tentatively 5%) Further instructions will be announced on Canvas    |
| Week 6 14 Sep 2026                                                  | Lab 4: Sequential Circuits                                              | Practice Task (Tentatively 7%) To complete task within 1 week                         |
| Recess Week                                                         | No Scheduled Lab                                                        |                                                                                       |
| Week 7 28 Sep 2026                                                  | Lab 5: Project Initiation                                               | Practice Task and Project Proposal (3%) To complete within 1 week                     |
| Week 8 5 Oct 2026                                                   | No Scheduled Lab                                                        |                                                                                       |
| Week 9 12 Oct 2026                                                  | Lab 6: Project Work                                                     |                                                                                       |
| Week 10 19 Oct 2026                                                 | Lab 7: Progress Checkpoint 2/3                                          | Progression Test (12%) Further instructions will be announced on Canvas               |
| Week 11 26 Oct 2026                                                 | No Scheduled Lab                                                        |                                                                                       |
| Week 12 2 Nov 2026                                                  | Lab 8: Progress Checkpoint 3/3                                          | Project Assessment (27%) Further details will be given in the Project Manual          |
| Week 13 9 Nov 2026                                                  | No Scheduled Lab                                                        |                                                                                       |

Progression Tests have the following characteristics:

- Requires the knowledge and debugging skills from the previous Practice Tasks.
- No usage of A.I.
- No usage of VS Code.
- Limited time: No trial-and-error type of coding. Think before you carefully code!

## EE2026: DIGITAL DESIGN

## Academic Year 2026-2027, Semester 1

## LAB 1: Quick Start Guide to Vivado 2025.2, Basys 3 Development Board, and Verilog HDL

## HARDWARE COMPATIBILITY:

- Vivado 2025.2 allows for Basys3 hardware connection only on Intel or AMD x86/x64 based processors, and using Windows. It will not allow Basys3 hardware connection on ARM based processors (Such as Apple's M1, M2, M3 etc. processors).
- Virtualisation of windows, or non-English character (Eg. Chinese version of windows) Windows, generally have issues with the Basys3 hardware connection.

## FOR ALL EE2026 LAB AND PROJECT SESSIONS:

- You are strongly encouraged to bring to lab, your own Windows laptop with Vivado 2025.2 already installed. You may still use the desktop PC in lab if you do not have a windows laptop (With x86/x64 processors) that can be brought to lab.
- Use the D:\MyWork folder for your work if you are using the lab PC. You are required to delete all folders within the D:\MyWork folder before starting your lab session, and when you leave the lab.

## OVERVIEW:

Using a simple Boolean design problem, an introductory approach to the Vivado software used in EE2026 will be covered. In this lab:

- An introduction to very basic Verilog HDL (Hardware Description Language) is provided.
- The overall process flow of designing, synthesising, simulating and implementing a program is covered.
- Programming Digilent's Basys 3 development board, which features an FPGA from Xilinx's Artix-7 family, is illustrated.

## GRADED PRACTICE TASK [CANVAS SUBMISSION REQUIRED]:

It is required to have the Vivado software already installed on your English-Based Windows laptop with Intel / AMD processors before the lab session. The Graded Practice Task for lab 1 (GPT-1) is required to be started during your first lab session and preferably completed during the lab session.

Details for GPT-1 are available at the end of this lab manual.

## VIVADO SETUP:

The Vivado 2025.2 software is already installed on the computers in the Digital Electronics Lab, and are ready for immediate usage. Some quick guidelines on installing the required software for EE2026 on your personal computer is provided in this section.

## Software Download:

AMD Unified Installer for FPGAs &amp; Adaptive SoCs 2025.2 [Nov 20, 2025]

Link: https://www.amd.com/en/support/downloads/adaptive-socs-and-fpgas/development-tools/2025-2.html

<!-- image -->

You may choose either one of the two installers. Take note of the file size and the large amount of time you may require (One takes a long time to install while the other one takes a long time to download)!

Warning: Do not use other versions of the software. Only the Vivado 2025.2 Windows OS version should be used. Compatibility issues will occur with other versions of the software, and assessment of your project may not be possible.

## Software Installation

During the installation, select the following options:

<!-- image -->

<!-- image -->

## Software License

License the software by using the Vivado License Manager 2025.2:

Vivado License Manager 2025.2

File Help

AMDA

Vivado

Get License

Obtain License

Set Proxy

Load License

Manage License Search Paths

Manage License

A

View License Status

①View Host Information

View System Information

View Current Tool Version Limit

License Diagnostics

. Perform Diagnostics

□

×

License Manager

Select one of the following options

Start Now! 30 Day Trial Obtain License

Get My Full or Purchased Certificate-Based License

Connect Now

Description of the above selected option

This selection will help you get your full or purchased

Certificate-based licenses and start using the AMD Adaptive

SoCs and FPGAs design tools. You will be taken to the

product licensing website where, if you have full or

purchased licenses, you will see an account drop-down menu.

In the appropriate license account, you can generate a

license for the software and IPs you have purchased. After

generation, the license file is sent to your e-mail. Once

you have saved this file to your machine, click on the Load

License selection to copy your .lic file to a default

location.

Certificate Based Licenses

<!-- image -->

## DESCRIPTION OF THE SIMPLE BOOLEAN DESIGN TASK

The following task is required to be implemented on the Basys 3 development board:

- When switch A turns on, only LED1 lights up.
- When switch B turns on, only LED2 lights up.
- When both switches A and B turn on, LED1, LED2, and LED3 light up.

## UNDERSTANDING | TASK 1

Complete the truth table for the simple boolean design task:

|   INPUT - A |   INPUT - B | OUTPUT - LED1   | OUTPUT - LED2   | OUTPUT - LED3   | MINTERM   |
|-------------|-------------|-----------------|-----------------|-----------------|-----------|
|           0 |           0 |                 |                 |                 | 𝐴̅ 𝐵ത     |
|           0 |           1 |                 |                 |                 | 𝐴̅ 𝐵      |
|           1 |           0 |                 |                 |                 | 𝐴𝐵ത       |
|           1 |           1 |                 |                 |                 | 𝐴𝐵        |

## Deriving an SOP Boolean Equation for the Design Task

Given any truth table with any number of input variables, the sum-of-products (SOP) or product-of-sums (POS) form may be used to write out a Boolean equation for each output variable. Let us use the canonical SOP form for LED1:

<!-- formula-not-decoded -->

<!-- image -->

## UNDERSTANDING | TASK 2

Work out the canonical SOP Boolean equations for LED2 and LED3.

## Illustrating Logic Expressions by Using a Schematic of Gates

The Boolean equations for LED1, LED2, and LED3, can be implement by using: 2 NOT gates, 3 AND gates, 2 OR gates

<!-- image -->

## Verilog Hardware Description and FPGA Implementation

The Vivado software is an integrated design environment, among which we will be introducing the following:

- HDL Coding.
- Simulation of the design.
- Synthesis of the codes.
- Implementation of the design to a target FPGA.
- Programming an FPGA with a bitstream.

The remaining part of this lab manual will now briefly show the general steps required to go from the design task till programming the FPGA on the Basys 3 development board.

## INTRODUCTORY QUICK START GUIDE TO XILINX'S VIVADO 2018.2 SOFTWARE

During your lab session, your EE2026 lab assistants may provide you helpful hints on the usage of the Vivado 2025.2 software, beyond the most basic things that are described in this section.

## Creating a New Verilog Project in Vivado

- Open the Vivado 2025.2 software.
- Create Project, then Next.
- Enter a Project name and Project Location. Ensure that the Project name and complete Project location for your project folder does not have any spaces, special characters, non-English characters, and that your Project name does not start with a number.
- Select RTL Project (Sub-options should be unchecked).
- Create File. File type is Verilog. File name example: simple\_boolean.
- In Add constraints, click on Next without any changes.
- Ensure the correct chip is used. EE2026 uses the following FPGA chip:

## xc7a35tcpg236-1

<!-- image -->

- In the final summary window, click Finish to create the project.
- Create a module based on the inputs and outputs of the simple Boolean design task:

<!-- image -->

## Writing Verilog HDL Code

Open the module that has been created by double clicking on it in the Sources window

## UNDERSTANDING | TASK 3

Code the behaviour of the module by converting the SOP expressions for LED1, LED2, and LED3 to the Verilog equivalent. The codes are to be inserted between "module" and "endmodule".

| Common Operators   | Common Operators   | Verilog Representation   |
|--------------------|--------------------|--------------------------|
| OR                 | 𝐀+𝐁                | &#124;                   |
| AND                | 𝐀𝐁                 | &                        |
| NOT                | 𝐀ഥ                 | ~                        |
| XOR                | 𝐀⊕𝐁                | ^                        |

<!-- image -->

<!-- image -->

The assign statement causes the left-hand side of the expression to be updated every time there is a change on the right-hand side of the expression. It is called a continuous assignment statement, describing combinational logic whereby the output on the left is a function of current inputs on the right. All the assign statements run concurrently.

After writing the codes for LED1, LED2 and LED3, in the Flow Navigator (Left side window) expand RTL ANALYSIS: Open Elaborated Design, then select Schematic. The Register Transfer Level (RTL) schematic of the design will appear.

## UNDERSTANDING | TASK 4

What similarities and differences do you notice between the RTL schematic and the schematic from the previous section?

<!-- image -->

## Testbench and Behavioural Simulation

A testbench is an HDL module that is used to test another module:

- In the Flow Navigator, click on PROJECT MANAGER -&gt; Add Sources -&gt; Add or create simulation sources.
- Create File and provide a Verilog file name (Example: test\_simple\_boolean).
- In the subsequent Define Module window, provide a Module name (Example: test\_my\_control\_module).
- Do not input any I/O Port Definitions, and click on OK to finish creating the simulation module template.

In the simulation file, write the code as shown below:

<!-- image -->

In the Flow Navigator window, click on SIMULATION -&gt; Run Simulation -&gt; Run Behavioural Simulation. A noticeable waveform pattern may not be seen by default. From the menu, select View  Zoom Fit, or press Ctrl+0 How do the waveforms show that your design is indeed working as desired?

<!-- image -->

Suggestion: Do not save the simulation window waveform, as this may consume a large amount of storage space.

## Synthesis

Logic synthesis transforms HDL code into an optimised set of logic gates to reduce the amount of hardware, and to efficiently perform the intended function.

- Right-click on your Verilog design source file and select Set as Top. (This is disabled if the file is already the top module) When there are multiple design and simulation modules, the "Set as Top" option selects the design, or simulation, modules to be considered when performing the different stages of the project flow.
- In the Flow Navigator window, click on SYNTHESIS -&gt; Run Synthesis and wait for its completion. The Project Status Bar at the top right provides an indication of the ongoing progress.
- In the Flow Navigator window, click on SYNTHESIS -&gt; Open Synthesized Design -&gt; Schematics to see the following:
- Click on "LUT2" to select it. The Cell Properties allows the truth table for this LUT (AND gate in this example) to be viewed:

<!-- image -->

<!-- image -->

## UNDERSTANDING | TASK 5

Compare the two schematics: Non-optimised (Schematics from RTL Analysis) and optimised (Schematics from Synthesis) and. How is this optimised circuit equivalent to the SOP equations of the simple boolean design task?

<!-- image -->

<!-- image -->

## Design Constraints

Design constraints, such as physical I/O pin mapping, must be defined before doing an implementation:

- In the Flow Navigator, click on PROJECT MANAGER -&gt; Add Sources -&gt; Add or create constraints.
- Create File and provide an XDC (Xilinx Design Constraints) file name (Example: my\_basys3\_constraints).
- Open the my\_basys3\_constraints.xdc file from the Sources window.
- A template, known as the Basys3\_Master.xdc is provided on CANVAS. Open that template using a basic text editor, such as notepad. Copy all the contents of the template to the my\_basys3\_constraints in Vivado.
- Link all signals (A, B, LED1, LED2, LED3) of your design to some physical pins of the FPGA, by making these changes:

<!-- image -->

## Implementation, Bitstream Generation and Program Download

- In the Flow Navigator, click on IMPLEMENTATION -&gt; Run Implementation and wait for its completion.
- In the Flow Navigator, click on PROGRAM AND DEBUG -&gt; Generate Bitstream and wait for its completion.

Before using your Basys 3 development board, and to prevent potential damage to it, take note of the following recommendations and warnings to extend the longevity of the device:

⚠ Make sure the Basys 3 development board is powered OFF by placing SW16 (Top Left corner of the board) in the OFF position before connection to/removal from the USB port of the computer.

⚠ The chips on the board are electrostatic sensitive. Avoid touching them. Handle the board by the edges to prevent damage.

⚠ Make sure the board is not in contact with any metal components, whether above or below. Do not place any liquid sources near the FPGA board.

<!-- image -->

- Turn on the power to the Basys3 development board by setting SW16 to ON
- In the Flow Navigator, click on PROGRAM AND DEBUG -&gt; Open Hardware Manager -&gt; Open target -&gt; Auto Connect
- After connection, click on PROGRAM AND DEBUG -&gt; Open Hardware Manager -&gt; Program Device -&gt; xc7a35t\_0
- By default, if the bitstream was successfully generated, the path name for the Bitstream file is automatically provided
- Click on Program. You may now test your design on the Basys3 by toggling SW0 and SW1

## BEFORE STARTING ON GPT-1:

Each student has a personalised requirement based on student matriculation number. Carefully write down and use your exact number, as mistakes in the student matriculation number are not accepted. Appeals due to wrong number used for your personalised requirement will be rejected.

<!-- image -->

Students are required to carefully read all the assignment requirements, and to enhance their understanding by looking at the example.

Marks are given for using your correct student matriculation number, and grading is done only once. Re-submissions, late submissions, or updates, even if very simple or minor, are not accepted after the grading.

## GRADED PRACTICE TASK 1 (GPT-1)

Complete as much as possible, in ONE working bitstream for this whole assignment. It is much better to have a working program with some completed functionalities, instead of submitting a program without a working bitstream (No marks given).

## IMPORTANT CHARACTERS

In this assignment, these are the important characters to note from your student matriculation number:

- The rightmost alphabet of your student matriculation number (Initialistion)
- The five rightmost numerical values of your student matriculation number (Subtask B)
- The 1 st rightmost numerical value of your student matriculation number (Subtask B)

## INITIALISATION

When the program starts, all 16 active-high switches (SW0 to SW15) are in the OFF position. All 16 active-high LEDs (LD0 to LD15) are also OFF. The seven segment displays must automatically display the rightmost alphabet of your student matriculation number on all the 4 (four) anodes of the 7-segment displays. The character must be displayed exactly as indicated (Decimal point is OFF):

<!-- image -->

## SUBTASK A

Consider the 10 (ten) switches SW0 to SW9 (Ignore SW10 to SW15). Whenever any of these 10 switches are ON, the corresponding LED LDX, where X is a number ranging from 0 to 9, must be ON. (For example, if SW0 is ON, then LD0 must be ON. If SW3, SW7 and SW9 are ON, then LD3, LD7 and LD9 must be ON.) Do not put constraint to SW10 to SW15, and LD10 to LD15.

## SUBTASK B

Continuing from SUBTASK A, create your personal student matriculation number password based on the five rightmost numerical values of your student matriculation number.

These five digits (May be less than five digits if you have duplicate numbers) will represent the switches that need to be ON, while all the other switches between SW0 to SW9 must be OFF, to be considered a correct password. Whenever the password is wrong, all the 4 (four) anodes of the 7-segment displays show the rightmost alphabet. (For example, if all the ten switches SW0 to SW9 are turned ON, that is considered as a wrong password)

Whenever the password entered by the user is the correct password, then instead of all the 4 (four) anodes of the 7-segment displays showing your rightmost alphabet, only specific anodes of the 7-segment displays must show that alphabet. The specific anodes on which the character should be displayed is dependent on the 1 st rightmost numerical value of your student matriculation number, as indicated in the table below:

| 1 st Rightmost Numerical Value   | Anode AN3   | Anode AN2   | Anode AN1   | Anode AN0   |
|----------------------------------|-------------|-------------|-------------|-------------|
| 0 , 1                            | ON          | OFF         | OFF         | ON          |
| 2 , 3                            | ON          | OFF         | ON          | OFF         |
| 4 , 5                            | ON          | ON          | OFF         | OFF         |
| 6 , 7                            | OFF         | ON          | ON          | OFF         |
| 8 , 9                            | OFF         | ON          | OFF         | ON          |

Note: Marks will not be given if wrong switch constraints are used! If your student matriculation number password has a 0, then it refers to SW0. If your student matriculation number password has a 1, then it refers to SW1. If your student matriculation number password has a 2, then it refers to SW2 etc…Ensure you have noted down your 5 rightmost numerical values of your student matriculation number accurately for the password.

## SUGGESTIONS

- Create a new Vivado project for this assignment, instead of continuing from your previous Vivado project.
- This assignment can be fully completed by using SOP / POS expressions.
- This is a warm-up exercise. It is not recommended to use contents not taught in this lab session.
- Simulations are not required in the submission, but you are encouraged to practice them!

## GETTING STARTED WITH THE SEVEN-SEGMENT DISPLAYS

<!-- image -->

Each segment behaves like an LED, and each controlled by the pin indicated in the Basys3\_Master.xdc:

```
#7 Segment Display
```

```
set_property -dict PACKAGE PIN W7 IOSTANDARD LVCMOS33 } [get_ports seg_A] set_property -dict PACKAGE PIN W6 IOSTANDARD LVCMOS33 } [get_ports seg_B] set_property -dict PACKAGE PIN U8 IOSTANDARD LVCMOS33 } [get_ports seg_C] set_property -dict PACKAGE PIN V8 IOSTANDARD LVCMOS33 } [get_ports seg_D] set_property -dict PACKAGE PIN U5 IOSTANDARD LVCMOS33 [get_ports seg_E] set_property -dict PACKAGE PIN V5 IOSTANDARD LVCMOS33 } [get ports seg_F] set_property -dict PACKAGE PIN U7 IOSTANDARD LVCMOS33 } [get ports seg_G] set_property -dict PACKAGE PIN V7 [Oo   ] {  DP
```

Each anode is like an output that needs to be turned ON, and each is controlled by the pin indicated in the Basys3\_Master.xdc:

<!-- image -->

- In your constraint file, it is compulsory to put constraints to the 8 segments (7 segments + decimal point) of the sevensegment display, and to the 4 anodes of the seven-segment display.
- Segments or anodes that need to be OFF must explicitly be assigned a value of '1' in your Verilog codes. Do not leave the values "floating"! For example, if the 'dot' segment is required to be off, assign a value of '1' to it.

The circuit for the seven-segment displays on the Basys3 board is such that:

- A value of '1' turns OFF the segment / anode
- A value of '0' turns ON the segment / anode

What devices / gates would you use to turn a '1' into '0', or vice-versa?

## EXAMPLE OF GPT-1 BEHAVIOUR:

If your student matriculation number is A0159089Y, then:

1 st rightmost numerical value:

9 (Means only AN2 and AN0 will be ON if password is correct)

Five rightmost numerical values: 59089 (Means password is SW0, SW5, SW8, SW9)

Rightmost alphabet:

Y

<!-- image -->

## CANVAS SUBMISSION INSTRUCTIONS

- Ensure that your bitstream has been successfully generated and tested on your Basys 3 development board BEFORE archiving your Vivado workspace for CANVAS upload.
- It is compulsory to archive your project in a compressed form without any saved simulation waveforms. Follow the instructions given in the pdf: "Archive Project in Vivado 2025.2". The archive size should not exceed 5 MB in size for any lab assignments. If the archive size exceeds, ensure that there is no ".sim" folder in your Vivado project folder before archiving.
- After following the instructions in "Archive Project in Vivado 2025.2", rename your project archive as indicated in the appendix of this lab manual.
- Upload to CANVAS EE2026 -&gt; Assignments -&gt; Lab 1 -&gt; GPT-1 Submission (On-Time).
- Download your CANVAS archive after uploading. Click and drag the single folder within that archive to desktop, and then open the Vivado project (.xpr) in that extracted folder to see if it can be opened. You can ignore "out-of-date" warnings. Check if you can also run your bitstream correctly. No project file and no working bitstream is equivalent to losing all marks.
- GPT-1 is recommended to be completed within the lab session itself. You are however allowed to upload to CANVAS without penalties before Monday 31 st August 2026, 6:00 A.M. Avoid planning to upload during the additional grace period of 2 hours. (Grace period is for last-minute cases, such as due to slow internet, wrong uploads etc.)
- The late submission folder closes 1 week after the original deadline. Late submissions are not graded if submissions are found in the on-time folder. Do not submit in the late submission folder if you have already submitted in the on-time folder, as it will be ignored and only the on-time submission will be graded. The late submission folder will be located at: CANVAS EE2026 -&gt; Assignments -&gt; Lab 1 -&gt; GPT-1 Submission (Late).
- Re-submissions, late submissions, or updates, even if very simple or minor, are not accepted after your original submission has been graded.
- Submissions through emails, file sharing programs, or links, are not accepted. Submissions must be officially submitted to, and downloadable from, Canvas in the correct on-time or late folder.

## Plagiarism is penalised with a 100% penalty for all SOURCES and RECIPIENTS

All past and future submissions, and marks, will be reviewed in greater detail, for any person found to have plagiarised

ALL THE SUBMISSION INSTRUCTIONS LISTED ABOVE WILL AFFECT YOUR GRADES!

\_ \_ \_ \_ \_ \_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_\_ \_ \_ \_ \_ \_

## GRADING PROCESS

Submissions not following all the CANVAS SUBMISSION INSTRUCTIONS (listed above) will not be graded immediately, and they will instead be reviewed towards the end of the semester. You will not be able to see your submission results during the lab sessions in such situations.

## APPENDIX (COMPULSORY renaming just before CANVAS upload):

It is compulsory to rename your project archive just before the CANVAS upload, as listed in the table below.

Do not change any other part of the naming. Simply copy the naming from the table below, and paste it while renaming your project archive. Penalties will be incurred if your submission cannot be found according to the exact naming template below.

CANVAS may automatically add a suffix (Example. "-1", "-2", "-3" etc.) at the end of the filename if you submit multiple files. That is acceptable and we will grade the latest file submitted within that on-time folder.

| Name                                     | Archive Naming (.xpr.zip and .zip accepted)                                |
|------------------------------------------|----------------------------------------------------------------------------|
| AARON CHIN JIN HAO                       | GPT1_AARON CHIN JIN HAO_163_Archive                                        |
| ADI RAMANLAL                             | GPT1_ADI RAMANLAL_033_Archive                                              |
| ADVAIT BAGRI                             | GPT1_ADVAIT BAGRI_209_Archive                                              |
| AHMED IMAAD                              | GPT1_AHMED IMAAD_686_Archive                                               |
| ALYCIA YAK SHI YI                        | GPT1_ALYCIA YAK SHI YI_246_Archive                                         |
| AMBAR                                    | GPT1_AMBAR_974_Archive                                                     |
| ANDREW CHONG KIAN WEI                    | GPT1_ANDREW CHONG KIAN WEI_019_Archive                                     |
| ANDREW YAP ZI ZEN                        | GPT1_ANDREW YAP ZI ZEN_117_Archive                                         |
| ARNAV PARAG SALKADE                      | GPT1_ARNAV PARAG SALKADE_052_Archive                                       |
| ARORA JITISHA                            | GPT1_ARORA JITISHA_189_Archive                                             |
| ARUN PANCHAPAKESAN IYER                  | GPT1_ARUN PANCHAPAKESAN IYER_842_Archive                                   |
| ATHARVA REGE                             | GPT1_ATHARVA REGE_841_Archive                                              |
| BALAKRISHNAN SHRIKKANTH                  | GPT1_BALAKRISHNAN SHRIKKANTH_980_Archive                                   |
| BARANIKUMAR SARITHA PADMANABAN           | GPT1_BARANIKUMAR SARITHA PADMA_345_Archive                                 |
| BETTS DANIEL AN-ZHE                      | GPT1_BETTS DANIEL ANZHE_421_Archive                                        |
| BHAO TANUSH                              | GPT1_BHAO TANUSH_706_Archive                                               |
| BI JIALIN                                | GPT1_BI JIALIN_083_Archive                                                 |
| BODAPATI VAMSHI KRISHNA                  | GPT1_BODAPATI VAMSHI KRISHNA_405_Archive                                   |
| BRYAN CHUA XIANG YU                      | GPT1_BRYAN CHUA XIANG YU_710_Archive                                       |
| CAI YI HANG                              | GPT1_CAI YI HANG_455_Archive                                               |
| CHAN CHEE HENG                           | GPT1_CHAN CHEE HENG_721_Archive                                            |
| CHANG YICHUN                             | GPT1_CHANG YICHUN_522_Archive                                              |
| CHANG ZI SHYAN, SHERWIN                  | GPT1_CHANG ZI SHYAN SHERWIN_293_Archive                                    |
| CHEN CHENG-SHIH                          | GPT1_CHEN CHENGSHIH_136_Archive                                            |
| CHEN HOK LEONG                           | GPT1_CHEN HOK LEONG_601_Archive                                            |
| CHEN ZHENONG                             | GPT1_CHEN ZHENONG_159_Archive                                              |
| CHEW WAI JUN EVAN                        | GPT1_CHEW WAI JUN EVAN_524_Archive                                         |
| CHIA MING HENG, TITUS                    | GPT1_CHIA MING HENG TITUS_200_Archive                                      |
| CHUA CHOON HSIANG                        | GPT1_CHUA CHOON HSIANG_727_Archive                                         |
| CHUA JINGHAO                             | GPT1_CHUA JINGHAO_532_Archive                                              |
| DARREN TOH QING HONG                     | GPT1_DARREN TOH QING HONG_467_Archive                                      |
| DONGJIN SHIN                             | GPT1_DONGJIN SHIN_719_Archive                                              |
| DOUGLAS ETHAN KWOK                       | GPT1_DOUGLAS ETHAN KWOK_301_Archive                                        |
| DUONG NGHIEP HOANG                       | GPT1_DUONG NGHIEP HOANG_675_Archive                                        |
| EETHAN ZHANG YOU JIE                     | GPT1_EETHAN ZHANG YOU JIE_514_Archive                                      |
| ELYSSA TJIN YI JING                      | GPT1_ELYSSA TJIN YI JING_142_Archive                                       |
| ENZO HO                                  | GPT1_ENZO HO_460_Archive                                                   |
| ERNEST GOH CHIN WEE                      | GPT1_ERNEST GOH CHIN WEE_869_Archive                                       |
| EUGENE QUEK                              | GPT1_EUGENE QUEK_592_Archive                                               |
| GABRIEL YU YAO SOON                      | GPT1_GABRIEL YU YAO SOON_978_Archive                                       |
| GAN SIM RU DAYNA GANGADHAR NANDI GAUTHAM | GPT1_GAN SIM RU DAYNA_051_Archive GPT1_GANGADHAR NANDI GAUTHAM_850_Archive |
| GARG DIVYANSH                            | GPT1_GARG DIVYANSH_042_Archive                                             |

| GARG SANCHIT AMIT                  | GPT1_GARG SANCHIT AMIT_679_Archive                               |
|------------------------------------|------------------------------------------------------------------|
| GLAENNFJORD MILLA LINNEA ASTRID    | GPT1_GLAENNFJORD MILLA LINNEA _gl_Archive                        |
| GLENNON PHUA QING XUN              | GPT1_GLENNON PHUA QING XUN_609_Archive                           |
| GOH ROU HUI ASHLEY                 | GPT1_GOH ROU HUI ASHLEY_439_Archive                              |
| GOPINATHAN MAIYURI                 | GPT1_GOPINATHAN MAIYURI_060_Archive                              |
| GUPTA TANMAY                       | GPT1_GUPTA TANMAY_349_Archive                                    |
| HAN QI-ZE                          | GPT1_HAN QIZE_320_Archive                                        |
| HAN ZHONG DING                     | GPT1_HAN ZHONG DING_590_Archive                                  |
| HENG YONG HEN                      | GPT1_HENG YONG HEN_977_Archive                                   |
| HEU YU HUI                         | GPT1_HEU YU HUI_290_Archive                                      |
| HUANG SHANGYI                      | GPT1_HUANG SHANGYI_564_Archive                                   |
| IAN LEE JIAYI                      | GPT1_IAN LEE JIAYI_769_Archive                                   |
| IFTIKHAR YUHAN BIN IRZAD YUHANIZAN | GPT1_IFTIKHAR YUHAN BIN IRZAD _693_Archive                       |
| ISAAC GOH YONG CHEE                | GPT1_ISAAC GOH YONG CHEE_412_Archive                             |
| JAIN TANMAY                        | GPT1_JAIN TANMAY_216_Archive                                     |
| JANG SEOK KEON                     | GPT1_JANG SEOK KEON_036_Archive                                  |
| JAVIER LEE RUI YANG                | GPT1_JAVIER LEE RUI YANG_587_Archive                             |
| JEREMIAH JAMES                     | GPT1_JEREMIAH JAMES_493_Archive                                  |
| JORDAN RIATONO                     | GPT1_JORDAN RIATONO_175_Archive                                  |
| JOSEFSSON CARL OSCAR WILLEHARD     | GPT1_JOSEFSSON CARL OSCAR WILL_j_Archive                         |
| KANG KIAT YANG                     | GPT1_KANG KIAT YANG_549_Archive                                  |
| KANNI KUMARAN SRISURAJ             | GPT1_KANNI KUMARAN SRISURAJ_081_Archive                          |
| KARAN BONTHA                       | GPT1_KARAN BONTHA_031_Archive                                    |
| KARTHIK SIVASUBRAMANIAN            | GPT1_KARTHIK SIVASUBRAMANIAN_056_Archive                         |
| KARTIKEYAN RONITH                  | GPT1_KARTIKEYAN RONITH_987_Archive                               |
| KARUNANITHI NAVIN ANAND            | GPT1_KARUNANITHI NAVIN ANAND_370_Archive                         |
| KAUSHAL RAJESH                     | GPT1_KAUSHAL RAJESH_862_Archive                                  |
| KHOO KAI JUN                       | GPT1_KHOO KAI JUN_957_Archive                                    |
| KIM DOYEON                         | GPT1_KIM DOYEON_415_Archive                                      |
| KIM TAE-EUN                        | GPT1_KIM TAEEUN_919_Archive                                      |
| KOH KA HOW                         | GPT1_KOH KA HOW_373_Archive                                      |
| KOH LI WEI, OLIVER KOTHARI AADI    | GPT1_KOH LI WEI OLIVER_592_Archive GPT1_KOTHARI AADI_808_Archive |
| KRONHAMN OSCAR LUDVIG              | GPT1_KRONHAMN OSCAR LUDVIG_kr_Archive                            |
| KUMARESAN KUGAPRYAN                | GPT1_KUMARESAN KUGAPRYAN_993_Archive                             |
| KYLE LEE YAO YU                    | GPT1_KYLE LEE YAO YU_663_Archive                                 |
| LAM LOK SANG MATTHEW LUCAS         | GPT1_LAM LOK SANG MATTHEW LUCA_294_Archive                       |
| LAM YAP TING                       | GPT1_LAM YAP TING_341_Archive                                    |
| LAU ZHE WEN                        | GPT1_LAU ZHE WEN_969_Archive                                     |
| LAW SHAO CHONG                     | GPT1_LAW SHAO CHONG_761_Archive                                  |
| LEE CHANG FENG                     | GPT1_LEE CHANG FENG_463_Archive                                  |
| LEE CHEONG WENG JUSTIN             | GPT1_LEE CHEONG WENG JUSTIN_211_Archive                          |
| LEE EE XUAN                        | GPT1_LEE EE XUAN_562_Archive                                     |
| LEE KWAN TZE                       | GPT1_LEE KWAN TZE_762_Archive                                    |
| LEE PEI LING                       | GPT1_LEE PEI LING_692_Archive                                    |
| LEE ZHON CHEN                      | GPT1_LEE ZHON CHEN_758_Archive                                   |
| LEON MATTHEW WEI                   | GPT1_LEON MATTHEW WEI_323_Archive                                |
| LEROY KOH                          | GPT1_LEROY KOH_782_Archive                                       |
| LEW YIK CHIN                       | GPT1_LEW YIK CHIN_716_Archive                                    |
| LI MEIYI                           | GPT1_LI MEIYI_500_Archive                                        |
| LI YI AN                           | GPT1_LI YI AN_037_Archive                                        |
| LIAO YIRAN LIM CI ANN, ALOYSIUS    | GPT1_LIAO YIRAN_844_Archive GPT1_LIM CI ANN ALOYSIUS_771_Archive |

| LIM JI YONG                                    | GPT1_LIM JI YONG_851_Archive                                                     |
|------------------------------------------------|----------------------------------------------------------------------------------|
| LIM JING RUN                                   | GPT1_LIM JING RUN_884_Archive                                                    |
| LIM JUN ZHAN                                   | GPT1_LIM JUN ZHAN_890_Archive                                                    |
| LIM SHAU SHEE                                  | GPT1_LIM SHAU SHEE_975_Archive                                                   |
| LIM SI HAN, GAVIN                              | GPT1_LIM SI HAN GAVIN_446_Archive                                                |
| LIM ZI JING                                    | GPT1_LIM ZI JING_395_Archive                                                     |
| LIU BOREN LAWRENCE                             | GPT1_LIU BOREN LAWRENCE_737_Archive                                              |
| LOK WEI XIONG                                  | GPT1_LOK WEI XIONG_376_Archive                                                   |
| LOKE JING JIE EVAN                             | GPT1_LOKE JING JIE EVAN_701_Archive                                              |
| LOKHANDWALA ALIASGAR                           | GPT1_LOKHANDWALA ALIASGAR_001_Archive                                            |
| LOO ZHONG EN SAMUEL                            | GPT1_LOO ZHONG EN SAMUEL_434_Archive                                             |
| LOUISA CHUNG YU                                | GPT1_LOUISA CHUNG YU_654_Archive                                                 |
| LOW YI JIE SHERYL                              | GPT1_LOW YI JIE SHERYL_847_Archive                                               |
| LYU JINHAN                                     | GPT1_LYU JINHAN_276_Archive                                                      |
| MADHU KUMAR ANANNYA                            | GPT1_MADHU KUMAR ANANNYA_082_Archive                                             |
| MADNANI KHUSHI                                 | GPT1_MADNANI KHUSHI_069_Archive                                                  |
| MANDE NEIL ASHVINIKUMAR                        | GPT1_MANDE NEIL ASHVINIKUMAR_848_Archive                                         |
| MANOJ AMIT                                     | GPT1_MANOJ AMIT_044_Archive                                                      |
| MARCUS LEE WEI                                 | GPT1_MARCUS LEE WEI_368_Archive                                                  |
| MARCUS LIM                                     | GPT1_MARCUS LIM_380_Archive                                                      |
| MIRA KIM FABE                                  | GPT1_MIRA KIM FABE_490_Archive                                                   |
| MOON JOONCHUL                                  | GPT1_MOON JOONCHUL_280_Archive                                                   |
| MOON SI HO                                     | GPT1_MOON SI HO_044_Archive                                                      |
| MUHAMMAD ASYRAF BIN ABDUL RAHIM                | GPT1_MUHAMMAD ASYRAF BIN ABDUL_606_Archive                                       |
| MUHAMMAD HAZIQ BIN ABDUL RAHIM                 | GPT1_MUHAMMAD HAZIQ BIN ABDUL _198_Archive                                       |
| MUN JIA HAO                                    | GPT1_MUN JIA HAO_276_Archive                                                     |
| MUTHUMANIKANTAN PAVITHRA                       | GPT1_MUTHUMANIKANTAN PAVITHRA_472_Archive                                        |
| NANDHINI NACHIAPPAN                            | GPT1_NANDHINI NACHIAPPAN_089_Archive                                             |
| NATARAJAN SRINIVASAN                           | GPT1_NATARAJAN SRINIVASAN_636_Archive                                            |
| NATHAN BONG NENG QUAN                          | GPT1_NATHAN BONG NENG QUAN_650_Archive                                           |
| NEHRU KABILLAN                                 | GPT1_NEHRU KABILLAN_803_Archive                                                  |
| NEO KUANG YI JAYDEN                            | GPT1_NEO KUANG YI JAYDEN_533_Archive                                             |
| NG YEE SUNG                                    | GPT1_NG YEE SUNG_664_Archive                                                     |
| NG ZHI HOU                                     | GPT1_NG ZHI HOU_719_Archive                                                      |
| NG ZI LE                                       | GPT1_NG ZI LE_452_Archive                                                        |
| NGUYEN DUC KHOA                                | GPT1_NGUYEN DUC KHOA_243_Archive                                                 |
| NGUYEN TAN KIET                                | GPT1_NGUYEN TAN KIET_449_Archive                                                 |
| ONG JUNYIN, JUSTIN                             | GPT1_ONG JUNYIN JUSTIN_114_Archive                                               |
| ONG LI KIAT, ISAAC                             | GPT1_ONG LI KIAT ISAAC_158_Archive                                               |
| ONG MING YU                                    | GPT1_ONG MING YU_773_Archive                                                     |
| OOI WEN YUE                                    | GPT1_OOI WEN YUE_036_Archive                                                     |
| PAI SHASHANK LALITKUMAR                        | GPT1_PAI SHASHANK LALITKUMAR_208_Archive                                         |
| PAN QI YUAN KEVIN                              | GPT1_PAN QI YUAN KEVIN_471_Archive                                               |
| PATEL SIDDHARTH BUNTYBHAI                      | GPT1_PATEL SIDDHARTH BUNTYBHAI_689_Archive                                       |
| PEMMASANI PRABAKARAN RASHMETA SAI              | GPT1_PEMMASANI PRABAKARAN RASH_248_Archive                                       |
| PENG BOHAO                                     | GPT1_PENG BOHAO_755_Archive                                                      |
| PLOGNER OSKAR NILS ALFRED                      | GPT1_PLOGNER OSKAR NILS ALFRED__Archive                                          |
| RAJASEKARAN KRITHIKA                           | GPT1_RAJASEKARAN KRITHIKA_539_Archive                                            |
| RAMESH GOKUL SAI                               | GPT1_RAMESH GOKUL SAI_662_Archive                                                |
| RAVI DEEPAK                                    | GPT1_RAVI DEEPAK_148_Archive                                                     |
| REYAS MOHIDEEN FAWAZ REYES JUSTIN NOEL DOTIMAS | GPT1_REYAS MOHIDEEN FAWAZ_413_Archive GPT1_REYES JUSTIN NOEL DOTIMAS_680_Archive |
| ROYSTON CHEW YI DE                             | GPT1_ROYSTON CHEW YI DE_430_Archive                                              |

| RUBENNISHWARAAN KARUPPIAH            | GPT1_RUBENNISHWARAAN KARUPPIAH_691_Archive                             |
|--------------------------------------|------------------------------------------------------------------------|
| RYAN PRIYANK SUNJAI DHAS             | GPT1_RYAN PRIYANK SUNJAI DHAS_098_Archive                              |
| RYAN VERNADOS                        | GPT1_RYAN VERNADOS_024_Archive                                         |
| SAM LEE HUEY SAMANTHA                | GPT1_SAM LEE HUEY SAMANTHA_617_Archive                                 |
| SAMPATHAWADUGE NILANA IMANDIV SILVA  | GPT1_SAMPATHAWADUGE NILANA IMA_372_Archive                             |
| SELVAM ANAND                         | GPT1_SELVAM ANAND_304_Archive                                          |
| SELVASINGH OLIVER JOSEPH             | GPT1_SELVASINGH OLIVER JOSEPH_070_Archive                              |
| SEOW CHENG SI                        | GPT1_SEOW CHENG SI_802_Archive                                         |
| SHEN YUNCONG                         | GPT1_SHEN YUNCONG_412_Archive                                          |
| SHUKLA ATHARVA                       | GPT1_SHUKLA ATHARVA_251_Archive                                        |
| SINGARAM KARTHIKEYAN                 | GPT1_SINGARAM KARTHIKEYAN_091_Archive                                  |
| SPENCER TING TIEW YU                 | GPT1_SPENCER TING TIEW YU_254_Archive                                  |
| SRIRAM ANUPAMA                       | GPT1_SRIRAM ANUPAMA_775_Archive                                        |
| STEFAN CHOO BIN HAO                  | GPT1_STEFAN CHOO BIN HAO_098_Archive                                   |
| STEVEN MARCUS KHOO TENG EE           | GPT1_STEVEN MARCUS KHOO TENG E_978_Archive                             |
| SUA ISAAC                            | GPT1_SUA ISAAC_138_Archive                                             |
| TAN BOON LEONG                       | GPT1_TAN BOON LEONG_443_Archive                                        |
| TAN JIN XIANG                        | GPT1_TAN JIN XIANG_014_Archive                                         |
| TAN KAI SHENG                        | GPT1_TAN KAI SHENG_237_Archive                                         |
| TAN SWEE KIAT                        | GPT1_TAN SWEE KIAT_110_Archive                                         |
| TAN YONG XIANG                       | GPT1_TAN YONG XIANG_557_Archive                                        |
| TAN YU JUN                           | GPT1_TAN YU JUN_046_Archive                                            |
| TEE REN WEY                          | GPT1_TEE REN WEY_983_Archive                                           |
| THAM YOU JIE                         | GPT1_THAM YOU JIE_411_Archive                                          |
| THOW JIA LE CALEB                    | GPT1_THOW JIA LE CALEB_252_Archive                                     |
| TIFFANY HENG                         | GPT1_TIFFANY HENG_973_Archive                                          |
| TIU SHENG YANG                       | GPT1_TIU SHENG YANG_815_Archive                                        |
| TOH JIAN BIN                         | GPT1_TOH JIAN BIN_754_Archive                                          |
| TOH SIEW HEAN                        | GPT1_TOH SIEW HEAN_512_Archive                                         |
| TRAN HOANG KHANG                     | GPT1_TRAN HOANG KHANG_579_Archive                                      |
| TRICIA LIM ZI NING                   | GPT1_TRICIA LIM ZI NING_575_Archive                                    |
| TRIPATHI ANOUSHKA                    | GPT1_TRIPATHI ANOUSHKA_062_Archive                                     |
| TRISTAN LAU YUE SHEN TRUONG PHI HUNG | GPT1_TRISTAN LAU YUE SHEN_950_Archive GPT1_TRUONG PHI HUNG_402_Archive |
| VISHWAK NATTAMAI                     | GPT1_VISHWAK NATTAMAI_645_Archive                                      |
| VISHWANATH ANNANYA                   | GPT1_VISHWANATH ANNANYA_037_Archive                                    |
| VITO BENEDICT HALIM                  | GPT1_VITO BENEDICT HALIM_783_Archive                                   |
| VIVEKAN KATHIRAVAN                   | GPT1_VIVEKAN KATHIRAVAN_236_Archive                                    |
| VUPPU NAGARAJAN YUVEN RAAJ           | GPT1_VUPPU NAGARAJAN YUVEN RAA_686_Archive                             |
| WAHLGREN HANNA CHRISTINA             | GPT1_WAHLGREN HANNA CHRISTINA__ch_Archive                              |
| WANG QICHEN                          | GPT1_WANG QICHEN_536_Archive                                           |
| WILL CHIN JUN YU                     | GPT1_WILL CHIN JUN YU_806_Archive                                      |
| WONG WEI LUN                         | GPT1_WONG WEI LUN_308_Archive                                          |
| XANDER LIM                           | GPT1_XANDER LIM_790_Archive                                            |
| XU RUIJIE                            | GPT1_XU RUIJIE_009_Archive                                             |
| YEW SU YI                            | GPT1_YEW SU YI_674_Archive                                             |
| YONG CHUAN ONN                       | GPT1_YONG CHUAN ONN_697_Archive                                        |
| YU YIFAN                             | GPT1_YU YIFAN_811_Archive                                              |
| YUE WEI AN JOSHUA                    | GPT1_YUE WEI AN JOSHUA_221_Archive                                     |
| ZEPH TANG ZHENKAI                    | GPT1_ZEPH TANG ZHENKAI_461_Archive                                     |
| ZHAO ZEYU                            | GPT1_ZHAO ZEYU_093_Archive                                             |
| ZOE TAY HUI EN ZOU YUYANG            | GPT1_ZOE TAY HUI EN_198_Archive GPT1_ZOU YUYANG_145_Archive            |

If you have registered for EE2026 labs late, your name may not be present in this lab manual. It will be included in subsequent lab manuals. Please use this naming template meanwhile: GPT1\_Name as on Matriculation Card\_Archive

-------------------------------------------------------------------------------------

## FINAL CHECKLIST FOR GPT-1:

Grading is done only once. Re-grading due to not meeting the checklist below are not accepted.

- [ ] □ I have used the exact and correct numbers and alphabet from my student matriculation number for the assignment.

- [ ] □ I have named the submitted archive according to the given template.

- [ ] □ The submitted archive is less than 5 MB (Delete ".sim" folder if more than 5 MB. Penalty of up to 10% apply if ≥5 MB).

- [ ] □ I confirm that the uploaded submission is the correct / latest version, and not an older one.

- [ ] □ I have downloaded my submission before the deadline and confirmed that it was properly uploaded to canvas.

- [ ] □ I confirm that the grader need not "Generate bitstream", as the bitstream is already there during "Program Device".

- [ ] □ I have carefully verified the bitstream in my CANVAS submission, and it works exactly as I expected.