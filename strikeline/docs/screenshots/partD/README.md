# Part D: game flow, menus and saves

Part D draws the menus, the VGA panel and pop-ups (`vga_hud`) and the frame around
the top-down window, and its compositor stacks all the layers into the final picture.

| Image | Shows |
|---|---|
| `01_title_without_menus_vga` | Title screen with Part D's layers off: only Part A's pointer is left |
| `02_title_vga` | The title screen |
| `03_title_oled` | The title on the OLED |
| `04_menu_vga` | Main menu |
| `05_settings_vga` | Settings |
| `06_scores_vga` | High scores |
| `07_help_vga` | Help |
| `08_aim_panel_only_D_vga` | Aiming: Part D's panel and hint lines alone |
| `09_aim_full_with_panel_vga` | Aiming: the full frame, all four parts |
| `10_roll_full_with_panel_vga` | Ball rolling: the full frame |
| `11_pins_full_with_panel_vga` | Pin action: the full frame |
| `12_result_without_D_vga` | Result without Part D |
| `13_result_with_D_popup_vga` | + Part D's panel and the result pop-up |
| `14_topdown_add_D_frame_vga` | Top-down view: + Part D's STRIKELINE frame around the window |
