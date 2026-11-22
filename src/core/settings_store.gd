class_name SettingsStore
## 轻量设置存储（独立于存档，避免影响玩家进度）。
## 控制：keybinds = { action: [keycode, keycode] }；音频/画面/陀螺仪。

const PATH := "user://poga_settings.cfg"
const VERSION := 2
const ACTIONS: Array[String] = [
    "accelerate", "brake", "steer_left", "steer_right",
    "retry", "confirm", "back", "mute",
]
const DEFAULT_PAD: Dictionary = {
    "accelerate": [JOY_BUTTON_A, JOY_BUTTON_A],
    "brake": [JOY_BUTTON_B, JOY_BUTTON_B],
    "steer_left": [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_LEFT],
    "steer_right": [JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_RIGHT],
    "retry": [JOY_BUTTON_Y, JOY_BUTTON_Y],
    "confirm": [JOY_BUTTON_A, JOY_BUTTON_A],
    "back": [JOY_BUTTON_START, JOY_BUTTON_START],
    "mute": [-1, -1],
}
const DEFAULT_KEYS: Dictionary = {
    "accelerate": [KEY_W, KEY_UP],
    "brake": [KEY_S, KEY_SPACE],
    "steer_left": [KEY_A, KEY_LEFT],
    "steer_right": [KEY_D, KEY_RIGHT],
    "retry": [KEY_R, KEY_R],
    "confirm": [KEY_ENTER, KEY_KP_ENTER],
    "back": [KEY_ESCAPE, KEY_ESCAPE],
    "mute": [KEY_M, KEY_M],
}


static func load_settings() -> Dictionary:
    var data := {
        "sfx_db": -6.0,
        "music_db": -14.0,
        "gyro": false,
        "window": [1280, 720],
        "fps": 60,
        "keybinds": DEFAULT_KEYS.duplicate(true),
        "padbinds": DEFAULT_PAD.duplicate(true),
        "version": VERSION,
    }
    var config := ConfigFile.new()
    if config.load(PATH) != OK:
        return data
    data["sfx_db"] = float(config.get_value("audio", "sfx_db", data["sfx_db"]))
    data["music_db"] = float(config.get_value("audio", "music_db", data["music_db"]))
    data["gyro"] = bool(config.get_value("input", "gyro", false))
    data["window"] = config.get_value("video", "window", data["window"])
    data["fps"] = int(config.get_value("video", "fps", 60))
    var saved: Variant = config.get_value("input", "keybinds", null)
    if saved is Dictionary:
        for action: String in ACTIONS:
            if saved.has(action) and saved[action] is Array and saved[action].size() == 2:
                data["keybinds"][action] = saved[action]
    var saved_version := int(config.get_value("meta", "version", 1))
    var saved_pad: Variant = config.get_value("input", "padbinds") if config.has_section_key("input", "padbinds") else null
    if saved_version >= VERSION and saved_pad is Dictionary:
        for action: String in ACTIONS:
            if saved_pad.has(action) and saved_pad[action] is Array and saved_pad[action].size() == 2:
                data["padbinds"][action] = saved_pad[action]
    return data


static func save_settings(data: Dictionary) -> void:
    var config := ConfigFile.new()
    config.set_value("audio", "sfx_db", float(data.get("sfx_db", -6.0)))
    config.set_value("audio", "music_db", float(data.get("music_db", -14.0)))
    config.set_value("input", "gyro", bool(data.get("gyro", false)))
    config.set_value("input", "keybinds", data.get("keybinds", DEFAULT_KEYS))
    config.set_value("input", "padbinds", data.get("padbinds", DEFAULT_PAD))
    config.set_value("meta", "version", VERSION)
    config.set_value("video", "window", data.get("window", [1280, 720]))
    config.set_value("video", "fps", int(data.get("fps", 60)))
    config.save(PATH)


static func ensure_buses() -> void:
    for bus_name: String in ["SFX", "Music"]:
        if AudioServer.get_bus_index(bus_name) == -1:
            AudioServer.add_bus()
            var idx := AudioServer.bus_count - 1
            AudioServer.set_bus_name(idx, bus_name)
            AudioServer.set_bus_send(idx, "Master")


static func apply_runtime() -> void:
    ensure_buses()
    var data := load_settings()
    var sfx_idx := AudioServer.get_bus_index("SFX")
    var music_idx := AudioServer.get_bus_index("Music")
    if sfx_idx >= 0:
        AudioServer.set_bus_volume_db(sfx_idx, float(data["sfx_db"]))
    if music_idx >= 0:
        AudioServer.set_bus_volume_db(music_idx, float(data["music_db"]))
    Engine.max_fps = int(data["fps"])
    if not OS.has_feature("mobile") and not OS.has_feature("editor"):
        # 编辑器内嵌窗口不允许改大小，跳过以免刷 “Embedded window can't be resized” 警告
        var w := int(data["window"][0])
        var h := int(data["window"][1])
        if w > 0 and h > 0:
            DisplayServer.window_set_size(Vector2i(w, h))
    apply_keybinds(data["keybinds"])
    apply_padbinds(data["padbinds"])


static func apply_padbinds(padbinds: Dictionary) -> void:
    for action: String in ACTIONS:
        if not InputMap.has_action(action):
            InputMap.add_action(action, 0.18)
        var events := InputMap.action_get_events(action)
        for event: InputEvent in events:
            if event is InputEventJoypadButton or event is InputEventJoypadMotion:
                InputMap.action_erase_event(action, event)
        var buttons: Array = padbinds.get(action, DEFAULT_PAD.get(action, [0, 0]))
        for button: int in buttons:
            if button < 0:
                continue
            var event := InputEventJoypadButton.new()
            event.button_index = button
            event.pressed = false
            InputMap.action_add_event(action, event)


static func apply_keybinds(keybinds: Dictionary) -> void:
    for action: String in ACTIONS:
        if not InputMap.has_action(action):
            InputMap.add_action(action, 0.18)
        var events := InputMap.action_get_events(action)
        for event: InputEvent in events:
            if event is InputEventKey:
                InputMap.action_erase_event(action, event)
        var keys: Array = keybinds.get(action, DEFAULT_KEYS[action])
        for keycode: int in keys:
            if keycode == 0:
                continue
            var event := InputEventKey.new()
            event.physical_keycode = keycode
            InputMap.action_add_event(action, event)