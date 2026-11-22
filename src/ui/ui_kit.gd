class_name UiKit
extends RefCounted
## UI 构建工具：统一字体、字号、配色、按钮样式。
##
## 约定：
## - 像素字体 Ark Pixel（OFL-1.1），字号必须是 10 的整数倍才能保持像素锐利；
## - 所有界面文字从这里取样式，禁止各处零散 add_theme_*_override；
## - 字体缺失时自动退回引擎默认字体（保证工程可运行）。

const FONT_PATH := "res://assets/fonts/ark-pixel-10px-monospaced-zh_hans.ttf"
const SIZE_SMALL := 20
const SIZE_BODY := 30
const SIZE_LARGE := 40
const SIZE_HERO := 80

const PANEL_BG := Color(0.035, 0.045, 0.035, 0.92)
const PANEL_BORDER := Color(0.52, 0.60, 0.49, 0.85)
const PANEL_BORDER_DIM := Color(0.24, 0.30, 0.23, 0.9)
const BUTTON_BG := Color(0.07, 0.09, 0.07, 0.9)
const BUTTON_BG_HOVER := Color(0.14, 0.18, 0.13, 0.95)
const BUTTON_BG_PRESSED := Color(0.05, 0.06, 0.05, 0.95)

static var _font: Font = null
static var _font_checked: bool = false


static func font() -> Font:
    if not _font_checked:
        _font_checked = true
        if ResourceLoader.exists(FONT_PATH):
            var loaded := load(FONT_PATH)
            if loaded is Font:
                _font = loaded
    if _font == null:
        return ThemeDB.fallback_font
    return _font


static func label(text: String, font_size: int = SIZE_BODY, color: Color = Tuning.COLOR_TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
    var node := Label.new()
    node.text = text
    node.add_theme_font_override("font", font())
    node.add_theme_font_size_override("font_size", font_size)
    node.add_theme_color_override("font_color", color)
    node.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.02, 0.95))
    node.add_theme_constant_override("outline_size", 6)
    node.horizontal_alignment = align
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node


static func button(text: String, font_size: int = SIZE_BODY, padding: float = 22.0, sound: String = "ui_click") -> Button:
    var node := Button.new()
    node.text = text
    node.add_theme_font_override("font", font())
    node.add_theme_font_size_override("font_size", font_size)
    node.add_theme_color_override("font_color", Tuning.COLOR_TEXT)
    node.add_theme_color_override("font_hover_color", Tuning.COLOR_ACCENT)
    node.add_theme_color_override("font_focus_color", Tuning.COLOR_ACCENT)
    node.add_theme_color_override("font_pressed_color", Tuning.COLOR_TEXT_DIM)
    node.add_theme_color_override("font_disabled_color", Color(0.45, 0.50, 0.44))
    node.add_theme_stylebox_override("normal", _box(BUTTON_BG, PANEL_BORDER_DIM, 3, padding))
    node.add_theme_stylebox_override("hover", _box(BUTTON_BG_HOVER, PANEL_BORDER, 3, padding))
    node.add_theme_stylebox_override("pressed", _box(BUTTON_BG_PRESSED, Tuning.COLOR_ACCENT, 3, padding))
    node.add_theme_stylebox_override("focus", _box(Color(0.10, 0.13, 0.10, 0.6), Tuning.COLOR_ACCENT, 3, padding))
    node.add_theme_stylebox_override("disabled", _box(Color(0.04, 0.05, 0.04, 0.75), Color(0.18, 0.22, 0.17), 3, padding))
    node.focus_mode = Control.FOCUS_ALL
    if display_server_has_audio():
        node.pressed.connect(func() -> void: UiSfx.play(sound, -6.0))
    return node


## 无头/纯服务端环境不播放 UI 音效。
static func display_server_has_audio() -> bool:
    return DisplayServer.get_name() != "headless"


static func panel(bg: Color = PANEL_BG, border: Color = PANEL_BORDER_DIM, padding: float = 18.0) -> PanelContainer:
    var node := PanelContainer.new()
    node.add_theme_stylebox_override("panel", _box(bg, border, 3, padding))
    return node


static func _box(bg: Color, border: Color, margin: int = 3, padding: float = 22.0) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = border
    style.border_width_left = margin
    style.border_width_right = margin
    style.border_width_top = margin
    style.border_width_bottom = margin
    style.corner_radius_top_left = 0
    style.corner_radius_top_right = 0
    style.corner_radius_bottom_left = 0
    style.corner_radius_bottom_right = 0
    style.content_margin_left = padding
    style.content_margin_right = padding
    style.content_margin_top = 10.0
    style.content_margin_bottom = 10.0
    return style


static func spacer(min_height: float) -> Control:
    var node := Control.new()
    node.custom_minimum_size = Vector2(0.0, min_height)
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node


## 通用像素进度条（经验条 / 耐力条等）。数值 0..1。
class PixBar:
    extends Control
    var value: float = 0.0
    var fill_color: Color = Tuning.COLOR_BAR_FILL
    var background_color: Color = Color("2b2b2b")
    var shadow_value: float = -1.0
    var shadow_color: Color = Tuning.COLOR_BAR_CAP
    var segments: int = 4

    func _draw() -> void:
        var rect := Rect2(Vector2.ZERO, size)
        draw_rect(rect, background_color)
        if shadow_value >= 0.0:
            draw_rect(Rect2(0.0, 0.0, size.x * clampf(shadow_value, 0.0, 1.0), size.y), shadow_color)
        draw_rect(Rect2(0.0, 0.0, size.x * clampf(value, 0.0, 1.0), size.y), fill_color)
        for i: int in range(1, segments):
            var x := size.x * float(i) / float(segments)
            draw_line(Vector2(x, 0.0), Vector2(x, size.y), Color(0.0, 0.0, 0.0, 0.28), 1.0)
        draw_rect(rect, Color(0.66, 0.66, 0.66, 0.9), false, 2.0)

    func set_value(new_value: float) -> void:
        value = new_value
        queue_redraw()


static func bar(height: float = 16.0) -> PixBar:
    var node := PixBar.new()
    node.custom_minimum_size = Vector2(0.0, height)
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return node


## 统一的“选中/未选中”按钮外观（难度选择等分段控件）。
static func set_button_selected(button: Button, selected: bool, padding: float = 14.0) -> void:
    if selected:
        button.add_theme_stylebox_override("normal", _box(Color(0.16, 0.16, 0.16, 0.95), Tuning.COLOR_ACCENT, 3, padding))
        button.add_theme_stylebox_override("hover", _box(Color(0.20, 0.20, 0.20, 0.95), Tuning.COLOR_ACCENT, 3, padding))
        button.add_theme_color_override("font_color", Tuning.COLOR_ACCENT)
    else:
        button.add_theme_stylebox_override("normal", _box(BUTTON_BG, PANEL_BORDER_DIM, 3, padding))
        button.add_theme_stylebox_override("hover", _box(BUTTON_BG_HOVER, PANEL_BORDER, 3, padding))
        button.add_theme_color_override("font_color", Tuning.COLOR_TEXT_DIM)


static func separator() -> HSeparator:
    var node := HSeparator.new()
    var style := StyleBoxFlat.new()
    style.bg_color = PANEL_BORDER_DIM
    style.content_margin_top = 1.0
    style.content_margin_bottom = 1.0
    node.add_theme_stylebox_override("separator", style)
    return node
