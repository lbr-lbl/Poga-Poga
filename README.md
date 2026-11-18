# Poga Poga — 最小可玩版本（v0.5）

俯视角史莱姆（鼻涕虫）融合竞速。玩家控制一只史莱姆在黑白林间小道上慢慢蠕动、滑行、转向；
靠近其他史莱姆时**躯体会真正融合成一坨连续的黏液**，只有眼睛各自露在外面；
真正的碰撞发生在**眼睛之间**——眼睛撞到一起会减速、稳定崩溃、约束松弛，甚至把整团撞散。

> 基于 `策划案/《Poga Poga》策划案 v0.2.md` 落地。
> **v0.5 按试玩反馈改版**：UI 统一、取消镜头旋转、耐力真正生效、经验/等级替换点数、
> AI 三档难度、障碍物可读性、史莱姆表情形态、玩家史莱姆音效。

---

## 快速开始

**环境**：Godot **4.7.2**（`4.7.x` 均可），Windows 默认 `d3d12 + mobile` 渲染后端。

```bash
# 方式 A：用 Godot 打开 project.godot，F5 运行（主场景 res://scenes/main.tscn）
# 方式 B：命令行
godot --path .
```

首次运行自动导入字体与音效。工程无第三方插件依赖。

**操作**

| 行为 | 键盘 | 手柄 | 触屏（原型） |
| --- | --- | --- | --- |
| 加速 | `W` / `↑` | `A` / 右扳机 | 按住屏幕 |
| 刹车 | `S` / `↓` / `空格` | `B` / 左扳机 | 双指按下 |
| 左转 / 右转 | `A` `D` / `←` `→` | 左摇杆 | 左右拖动 |
| 滑行 | 松开所有键 | — | 松手 |
| 重试 | `R` | `Y` | 结算按钮 |
| 返回菜单 | `Esc` | `Start` | 结算按钮 |
| 开关像素化（调试） | `F3` | — | — |

**过关条件**：玩家个体排名第一。失败可无限立即重试。

---

## 本轮改了什么（v0.5）

| # | 反馈 | 处理 |
| --- | --- | --- |
| 1 | 主菜单 UI 风格要统一 | 重做 [main_menu.gd](src/ui/main_menu.gd)：与结算/HUD 共用同一套 [UiKit](src/ui/ui_kit.gd)（像素字体、直角细边框、统一字号层级、统一选中态），顶部身份区 + 左右两栏 + 底部操作条 |
| 2 | 镜头旋转头晕 | **取消相机旋转**（固定朝向、上=北），只保留平滑跟随 + 速度/团规模缩放 |
| 3 | 耐力条像摆设 | 耐力消耗改为「基础消耗 + 速度相关消耗」（低速也持续掉），上限也会明显下降；HUD 改成大号分段条 + 百分比数字 + 低耐力闪烁 + 上限刻线 |
| 4 | 点数增益过大、太容易获得、重置回到 5 级 | 改为**经验升级**：每场按「排名 × AI 难度 × 关卡难度」得经验，升级所需经验递增（80 + 30×等级），每级 +1 加点；属性等级 **0→5** 起步，重置回到 **Lv.0 / 0 经验 / 0 加点**；单点增益下调（速度 +3%/点等）。**AI 分三档**：简单/普通/困难，对手属性、失误率、弯道刹车、领骑耐心、融合倾向逐档增强，经验加成 ×1.0 / ×1.45 / ×2.0 |
| 5 | 障碍物看不清 | 凋落物全部加 **白描边 + 深色主体 + 双色警示环**，并在浏览器尺寸下重新调过对比度 |
| 6 | 史莱姆形态 | 加速时两眼**靠近**（×0.78），刹车时**拉远**（×1.30）；碰撞时眯成 **`><`** 并左右晃动（眼睛与黏液躯体一起抖） |
| 7 | 音效 | 新增玩家史莱姆位置音源 [slime_audio.gd](src/audio/slime_audio.gd)：加速循环「win~ win~」、刹车循环「Pooo~」、碰撞一次性「Poga」；音频由 [gen_slime_sfx.py](tools/gen_slime_sfx.py) 程序化生成 |

---

## 画面

| 主菜单 | 比赛 |
| --- | --- |
| ![主菜单](docs/screenshots/menu.png) | ![比赛](docs/screenshots/race.png) |

| 结算 |
| --- |
| ![结算](docs/screenshots/settlement.png) |

> 截图由 `godot --path . -- --shots` 自动生成。

---

## 核心机制

### 1. 躯体融合：一坨黏液 + 各自的眼睛

- 融合团成员躯体中心间距仅 26px（小于两倍半径 36px），躯体必然重叠；
- 躯体由 [SlimeBlobLayer](src/view/blob_layer.gd) + [slime_blob.gdshader](shaders/slime_blob.gdshader) 的
  **metaball 场**实时合成：靠拢融成一坨、拉开自然断开；每只史莱姆的灰阶体色参与场混合，融合后仍能看出个体；
- 眼睛由各自的 `Racer` 画在黏液层之上（“融合后只露眼睛”），眼睛大小/间距是识别个体的主要线索，玩家眼睛更大更亮。

### 2. 碰撞 = 眼睛撞眼睛

- 躯体不互相碰撞（它们是融合的），只有眼睛是“硬”的；
- 同团内眼睛相撞：减速 + 稳定低谷 + 约束张力激增（`EYE_SHOCK`），撞得深会把整团撞散；
- 不同个体眼睛相撞：惩罚更重，双方直接脱离当前团；
- 眼睛间距会随团内张力挤近，越挤越容易撞。

### 3. 鼻涕虫式移动

最高速 215px/s、加速度低、侧向抓地低、滑行阻力小：起步肉、转向滑、松手还能溜很远。
加速力有轻微蠕动节律，配合黏液 shader 的呼吸/拉伸，移动像一拱一拱的鼻涕虫。

### 4. 黑白林间小道 + 树叶碰撞边界

纯灰阶画面；赛道两侧是成片**树叶轮廓**，贴边叶片同时是碰撞体（撞上会减速、掉耐力、可能散团），
外圈还有更暗的叶团与树冠剪影。障碍物（树枝/落叶/石子）带白描边与警示环。

### 5. 相机

固定俯视朝向，平滑跟随玩家；速度越快镜头略拉远、融合团越大略拉远。不再随角色旋转。

### 6. 成长与难度

- 车手等级 0~10：经验 = `70 × 关卡难度 × 排名系数 × AI 难度加成`；
- 升级所需经验 `80 + 30 × 当前等级`，每升 1 级获得 1 点自由加点；
- 属性三项（耐力/速度/稳定）等级 0~5，最终属性 = 基础 5 + 等级；重置按钮回到 Lv.0；
- AI 三档（简单/普通/困难）在菜单选择：属性加成 0 / +0.3 / +0.6，速度 ×0.85 / ×1.0 / ×1.08，
  失误率 ×2.4 / ×1.0 / ×0.35，弯道刹车与领骑耐心也逐档变化。

### 7. 表情形态与音效

- 加速：两眼靠近；刹车：两眼拉远；碰撞：眯成 `><` + 左右晃动（约 0.55s）；
- 音效挂在玩家史莱姆上（位置音源），加速/刹车循环、碰撞一次性；音高随速度/随机微调。

---

## 已实现内容（对照策划案）

| 策划案条目 | 实现情况 |
| --- | --- |
| Demo 三关（环 1 / 坡 2 / 凋落物 3 圈） | ✅ `src/data/level_catalog.gd` |
| 玩家 + AI 5 只同台，个体第一过关 | ✅ `src/sim/race.gd` |
| 自动吸附 / 分离、眼睛约束、纵列增益、易散团 | ✅ `fusion_pack.gd` + `race.gd` 眼睛碰撞 |
| 团内调位（加速前移 / 刹车后移 / 转向偏移） | ✅ 纵向弹力刻意做软 |
| 碰撞：减速、稳定低谷、约束松弛、易散团 | ✅ 眼睛相撞触发 |
| 双层耐力、滑行恢复、刹车不是最优解 | ✅ `racer.gd`，HUD 可见波动 |
| 三属性与成长 | ✅ 经验升级 + 加点（比赛中锁定） |
| 每圈检查点、个体过线记圈、终点判定 | ✅ 弧长跨圈修正 + 检查点顺序校验 |
| AI：找团/跟车/耐心轮换/弯道/耐力/冲刺/避障/脱困 | ✅ `ai_driver.gd`（含三档难度） |
| HUD / 结算 / 加点 UI | ✅ 统一像素风格 |
| 黑白像素、林间小道、无融合提示、无玩家标识 | ✅ 纯灰阶 + metaball 黏液 + 眼睛识别 |
| 史莱姆形态与音效 | ✅ 眼睛形态 + 玩家位置音源 |
| 2.5D 微倾 / 真实坡度 | ⚠️ 仍为俯视 2D，坡度用分区速度/耐力修正近似 |
| 团体赛 / 服装系统 | ⏸ 未实现（保留个体记圈接口） |

## 简化与边界

- **团体赛**：仍只保留个体记圈/排名。
- **移动端触屏**：按住加速 + 横向拖动转向 + 双指刹车，未真机验证。
- **服装系统**：用体色灰阶 + 眼睛大小/间距区分个体。
- **坡度**：`LevelDef.slopes` 分区系数，无真实高度物理。
- **音效**：目前只有玩家史莱姆的 3 个程序化音效，无 BGM。

---

## 工程结构

```
poga-poga/
├─ project.godot
├─ scenes/main.tscn               # 唯一入口场景（其余节点由脚本构建）
├─ src/
│  ├─ main.gd                     # 应用根：菜单/比赛/结算、像素化层、自动化测试入口
│  ├─ core/                       # game_state.gd（等级/经验/存档）、input_setup.gd（InputMap）
│  ├─ data/                       # tuning.gd（唯一数值源）、level_def.gd、level_catalog.gd
│  ├─ sim/                        # race_track / racer / fusion_pack / ai_driver / race
│  ├─ view/                       # track_view（赛道/树叶/障碍）、blob_layer（黏液层）
│  ├─ audio/                      # slime_audio.gd（玩家史莱姆位置音源）
│  └─ ui/                         # ui_kit / hud / main_menu / settlement
├─ shaders/
│  ├─ slime_blob.gdshader         # metaball 躯体融合
│  └─ pixelate.gdshader           # 全屏像素化 + 色阶量化
├─ assets/
│  ├─ fonts/                      # Ark Pixel 10px 中文像素字体（OFL-1.1）
│  └─ sfx/                        # winwin / pooo / poga（程序化生成）
├─ tools/
│  ├─ verify.ps1                  # 一键验证
│  └─ gen_slime_sfx.py            # 音效生成脚本
├─ docs/screenshots/
├─ 策划案/
├─ README.md
└─ 项目规范.md
```

**渲染层级**（从下到上）：

```
0  世界：赛道(z=-10) → 黏液层(z=5) → 眼睛(z=10/20)
1  PixelLayer：全屏像素化 + 色阶量化
2  HUD（CanvasLayer）
3  UI：菜单 / 结算（CanvasLayer）
```

---

## 自动化验证

```powershell
# 导入 + 启动检查 + 三关自动跑 + 难度档位冒烟 + 机制验证
powershell -NoProfile -File tools\verify.ps1

# 额外生成 3 张界面截图
powershell -NoProfile -File tools\verify.ps1 -Shots
```

单条命令：

```bash
godot --headless --path . --fixed-fps 60 -- --autotest --level=1 --tier=1
godot --headless --path . --fixed-fps 60 -- --autotest --pattern=mechanics
godot --path . --resolution 1280x720 -- --shots
```

输出字段：

| 输出 | 含义 |
| --- | --- |
| `AUTOTEST_RESULT level/tier/won/rank/time/laps/xp/level_after` | 单关自动跑结果（玩家由 AI 接管） |
| `AUTOTEST_RANKING` | 每个个体的进度与平均速度 |
| `AUTOTEST_STATS absorb/detach/eye_coll/leaf_coll/debris_coll/offroad_ratio/packs` | 融合/散团、眼睛碰撞、树叶/障碍碰撞、越野比例 |
| `AUTOTEST_STAMINA min/max/cap_min/eye_form` | 耐力波动范围、眼睛形态倍率范围（<1 加速挤近，>1 刹车拉远） |
| `MECHANICS fused/detach/reabsorb/eye_form` | 自动吸附 → 主动散团 → 重新吸附，以及形态验收 |

**当前基线**（Godot 4.7.2 / Windows，`--fixed-fps 60`，普通难度，AI 种子固定）：

| 关卡 | 自动跑结果 |
| --- | --- |
| 第 1 关 环（1 圈） | `rank=3 time=35.85 xp=46` |
| 第 2 关 坡（2 圈） | `rank=2 time=78.75 xp=89 → Lv.1` |
| 第 3 关 凋落物（3 圈） | `rank=2 time=125.93 xp=112 → Lv.1` |
| 简单 / 困难（第 1 关冒烟） | `tier=0 rank=4 time=41.78` / `tier=2 rank=6 time=34.58` |
| 机制 | `fused_at=0.00 detach_at=4.22 reabsorb_at=12.02 max_pack=4 best_pack_index=0 eye_form=0.78..1.30` |
| 耐力 | `min=0.00 max=1.00 cap_min=0.85`（条会明显起伏） |

> 自动驾驶不是“最优玩家”：它不会主动卡位/突围，简单难度下反而容易被慢团拖住。
> 所以难度档位的“手感”需要人工试玩确认，自动测试只保证不崩、机制生效、时长合理。

---

## 调参指南

| 想改什么 | 看哪里 |
| --- | --- |
| 移动手感（慢/黏） | [tuning.gd](src/data/tuning.gd)：`BASE_MAX_SPEED`、`BASE_ACCEL`、`LATERAL_GRIP`、`COAST_DRAG_BASE`、`GOO_PULSE_*` |
| 耐力 | `DRAIN_ACCEL / DRAIN_CAP / REGEN_*`；耐力条在 `hud.gd` |
| 融合 | `PACK_*`、`ABSORB_*`、`EYE_*` |
| 难度 | `AI_TIER_SPEED / MISTAKE / BRAKE / PATIENCE / FUSE / STATS` |
| 成长 | [game_state.gd](src/core/game_state.gd)：`XP_BASE / XP_GROWTH / BASE_XP / RANK_XP_COEF / AI_TIER_XP_COEF / LEVEL_MAX` |
| 关卡 | [level_catalog.gd](src/data/level_catalog.gd)：圈数、宽度、AI 基础参数、坡度、障碍物 |

改完跑 `tools/verify.ps1`：重点看 `AUTOTEST_STATS`（机制是否发生）、`AUTOTEST_STAMINA`（耐力/形态是否在动）、
`AUTOTEST_RESULT`（时长与经验）。

---

## 已知问题 / 后续

1. 音效只有玩家史莱姆 3 个，且未做混音总线 / 设置开关；后续可补 AI 环境音与 BGM。
2. 触屏方案未真机验证。
3. AI 突围意识弱：简单档中自动跑会被慢团拖住（人类玩家影响较小）。
4. 融合团 churn 仍偏高（一场 10~30 次融合/散团），后续可加“撞眼后短暂免疫”。
5. 无暂停菜单、无设置项（仅 `F3` 切像素化）。

## 素材与许可

- **字体**：Ark Pixel Font 10px（TakWolf），SIL OFL-1.1，见 `assets/fonts/OFL.txt`。
- **音效**：`tools/gen_slime_sfx.py` 程序化生成，无第三方版权。
- **图标**：Godot 模板 `icon.svg`。