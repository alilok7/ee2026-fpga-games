# EE2026 FPGA games: StrikeLine and KeyLight

Two candidate games for the NUS **EE2026 I-FDP** project (AY2026/27 Sem 1), for the **Digilent Basys3** (Artix-7) with a **Pmod OLED 96×64** screen. Four students (parts **A, B, C, D**), each owning one part, integrated into **one bitstream** per game.

| Game | What it is | State |
|---|---|---|
| **StrikeLine** (`strikeline/`) | Ten-pin bowling: hold the mouse button, flick forward, curve the flick to hook the ball. Real ball and pin physics, real scoring, saves in flash | **Complete.** v1 and v2 released, all testbenches pass, timing met |
| **KeyLight** (`keylight/`) | Piano rhythm game: the 13 switches are piano keys, notes fall on the OLED, sound through a Pmod AMP2 | Vertical slice (play songs, Free Play); later phases not built |

> **Using an AI agent?** Start with [`CLAUDE.md`](CLAUDE.md). It tells the agent where everything is and what to read first.

## Downloads (Releases)

| Release | File | Notes |
|---|---|---|
| `strikeline-v2.0` | `strikeline_v2.bit` | **Recommended.** First-person view, fixed hook physics, 7-seg live score, switches = settings / buttons = actions. Also has `strikeline_v2_phaseA.bit` (v1 + new 7-seg only) |
| `strikeline-v1.0` | `strikeline_v1_2026-11-03.bit` | First complete version, top-down only. Kept as a backup |
| `keylight-slice` | `keylight.bit` | KeyLight vertical slice |

Program: Vivado → Open Hardware Manager → Open target → Program device → choose the `.bit`. Plug the OLED into **JC**; for StrikeLine plug a **wired USB mouse** into the board's full-size **USB-A port** (top edge). Exact controls: [`docs/CONTROLS.md`](docs/CONTROLS.md).

The source of each version is the git tag of the same name (`git checkout strikeline-v1.0`). `main` = StrikeLine v2 + KeyLight.

## How it was built (the prompting)

1. The team wrote an **engineering brief** and a **roadmap / work split** for each game. They are in [`prompts/`](prompts/), unchanged: they are the prompts.
2. These were given to an **AI coding assistant (Claude, in Claude Code)**, which wrote the RTL, testbenches, generator scripts and docs phase by phase. It ran Vivado simulations and builds after every step and fixed what failed.
3. The team steered with follow-up prompts: build both games so we can compare, finish StrikeLine first, then for v2 *discuss first, plan, wait for approval, keep the old bitstream as a backup*.
4. Every phase, bug and number (LUTs, timing, tuning) is in [`docs/BUILD_HISTORY.md`](docs/BUILD_HISTORY.md). AI use is declared in each game's `docs/REFERENCES_AND_AI_USE.md`, as the course requires.

## Four people's work, one bitstream

The course marks each student on their own part and the team on integration, so each game is split into four parts with a **frozen interface contract**:

| Part | StrikeLine | KeyLight |
|---|---|---|
| **A** | Mouse + swipe gesture (speed, aim, spin) | Sound engine |
| **B** | Ball physics, lane, cameras, first-person view | Inputs, Free Play |
| **C** | Pin physics, collisions, pin-setter, splits | Rhythm game engine |
| **D** | Game flow, scoring, menus, HUD, text, flash saves | UI, menus, 7-seg |

Each part lives in its own folder (`rtl/a_*`, `rtl/b_*`, `rtl/c_*`, `rtl/d_*`); the top module only wires them together through `strike_defs.vh` / `keylight_defs.vh`. Data flows A → B → C → D (swipe → ball → pins → score), settings reach every part, one text engine and one video compositor are shared. Details: [`docs/TEAM.md`](docs/TEAM.md) and each game's `docs/INTERFACES.md`. Each student's design notes and 15 Q&A: `docs/A..D_DESIGN.md`.

## StrikeLine features

- **Swipe throwing**: flick speed → ball speed (10-22 mph), flick angle → aim (with a ±6° straight zone), flick curvature → hook (spin 1-7, either direction). Trail, power meter, LEDs show power then hook.
- **Ball physics**: skid → hook → roll phases, oil pattern (short / long), 12 / 14 / 16 lb ball, gutters, left- or right-handed.
- **Pin physics**: 10 pins, all 45 pin pairs checked, impulse collisions, wobble and topple, settle detection, split detection (e.g. 7-10), pin-setter and rake animation.
- **First-person view** (v2) while aiming and rolling, top-down for results; classic top-down with sw4. Minimap, physics debug view, slow motion, pause.
- **Real ten-pin scoring**: strikes, spares, 10th frame, 1 or 2 players, scorecard with marks. Quick Game (frames 8-10), Full Game, Spare Challenge, Swipe Lab (practice with readouts).
- **7-segment**: ball speed after each throw, then live points (v2), player number, spare challenge made / tries.
- **Saves in flash** (CRC-16, two slots, survives power cuts): resume an unfinished game after reprogramming, top-5 scores with initials, best game.
- **Instant replay** at half speed, neon "cosmic" theme, adjustable mouse sensitivity and brightness, soft reset.

Screenshots (from simulation of the real design): [`strikeline/docs/screens/`](strikeline/docs/screens/).

## KeyLight features (slice)

Song select with 3 difficulties, falling notes with PERFECT / GOOD / MISS judgement, combo multiplier, grade and accuracy, guide LEDs above the switches, Free Play with octave up, pause and mute, colour-bar self test. Planned but not built: Learn mode, high scores, settings, recorder, flash saves, polyphony.

## Build and test

Needs Vivado (built with 2025.2), Python 3, Git Bash. From a game folder (`strikeline/` or `keylight/`):

```
python tools/make_data.py                    # only after editing text/ songs/ or a generator
bash sim/run_sim.sh all                      # every testbench, each line must say PASS
vivado -mode batch -source tools/build.tcl   # -> build/<game>.bit + timing / utilisation reports
```

Last results: StrikeLine v2 15,785 LUT (75.9 %), 51 DSP, 3 BRAM, WNS +0.251 ns. KeyLight 3,815 LUT (18.3 %), WNS +0.309 ns. **Not yet tested on real hardware**: see the checklist in `strikeline/README.md`.

## Repository map

```
prompts/      the original briefs (the prompts the AI worked from)
docs/         BUILD_HISTORY, CONTROLS, TEAM, FILE_MAP (every file and its purpose)
strikeline/   bowling game: rtl/ sim/ tools/ data/ text/ constraints/ docs/
keylight/     piano game, same layout (+ songs/)
scripts/      gen_file_map.py (regenerates docs/FILE_MAP.md)
CLAUDE.md     entry point for AI agents (AGENTS.md points to it)
```

Course-provided files (`rtl/provided/`: OLED driver, PS/2 mouse controller) are used unchanged. Course manuals and lecture notes are not included.
