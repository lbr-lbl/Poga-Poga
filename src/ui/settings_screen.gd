class_name SettingsScreen
extends Control
## 设置：操作 / 声音 / 画面。操作支持键盘与手柄各自两个备用键、冲突检测、监听改键。

signal back_pressed()

const ACTION_NAMES := {
    "accelerate": "加速", "brake": "刹车", "steer_left": "左转", "steer_right": "右转",
    "retry": "重试", "confirm": "确认", "back": "返回", "mute": "静音",
}

var _tab_buttons: Array[Button] = []
var _mode_buttons: Array[Button] = []
var _content: VBoxContainer
var _toast: Label
var _settings: Dictionary = {}
var _key_buttons: Dictionary = {}
var _bind_mode: String = "keyboard"
var _listening_action := ""
var _listening_slot := 0
var _gyro_check: CheckButton
var _current_tab: int = 0
var _gyro_refresh_done: bool = false
var _sfx_slider: HSlider
var _music_slider: HSlider
var _window_option: OptionButton
var _fps_option: OptionButton


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _settings = SettingsStore.load_settings()
    _build()
    _show_tab(0)
    if OS.get_cmdline_user_args().has("--settings-pad"):
        _set_bind_mode("pad")
    if OS.get_cmdline_user_args().has("--settings-test"):
        _run_settings_test()


func _build() -> void:
    add_child(MenuBackdrop.new())
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 60)
    margin.add_theme_constant_override("margin_right", 60)
    margin.add_theme_constant_override("margin_top", 24)
    margin.add_theme_constant_override("margin_bottom", 12)
    add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    margin.add_child(column)

    var header := HBoxContainer.new()
    column.add_child(header)
    var title := UiKit.label("设置", 60, Tuning.COLOR_ACCENT)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(title)
    var back_button := UiKit.button("返回  Esc", UiKit.SIZE_SMALL, 10.0, "ui_back")
    back_button.pressed.connect(func() -> void: back_pressed.emit())
    header.add_child(back_button)

    var tabs := HBoxContainer.new()
    tabs.add_theme_constant_override("separation", 10)
    column.add_child(tabs)
    for name: String in ["操作", "声音", "画面"]:
        var button := UiKit.button(name, UiKit.SIZE_BODY, 12.0, "ui_click")
        button.custom_minimum_size = Vector2(180.0, 44.0)
        button.pressed.connect(_show_tab.bind(tabs.get_child_count()))
        tabs.add_child(button)
        _tab_buttons.append(button)
    column.add_child(UiKit.separator())

    _content = VBoxContainer.new()
    _content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _content.add_theme_constant_override("separation", 4)
    column.add_child(_content)

    _toast = UiKit.label("", UiKit.SIZE_SMALL, Tuning.COLOR_ACCENT)
    column.add_child(_toast)


func _show_tab(index: int) -> void:
    _current_tab = index
    _gyro_check = null
    _mode_buttons.clear()
    _key_buttons.clear()
    for i: int in range(_tab_buttons.size()):
        UiKit.set_button_selected(_tab_buttons[i], i == index, 12.0)
    for child: Node in _content.get_children():
        child.queue_free()
    match index:
        0:
            _build_controls()
        1:
            _build_audio()
        _:
            _build_video()
    _focus_default()


func _process(_delta: float) -> void:
    # 陀螺仪可能在打开设置后才被探测到；探测到后刷新一次操作页
    if OS.has_feature("mobile") and _current_tab == 0 and GyroProbe.available and not _gyro_refresh_done and _gyro_check == null:
        _gyro_refresh_done = true
        _show_tab(0)


func _focus_default() -> void:
    if not _mode_buttons.is_empty() and is_instance_valid(_mode_buttons[0]):
        _mode_buttons[0].grab_focus()
        return
    for child: Node in _content.get_children():
        if child is Button and not (child as Button).disabled:
            (child as Button).grab_focus()
            return
        if child is Control:
            for sub: Node in child.get_children():
                if sub is Button and not (sub as Button).disabled:
                    (sub as Button).grab_focus()
                    return
                if sub is HSlider or sub is OptionButton:
                    (sub as Control).grab_focus()
                    return


func _build_controls() -> void:
    _content.add_child(UiKit.label("当前输入：%s" % InputDevice.guide(), UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM))
    var mode_row := HBoxContainer.new()
    mode_row.add_theme_constant_override("separation", 8)
    _content.add_child(mode_row)
    mode_row.add_child(UiKit.label("改键对象", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT))
    for mode_name: String in ["键盘", "手柄"]:
        var mode_button := UiKit.button(mode_name, UiKit.SIZE_SMALL, 8.0, "ui_click")
        mode_button.custom_minimum_size = Vector2(120.0, 30.0)
        mode_button.pressed.connect(_set_bind_mode.bind("keyboard" if mode_name == "键盘" else "pad"))
        mode_row.add_child(mode_button)
        _mode_buttons.append(mode_button)

    var rows := VBoxContainer.new()
    rows.add_theme_constant_override("separation", 2)
    _content.add_child(rows)
    for action: String in SettingsStore.ACTIONS:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 8)
        rows.add_child(row)
        var name_label := UiKit.label(ACTION_NAMES.get(action, action), UiKit.SIZE_SMALL, Tuning.COLOR_TEXT)
        name_label.custom_minimum_size = Vector2(92.0, 0.0)
        row.add_child(name_label)
        for slot: int in range(2):
            var button := UiKit.button("", UiKit.SIZE_SMALL, 8.0, "ui_click")
            button.custom_minimum_size = Vector2(230.0, 30.0)
            button.pressed.connect(_start_listen.bind(action, slot))
            row.add_child(button)
            _key_buttons["%s:%d" % [action, slot]] = button
    _refresh_bind_buttons()

    if OS.has_feature("mobile") and GyroProbe.available:
        _gyro_check = CheckButton.new()
        _gyro_check.text = "开启陀螺仪（与触屏互斥）"
        _gyro_check.button_pressed = bool(_settings.get("gyro", false))
        _gyro_check.toggled.connect(_on_gyro_toggled)
        _content.add_child(_gyro_check)
    elif OS.has_feature("mobile"):
        _content.add_child(UiKit.label("未检测到陀螺仪，使用触屏操作", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM))
    else:
        _content.add_child(UiKit.label("触屏 / 陀螺仪仅在移动端启用", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM))
    _content.add_child(UiKit.label("方向键选中按钮，Enter / 手柄 A 确认；改键时按任意键，Esc 取消", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT_DIM))


func _run_settings_test() -> void:
    await get_tree().create_timer(0.3).timeout
    _show_tab(1)
    await get_tree().create_timer(0.25).timeout
    _show_tab(2)
    await get_tree().create_timer(0.25).timeout
    _show_tab(0)
    await get_tree().create_timer(0.25).timeout
    print("SETTINGS_TAB_TEST PASS")
    get_tree().quit(0)


func _set_bind_mode(mode: String) -> void:
    _bind_mode = mode
    _refresh_bind_buttons()


func _start_listen(action: String, slot: int) -> void:
    _listening_action = action
    _listening_slot = slot
    _toast.text = "按下新手柄键…" if _bind_mode == "pad" else "按下新按键…"


func _input(event: InputEvent) -> void:
    if _listening_action == "":
        return
    if _bind_mode == "pad":
        if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
            var pad_button := (event as InputEventJoypadButton).button_index
            if _pad_conflicts(pad_button):
                _toast.text = "这个手柄键已经被占用"
            else:
                var pads: Dictionary = _settings["padbinds"]
                var buttons: Array = pads.get(_listening_action, [0, 0])
                buttons[_listening_slot] = pad_button
                pads[_listening_action] = buttons
                _settings["padbinds"] = pads
                SettingsStore.save_settings(_settings)
                SettingsStore.apply_padbinds(pads)
                _refresh_bind_buttons()
                _toast.text = "已保存"
                _listening_action = ""
            get_viewport().set_input_as_handled()
        return
    if event is InputEventKey and (event as InputEventKey).pressed:
        var key := (event as InputEventKey).physical_keycode
        if key == KEY_ESCAPE:
            _listening_action = ""
            _toast.text = "已取消"
        elif _key_conflicts(key):
            _toast.text = "这个键已经被占用"
        else:
            var binds: Dictionary = _settings["keybinds"]
            var keys: Array = binds.get(_listening_action, [0, 0])
            keys[_listening_slot] = key
            binds[_listening_action] = keys
            _settings["keybinds"] = binds
            SettingsStore.save_settings(_settings)
            SettingsStore.apply_keybinds(binds)
            _refresh_bind_buttons()
            _toast.text = "已保存"
            _listening_action = ""
        get_viewport().set_input_as_handled()


func _key_conflicts(key: int) -> bool:
    var binds: Dictionary = _settings["keybinds"]
    for action: String in binds.keys():
        var keys: Array = binds[action]
        for slot: int in range(keys.size()):
            if action == _listening_action and slot == _listening_slot:
                continue
            if int(keys[slot]) == key and key != 0:
                return true
    return false


func _pad_conflicts(pad_button: int) -> bool:
    var pads: Dictionary = _settings["padbinds"]
    for action: String in pads.keys():
        var buttons: Array = pads[action]
        for slot: int in range(buttons.size()):
            if action == _listening_action and slot == _listening_slot:
                continue
            if int(buttons[slot]) == pad_button and pad_button >= 0:
                return true
    return false


func _refresh_bind_buttons() -> void:
    for i: int in range(_mode_buttons.size()):
        if is_instance_valid(_mode_buttons[i]):
            UiKit.set_button_selected(_mode_buttons[i], (i == 0 and _bind_mode == "keyboard") or (i == 1 and _bind_mode == "pad"), 8.0)
    var binds: Dictionary = _settings["padbinds"] if _bind_mode == "pad" else _settings["keybinds"]
    for action: String in SettingsStore.ACTIONS:
        var keys: Array = binds.get(action, [0, 0])
        for slot: int in range(2):
            var button: Button = _key_buttons.get("%s:%d" % [action, slot])
            if button == null or not is_instance_valid(button):
                continue
            var code := int(keys[slot])
            if code < 0:
                button.text = "（空）"
            elif _bind_mode == "pad":
                button.text = _pad_button_name(code)
            else:
                button.text = OS.get_keycode_string(code)


func _pad_button_name(button: int) -> String:
    match button:
        JOY_BUTTON_A:
            return "A"
        JOY_BUTTON_B:
            return "B"
        JOY_BUTTON_X:
            return "X"
        JOY_BUTTON_Y:
            return "Y"
        JOY_BUTTON_START:
            return "Start"
        JOY_BUTTON_BACK:
            return "Back"
        JOY_BUTTON_DPAD_LEFT:
            return "D-Pad ←"
        JOY_BUTTON_DPAD_RIGHT:
            return "D-Pad →"
        JOY_BUTTON_DPAD_UP:
            return "D-Pad ↑"
        JOY_BUTTON_DPAD_DOWN:
            return "D-Pad ↓"
        _:
            return "键 %d" % button


func _build_audio() -> void:
    _content.add_child(UiKit.label("音效音量", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT))
    _sfx_slider = _slider(float(_settings.get("sfx_db", -6.0)), _on_sfx_changed)
    _content.add_child(_sfx_slider)
    _content.add_child(UiKit.label("BGM 音量", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT))
    _music_slider = _slider(float(_settings.get("music_db", -14.0)), _on_music_changed)
    _content.add_child(_music_slider)


func _build_video() -> void:
    if not OS.has_feature("mobile"):
        _content.add_child(UiKit.label("窗口大小", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT))
        _window_option = OptionButton.new()
        for size_text: String in ["1280×720", "1600×900", "1920×1080"]:
            _window_option.add_item(size_text)
        _window_option.select(_window_index())
        _window_option.item_selected.connect(_on_window_selected)
        _content.add_child(_window_option)
    _content.add_child(UiKit.label("帧率上限", UiKit.SIZE_SMALL, Tuning.COLOR_TEXT))
    _fps_option = OptionButton.new()
    var refresh := int(DisplayServer.screen_get_refresh_rate())
    if refresh <= 0:
        refresh = 60
    var options: Array[int] = [30, 60, 90, 120]
    for fps: int in options:
        if fps <= refresh:
            _fps_option.add_item("%d FPS" % fps)
    if _fps_option.item_count == 0:
        _fps_option.add_item("60 FPS")
    _fps_option.selected = maxi(0, options.find(int(_settings.get("fps", 60))))
    _fps_option.item_selected.connect(_on_fps_selected)
    _content.add_child(_fps_option)


func _slider(value: float, callback: Callable) -> HSlider:
    var slider := HSlider.new()
    slider.min_value = -40.0
    slider.max_value = 0.0
    slider.step = 1.0
    slider.value = value
    slider.custom_minimum_size = Vector2(520.0, 28.0)
    slider.value_changed.connect(callback)
    return slider


func _on_gyro_toggled(on: bool) -> void:
    _settings["gyro"] = on
    SettingsStore.save_settings(_settings)


func _on_sfx_changed(value: float) -> void:
    _settings["sfx_db"] = value
    SettingsStore.save_settings(_settings)
    SettingsStore.apply_runtime()


func _on_music_changed(value: float) -> void:
    _settings["music_db"] = value
    SettingsStore.save_settings(_settings)
    SettingsStore.apply_runtime()


func _window_index() -> int:
    var w := int(_settings["window"][0])
    return 0 if w <= 1280 else (1 if w <= 1600 else 2)


func _on_window_selected(index: int) -> void:
    var sizes := [[1280, 720], [1600, 900], [1920, 1080]]
    _settings["window"] = sizes[index]
    SettingsStore.save_settings(_settings)
    SettingsStore.apply_runtime()


func _on_fps_selected(index: int) -> void:
    var fps_text := _fps_option.get_item_text(index)
    _settings["fps"] = int(fps_text.split(" ")[0])
    SettingsStore.save_settings(_settings)
    SettingsStore.apply_runtime()