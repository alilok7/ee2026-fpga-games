# Team structure: four parts, one bitstream

The course (NUS EE2026 I-FDP) marks each of four students on **their own part** (A, B, C, D), and the team on how well the four parts are **integrated into one bitstream**. Both games are therefore split into four parts with frozen interfaces, each with an owner who must be able to explain every line in the Q&A.

**How the code was produced:** the team wrote the engineering briefs and roadmaps (`prompts/`), and the RTL, testbenches, tools and docs were generated with an AI coding assistant (Claude) working from those briefs and from the team's follow-up instructions (see `docs/BUILD_HISTORY.md`). This is declared in each game's `docs/REFERENCES_AND_AI_USE.md`, as the course requires. Each student owns, studies and defends their part; `docs/A..D_DESIGN.md` in each game lists 15 likely assessor questions with answers per part.

## StrikeLine (bowling)

| Part | Owner | Folder | Responsibility | Gives the others |
|---|---|---|---|---|
| **A** | Student A | `strikeline/rtl/a_gesture/` | Mouse via MouseCtl, 200 Hz swipe capture, 4-tap filter, speed / aim / spin (cross-product curvature), stance, trail, meters, Swipe Lab | throw event → B, D; pointer and clicks → D |
| **B** | Student B | `strikeline/rtl/b_ball/` | Ball physics (skid → hook → roll, oil, gutter), ball→pin collisions, cameras, lane renderer, first-person view, minimap, ball renderer; owns `timebase` and the shared multiplier | ball state, camera → C, D; impulses → C |
| **C** | Student C | `strikeline/rtl/c_pins/` | 10-pin physics, 45-pair collision iterator, wobble / topple, settle detector, split detection, pin-setter + rake, pin renderer, pin LEDs | pin positions → B; result (standing, pins down, split) → D |
| **D** | Student D | `strikeline/rtl/d_game_ui/` | Game FSM + turn FSM (frames, 10th frame, 2 players, Spare Challenge), ten-pin scoring, menus, HUD, scorecard, shared text engine, 7-seg, compositor, flash save / resume with CRC, instant replay | game state + settings → all; rack commands → C |

Integration (whole team): `strikeline/rtl/top/My_Top_Module.v` (wiring only) and the contract `strikeline/rtl/top/strike_defs.vh`, documented in `strikeline/docs/INTERFACES.md`. The physics chain A → B → C → D, settings that change every part, a shared multiplier per part, one shared text engine, and one composited video stream are what make it one product rather than four demos.

## KeyLight (piano rhythm game)

| Part | Folder | Responsibility |
|---|---|---|
| **A** | `keylight/rtl/a_sound/` | Sound engine (DDS note generation, audio out to the Pmod AMP2) |
| **B** | `keylight/rtl/b_input_freeplay_storage/` | Switch/button conditioning, Free Play, (planned) recorder and flash storage |
| **C** | `keylight/rtl/c_game/` | Rhythm game engine: chart reader, note table, judgement, scoring, LED guides |
| **D** | `keylight/rtl/d_ui_learn/` | Mode FSM, menus / results UI, text, 7-seg, (planned) Learn mode |

Contract: `keylight/rtl/top/keylight_defs.vh`, documented in `keylight/docs/INTERFACES.md`.
