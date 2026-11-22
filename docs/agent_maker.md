# Maker acceptance report — Poga Poga v0.16

Time: 2026-11-21 14:05 (+08:00) · Godot 4.7.2.stable.official.ed1daf0bf · Windows
Project: `F:\Godot_project\poga-poga` · HEAD `f4ab583` (working tree dirty: v0.16 is uncommitted, 80 changed paths)

Verified snapshot hashes (sha256, first 16):
`racer.gd 5B1E542FD6A36075`, `race.gd E929657A555B8F8D`, `hud.gd BF2CD14F95BEF3D8`,
`main_menu.gd CBE9A28098E63E73`, `menu_backdrop.gd 7F90548646FF69EB`,
`tutorial.gd CF2DE79ABAAAB100`, `track_view.gd D5223917B009D70C`, `main.gd C8EE2085D0BC2314`.

Note: `src/sim/racer.gd` was edited at 13:54:57, i.e. after this acceptance started; all results below are
against the snapshot above (source hashes were unchanged across the final command runs at 14:00–14:01).

## Commands run

```
& $godot --headless --path . --quit-after 5
  -> Godot Engine v4.7.2 ... ; EXIT=0 ; 0x "SCRIPT ERROR" ; 0x "ERROR"

& $godot --headless --path . --fixed-fps 60 -- --autotest --level=0
  -> AUTOTEST_RESULT level=0 tier=1 won=false rank=2 time=30.48 ...
     EXIT=0, 0x SCRIPT ERROR

& $godot --headless --path . --fixed-fps 60 -- --autotest --level=0 --explode-check
  -> EXPLODE_CHECK PASS stamina=0.45 cap=0.75          (EXIT=0)
& $godot --headless --path . --fixed-fps 60 -- --autotest --level=0 --stamina-check
  -> STAMINA_CHECK PASS cap=0.60->0.46 stamina=0.31    (EXIT=0)

& $godot --headless --path . --fixed-fps 60 -- --autotest --level=0 --explode-check --stamina-check
  -> ONLY "STAMINA_CHECK PASS cap=0.60->0.46 stamina=0.31"  (EXIT=0; explode check silently skipped)
```

GUI captures used only for visual checks (written to `user://shots/`, no repo assets touched):
`--shots` (attract menu), `--shot --shot-time=4.2 --face-test=tired|empty|squint`,
`--shot --shot-time=4.0 --face-test=scatter`.

## Checklist

| # | Item | Verdict | Evidence |
|---|------|---------|----------|
| 1 | No SCRIPT ERROR on headless boot | PASS | boot + full level-0 autotest: exit 0, zero `SCRIPT ERROR`/`ERROR` lines |
| 2 | Eyes: no body rotation, horizontal, "><" tips inward | PASS | `racer.gd:512` `rotation = 0.0`; `:606` local `eye_center`; `:621-622` `Vector2(draw_spacing * 0.5, 0.0)` (horizontal, `:620` only widens 1.35x when squinting); `:659-665` left `>` / right `<` (apexes inward). Live capture confirms readable `><` |
| 3 | Low stamina `--`, exhausted `==` | PASS | `racer.gd:669-674` one dash per eye (+small droop); `:678-682` two dashes per eye; dispatch `:631-639`. Live capture: current build shows two separated dashes and clean `==` |
| 4 | Eye collisions drain stamina incl. same-pack | PASS | `race.gd:428-429` `a/b.drain_stamina(EYE_STAMINA_DRAIN)` executed before the `same_pack` split (`:426`, branch `:430`), so both branches drain |
| 5 | Empty lock holds 0; cap snap + bounce same frame | PASS | `racer.gd:370-372` forced `stamina = 0.0` while `_empty_lock > 0`; `:180-185` on expiry `stamina_cap -= STAMINA_CAP_SNAP` then bounce, before `_update_stamina`; runtime `STAMINA_CHECK PASS` |
| 6 | Stamina bar break/shatter state | PASS | `hud.gd:45-47` `StaminaBar.trigger_break`; `:141-167` `_draw_break` (jagged fracture, flying fragments, white crack); call `:215-216`; wrapper `:222-224`; `race.gd:623` triggers on player explosion. Live scatter capture shows shattered right half |
| 7 | Explosion → minis, wander, key-gated regroup, blob hidden | PASS (1 artifact) | 7 minis `racer.gd:452-460`; wander `:468-484`; regroup only while `absf(raw_throttle)>0.1 or absf(raw_steer)>0.1` (`:470`, `:487`, decay `:491`); body hidden `blob_radius = 0.0` `:449`, restored `:506`. Verified via `--face-test=scatter` capture. **Artifact:** eye sockets are drawn at `:625-626` *before* the scattered early-return `:628`, so a merged ~50x29 px black oval remains at the player position during scatter (body itself is hidden) |
| 8 | Prestart: `TrackView.prestart_mode` (empty field + gate), no slow-mo/focus, track loads on crossing | PASS | `track_view.gd:408` flag, `:41-44` early draw, `:57-79` empty field + checkered gate; `tutorial.gd:84-91` prestart branch forces `Engine.time_scale = 1.0`, `camera_zoom_bias = 1.0` and no `_focus_timer`, `:130-131` no letterbox; crossing detection `race.gd:179`, switchover `race.gd:185-207` (`prestart_mode=false`, AI visible, player at start). `docs/screenshots/tutorial.png` (valid, newer than relevant code) shows empty field + gate + "学习模式", no slow-mo framing |
| 9 | Menu background uses leaf shapes, no cloud circles | PASS | `menu_backdrop.gd:116-131` `_draw_leaf_shape`, used at `:100` for the canopy; grep: zero `draw_circle`/cloud hits. Live attract-menu capture shows leaf silhouettes only |
| 10 | Menu ignores input briefly after creation (`_input_lock`) | PASS (caveat) | `main_menu.gd:29` `_input_lock = 0.22`, `:43-44` countdown, `:57` all input ignored while locked, `:60-61` `back` never reveals; live attract capture still shows "PRESS ANY KEY" |

## Real inconsistencies / issues

1. **Screenshot evidence for items 9/10 is wrong/stale (high priority for delivery).**
   `docs/screenshots/menu.png` is not a menu at all — it is an in-race shot (HUD "排名 3/6", lap,
   stamina bar, start line). `docs/screenshots/menu_open.png` is pre-v0.16 (cloud-circle backdrop,
   3 menu items; current build = leaf canopy + 4 items). Cause is visible in the harness: `--shot`
   *starts a level* (`main.gd:125-128`), so a "menu" capture with `--shot` yields a race frame.
   A valid current attract-menu capture exists only in `user://shots/01_menu.png`.
2. **Scatter leaves a dark eye-socket oval.** `racer.gd:625-626` draws the sockets unconditionally,
   then `:628` takes the scattered branch; the black oval (two merged sockets) stays visible where the
   player exploded. Fix: move the socket draw below the scattered early-return.
3. **Eye collision points do not match the drawn eyes when heading != 0.** Drawing is world-horizontal
   (`racer.gd:621-622`) but `eye_left()/eye_right()` (`:141-150`) offset along body-right (rotated by
   `angle`). With `rotation` pinned to 0, collision truth and visuals diverge for turned racers; the
   header comment "眼睛也是碰撞判定的实际依据" is only true at angle 0. Impact is small
   (`eye_distance_to` takes the min of 4 pairs) but it is a real coherence gap.
4. **Combining `--explode-check --stamina-check` silently skips the explode check.**
   `main.gd:523-528` runs the stamina check and `return`s before the explode check; the literal command
   yields only the stamina line and still exits 0. Run the two flags as separate invocations (both PASS).
5. **`_input_lock` hole.** `main_menu.gd:62-63` reveals on *any* `InputEventKey`, including key release,
   so holding Esc (or a mouse button on "返回主菜单") longer than 0.22 s still reveals the menu on release.
   Works for normal taps, but the guard is not airtight.
6. **Prestart is untestable headless.** `race.gd:120` requires `DisplayServer.get_name() != "headless"`,
   and there is no `--prestart-check`; item 8 can only be judged by code + manual screenshot, so a
   regression would pass CI. Also `FOCUS_SCALE_PRESTART` (`tutorial.gd:13`, referenced at `:93`) is dead
   code because `:85` returns first.
7. `docs/screenshots/face_states.png` predates the final `racer.gd` edit (dash lengths/squint spacing were
   changed at 13:54:57), so that sheet still shows the older merged-dash look. Current-build captures
   (13:58–13:59) show correct `--`, `==`, `><`.

## Verdict

**MAKER PASS** — all 10 requested v0.16 behaviors are implemented and both runtime self-checks pass.
Before delivery, fix the two visible defects: the checked-in menu screenshots are wrong/stale
(`menu.png` is a race shot; `menu_open.png` is pre-v0.16), and the scatter state leaves a black
eye-socket oval where the player exploded.