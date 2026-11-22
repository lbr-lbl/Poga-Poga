class_name InputDevice
## 记录最近一次真正产生输入的设备，用于操作指引自动匹配。
## keyboard / gamepad / touch / gyro（gyro 单独由设置开关决定）。

static var last: StringName = &"keyboard"


static func update(event: InputEvent) -> void:
    if event is InputEventKey or event is InputEventMouse:
        last = &"keyboard"
    elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
        last = &"gamepad"
    elif event is InputEventScreenTouch or event is InputEventScreenDrag:
        last = &"touch"


static func guide() -> String:
    if last == &"gamepad":
        return "手柄：A 加速 / B 刹车 · D-Pad 转向"
    if OS.has_feature("mobile"):
        var settings := SettingsStore.load_settings()
        if bool(settings.get("gyro", false)) and (GyroProbe.available if GyroProbe != null else false):
            return "陀螺仪：倾斜加速 · 反向刹车 · 侧倾转向"
        return "触屏：左右半屏转向 · 双按加速 · 下划刹车"
    if last == &"touch":
        return "触屏：左右半屏转向 · 双按加速 · 下划刹车"
    return "键盘：W/↑ 加速 · S/空格 刹车 · A/D 转向"