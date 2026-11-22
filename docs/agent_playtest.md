# Playtester acceptance report — Poga Poga v0.16

Time: 2026-11-21 14:12–14:17 (+08:00) · Engine: `Godot 4.7.2.stable.official.ed1daf0bf`
Project: `F:\Godot_project\poga-poga` · Windows, D3D12, Forward Mobile, RTX 4060 · Resolution 1280x720
Role: PLAYTESTER acceptance. **No source code or assets were modified.** Only this file was written.

## Build under test (frozen snapshot)

`src/**/*.gd` fingerprint (sha256 over all 27 .gd files, path+hash):

```
SRC_SHA256=F72E439B050ECD8B1802881961D97205F2F3F8062F0B5D335D3D53ACE72E1D87  files=27
```

The same fingerprint was computed **before and after** the check run, so all commands below ran on one
identical tree (lead declared the tree frozen at ~14:11).

Process note: while the tree was still being edited I observed a transient hard compile break at
14:03:50 — `Parse Error: Identifier "FOCUS_SCALE_PRESTART" not declared in the current scope` in
`src/ui/tutorial.gd:92`, escalating to `Failed to load script "res://src/main.gd" with error "Compilation failed"`
(game cannot boot). It was fixed before the snapshot; the frozen tree compiles and runs with zero
`SCRIPT ERROR` / `ERROR` lines in every headless run below.

## 1. Runtime checks (exact stdout, exit codes)

### Check 1 — stamina / cap snap on empty rebound

```
& $godot --headless --path . --fixed-fps 60 -- --autotest --level=0 --stamina-check
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

STAMINA_CHECK PASS cap=0.60->0.46 stamina=0.31
CHECK1_EXIT=0
```

### Check 2 — explode → scatter → reaggregate

```
& $godot --headless --path . --fixed-fps 60 -- --autotest --level=0 --explode-check
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

EXPLODE_CHECK PASS stamina=0.45 cap=0.75
CHECK2_EXIT=0
```

### Check 3 — Esc pause really freezes the race

```
& $godot --headless --path . --fixed-fps 60 -- --autotest --level=0 --pause-check
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

PAUSE_CHECK PASS frozen=0.800
CHECK3_EXIT=0
```

### Check 4 — fusion / detach / reabsorb

```
& $godot --headless --path . --fixed-fps 60 -- --autotest --pattern=mechanics
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

t=0.0 rank=3 lap=0 s=66 packs=1 player_pack=3 stamina=1.00 cap=1.00 speed=8 throttle=0.00
t=0.8 rank=3 lap=0 s=120 packs=1 player_pack=3 stamina=0.98 cap=1.00 speed=86 throttle=1.00
t=1.8 rank=2 lap=0 s=237 packs=2 player_pack=2 stamina=0.93 cap=1.00 speed=125 throttle=1.00
  MECH t=3.42 steer=0.59 pack=2 lat=0.3 v=129
  MECH t=4.07 steer=0.79 pack=0 lat=0.0 v=46          <- forced steer pulls the pack apart
  MECH t=4.50 steer=0.95 pack=2 lat=0.0 v=31          <- re-fused
  MECH t=5.58 steer=0.95 pack=0 lat=0.0 v=95          <- detached again
t=9.8  rank=6 lap=0 s=636 packs=1 player_pack=0 stamina=0.08 cap=1.00 speed=11 throttle=0.05
t=12.8 rank=6 lap=0 s=1581 packs=1 player_pack=0 stamina=0.17 cap=0.72 speed=53 throttle=0.00
                                                     <- s jumps 647->1581: test-rig teleport (12s)
t=26.8 rank=6 lap=0 s=2817 packs=1 player_pack=0 stamina=0.23 cap=0.75 speed=144 throttle=0.35
MECHANICS fused_at=0.00 detach_at=4.22 reabsorb_at=4.50 max_pack=4 best_pack_index=0 eye_form=0.78..1.30
CHECK4_EXIT=0
```

Fusion at t=0.00, forced detach at 4.22 s, reabsorb at 4.50 s, largest pack 4, eye form breathing
0.78–1.30. PASS. (Identical numbers on two independent runs — the pattern is deterministic.)

### Check 5 — full race on level 2 (FALLEN) at tier 1

```
& $godot --headless --path . --fixed-fps 60 -- --autotest --level=2 --tier=1
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

AUTOTEST_RESULT level=2 tier=1 won=false rank=3 time=135.47 laps=[44.6666666666654, 41.383333333331] xp=78 level_after=0
AUTOTEST_RANKING A4(12619|93),A1(12514|92),P*(12185|90),A2(12161|90),A5(12049|89),A3(11995|89)
AUTOTEST_STATS absorb=120 detach=118 lead_changes=16 eye_coll=83 leaf_coll=0 debris_coll=120 explosions=11 offroad_ratio=0.000 packs=0
AUTOTEST_STAMINA min=0.00 max=1.00 cap_min=0.10 eye_form=0.78..1.02 level=0 xp=78/80 tier=1
CHECK5_EXIT=0
```

- The race **finishes** and reports a complete result: rank **3/6**, time **135.47 s**, explosions **11**,
  absorb 120 / detach 118, 0 % off-road. `laps` has 2 entries because the player had completed 2 of the
  3 laps when the AI leader crossed the line (the level is FALLEN = 3 laps).
- The autopilot does **not** win this level (see issue P5: a measurable balance change vs. the earlier build).

### Check 6 (new) — prestart / start gate, GUI build only

```
& $godotGUI --path . --resolution 1280x720 -- --prestart-check
PRESTART_CHECK PASS track loaded after start gate
PC_BARE_EXIT=0

& $godotGUI --path . --resolution 1280x720 -- --prestart-check --force-tutorial
PRESTART_CHECK PASS track loaded after start gate
PC_FORCE_EXIT=0
```

Both variants PASS. Note `--prestart-check` itself forces the tutorial on (`main.gd:218-220` sets
`_force_tutorial`), so the check is independent of the saved "skip guide" setting. Headless cannot run it
(`race.gd:120` requires a non-headless DisplayServer), which is why this is GUI-only.

## 2. Visual evidence (fresh captures on the frozen build)

All captures are 1280x720 PNGs under
`C:\Users\Administrator\AppData\Roaming\Godot\app_userdata\Poga Poga\shots\` (`fz_*.png` = frozen-build
set). They are outside the repo; this agent may only write its report, so the lead should copy any of them
into `docs/screenshots/` if wanted.

| Command | File | Observation |
|---|---|---|
| `--shot --shot-time=1 --level=0 --force-tutorial` | `fz_tutorial.png` | **Empty prestart field + start gate, no black-bar focus.** Uniform dark ground with scanlines; a 3.2x contrast boost of the frame confirms **no road/track is drawn** (no edges, no surface). Gate readable: white post, black/white chevron beam, checkered start stripe, white start-gate base bar. Tutorial panel: `学习模式  引导 3/5  按 S / 空格 刹车（手柄 B 或左扳机）`. HUD `排名 6/6`, timer `--:--.--`. No letterbox bars, no vignette, no zoom-in. Matches `docs/screenshots/tutorial.png`. |
| `--shot --shot-time=1` (task labels this "attract menu") | `fz_shot_time1_nolevel.png` | **Not the menu — a race countdown frame** (HUD `排名 3/6`, lap `1/1`, start line, fused 4-blob pack on the grid, timer `--:--.--`). The command cannot capture the menu: `main.gd:132-133` runs `elif _shot_mode: start_level(_shot_level)` and `_shot_level` defaults to 0, so `--shot` always starts level 0. Use `--shots` (01_menu) or `--shot --reveal-menu` instead. |
| `--shots` | `01_menu.png` … `05_settlement.png` | `01_menu.png` = real attract screen: CRT bezel, `1 PLAYER`, `POGA POGA`, blinking `PRESS ANY KEY`, canopy made of **lens-shaped leaf silhouettes** (no round clouds). Sequence also produced levels / driver / race / settlement without errors. |
| `--shot --shot-time=2 --reveal-menu` | `fz_menu_revealed.png` (== `docs/screenshots/menu_open.png`) | Revealed menu over the leaf canopy with 4 items: `开始游戏 / 操作说明 / 车手 · 加点 / 退出游戏`, footer `↑↓ 选择  Enter 确认  Esc 返回  M 静音`. Debug path prints 2 engine errors (see P3). |
| `--shot --shot-time=5 --level=0 --skip-tutorial --face-test=tired` | `fz_face_tired.png`, crop `fzcrop_tired.png` | Low stamina = **`--`**: two separated white dashes with a clear gap inside one dark eye socket. |
| `--face-test=empty` | `fz_face_empty.png`, crop `fzcrop_empty.png` | Exhausted = **`==`**: two distinct eye circles, each with two white bars. |
| `--face-test=squint` | `fz_face_squint.png`, crop `fzcrop_squint.png` | Collision = **`><`**, both apexes point inward (tips meet in the middle, reads as a bow-tie at this zoom). |
| `--face-test=scatter` | `fz_face_scatter.png`, crop `fzcrop_scatter.png` | Explosion = **exactly 7 mini slimes**, no main blob body, and **no residual black eye-socket oval** (old artifact gone — `racer.gd:608-610` now returns to `_draw_scattered()` before the socket draw). Only the fine white regroup ring remains at the centre. |
| `--face-test=scatter --shot-time=6.5` | `fz_face_scatter_late.png` | Scatter has re-aggregated into the normal single blob → regroup works in real gameplay (autopilot holding throttle). |
| docs sheet | `docs/screenshots/face_states.png` (refreshed 14:05) | `--`, `==`, `><` (tips inward) and mini-slimes with no main blob — all four required states present and matching the frozen build. |

Requested docs images vs. the frozen build (hashes/sizes verified):

- `docs/screenshots/menu.png` — sha16 `1EA226411004C84F`, byte-identical to the fresh `01_menu.png` of this
  run → genuine attract menu with leaf canopy. **Fixed.**
- `docs/screenshots/menu_open.png` — sha16 `776ED68A2188E44D`, 4-item revealed menu over leaf canopy. **Fixed.**
- `docs/screenshots/tutorial.png` — 302 931 B, empty field + gate + `学习模式`, no focus bars. **Current.**
- `docs/screenshots/face_states.png` — refreshed after the last `racer.gd` edit; consistent with the live captures.

## 3. Issues

**P3 — debug-path engine errors (low, non-blocking).** `--shot --reveal-menu` prints:

```
ERROR: Parent node is busy setting up children, `add_child()` failed. Consider using `add_child.call_deferred(child)` instead.
   [0] play (res://src/audio/ui_sfx.gd:38)  [1] _reveal (res://src/ui/main_menu.gd:91)  [2] reveal_now (res://src/ui/main_menu.gd:81)  [3] _ready (res://src/main.gd:122)
ERROR: Playback can only happen when a node is inside the scene tree
   [0] play (res://src/audio/ui_sfx.gd:40)  ...
WARNING: 5 ObjectDB instances were leaked at exit
```

Cause: `reveal_now()` is called from `Main._ready`, so `UiSfx.play()` adds its player while the parent is
still setting up children; the confirm SFX is lost. The menu still renders correctly; only the debug/capture
path is affected. Fix: defer the call (`reveal_now.call_deferred()`) or skip SFX until inside the tree.

**P4 — scatter can softlock a passive player (low/medium design risk, not hit by any check).**
`racer.gd:486-491`: `_regroup_progress` only advances while `absf(raw_throttle) > 0.1 or absf(raw_steer) > 0.1`;
it decays otherwise and there is **no timeout / auto-regroup**. If the player releases every key after the
explosion, the slime stays scattered indefinitely with no on-screen prompt (the regroup ring is the only
feedback). Every automated check holds throttle, so CI cannot catch this. Suggest an auto-regroup after
~3–4 s regardless of input.

**P5 — FALLEN (level 3) tier 1: deterministic autopilot loss, slower than the previous build (medium — lead
decision).** On the 14:05+ builds (including the frozen tree) the same command produced **identical** results
in 4/4 runs: `won=false rank=3 time=135.47`, only 2/3 laps, lap times 44.67 s / 41.38 s. An earlier run tonight
(13:55, before the last `racer.gd`/tuning edits) reported `won=true rank=1 time=131.28 laps=[33.70, 39.05, 58.53]`.
Explosions stayed at 11 in both. So the edits between ~13:54 and 14:03 cost roughly +11 s on lap 1 and turned
a win into a 3rd place. The race itself still completes and reports rank/time correctly (acceptance item
"can finish" = PASS). If "player can win FALLEN on 普通" is a delivery goal, re-check AI speed vs. player
stamina economy; if losing on 普通 is intended, ignore.

**P6 — stale doc screenshots outside the agreed set (low, docs only).** `docs/screenshots/levels.png`
(99 284 B, 12:28), `driver.png` (62 691 B, 2026-11-20), `race.png` (12:29) and `settlement.png` (2026-11-20)
predate the v0.16 UI. Fresh captures differ noticeably in size (levels 125 340 B, driver 91 183 B) and
content (current levels screen has the 对手强度 panel / 4 levels; current driver screen has 洗点/重置 rows).
README embeds these, so they are worth refreshing, but they are not part of this checklist.

**P7 — info only.** `--shot --shot-time=1` documented as "attract menu" is wrong (see table); the harness
has no `--shot`-without-level menu mode. Recommend documenting `--shots` / `--shot --reveal-menu` in
`main.gd`'s header comment and in README so the wrong capture is not produced again.

## 4. Verdict

All requested acceptance items pass on the frozen build:

| Item | Result |
|---|---|
| 1. stamina-check | **PASS** `cap=0.60->0.46 stamina=0.31`, exit 0 |
| 2. explode-check | **PASS** `stamina=0.45 cap=0.75`, exit 0 |
| 3. pause-check | **PASS** `frozen=0.800`, exit 0 |
| 4. mechanics pattern | **PASS** `fused_at=0.00 detach_at=4.22 reabsorb_at=4.50 max_pack=4 ... eye_form=0.78..1.30`, exit 0 |
| 5. level 2 / tier 1 full race | **PASS (finishes)** rank 3/6, time 135.47 s, explosions 11, exit 0 — but see P5 (autopilot no longer wins) |
| 6. prestart-check (GUI) | **PASS** `track loaded after start gate`, exit 0 (bare and `--force-tutorial`) |
| Faces: `--` / `==` / `><` / scatter 7 minis, no main blob | **PASS** (socket oval artifact fixed) |
| Prestart: empty ground + start gate, no black-bar focus | **PASS** |
| Menu: leaf canopy instead of round clouds | **PASS** (attract + revealed captures; docs image fixed) |
| Esc on title screen does not reveal the menu | **PASS** — `main_menu.gd:60-74` rejects `back` (press *and* release) and only accepts key/joypad/mouse **press** |

**PLAYTEST PASS** — no blocking defect. Non-blocking follow-ups in priority order: P3 (deferred
`reveal_now` SFX error), P5 (FALLEN tier-1 balance regression), P4 (scatter regroup timeout), P6/P7 (doc
screenshots + wrong documented capture command).