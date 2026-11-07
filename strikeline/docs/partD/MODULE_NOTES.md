# 08. Module notes: what each of my 9 modules does, how, and the proof

Each module has a block diagram in `images/`. The code is in `rtl/d_game_ui/`. The `tb_*` testbenches named below are in `sim/d/` (run with `bash sim/run_sim.sh all`). The `eq_*` comparison tests (my module vs the v3.5 original) and the picture testbenches live in my Part D workspace, because they need renamed copies of the v3.5 files.

**Two kinds of test.**
- `tb_*` tests check my module against answers I worked out by hand.
- `eq_*` tests run my module and the v3.5 original side by side with the same random inputs, and compare every output on every clock (or every pixel). That proves my file is a safe drop-in for the team build.

Overall picture: [images/D_overview.svg](images/D_overview.svg).

---

## Results at a glance

| Module | Lines (v3.5) | Test | Result |
|---|---|---|---|
| crc16 | 46 (26) | tb_crc16 | "123456789" -> 0x29B1; 76,800 cases = bit model = v3.5 |
| spi_byte | 79 (54) | tb_spi_byte, eq_spi_byte | 11 checks; 200,000 random clocks identical to v3.5 |
| save_image | 54 (43) | tb_save_image | 4 checks |
| persist_ctrl | 296 (250) | tb_persist, eq_persist | 25 checks; 400,000 random clocks (10,000 inserts) identical |
| flash_ctrl | 395 (321) | team tb_flash, eq_flash | 13/13 team checks; 40 saves + 9 power cuts identical on every SPI pin |
| game_fsm | 387 (306) | tb_game_fsm, eq_game_fsm | 50 checks; 2,000,000 random clocks identical (except the bug fix) |
| menu_render | 321 (289) | eq_menu_render, tb_menu_ppm | 4,177,920 pixels identical in all 17 states; 13 screens drawn |
| compositor | 205 (163) | eq_compositor | 300,000 clocks, 100,000 captures identical |
| vga_hud | 472 (458) | eq_vga_hud, tb_vhud_ppm | 2,764,800 VGA pixels identical; 5 pictures drawn |

Lines went up because of the comments and the clearer FSM structure. Size on the chip: see "LUT budget" at the end.

**What is different from v3.5 (on purpose):**
1. **game_fsm, bug fix:** in SETTINGS, changing a setting and then clicking a read-only row (BALL / HAND / THEME) made v3.5 forget the change, so it was never saved to flash. Mine remembers it (`set_dirty <= set_dirty | ...`). Checked in tb_game_fsm.
2. **persist_ctrl:** if a command arrives on the exact clock its own job finishes, v3.5 loses it (the flag clear wins). Mine keeps it ("set beats clear"). Checked in tb_persist, test 12.
3. **spi_byte:** after the last bit, SCK always returns low on the next clock. v3.5 left it high one extra clock if a new byte started at that moment. flash_ctrl never does that, so the flash sees identical signals (eq_flash).
4. **vga_hud:** the leftover Spare Challenge panel code is removed. The mode was deleted in v3.5 and nothing can turn it on, so this just saves logic.
5. **game_fsm:** `leave_mask` / `leave_idx` (also Spare Challenge) are now constants. They were constant before too.

Everything else is the same behaviour, written in a clearer style.

---

## 1. crc16 ([diagram](images/D_crc16.svg))

**Takes / gives:** used only inside flash_ctrl. Takes `crc_in[15:0]` (the CRC so far) and `data[7:0]` (the next byte). Gives `crc_out[15:0]`.

**How:** CRC = the remainder of dividing the data by the polynomial 0x1021, where subtraction is XOR. One data bit at a time: `fb = c[15] ^ d`, then `c = (c << 1) ^ (fb ? 0x1021 : 0)`. `crc_step` does one bit as a single `assign` (one assign). `crc16` chains 8 of them (like a ripple-carry adder chains full adders). There is no clock: it is purely combinational.

**Hand-worked check:** the first byte '1' (0x31), starting from 0xFFFF:

| bit | d | c[15] | fb | c << 1 | XOR 0x1021? | result |
|---|---|---|---|---|---|---|
| 7 | 0 | 1 | 1 | FFFE | yes | EFDF |
| 6 | 0 | 1 | 1 | DFBE | yes | CF9F |
| 5 | 1 | 1 | 0 | 9F3E | no | 9F3E |
| 4 | 1 | 1 | 0 | 3E7C | no | 3E7C |
| 3 | 0 | 0 | 0 | 7CF8 | no | 7CF8 |
| 2 | 0 | 0 | 0 | F9F0 | no | F9F0 |
| 1 | 0 | 1 | 1 | F3E0 | yes | E3C1 |
| 0 | 1 | 1 | 0 | C782 | no | **C782** |

The simulator prints the same 0xC782. All 9 bytes of "123456789" give **0x29B1**, the standard check value.

**Q&A**
- *Why a CRC and not a simple sum?* A sum misses swapped bytes and many 2-bit errors. CRC-16 catches every 1- and 2-bit error and every burst of up to 16 bits, so a slot that was cut off by a power loss is always rejected.
- *Why is it combinational?* flash_ctrl folds in one byte per clock as the slot streams past. 8 XOR steps fit easily in one clock.

## 2. spi_byte ([diagram](images/D_spi_byte.svg), [FSM](images/D_fsm_spi.svg))

**Takes:** `start`, `tx[7:0]` (from flash_ctrl), `miso` (QspiDB[1]). **Gives:** `rx[7:0]`, `done` (1 clock), `busy` (to flash_ctrl), `sck` (to STARTUPE2), `mosi` (QspiDB[0]).

**How:** a 2-state Moore FSM (IDLE, SHIFT) with a state register, `always @(*)` next-state, `assign busy = (state == SHIFT)`. It has two mod-8 counter submachines: `phase` (8 clocks per bit, like a clock divider, so SCK = 100 MHz / 8 = 12.5 MHz) and `bit_cnt`. There is also a shift register `sh`.

**Hand-worked check (one bit, SPI mode 0):**

| clock (phase) | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| SCK | 0 | 0 | 0 | 0 | **1** | 1 | 1 | 1 |
| MOSI | set to sh[7] | | | | (stable) | | | |
| action | | | | | sh <= {sh[6:0], miso} | | | bit_cnt + 1 (after bit 7: done) |

MOSI changes only while SCK is low, and the flash reads it on the rising edge (mode 0). A byte takes 8 × 8 = 64 clocks, and tb_spi_byte measures exactly 64.

**Q&A:** *Why 12.5 MHz?* The flash allows 50 MHz for READ. Going slower means the extra delay of the clock passing through STARTUPE2 doesn't matter.

## 3. save_image ([diagram](images/D_save_image.svg))

**Takes:** a write port from flash_ctrl (boot load) and one from persist_ctrl (game), plus 7 read addresses. **Gives:** 7 read bytes. They go to 0 flash_ctrl, 1 persist_ctrl, 2 C score_engine, 3 game_fsm, 4 / 5 menu_render, and 6 C turn_fsm.

**How:** `reg [7:0] mem [0:127]` is memory which Vivado builds as LUT-RAM. The write port is a 2-to-1 multiplexer with the flash having priority. Each read port is `assign rdN = mem[raN]` (a 128-to-1 mux). Vivado copies the RAM once per port, about 16 LUTs each.

**Q&A:** *Can both writers write at once?* No. flash_ctrl writes only during the boot load, which finishes before the title screen accepts a click. If they ever did write together, the flash would win (tested).

## 4. persist_ctrl ([diagram](images/D_persist_ctrl.svg), [FSM](images/D_fsm_persist.svg))

**Takes:** from C's turn_fsm: `c_roll` (+ player, index, value), `c_hdr` (+ valid, kind, player, frame), `c_clear`, `c_strike`, `c_spare`. From game_fsm: `c_gameend`, `c_insert`, `c_settings`. From either: `c_defaults`. Plus `rd` from image port 1.
**Gives:** `we`, `wa`, `wd`, `ra` (image port 1), and `busy` (to C turn_fsm, game_fsm, flash_ctrl).

**How:**
- **Pending flags (like an SR flip-flop):** each command SETS its own flag, the flag HOLDS, and the FSM CLEARS it when the job is done. So a command that arrives while another job runs waits for its turn instead of being lost.
- **FSM:** IDLE picks the lowest pending flag. Each job has its own states, and a `step` counter (a submachine) counts the clocks spent in a state, with one read or write per clock.
- `busy` is high from the very clock a command arrives, so flash_ctrl can never copy a half-updated image.

**Hand-worked check (top-5 insert of 150 into 200, 180, 120, empty, empty):**
1. FIND: entry k = 0. RDHI reads {valid, bit 8} = valid. CMP: is 150 > 200? No, so k = 1.
2. k = 1: is 150 > 180? No, so k = 2. k = 2: is 150 > 120? **Yes**, so pos = 2.
3. SHIFT: start at entry 3 (empty). MOVE copies entry 3 to entry 4, then entry 2 (120) to entry 3, byte by byte, from the bottom up so nothing is overwritten before it is copied. It stops when k = pos.
4. WRITE: entry 2 gets {150, valid, name}. The result is 200, 180, **150**, 120, empty (tb_persist checks this).

A 16-bit counter + 1 (STRIKE): read the low byte, read the high byte, write low + 1, write high + carry (carry = low was 0xFF). 0x00FF + 1 = 0x0100 is tested.

**Q&A:** *What if two commands come on the same clock?* Both flags are set, and IDLE serves them one after the other (tested with 4 at once). *Why "set beats clear"?* So a command arriving exactly as its own job finishes runs again instead of being lost.

## 5. flash_ctrl ([diagram](images/D_flash_ctrl.svg), [FSM](images/D_fsm_flash.svg))

**Takes:** `save_req` (C's turn_fsm OR game_fsm), `persist_busy`, `rd` (image port 0), `miso`.
**Gives:** `ra`, plus `we` / `wa` / `wd` for the boot load. Also `c_defaults` (to persist_ctrl), `load_done` and `flash_ok` (to game_fsm, menu, LEDs), `saving` (to C's HUD and vga_hud), `save_error`, `cs_n`, `sck` (through STARTUPE2) and `mosi`.

**How (modular FSM, three levels):**
- The **upper FSM** does the boot and save steps.
- For each step, a **transaction table** (an `always @(*)` output table) says which flash command it needs. The upper FSM starts it once with `t_go` and waits for `t_done`.
- The **lower FSM** runs one transaction: CS low, 4 clocks of set-up, command byte, 3 address bytes, n data bytes, then CS high for 16 clocks.
- Each byte is sent by **spi_byte** (start, then done).
- **crc16** runs over the bytes as they stream past, one byte behind.
- `poll_cnt` is a mod-X counter that gives a 4 s timeout while the FSM waits for the flash to finish erasing or programming.

**Boot:** dummy byte (STARTUPE2 swallows the first clock edges) → RDID 0x9F (00 or FF = no flash) → RDSR 0x05 (protect bits) → read slot A, then slot B, checking 'S', 'L', the version and the CRC → load the valid slot with the newer sequence number, or ask persist_ctrl for the factory defaults.

**Save:** wait for persist_ctrl to be idle → copy the image into a page buffer (with the new sequence number and CRC) → in the **older** slot: WREN, sector erase 0xD8, poll, WREN, page program 0x02, poll, read back and compare.

**Hand-worked check (which slot wins), the same sequence tb_flash runs:**

| event | slot A | slot B | after reprogramming |
|---|---|---|---|
| blank flash | empty | empty | defaults |
| save 1 (A is the older one) | seq 1 | empty | A (seq 1) |
| save 2 (B is older) | seq 1 | seq 2 | B (seq 2 is newer) |
| save 3: **power cut while erasing A** | half erased: CRC bad | seq 2 | **B** (last good) |
| save 4: **power cut while programming A** | half written: CRC bad | seq 2 | **B** |
| save 5 completes in A | seq 3 | seq 2 | A (seq 3) |

"Newer" uses (seq_B − seq_A) as a signed number, so it still works when the 16-bit counter wraps from 65535 to 0.

**Q&A**
- *Why STARTUPE2?* After configuration, the flash's clock pin (CCLK) belongs to the configuration logic. The only way user logic can drive it is STARTUPE2's USRCCLKO input.
- *Why two sectors?* An erase wipes a whole 64 KB sector. If both slots were in one sector, one erase would destroy both.
- *Why WREN twice?* The flash clears write-enable after every erase or program.
- *What happens with no flash?* RDID reads 00 or FF, so the game uses the defaults, skips saves, and plays normally (tested).
- *What does the XDC do for QSPI?* It assigns the pins QspiDB[3:0] and QspiCSn, puts a false path on them (slow I/O), and sets CONFIG_MODE SPIx4. The clock has no pin line because it goes through STARTUPE2.

## 6. game_fsm ([diagram](images/D_game_fsm.svg), [state diagram](images/D_fsm_game.svg))

**Takes:** from A: the mouse pointer and clicks, the wheel, buttons and switches. From C: `tstate`, `t_game_over`, `t_kind`, `game0/1`. From my modules: `load_done`, `persist_busy`, `rd` (image port 3).
**Gives:** `game_state` and `settings` to everyone; `go_new`, `go_resume`, `kind_out`, `abort` to C; `nudge_l/r` to A; `aim_zoom` to B; persist commands and `save_req`; and the menu registers (hover, chip, name ...) to menu_render.

**How:**
- `mode` is the state register, the `always @(*)` case is the next-state table, and `game_state` is a **Moore** output (it depends on `mode` only; in PLAY it equals turn_fsm's state).
- game_fsm is the main machine and C's turn_fsm is the submachine: `go_new` / `go_resume` are commands, `t_game_over` is the feedback.
- Transition actions (start a game, save settings ...) are registered, using `nextmode` to know which arrow is being taken.

**Hand-worked trace (Quick Game, a top-5 score, buttons only)** (tb_game_fsm runs exactly this):
1. BOOT → TITLE (load_done, settings read).
2. btnC → MENU (QUICK highlighted). btnC → `go_new`, kind 000 → PLAY.
3. `t_game_over` with 150 → QUAL (GAMEEND, read place 5: empty, so newhi = 01) → OVER.
4. btnC → NAME. U, U, C (letter C), D, C (letter Z), L (back), C, U, C (letter B) → `c_insert` with 'CZB' 150 into the Quick table → SCORES.

**Q&A:** *Is it Moore or Mealy?* `game_state` is Moore. The 1-clock commands are registered transition actions. *How does the hover follow the mouse?* `row_at = cursor_y / 8`; when a mouse packet arrives, hover takes that row.

## 7. menu_render ([diagram](images/D_menu_render.svg), pictures `images/sim_menu_*.png`)

**Takes:** pixel `ux, uy` (from B's view_map), `game_state`, the game_fsm registers, C's scores, and 2 image bytes. **Gives:** `color[15:0]`, `en`, `txt[52:0]` (a text request) to the compositor, plus `ra_lo` / `ra_hi`.

**How:** for every pixel, range checks decide the colour. Text cells use A's grids: 5x7 cells are 6 × 8 px (col = x / 6 = (x × 43) >> 8, row = y / 8), and 3x5 cells are 4 × 6 px. One combinational block per screen, then a multiplexer on `game_state`. The numbers come from the image and go through double dabble (bcd9 / bcd16).

**Hand-worked check:** pixel (20, 17) on the main menu. col = 20 × 43 >> 8 = 860 >> 8 = 3, fx = 20 − 18 = 2; row = 17 >> 3 = 2, fy = 1. Row 2 is item 2 (QUICK GAME), character col − 1 = 2, which is 'I'. The request is `tx_s(S_MENU + 11 + 2, ...)`, and the picture shows "QU**I**CK GAME".

## 8. compositor ([diagram](images/D_compositor.svg))

**Takes:** every layer's en / colour / text (A, B, C, and mine), plus `cap`, `scr`, `v3d`, `u_in`, `rp_full` from B. **Gives:** `pix[15:0]` to B's frame buffers.

**How:**
1. A priority encoder picks the first valid text request, which goes to A's single text engine.
2. Five `text_layer` instances (structural) turn the engine's answer into each layer's colour.
3. A priority multiplexer picks the front-most layer.
4. Brightness is applied with shifts.
5. The fade is a counter.
6. The D flip-flop `pix` captures the result on `cap`.

**Hand-worked check:** white (R = 31) at brightness 2 (× 3/4): 31 − (31 >> 2) = 31 − 7 = 24. At fade 4 (of 8): 24 × 4 = 96, and 96 >> 3 = **12**.

**Q&A:** *Why 7 clocks?* render_scan holds each pixel for 8 clocks and pulses `cap` on the 7th. The XDC line `set_multicycle_path -setup 7 -to u_comp/pix_reg[*]` gives the long combinational path through the renderers that much time. That is why the register must stay named `pix`.

## 9. vga_hud ([diagram](images/D_vga_hud.svg), pictures `images/sim_vga_*.png`)

**Takes:** the VGA pixel in two grids; swipe info (A); ball speed, position, revs and phase (B); frame, scores, pins, popups and banner (C); `paused`, `saving`, `aim_zoom`. **Gives:** `color`, `en`, `txt` to the compositor (`card_addr` is unused).

**How:** registers hold the frame counter, the last throw, a 1.5 s message timer, the entry board, and every number's digits (registered, so the double dabble is off the pixel path). Four pixel blocks (panel, overlays, replay look, menu backdrop) feed a multiplexer. `vh_board` (3 instances) turns a position into a board number.

**Hand-worked check (live speed):** ball_vy = 1196 (17 mph). 1196 × 145 = 173,420, and >> 10 gives 169, so the panel shows **16.9** mph (it scales mph × 10).

---

## LUT budget (each module synthesised on its own, out of context)

Measured with `tools/compare_util.tcl` (Vivado 2025.2, xc7a35t):

| Module | mine LUT | v3.5 LUT | mine FF | v3.5 FF |
|---|---|---|---|---|
| crc16 | 16 | 16 | 0 | 0 |
| spi_byte | 16 | 20 | 26 | 26 |
| save_image | 240 | 240 | 0 | 0 |
| persist_ctrl | 278 | 268 | 139 | 143 |
| flash_ctrl | 1129 | 1109 | 1299 | 1302 |
| game_fsm | 257 | 175 | 118 | 124 |
| menu_render | 883 | 890 | 7 | 7 |
| compositor | 729 | 730 | 26 | 26 |
| vga_hud | 1040 | 1099 | 123 | 143 |
| **total** | **4588** | **4547** | **1738** | **1771** |

**+41 LUTs** overall, inside the budget of about +250. game_fsm grew by 82 because the next-state logic and the transition actions each decode the conditions (the price of the 3-part FSM structure). vga_hud shrank by 59 because the dead Spare Challenge code is gone. In the full chip, synthesis shares some logic across modules, so the real difference can be a little different. Check it after the team build.

## The test top (board) ([diagram](images/D_test_top.svg))

My Part D workspace has a test top (`test_top/D_test_top.v`, not in this repo) that runs Part D alone on the Basys3: OLED menus, buttons, LEDs, 7-seg, and the real flash. A stub stands in for C's turn_fsm: a "game" lasts 3 s (a green bar counts down) and ends with the score set on sw9..sw1. Built with `test_top/build_test_top.tcl`: **3,332 LUTs, WNS +0.812 ns, WHS +0.043 ns, 0 failing endpoints.**
