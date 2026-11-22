# Judge acceptance report — Poga Poga v0.16

Time: 2026-11-21 14:27 (+08:00) · Godot **4.7.2.stable.official.ed1daf0bf** · Windows / PowerShell
Project: `F:\Godot_project\poga-poga` · HEAD `f4ab583` (v0.16 uncommitted)

Final verdict run on the **frozen tree** (last write: `src/ui/hud.gd` 14:23:41, docs 14:18:21, screenshots
14:24:45). No tracked file changed during the regression run (before/after hash comparison) or afterwards.

| file | sha256 (first 16) | mtime |
|---|---|---|
| src/ui/hud.gd | `88D9F9C305E31C2C` | 14:23:41 |
| src/sim/race.gd | `8710110A14062EF3` | 14:19:50 |
| src/sim/racer.gd | `DCB881E22CEEE1DD` | 14:19:50 |
| src/main.gd | `6B4F96EBD67D58EE` | 14:19:50 |
| src/data/tuning.gd | `3BB6559553FB2757` | 13:51:31 |
| tools/verify.ps1 | `8095A76EA1996F0D` | 13:53 |
| README.md | `4E4DCDCF39EEB7D0` | 14:13:07 |
| 项目规范.md | `BAA8116DF20FFFB2` | 14:18:21 |
| GLOBAL_REQUIREMENTS.md | `A2B6B453C8FFAC5F` | 14:18:21 |

History of this acceptance (for the record): pass #1 found stale `0.35/0.55` constants → FAIL; docs were
fixed; a later code edit left a `hud.gd:46` parse error → FAIL #2; the HUD fix (stray methods removed,
`StaminaBar.trigger_break()` restored inside the inner class, Hud methods kept at top level) is present and
this final run is green.

---

## 1. Full regression — PASS

Command: `& .\tools\verify.ps1` → **exit code 0**, printed **`全部检查通过。`**, 0 `SCRIPT ERROR` /
`Parse Error`, `TREE_STABLE_DURING_VERIFY=True`.

All **6** `AUTOTEST_RESULT` lines (4 levels + 2 difficulty tiers):

```
AUTOTEST_RESULT level=0 tier=1 won=false rank=2  time=32.58  laps=[] xp=66  level_after=0
AUTOTEST_RESULT level=1 tier=1 won=true  rank=1  time=80.27  laps=[35.5666666666659, 44.6999999999975] xp=137 level_after=1
AUTOTEST_RESULT level=2 tier=1 won=false rank=3  time=135.47 laps=[44.6666666666654, 41.383333333331] xp=78  level_after=0
AUTOTEST_RESULT level=3 tier=1 won=false rank=10 time=112.73 laps=[] xp=27  level_after=0
AUTOTEST_RESULT level=0 tier=0 won=false rank=6  time=38.23  laps=[] xp=8   level_after=0
AUTOTEST_RESULT level=0 tier=2 won=false rank=2  time=27.77  laps=[] xp=91  level_after=1
```

Diagnostics proving the mechanics actually fire (not a “no crash” pass):

```
AUTOTEST_STATS   level=0 eye_coll=35  absorb=31  detach=28  lead_changes=9
AUTOTEST_STATS   level=3 eye_coll=163 absorb=171 detach=167 lead_changes=47
AUTOTEST_STAMINA level=0 min=0.00 max=1.00 cap_min=0.80
AUTOTEST_STAMINA level=2 min=0.00 max=1.00 cap_min=0.10
MECHANICS fused_at=0.00 detach_at=4.22 reabsorb_at=4.50 max_pack=4 best_pack_index=0 eye_form=0.78..1.30
```

The script’s own gates all held (audio assets, InputMap actions, eye collisions on level 1, stamina not
cosmetic, FINALE lead rotation, fusion/detach/reabsorb, form range).

## 2. Headless boot — PASS

`& Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 5` → exit **0**, only the engine
banner, **0** `SCRIPT ERROR` / `Parse Error` / `ERROR` lines. (The `hud.gd:46` parse error from the interim
state is gone; the class structure is now valid: `class StaminaBar` holds `trigger_break()` at L46, while
`Hud.show_scatter_hint/hide_scatter_hint/trigger_break` sit at top level L223/L228/L233.)

## 3. Versions — PASS

| Item | Evidence |
|---|---|
| README v0.16 | L1 `# Poga Poga — 最小可玩版本（v0.16）`; `## 本轮改了什么（v0.16）` L110 with 9-row table L112–121 |
| 项目规范 v1.13 | L1; changelog L20 `v1.13「--/== 表情 / 眼睛水平排列 / 团内碰撞耗耐力 / 回弹同帧 / 耐力条破碎 / 分裂小史莱姆 / 空地序章」` |
| GLOBAL_REQUIREMENTS v0.16 | L5 `最后更新：2026-11-21（v0.16）` |

Doc constants are now consistent with code and runtime:

- `项目规范.md` L475: `…分裂成小史莱姆、持续按移动键后按 0.45/0.75 聚合` (matches its own baseline L575
  `EXPLODE_CHECK PASS stamina=0.45 cap=0.75`, `tuning.gd:38-39` = 0.45/0.75, README L118/L299)
- `GLOBAL_REQUIREMENTS.md` L52: `…持续按移动键才聚合，聚合为耐力 0.45 / 上限 0.75；`; L115 same value
- Level count fixed: `项目规范.md` L433 `（4 关）`, L465 `--level=0/1/2/3 … 四关完赛`, L503 `4 关…`
- Grep over `项目规范.md` + `GLOBAL_REQUIREMENTS.md`: **0** remaining `0.35/0.55`, `五关`, `5 关`,
  `level=0/1/2/3/4` (README keeps `0.35/0.55` only in the historical v0.15 row — correct)

## 4. GLOBAL_REQUIREMENTS requirements — PASS

`--`/`==` (L53) · 散开/聚合 (L52, L117) · 碰撞扣耐力 incl. same pack (L54) · 空场地序章 + 起跑门加载 (L118) ·
叶片树冠 / menu leaf (L28) · Esc 揭幕守卫 (L29, L108) · `PRESS ANY KEY` attract (L26, L27, L104).

## 5. Screenshots and README references — PASS

- README: **15 image references, 0 missing**; `face_states.png` linked (L238), captions match content.
- Refreshed shots inspected (content, not just existence):

| file | sha256 (short) | verified content |
|---|---|---|
| `menu.png` | `dcb4b6f1…` | attract screen: LOGO + `PRESS ANY KEY` only, leaf-canopy backdrop |
| `menu_open.png` | `776ed68a…` | post-key menu with 4 items (开始游戏 / 操作说明 / 车手·加点 / 退出游戏) |
| `levels.png` | `f36c4504…` | 选择赛段: LEVEL 1 RING / 2 HILL / 3 FALLEN / 4 FINALE, 对手强度, “需要操作指引：关”, Esc 返回 |
| `driver.png` | `101a7dff…` | 车手: Lv.0, 经验 0/80, 耐力/速度/稳定 0/5, 洗点 + 重置等级, Esc 返回 |
| `race.png` | `f0604d12…` | in-race HUD: 排名 2/6, 圈 1/1, timer, folded waist stamina bar |
| `settlement.png` | `67575224…` | 结算: LEVEL 1 RING, 排名 2/6, 总用时 00:32.58, 获得经验 +66, 重试/下一关/返回菜单 — matches the level-0 autotest result above |
| `face_states.png` | `f2712eab…` | `--` / `==` / `><` + 7 mini slimes, no black socket oval (scatter early-return `racer.gd:615-616` precedes socket draws `:633-634`) |
| `tutorial.png` | `1b55e01a…` | prestart empty field + start gate + “学习模式 引导 3/5”, no slow-mo/letterbox focus |

## 6. Workspace cleanliness — PASS

`_*.py` / `_*.txt` anywhere outside `.git`: **0**; zero-byte files outside `.godot`: **0** (the temporary
`tools/_r16_fix3.py` helper used for the 14:19 code edit has been removed).

## 7. Role reports — PASS (complete)

`docs/acceptance_maker.md`, `acceptance_playtest.md`, `acceptance_judge.md` (prior rounds) plus
`docs/agent_maker.md` (14:02:07) and `docs/agent_playtest.md` (14:17:36, 13 604 bytes — records
`STAMINA_CHECK`, `EXPLODE_CHECK 0.45/0.75`, `PAUSE_CHECK frozen=0.800`, `PRESTART_CHECK PASS`).

## 8. Requested mechanics documented — PASS

| # | Requirement | Docs evidence |
|---|---|---|
| 1 | `--` / `==` expressions | README L114; spec L20/L476; GLOBAL L53/L116 |
| 2 | Horizontal eyes / `><` tips inward | README L114; GLOBAL L53 |
| 3 | Collision stamina drain (incl. same pack) | README L115; GLOBAL L54 |
| 4 | Empty-rebound cap sync (same frame) | README L116; GLOBAL L49; spec L270–271 |
| 5 | Stamina bar break (right shattered, left draining) | README L117; GLOBAL L117 |
| 6 | Split mini slimes + press-to-regroup | README L118; GLOBAL L52/L115; spec L475 |
| 7 | Esc return guard (no PRESS ANY KEY) | README L119; GLOBAL L29/L108 |
| 8 | Prestart empty field + track load at gate | README L121; GLOBAL L118; spec L477 |
| 9 | Menu leaf backdrop | README L120; GLOBAL L28 |

## 9. Issues found in this final pass

None blocking. No new documentation/screenshot inconsistency, no script errors, no temporary artifacts,
no missing image references. The two earlier blockers (stale `0.35/0.55` constants; `hud.gd:46` parse error)
are both resolved and re-verified in this run.

## Verdict

**JUDGE PASS**

- `tools/verify.ps1`: exit 0, `全部检查通过`, 6/6 `AUTOTEST_RESULT`, `MECHANICS fused 0.00 / 4.22 / 4.50`,
  no `SCRIPT ERROR`, tree stable during the run.
- Headless boot clean (exit 0, no errors).
- README v0.16 (+ v0.16 round table, face_states link), 项目规范 v1.13, GLOBAL_REQUIREMENTS v0.16, all
  constants and level counts consistent with code (`0.45/0.75`, 4 levels).
- All 15 README image references resolve; refreshed menu / levels / driver / race / settlement screenshots
  verified visually and match the current build and the autotest baseline.
- Requested mechanics documented in README/spec/GLOBAL and corroborated by code + runtime checks.
- Workspace clean; role reports complete.