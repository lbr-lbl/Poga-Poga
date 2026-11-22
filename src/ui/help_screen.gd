class_name HelpScreen
extends Control
## 操作说明：把按键、融合规则、耐力规则和比赛目标讲清楚。
## 从主菜单进入，Esc/返回按钮回主菜单。

signal back_pressed()


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build()


func _build() -> void:
    add_child(MenuBackdrop.new())

    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 60)
    margin.add_theme_constant_override("margin_right", 60)
    margin.add_theme_constant_override("margin_top", 40)
    margin.add_theme_constant_override("margin_bottom", 24)
    add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    margin.add_child(column)

    var header := HBoxContainer.new()
    column.add_child(header)
    var title := UiKit.label("操作说明", 60, Tuning.COLOR_ACCENT)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(title)
    header.add_child(UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM))

    column.add_child(UiKit.separator())

    var content := HBoxContainer.new()
    content.add_theme_constant_override("separation", 18)
    content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(content)

    content.add_child(_panel("移动", [
        "W / ↑：加速（手柄 A，屏幕按住）",
        "S / 空格：刹车（手柄 B / 左扳机）",
        "A / D 或 ← →：转向（手柄左摇杆）",
        "松开所有键：滑行，慢慢恢复耐力",
    ]))
    content.add_child(_panel("融合与碰撞", [
        "靠近其他史莱姆会自动融合成一团",
        "同一团里，所有史莱姆会共享部分速度增益",
        "眼睛撞在一起会掉速、让团变散",
        "撞得太狠，整团会被撞散",
    ]))
    content.add_child(_panel("耐力", [
        "耐力条最窄处 = 耐力见底",
        "耐力低时极速和加速度都会下降",
        "耐力清空会进入喘息，之后才慢慢恢复",
        "清空回弹时，临时上限会掉一截",
    ]))

    var bottom := HBoxContainer.new()
    bottom.add_theme_constant_override("separation", 18)
    column.add_child(bottom)
    var goals := UiKit.panel(Tuning.COLOR_PANEL, UiKit.PANEL_BORDER_DIM, 14.0)
    goals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bottom.add_child(goals)
    var goals_column := VBoxContainer.new()
    goals_column.add_theme_constant_override("separation", 6)
    goals.add_child(goals_column)
    goals_column.add_child(UiKit.label("目标与其他", UiKit.SIZE_BODY, Tuning.COLOR_TEXT))
    goals_column.add_child(UiKit.label("目标：第一名冲线；失败按 R 重试。", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM))
    goals_column.add_child(UiKit.label("Esc：暂停菜单（继续 / 重试 / 返回主菜单）    M：音乐静音    F3：像素化开关", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM))

    var back := UiKit.button("返回主菜单", UiKit.SIZE_BODY, 12.0, "ui_back")
    back.custom_minimum_size = Vector2(0.0, 50.0)
    back.pressed.connect(func() -> void: back_pressed.emit())
    column.add_child(back)


func _panel(title: String, lines: Array[String]) -> Control:
    var panel := UiKit.panel(Tuning.COLOR_PANEL, UiKit.PANEL_BORDER_DIM, 16.0)
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 6)
    panel.add_child(column)
    column.add_child(UiKit.label(title, UiKit.SIZE_BODY, Tuning.COLOR_ACCENT))
    for line: String in lines:
        var label := UiKit.label(line, UiKit.SIZE_SMALL, Tuning.COLOR_TEXT)
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        column.add_child(label)
    return panel
