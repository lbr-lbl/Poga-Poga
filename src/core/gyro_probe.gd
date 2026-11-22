extends Node
## 移动端陀螺仪可用性探测：只有检测到真实非零陀螺仪数据才认为设备有陀螺仪。
## 桌面/模拟器没有陀螺仪时 available 保持 false，设置里不显示开关。

var available: bool = false
var _elapsed: float = 0.0


func _ready() -> void:
    set_process(OS.has_feature("mobile"))


func _process(delta: float) -> void:
    if available:
        set_process(false)
        return
    _elapsed += delta
    var gyro := Input.get_gyroscope()
    if gyro.length() > 0.01:
        available = true
        set_process(false)
    elif _elapsed > 3.0:
        # 继续低频探测，避免用户 3 秒后才移动设备时误判
        _elapsed = 0.0