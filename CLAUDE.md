# CLAUDE.md: start here (for AI agents)

If someone gives you this repo and says **"StrikeLine"**, **"KeyLight"**, **"EE2026 FPGA games"** or **"the bowling / piano FPGA project"**, this is the project. Read in this order, then brief the user (what the game is, its state, the next steps):

1. `README.md`: the two games, features, releases, team split.
2. `docs/BUILD_HISTORY.md`: how it was prompted and built, every phase, every bug found, resource and timing numbers, open items.
3. `docs/CONTROLS.md`: exact controls (StrikeLine v2, v1, KeyLight). Answer control questions from this file.
4. `docs/TEAM.md`: the four parts A-D and who owns what.
5. `docs/FILE_MAP.md`: every file and its one-line purpose. Use it instead of searching.
6. `prompts/`: the original briefs. They are the spec. When the code and the brief disagree, the code + `docs/BUILD_HISTORY.md` describe what was actually built (v2 changed some inputs on purpose).
7. Per game: `<game>/docs/INTERFACES.md` (the contract between parts, with the resource log), `<game>/docs/A..D_DESIGN.md` (design notes + 15 Q&A per part), `<game>/docs/DEMO_SCRIPT.md`.

## Facts to keep straight

- Board: Basys3 (XC7A35T), Pmod OLED 96×64 RGB on **JC**. StrikeLine needs a wired USB mouse in the board's **USB-A host port**. KeyLight optionally uses a Pmod AMP2 on **JA** top row.
- StrikeLine **v3** (working copy, not tagged): a **VGA monitor** is the main screen (160×120 logical, shown 640×480) and the OLED is a second screen. `render_scan` draws both pictures into frame buffers in `vga_out` once per frame; `view_map` says which picture a pixel is in (the 96×64 "UI space" or the VGA 3-D layout). See `docs/BUILD_HISTORY.md` section 5. v3.1 (in this repo, uncommitted until the team commits it): holding the right button zooms the first-person view (dolly zoom in `camera.v`: `k_fp`, `zoom_lvl`). The v2 bitstream is attached to the `strikeline-v2.0` release; a local copy was kept outside the repo in `strikeline_v2_backup/`.
- One 100 MHz clock, tick enables only (`rtl/top/timebase.v`). The contract headers `strike_defs.vh` / `keylight_defs.vh` are frozen: change them only with the whole team.
- Tags: `strikeline-v1.0` (first complete version) and `strikeline-v2.0` (= `main` for StrikeLine). Bitstreams are attached to the GitHub Releases, not committed.
- The code was written by an AI assistant from the team's prompts; each student must be able to explain their own part. Keep `docs/REFERENCES_AND_AI_USE.md` truthful if you add work.
- StrikeLine v3 was programmed on a Basys3 once (started normally); not yet checked in detail on a monitor. KeyLight is a vertical slice.

## Commands (Git Bash, from `strikeline/` or `keylight/`)

```
python tools/make_data.py                    # regenerate data/*.mem after editing text/, songs/ or tools/gen_*.py
bash sim/run_sim.sh all                      # all testbenches (or a name: bash sim/run_sim.sh tb_top)
bash sim/lint.sh                             # StrikeLine: quick syntax check of every RTL file
vivado -mode batch -source tools/build.tcl   # bitstream + reports in build/
python ../scripts/gen_file_map.py            # (from repo root: python scripts/gen_file_map.py) after adding files
```

## Gotchas

- `run_sim.sh` copies sources to a work folder under `$TEMP` (the original working copy lived in a OneDrive path with spaces). VHDL (`MouseCtl`) is compiled only when a testbench instantiates `My_Top_Module`.
- `tb_top` / `tb_screens` simulate the whole bitstream and take minutes. xsim rejects delay literals above 32 bits: use loops.
- `build.tcl` builds in a unique `$TEMP` folder per run (Vivado locks `.Xil`), then copies the bit and reports to `build/`.
- StrikeLine v2 was at about 76 % LUT and WNS +0.25 ns (v3 numbers: `docs/INTERFACES.md` resource log). Pipeline new arithmetic; use the shared multiplier of your part; keep `use_dsp` local.
- On the v3 build PC Windows Device Guard blocks `xvhdl.exe`: `run_sim.sh` then uses `sim/stub/MouseCtl_stub.vsim` (the full-design testbenches force the mouse outputs anyway). `xvlog`/`xsim` sometimes fail to launch once ("child exe not found"): rerun; if it keeps failing, Windows has blocked that compiled simulator: run with a fresh work folder, e.g. `SIM_WORK=$TEMP/strikeline_sim2 bash sim/run_sim.sh tb_top`.
- PowerShell edits: never `Set-Content -Encoding utf8` on RTL (adds a BOM xvlog rejects), and `$signed` inside double-quoted PowerShell strings is eaten (it is read as a variable).
- Verilog-2001 only (no SystemVerilog keywords; `cell` and `edge` are reserved).
- Every new RTL / tool file starts with a header comment `// name.v - purpose` so `scripts/gen_file_map.py` can describe it.
