# StrikeLine screenshots

All images are real frames of `main` at `470888e` (Parts A + B + C + D integrated),
captured in simulation from the two frame buffers (`tb_screens`), so they show exactly
what the Basys3 sends to the screens:

- VGA: 320 x 240, 512 colours, saved at 640 x 480 like the monitor shows it
- OLED: 96 x 64, saved x4

| Folder | What is in it |
|---|---|
| `general/vga`, `general/oled` | The 15 standard game screens (title, menu, settings, high scores, help, aim, zoom, swipe, roll, roll + zoom, pin action, result, replay, scorecard, classic top-down debug view), on each screen |
| `partA` .. `partD` | How each part builds the picture: the same frozen moment captured with that part's layers switched off, then on, plus each part's layers on their own (on black) |
| `comparison_v3.5` | The 7 VGA screens that differ from v3.5: v3.5, main and the changed pixels (only the ball markings changed, Part B's new ball design) |

## How the layer pictures were made

The compositor (`rtl/d_game_ui/compositor.v`) stacks every part's layer into one pixel:

| Part | Layers |
|---|---|
| A | pointer, aim dots, stance readout, power / spin meters, swipe trail |
| B | lane, backdrop (masking unit, curtain, ceiling), ball |
| C | pins, in-game HUD, scorecard |
| D | menus, VGA panel and pop-ups (`vga_hud`), the frame around the top-down window |

A scratch copy of `tb_screens` forced chosen layer enables in `u_comp` to 0 at a frozen
moment and captured the frame, then turned the layers back on one part at a time.
No project file was changed for this.
