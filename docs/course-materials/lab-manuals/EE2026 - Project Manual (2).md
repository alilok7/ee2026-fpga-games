<!-- Converted from "EE2026 - Project Manual (2).pdf" on 2026-10-31 with Docling; checked against source by Claude. Notes: Section 1 and Section 5 tables, the 3.2/GPT-5.2/GPT-5.3 headings, title order and the ITEM C sentence were rebuilt by hand from the page images. Coloured emphasis in the PDF is shown as bold. Images and diagrams are described in [Figure: …] notes. -->

# LAB VENUE: DIGITAL ELECTRONICS LAB @ E4-03-07

## UPDATED LAB SCHEDULE:

To improve on the time interval between the four major graded components* of the 100% CA EE2026 course, kindly note the updated schedule for labs.

**ATTENDANCE IS COMPULSORY FOR ALL LABS!**

| Week / Date | Session | Lab |
|---|---|---|
| **Week 7:** 28 Sep 2026 | Mon A.M. | **Lab 5:** Project Initiation |
| **Week 7:** 28 Sep 2026 | Mon P.M. | **Lab 5:** Project Initiation |
| **Week 7:** 2 Oct 2026 | Fri A.M. | **Lab 5:** Project Initiation |
| **Week 8:** 5 Oct 2026 | Mon A.M. | **Lab 6:** Project Work |
| **Week 8:** 5 Oct 2026 | Mon P.M. | **Lab 6:** Project Work |
| **Week 8:** 9 Oct 2026 | Fri A.M. | **No Scheduled Lab (NUS Wellness Day)** |
| **Week 9:** 12 Oct 2026 | Mon A.M. | **Lab 7:** Progress Checkpoint 2/3 |
| **Week 9:** 12 Oct 2026 | Mon P.M. | **Lab 7:** Progress Checkpoint 2/3 |
| **Week 9:** 15 Oct 2026 | 12 to 2 P.M. | **Lab 6:** Project Work **(Makeup for 9 Oct 2026)** |
| **Week 9:** 16 Oct 2026 | Fri A.M. | **Lab 7:** Progress Checkpoint 2/3 |
| **Week 10** | - | No Scheduled Lab |
| **Week 11** | - | No Scheduled Lab |
| **Week 12** | - | No Scheduled Lab |
| **Week 13** | Multiple Slots | **Lab 8:** Multiple Slots for Project Assessment |

> [Figure: an arrow in the schedule links the cancelled 9 Oct 2026 lab to the 15 Oct 2026 makeup slot.]

\* Currently, the schedule for the four major components is:

1. Theory Quiz 1 by Prof. Massimo (Week 7)
2. Progress Checkpoint 2 – Graded Practical Test GPT-7 (Week 9)
3. Theory Quiz 2 by Prof. Chua (To be determined)
4. Progress Checkpoint 3 – Group Project Assessment GPA-8 (Week 13)

Refer to Canvas for details and further updates

---

# EE2026: DIGITAL DESIGN
## Academic Year 2026-2027, Semester 1
## FPGA Design Project (FDP)

## GROUPING

Students need to form their team of 4 and register during the lab session in week 7. Depending on class size, we may need to create one to three teams of 3. We will arrange for students without a team to meet each other during the lab session in week 7.

**Teams should confirm with all their members if they have submitted GPT-4 before registering their team in week 7. Students who have not yet submitted GPT-4 cannot register for a group until submission of GPT-4.**

## ABSTRACT

A FPGA Design Project (FDP) that makes use of the Basys3 development board and the following devices will need to be created:

| Device | Description |
|---|---|
| **Computer Mouse** *(Optional)*<br>*1 piece / team* | Clicks and movements on this device will provide digital signals to the FPGA |
| **Pmod OLED**<br>*1 piece / member* | Information can be displayed on this 96x64 pixels display screen with 16-bit colour resolution |

*Deadline extensions are not given for damaged components. Use them with upmost care!*

This FPGA project requires student to apply their fundamental programming skills in higher-order thinking tasks. The week 7 lab session **briefly guides** you in getting started with a basic system consisting of the OLED. Exact steps are not provided, and you are expected to code, observe, and make conclusions!

After familiarising with the usage of the OLED, you will need to use your own technical skills, logic, creativity, or resourcefulness to create an Interactive FDP (I-FDP), while deciding what is best **implemented within the resource limitations of the FPGA**.

## PLAGIARISM WARNING

This is a teamwork project. Discussions are encouraged. However, 'discussion' is not a valid excuse if your codes turn out to be uncomfortably similar. NUS and the EE2026 teaching team take plagiarism very seriously.

- Each individual carries responsibility for **both** the team and individual portions of the project. Claiming for work done by, and not limited to, senior students, family members, relatives, paid or unpaid service providers, etc. are serious offences.
- All members of the team of the project solutions (codes) or reports will be **unconditionally penalised** in such cases.
- Students will be reported to BoD (Board of Discipline).

---

# SECTION 1. SCHEDULE AND PROJECT COMPONENTS

The project components of EE2026 makes up 30% of the course grade.

| Week | Suggested Project Task | Marks | Evaluation |
|---|---|---|---|
| Week 7, 8 | **(U)GPT-5:** Familiarisation of OLED usage<br>I-FDP project discussion within team | - | (U)GPT-5 is not graded and submission is not required |
| Week 8, 9 | **GPT-6:** Preparation of proposal document<br>Start of programming for the I-FDP | 2% (Group) | GPT-6 CANVAS submission required in week 9 (See Section 6) |
| Weeks 9, 10, 11, 12<br>(Some weeks do not have scheduled labs) | **Student A:** Component A of I-FDP | 9% (Individual) | I-FDP is evaluated around week 13 in **ONE** bitstream for the team. Multiple bitstreams are **not** allowed.<br><br>CANVAS submission is required in week 12 / 13. (See Section 7) |
| ″ | **Student B:** Component B of I-FDP | 9% (Individual) | ″ |
| ″ | **Student C:** Component C of I-FDP | 9% (Individual) | ″ |
| ″ | **Student D:** Component D of I-FDP | 9% (Individual) | ″ |
| ″ | **Group:** Full integration of I-FDP components A, B, C and D in 1 bitstream | 9% (Group) | ″ |
| 12, 13 | Submission of online (CANVAS) peer feedback before deadline | 1% (Individual) | Evaluated during presentation, through report, and from peer feedback |
| ″ | Overall project execution, Q&A, understanding, meeting report requirements and word limits, qualitative comments in peer feedback | 9% (Individual) | ″ |

*(″ = merged cell in the original, same as the row above.)*

# SECTION 2. SOFTWARE FILES

A project template (**FDP2026.xpr.zip**) can be downloaded from CANVAS. The template consists of the following design sources:

### Design Sources:

**My\_Top\_Module.v**: The top-module of the design. This will be your main module, or typically called the Top Level module, where you instantiate the sub-modules and make the necessary links between these sub modules. **You will need to modify this module, as well as create other design sources for use in this module.**

**Oled\_Display.v**: An interface module between your design on the FPGA and the OLED display. This module works to send serial SPI data into the OLED display for initialization and drawing. **You are NOT required to make changes to this module. Optionally, you should read the description inside if you want to know more about the input and output signals.**

**MouseCtl.vhd**: An interface module between the computer mouse, Ps2Interface.vhd and your design on the FPGA. This module signals when clicks and movements are detected on the computer mouse connected to the Basys3 USB port. A wired mouse is recommended, as not all wireless mice will work. **You are NOT required to make changes to this module. This module is optional, and its usage will not be explained.**

### Constraint Sources:

**Basys3\_Master.xdc**: A master constraints file that defines the I/O constraints for the Basys 3 Development Board

# SECTION 3. MODULE SETUP AND TESTING GUIDELINES

## 3.1 OLED\_DISPLAY.V MODULE

**Setting up the OLED by using `Oled_Display.v`**

> [Figure: block diagram of `Oled_Display.v`. Inputs: `clk` (6.25 MHz clock, SPI signal); `reset` (SPI signal; "Reset the state machine to restart from the initialisation phase"); `[15:0] pixel_data` (16-bit colour setting: 5b R, 6b G, 5b B). Outputs to the Pmod header: `pmodoledrgb_cs` → JX[0], `pmodoledrgb_sdin` → JX[1], `pmodoledrgb_sclk` → JX[3], `pmodoledrgb_d_cn` → JX[4], `pmodoledrgb_resn` → JX[5], `pmodoledrgb_vccen` → JX[6], `pmodoledrgb_pmoden` → JX[7]. Status outputs: `frame_begin` ("Asserted for one clock cycle when beginning a new frame on the screen"), `[12:0] pixel_index` ("Current pixel being updated. Goes from 0 to 6143"), `sending_pixels`, `sample_pixel`. Also shows the 12-pin Pmod header numbering (pins 1–6 top row, 7–12 bottom row) and a photo of the Pmod OLED.]

- **3.A1 Instantiate the `Oled_Display.v` module in `Top_Student.v`**
- **3.A2 Create and provide a 6.25 MHz clock signal named `clk6p25m`, to `Oled_Display.v`**
- **3.A3 Create a 16-bit signal named `oled_data` and initialize it with a value of `16'h07E0`.**
  The `oled_data` defines the colour of each pixel. The RGB OLED screen has 16-bit colour resolution, this is represented through 5 bits for the red colour component, 6 bits for the green colour component, and 5 bits for the blue colour component. Connect `oled_data` to the `pixel_data` input of `Oled_Display.v`
- **3.A4 Connect the `Jx[7:0]` signals to the PmodOLED device accordingly.**
- **3.A5 Attach the OLED display to the Basys3 and update the constraints file accordingly.**
  **Very important:** To avoid damaging the devices, ensure the Basys3 board is OFF before connecting the OLED. **DO NOT** touch the OLED ribbon cable when inserting / removing the OLED from the Basys3 board.
- **3.A6 Optionally connect the `reset` port of `Oled_Display.v` to any pushbutton, or alternatively give the `reset` port a constant value of 0.**
- **3.A7 Generate the bitstream and download to the FPGA.**
  Verify that the background colour of the screen is green.
- **3.A8 Write the codes that uses sw[4] to select between one of these two possibilities:**
  - sw[4] is OFF: The background colour is green.
  - sw[4] is ON: The background colour is red.
- **3.A9 Generate the bitstream and download to the FPGA.**
  If the above steps are executed correctly, you would observe a green background on the OLED when sw[4] is OFF, and a red background when sw[4] is ON.

## 3.2 MOUSECTL.VHD MODULE [This optional (And not explained) component may be used in section 5: I-FDP]

**Setting up the computer mouse by using `MouseCtl.vhd`**

> [Figure: block diagram of `MouseCtl.vhd`. Inputs: `clk` (100 MHz clock), `rst` (Reset signal), `[11:0] value` (Settings value), `setx` (Settings for setx), `sety` (Settings for sety), `setmax_x` (Settings for setmax_x), `setmax_y` (Settings for setmax_y). Bidirectional: `ps2_clk` (Clock signal for PS/2), `ps2_data` (Serial data for PS/2). Outputs: `[11:0] xpos` (x-axis value), `[11:0] ypos` (y-axis value), `[3:0] zpos` (z-axis value), `left` (Left button clicked), `middle` (Middle button clicked), `right` (Right button clicked), `new_event` (Event detection).]

- **3.B1 Instantiate the `MouseCtl.vhd` module in `Top_Student.v`**
- **3.B2 Provide a 100 MHz clock signal to `MouseCtl.vhd`**
- **3.B3 Connect ps2\_clk port and ps2\_data port.**
  `ps2_clk` is an inout signal which is connected to the FPGA PACKAGE\_PIN C17.
  `ps2_data` is an inout signal which is connected to the FPGA PACKAGE\_PIN B17.
- **3.B4 Set default values for `value`, `setx`, `sety`, `setmax_x`, `setmax_x`.**
  There is no need to offset any of these values, and we can assume the origin to be the default.
- **3.B5 Write the code that turns on certain leds based on the mouse clicks.**
  led[15] must turn ON when the signal from "`left`" port is high.
  led[14] must turn ON when the signal from "`middle`" port is high.
  led[13] must turn ON when the signal from "`right`" port is high.
- **3.B6 Generate the bitstream and download to the FPGA.**
  Ensure that the mouse is connected to the (upper right) USB port of your Basys3 board. A wired mouse is recommended for testing purposes. Download your program to the FPGA. Press any of the three mouse buttons and observe which LED lights up on the Basys3 development board.

# SECTION 4. LAB 5: (UNGRADED) GRAPHICAL PROGRAMMING TRAINING – (U)GPT-5

GPT-5 is to help students to get familiarised with the usage of the OLED screen. It is required to try these tasks before deciding on your I-FDP project, and before the next progress checkpoint lab.

### OLED COORDINATES SYSTEM:

Work on creating an **x** and **y** coordinate system derived from `pixel_index` to make the pixel drawings on the OLED screen less cumbersome (*Hint: You may employ the modulus % and / operators*)

## GPT-5.1: TRAINING TASK 1

> [Figure: three OLED screenshots. (1) "Two characters and solid white circle": a red "5" and a green "8" with a small white circle at top left. (2) "Clearing the OLED by pressing BTNU": a blank black screen. (3) "Pressing BTNU to revert to the original screen": the "5", "8" and circle again.]

Consider the **2nd Rightmost Number**, **1st Rightmost Number** of your student number:

> [Figure: student-number boxes "A 0 _ _ _ _ _ _ _" labelled 7th, 6th, 5th, 4th, 3rd, 2nd, 1st Rightmost Number and Rightmost Alphabet; the 2nd rightmost box is shaded red and the 1st rightmost box green.]

**Part A:** When the program starts, the following appears on the black OLED screen:
- The **2nd Rightmost Number** appears on the left side of the OLED in **red colour**
- The **1st Rightmost Number** appears on the right side of the OLED in **green colour**
- A solid **white circle**, with radius **between 4 to 8 pixels**, appears near the top left of the OLED screen
  *Hint: Consider using the equation of a circle to draw the solid circle*

Use the number template shown below as the requirement for a readable character for this basic task:

| Number template | Requirements |
|---|---|
| [Figure: block-style digits 0 1 2 3 4 5 6 7 8 9] | Height of each character: **At least** 45 pixels<br>Width of each character: **At least** 25 pixels<br>Lines thickness: **At least** 6 pixels thick |

**Part B:** If both characters and solid white circle are present on the OLED, the user can press the up pushbutton (BTNU) to clear them from the screen.

If the screen is empty, the user can press the up pushbutton (BTNU) to make the two characters and solid white circle appear on the screen again.

This process can happen an infinite number of times.

**Important note regarding the pushbutton presses:**

- The user may press and release the pushbutton within 200 milliseconds (No need to count the actual duration the user pressed the pushbutton, or if 200 milliseconds have been exceeded). The pushbutton signal detection must be **very responsive** to this quick pressing (Example: Detection done every 1 millisecond) and **must apply debouncing** to avoid multiple presses detection. For debouncing, create a counter that counts for 200 milliseconds at the start of the pushbutton pressing, and during that time, bouncing pushbutton signals must be ignored.
- The user may also press and hold for more than 200 milliseconds. In such case, **the pushbutton press should be detected as being just one press**, no matter how long the pushbutton is pressed and held. It may be held for as long as 5 seconds.

## GPT-5.2: TRAINING TASK 2

> [Figure: three OLED screenshots along the bottom of the screen: a red "3", a solid square and a blue "7". (1) "Two characters and a green solid square". (2) "Solid square change colour by pressing BTND": the square is red. (3) "Solid square change colour by pressing BTND": the square is blue.]

Consider the **4th Rightmost Number, 2nd Rightmost Number** of your student number:

> [Figure: student-number boxes "A 0 _ _ _ _ _ _ _"; the 4th rightmost box is shaded red and the 2nd rightmost box blue.]

**Part A:** When the program starts, the following appears on the black OLED screen:
- A **green 20x20 pixels solid square** on the bottom middle of the OLED
- A **red character representing the 4th rightmost number** on the bottom left of the OLED
- A **blue character representing the 2nd rightmost number** on the bottom right of the OLED

Use the number template shown below as the requirement for a readable character for this basic task:

| Number template | Requirements |
|---|---|
| [Figure: block-style digits 0 1 2 3 4 5 6 7 8 9] | Height of the character: **Exactly** 20 pixels<br>Width of the character: **Maximum** of 20 pixels<br>Lines thickness: **Between** 2 to 5 pixels thick |

**Part B:** The solid square on the bottom middle of the OLED can change colour. Each time the down pushbutton (BTND) is pressed, the colour for the solid square changes in this sequence (one colour change per pushbutton press):

Green > Red > Blue > Yellow > "Back to Green" (Sequence repeats)

**Important note regarding the pushbutton presses:**

- The user may press and release the pushbutton within 200 milliseconds (No need to count the actual duration the user pressed the pushbutton, or if 200 milliseconds have been exceeded). The pushbutton signal detection must be **very responsive** to this quick pressing (Example: Detection done every 1 millisecond) and **must apply debouncing** to avoid multiple presses detection. For debouncing, create a counter that counts for 200 milliseconds at the start of the pushbutton pressing, and during that time, bouncing pushbutton signals must be ignored.
- The user may also press and hold for more than 200 milliseconds. In such case, **the pushbutton press should be detected as being just one press**, no matter how long the pushbutton is pressed and held. It may be held for as long as 5 seconds.

## GPT-5.3: TRAINING TASK 3

> [Figure: three OLED screenshots with a light-blue "2" on the left and an orange "6" in the middle. (1) "Two characters when the program starts". (2) "Blue character moves when switch SW1 is turned ON" (arrow pointing right). (3) "Blue character stops when switch SW1 is turned OFF": the "2" overlaps the "6".] *Arrows are not present on the OLED. They are only for illustration purposes of the movement directions.*

Consider the **3rd Rightmost Number**, **1st Rightmost Number** of your student number:

> [Figure: student-number boxes "A 0 _ _ _ _ _ _ _"; the 3rd rightmost box is shaded orange and the 1st rightmost box light blue.]

**PART A:** When the program starts, the following appears on the black OLED screen:
- The **1st Rightmost Number** appears on the left side of the OLED in **blue colour**
  To improve visibility of the number on the OLED, use a lighter blue colour!
- The **3rd Rightmost Number** appears in the middle of the OLED in **orange colour**

Use the number template shown below as the requirement for a readable character for this basic task:

| Number template | Requirements |
|---|---|
| [Figure: block-style digits 0 1 2 3 4 5 6 7 8 9] | Height of each character: **Between** 20 to 30 pixels<br>Width of each character: **Between** 15 to 20 pixels<br>Lines thickness: **Exactly** 4 or 5 pixels thick |

**PART B:** If switch **SW1** is turned ON, the blue number moves between the right edge and left edge of the screen. The movement speed must be such that is takes around **3 ± 0.5 seconds** to move from one edge to the opposing edge. For ease of programming, there is no need to be exactly at the edge (It can be within 3 pixels from the edges)

If **SW1** is turned OFF, the movement of this **blue number** must stop, and if **SW1** is turned ON, it resumes in the same direction that it was going before it stopped. **SW1** can be turned ON / OFF an infinite number of times.

**Important note regarding the number movement:**

The **movement animation should be smooth**. It should not appear as if the moving number is skipping pixels or teleporting itself to move. There is also no restriction on which number is in the foreground, and which number in the background when they cross path near the middle of the screen.

## GPT-5.4: TRAINING TASK 4

Integrate the previous 3 training tasks into one single bitstream to get an idea of the process involved in integration.

In the one single bitstream, when the program starts, the seven-segments displays show your group ID in this format:

> [Figure: seven-segment display showing "Id." followed by two empty digits. Callout: "These two digits are your team number. **Please remember your team number when you sign up in lab in week 7.**"]

The training task to present should be based on the following truth table:

| INPUTS: SW15 | INPUTS: SW14 | INPUTS: SW13 | OUTPUTS: OLED |
|---|---|---|---|
| 0 | 0 | 1 | Contents of Training Task 1 |
| 0 | 1 | X | Contents of Training Task 2 |
| 1 | X | X | Contents of Training Task 3 |

*Hint: To be able to show different characters on the seven-segments displays, it is required to:*

- *Show a character on only 1 anode at a time*
- *Show another character on another anode a few milliseconds later (around 200 to 500 Hz)*
- *Repeat the above continuously*

*An example of the above task is illustrated below:*

> [Figure: multiplexing sequence. 1st Sequence shows "F" on the leftmost digit only, 2nd Sequence "A" on the second digit, 3rd Sequence "S" on the third, 4th Sequence "t" on the rightmost; "3 milliseconds passed" between each step, then back to the 1st Sequence.]

*For humans, this is what they will see:*

> [Figure: seven-segment display showing "FASt" on all four digits at once.]

# SECTION 5. THE INTERACTIVE FDP (I-FDP)

An Interactive FPGA Design Project (I-FDP) is required to be implemented **within the resource limitations of the FPGA** on the Basys3 board, in **ONE** bitstream. Working together as a group, divide the responsibilities among the team members to achieve the following specifications for the I-FDP:

| Group Theme | **FPGA Based Smart Graphical Calculator using Verilog Language** |
|---|---|
| **Functionality** | **Compulsory requirement:** Able to perform simple additions and subtractions of whole numbers (with single digits for operands, such as 8 + 5).<br><br>**Possible enhancements (non-exhaustive):** Multiplication, division, decimal points, different number representations, trigonometry, graphing, conversions, educational components etc. |
| **Robustness and Reliability** | **Compulsory requirement:** Reprogramming the FPGA is not required for each calculation. System does not crash often due to unexpected behaviours.<br><br>**Possible enhancements (non-exhaustive):** Switching between different functionalities always work, reset in-built, reliable communication between multiple Basys3 board if there are multiple boards etc. |
| **User Interface** | **Compulsory requirement:** Usage of switches, LEDs and OLED.<br><br>**Possible enhancements (non-exhaustive):** Usage of a seven-segments display, multiple OLEDs, mouse, computer keyboard etc. *Note: Usage of unnecessary devices is discouraged (It negatively affects the product)* |
| **User Experience** | **Compulsory requirement:** User can input values, and see output values, on the Basys3 board, with ease.<br><br>**Possible enhancements (non-exhaustive):** Intuitive usage of the calculator with minimal documentation, adequate on-board guidance where required, brightness/mode of the OLED, elements of fun and excitement when using the product, etc. |

**Compulsory requirements** are the bare minimum required to show your fundamental Verilog capabilities.

**Possible enhancements** are value-added components that further demonstrate your Verilog capabilities and are not as straightforward to efficiently implement. The enhancement(s) must be strongly related to the group theme. Each team is encouraged to work together on a larger enhancement by appropriately dividing the responsibilities, instead of multiple unrelated / simpler enhancements, for the I-FDP.

When working on possible enhancements, note that it is not compulsory to have all the basic capabilities of a calculator. For example, some teams may not wish to implement inefficiently coded multiplication/division and instead focus on interactive control of graphs due to FPGA resource limitations.

**Each team member must have a reasonable amount of Verilog coding to do, and their allocated responsibility should not have much overlap with the other members of the team. These individual responsibilities would form the marks for the individual marks of the I-FDP implementation.**

**The group marks of the I-FDP implementation consider how well the different components from each team member are integrated together into one bitstream to create a more complete project. It must not be a separate component.**

## ALTERNATIVE GROUP THEME OPTION FOR I-FDP:

To allow teams to further explore other options that they wish to implement using the Basys3 and Verilog as the building block, teams are encouraged to choose other group **themes that match their interests**, instead of the FPGA Based Smart Graphical Calculator described above. In such cases, please note that the same rules apply:

- The individual I-FDP implementation should be strongly related to the group I-FDP implementation, and not something different / unrelated. A project that focuses on one main theme with **deeper integration has significantly higher value**, than a project that has many smaller unrelated components and lower integration complexity.
- The same criteria will be used to judge your chosen I-FDP, namely: **Functionality**, **Robustness and reliability**, **User Interface** and **User Experience**

## OTHER OPTIONAL DEVICES:

**The Basys3 and OLED screen are compulsory devices for the I-FDP. All other devices are optional, and they are not needed for a project to be considered excellent.**

**Usage of devices (except computer keyboards and mouse which are allowed) not provided by the lab are not allowed, and the team will be penalised if unauthorised devices are used without explicit written email approval by your lab instructor.**

**Hardware is not assessed in EE2026, and no additional marks are given for optional devices and the usage of their corresponding design sources.**

The lab also has the devices listed below that you can use, and you can request to sign out for these devices **during EE2026 lab sessions**. The lab counter does not distribute EE2026 components outside EE2026 lab sessions hours. **These external devices will not be explained, and design sources will not be provided. No additional marks are given for their usage**:

- PMOD for audio input
- PMOD for audio output
- VGA output to HDMI converter

If you need to connect a Basys3 development board to another Basys3 development board, please seek **explicit email approval** from your lab assistant **before** making the connection. Connections between multiple Basys3 boards require you to **provide a schematic of which ports will be connected via wires** in the approval request email. **Do not request for Basys3 boards connections without providing the exact port connections schematics**. Also, wires will need to be connected to appropriate headers. Do not use wires without headers.

## RESTRICTION FOR OLED CONNECTION:

It is not allowed to directly connect two OLED displays to the same side of the basys3 board, as they will physically interfere with each other. Marks will be lost in such scenarios of inappropriate connections.

## FPGA RESOURCE LIMITATIONS:

All teams have the Basys3 board with the same amount of FPGA resources available, and your program cannot exceed the resource limits of the FPGA.

The FPGA resource utilisation can be found in the Project Summary -> Utilization -> Post-Implementation. For example:

> [Figure: Vivado Utilization bar graph (Post-Implementation tab): LUT 98%, LUTRAM 21%, FF 13%, BRAM 97%, DSP 82%, IO 80%, BUFG 15%, PLL 20%.]

Team members must:
- Plan carefully
- **Limit the number** of components / capabilities or **implement them more efficiently**
- **INTEGRATE EARLY and regularly**
- Monitor FPGA resource usage which might increase exponentially during integration.

# SECTION 6. LAB 6: GRADED PROPOSED THEME - GPT-6 (UPLOAD TO CANVAS IN WEEK 9)

A description of the group theme your group has chosen needs to be **submitted to CANVAS**. The description should be no more than 2 pages (1 sheet), and should make use of the template below:

**I-FDP PROPOSAL DOCUMENT**

| Group ID: **SX\_YZ** | **Description**<br>**(Pictures / Drawings / Sketches / Gantt Charts are optional and not necessary)** |
|---|---|
| **Group Theme:**<br>*Title of the group theme* | *Describe the overall group theme that your team wants to implement on the Basys3. If you are choosing the default FPGA Based calculator, this would involve indicating the overall functions of your calculator. The description for this part is recommended to be between 100 to 200 words.* ***Minimum of 100 words required.*** |
| **Group Member 1:**<br>*Name of group member* | ***Member responsibility:*** *"Describe **one major component** that this group member is required to do with respect to the group theme"*<br><br>***Week 7:*** *"Describe what the student has **already done** for this week"*<br>***Week 8:*** *"Describe what the student has **already done** for this week"*<br>***Week 9:*** *"Describe what the student has **already done** for this week"*<br>***Week 10:*** *"Describe what the student will be doing for this week"*<br>***Week 11:*** *"Describe what the student will be doing for this week"*<br>***Week 12:*** *"Describe what the student will be doing for this week"*<br><br>*The description for this part is recommended to be between 100 to 300 words and can be in bullet points format.* ***Minimum of 100 words required.*** |
| **Group Member 2:**<br>*Name of group member* | *(Same as Group Member 1.)* |
| **… More members** | *… More members* |

*(The Group Member 2 cell in the original repeats the Group Member 1 text word for word.)*

Your team can still make changes to the actual implementations. There is no need to update the above document after submission.

The GPT-6 marks are given as follows:
- 1% of the course grade: Distinct and meaningful week 7 to 9 task descriptions
- 1% of the course grade: Clearly defined week 10 to 12 task descriptions

## UPLOAD DETAILS FOR GPT-6:

- One **single PDF** submission **per group**
- File name format: **GPT6\_SX\_YZ**, where **SX\_YZ** is your group ID (See PDF on CANVAS for your group ID near submission time).
- Upload in the CANVAS folder named: **GPT-6 Document Submission**
- Deadline for submission: **Monday 19th October 2026, 6 AM**

# SECTION 7. FINAL I-FDP SUBMISSION INSTRUCTIONS

On average, the demonstration of the I-FDP in week 13 should have sufficient components for a duration of 2 to 5 minutes for the team, excluding questions asked by the assessor. Questions by the grader can extend the duration to more than 10 minutes.

**Ensure that your project demonstration does not require the assessor to wait for very long, or to go through a lot of difficult steps, to see specific components / capabilities of your I-FDP. The assessor will skip those components / capabilities if there are time limitations, and this will affect the marks given.**

There are two items (ITEM A, and ITEM B) to submit to CANVAS, and ITEM C to complete on CANVAS:

| Official Lab Session | ITEM A (Submit on CANVAS)<br>Project Archive | ITEM B (Submit on CANVAS)<br>Report | ITEM C (Complete on CANVAS)<br>Peer Feedback |
|---|---|---|---|
| Monday, Tuesday, Wednesday, Thursday, Friday | **Deadline:** Week 12 / 13. Exact date will be announced on Canvas after Theory Quiz 2 date is finalised. | **Deadline:** Week 12 / 13. Exact date will be announced on Canvas after Theory Quiz 2 date is finalised. | **Deadline:** Week 12 / 13. Exact date will be announced on Canvas after Theory Quiz 2 date is finalised. |

**Deadlines cannot be extended. Plan early on how to use the 6 weeks (Weeks 7 to 12) allocated for the project.**

## ITEM A: Project Archive Submission

- Only **ONE** Vivado project archive submission **PER team**. **The archive should not exceed 500 MB in size.** (Excess of 500 MB in size is only allowed with prior approval from the lab instructor)
- All functions must be present in **one single bitstream**. Ensure that your **one single bitstream** has been successfully generated and tested on your Basys 3 development board **BEFORE** archiving your Vivado workspace for CANVAS upload. Download your CANVAS archive after uploading. Unzip it and check if you can run your **one single bitstream** correctly.

## ITEM B: Report Submission in PDF Format:

**Grading of the I-FDP is based on the description given in the report**, with the described components / capabilities validated through the project demonstration to the assessors. **Understand the requirements below while writing the report**:

### Sheet A (Pages 1 and 2) – Component / capability description part:

- Use the template shown on the last page. Note of the placement of the group ID, name, matriculation and word count.
- Consists of these sections: One for the group theme, and one section for each team member.
  - 4 members team: Total amount of words for the **5 sections combined** must **not exceed 500 words**.
  - 3 members team: Total amount of words for the **4 sections combined** must **not exceed 400 words**.
  - 2 members team: Total amount of words for the **3 sections combined** must **not exceed 300 words**.
- Summarise your components / capabilities descriptions clearly and concisely.
  - The special / interesting capabilities can be in bold characters, but do not overuse bold characters. Less than 20% of words for the description are allowed to be in bold characters.
  - If optional devices (Eg. Computer mouse, computer keyboard) are used, they should be clearly indicated in bold.
  - Usage of bullet points or numbering are allowed.
  - Instructions on how these components / capabilities can be operated by the user are optional
- Showing components / capabilities during the project demonstration to the assessors, but not described in the report, will not be given marks.
- Claiming for components / capabilities in the report, but which has not been implemented and demonstrated in the one single bitstream for the team, negatively affects all marks. **In the report, do not include non-working parts or parts that cannot fit within the FPGA resource availability, to avoid penalties to the team.**
  - The team is responsible in ensuring that each team member has accurately indicated the components / capabilities that is implemented in the one single bitstream being used for the demonstration.
  - Demonstrating in a separate bitstream, such as due to running out of FPGA resources after integration, is not accepted.
- Images that support your components / capabilities need to be clear and in colour
  - Real images from the OLED screen are required, instead of simulated ones from the computer
  - Pictures should show the parts being focused on. For example, do not show the whole Basys3 board if only the 7-segments values are the parts in focus.

### Sheet B (Pages 3 and 4) – Course feedback and references part:

- This sheet of A4 paper must only consist of course feedback and references.
- Include **course related feedback** (Ideally, no feedback about teachers in the report. It must be about the course):
  - Feedback, whether positive or negative, **DO NOT** have any effects on your grades.
  - Negative feedback with constructive comments is encouraged in this report, as they will allow two-way communications between students / teachers during the project presentation, to understand what to improve.
  - Anonymous feedback of teachers, or course feedback that don't need two-way communications, can be given on the official NUS end-of-semester feedback.
  - You are the inaugural batch for GPT-3. We are applying some of your suggestions in GPT-7, but there might be more feedback you might want to indicate to make future batches have better experiences in GPT-3 / GPT-7.
- **Include references used.** (GitHub, Websites, YouTube, Chatbots, AI, etc…)
  - **Compulsory** to include references to **open-sources codes**. Full penalties apply if open-source codes are used without clear references.
  - Usage of **Artificial Intelligence (AI)** or **automated code generators** must be **clearly indicated and documented**. You can use more pages (Page 5, 6, 7, etc…) to document that usage if AI has been used.
- Full penalties apply for the project if **open-source codes / AI / code generators / chatbots** have been used (These are allowed to be used) but **not properly documented on how they have been used in the project**.

## ITEM C: Peer Feedback

Details for the peer feedback will be released through CANVAS announcement in week 12.

---

## TEMPLATE FOR SHEET A (PAGES 1 AND 2) OF THE REPORT:

Text in black is the text that needs to be present in your report according to your custom details.
*Text in grey is only for explanation purposes here and is not needed in your report.* (Shown in italics below.)

> [Figure: a two-column template. Each section has a header bar (team/student name, name of theme/component, word count), with the description on the left and photo boxes on the right. The sections are shaded pastel pink (Team), red (A), blue (B), yellow (C) and green (D).]

**Team: SX\_YZ** | *Name of group theme:* **A-mazing graphs game…** | **55 words**
- *The description of the group theme is written in this section. Count the number of words (Group theme) from this section.*
- *Describe the group theme, indicating what the system can do overall. By reading this description, the user should know what the whole system is capable of and what are the star components / capabilities of the system, if any. The group theme MUST be a superset of the individual components, and not something different*
- *Picture box: Take only one picture of the whole system, showing where the OLED (and other devices you have used) are connected. The system should be running with your bitstream loaded, and the OLED screen / LED / Segments are showing something*

***Student A:*** **Alice (A0000000X)** | *Name of component:* **Arithmetic process of…** | **88 words**
- *The description for student A is written in this section. Count the number of words (Student A) from this section. Example (Based on a past project):*
  - *Calculator with 2 decimal point precision*
  - *Q16.8 fixed point arithmetic*
  - *Avoiding overflow through widening to Q48.8…*
  - *Shift-add algorithm for LUT reduction…*
- *Picture boxes: three.*

***Student B:*** **Betty (A0000000X)** | *Name of component:* **Physics simulation of …** | **65 words**
- *The description for student B is written in this section. Count the number of words (Student B) from this section. Example (Based on another past project):*
  - *Verlet integration: Numerically stable…*
  - *Multipass iterative constraint resolver: Allows item of arbitrary length*
  - *Randomized wind using 16-bit LFSR…*
- *Picture boxes: two.*

***Student C:*** **Charlie (A0000000X)** | *Name of component:* **Windows interaction with…** | **128 words**
- *… Example (Based a separate past project):*
- *The number in bracket used here allows for image matching*
  - *Gesture recognition from mouse (1)*
  - *Adjustable cursor and size: For ease of viewing*
  - *Speed of scrolling based on pushbutton press duration (2)*
- *Picture boxes: six, two of them labelled (1) and (2).*

***Student D:*** **Dawn (A0000000X)** | *Name of component:* **Interactive graph for…** | **93 words**
- *… Example (Based a different past project):*
  - *Implemented a viewport controller that maintains zoom exponent and offset and it also acts as a movable and scalable window into a world coordinate system.*
  - *Intuitive mouse wheel that performs a smooth geometric zoom about the centre of the screen... (1)*
- *Picture boxes: two, one labelled (1).*

Do not exceed allowable number of words! More words do not mean more marks and usually has the opposite effect!

**Colour Requirements to Ensure Accurate Grading:**

- Highlight **TEAM SECTION IN PASTEL (OR LIGHT) PINK** (Do not use dark / bright pink)
- Highlight **STUDENT A SECTION IN PASTEL (OR LIGHT) RED** (Do not use dark / bright red)
- Highlight **STUDENT B SECTION IN PASTEL (OR LIGHT) BLUE** (Do not use dark / bright blue)
- Highlight **STUDENT C SECTION IN PASTEL (OR LIGHT) YELLOW** (Do not use dark / bright yellow)
- Highlight **STUDENT D SECTION IN PASTEL (OR LIGHT) GREEN** (Do not use dark / bright green)

Bring **TWO printed copies** of your report in **COLOUR**, when you come for your assessment.
