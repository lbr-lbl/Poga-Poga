extends Node
## 运行时注册输入映射（键盘 / 手柄 / 触屏）。
##
## 项目不在 project.godot 里硬编码 InputMap，原因是：
## 1. 文本格式的 InputEvent 序列化在引擎版本间字段易变，手工维护风险高；
## 2. 这里可以同时注册“键盘 + 手柄轴”到同一个 action，逻辑侧统一读取 action_strength；
## 3. 触屏手势由 PlayerInput 单独处理，不污染 InputMap。
##
## 约定：所有 gameplay 输入都必须经过 InputMap action，禁止在玩法代码里直接读键码。

const KEY_ACTIONS: Dictionary = {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN, KEY_SPACE],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"retry": [KEY_R],
	"confirm": [KEY_ENTER, KEY_KP_ENTER],
	"back": [KEY_ESCAPE],
	"ui_debug": [KEY_F3],
}

const PAD_ACTIONS: Dictionary = {
	"accelerate": [JOY_BUTTON_A],
	"brake": [JOY_BUTTON_B],
	"retry": [JOY_BUTTON_Y],
	"confirm": [JOY_BUTTON_A],
	"back": [JOY_BUTTON_START],
}


func _ready() -> void:
	_register_keys()
	_register_pad_buttons()
	_register_pad_axes()


func _register_keys() -> void:
	for action: String in KEY_ACTIONS.keys():
		_ensure_action(action)
		for keycode: int in KEY_ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)


func _register_pad_buttons() -> void:
	for action: String in PAD_ACTIONS.keys():
		_ensure_action(action)
		for button: int in PAD_ACTIONS[action]:
			var event := InputEventJoypadButton.new()
			event.button_index = button
			event.pressed = false
			InputMap.action_add_event(action, event)


func _register_pad_axes() -> void:
	# 扳机轴：accelerate / brake，提供 0..1 的模拟量
	_ensure_action("accelerate")
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	InputMap.action_add_event("accelerate", rt)

	_ensure_action("brake")
	var lt := InputEventJoypadMotion.new()
	lt.axis = JOY_AXIS_TRIGGER_LEFT
	lt.axis_value = 1.0
	InputMap.action_add_event("brake", lt)

	# 左摇杆横向：steer_left / steer_right
	_ensure_action("steer_left")
	var sl := InputEventJoypadMotion.new()
	sl.axis = JOY_AXIS_LEFT_X
	sl.axis_value = -1.0
	InputMap.action_add_event("steer_left", sl)

	_ensure_action("steer_right")
	var sr := InputEventJoypadMotion.new()
	sr.axis = JOY_AXIS_LEFT_X
	sr.axis_value = 1.0
	InputMap.action_add_event("steer_right", sr)


func _ensure_action(action: StringName) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.18)