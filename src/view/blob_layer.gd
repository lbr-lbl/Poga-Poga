class_name SlimeBlobLayer
extends Sprite2D
## 黏液层：一个覆盖摄像机的 1x1 Sprite + metaball shader，把全部史莱姆的躯体合成一坨。
##
## 为什么这么做：
## - 2D 里要让“多个圆合并成一个连续形状”，metaball 场是最省事且效果最像黏液的做法；
## - 用一张覆盖屏幕的 quad 在片元里算场，避免 CPU 提取等值线（复杂且抖动）；
## - 相机旋转 / 缩放 / 抖动都通过每帧同步 quad 的世界变换自动跟随（见 follow_view）。
##
## 注意：本节点必须位于世界层（Race 子节点），z_index 在赛道之上、眼睛之下。

const MAX_BLOBS := 10

var _material: ShaderMaterial
var _positions := PackedVector2Array()
var _radii := PackedFloat32Array()
var _dirs := PackedVector2Array()
var _stretches := PackedFloat32Array()
var _tints := PackedFloat32Array()
var _phases := PackedFloat32Array()


func _ready() -> void:
	z_index = 5
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(image)

	for i: int in range(MAX_BLOBS):
		_positions.append(Vector2.ZERO)
		_radii.append(0.0)
		_dirs.append(Vector2.RIGHT)
		_stretches.append(0.0)
		_tints.append(0.0)
		_phases.append(0.0)

	_material = ShaderMaterial.new()
	var shader := load("res://shaders/slime_blob.gdshader")
	if shader != null:
		_material.shader = shader
	material = _material
	_material.set_shader_parameter("body_color", Tuning.COLOR_BLOB_BODY)
	_material.set_shader_parameter("tint_color", Tuning.COLOR_BLOB_TINT)
	_material.set_shader_parameter("rim_color", Tuning.COLOR_BLOB_RIM)


## 每帧同步全部史莱姆的躯体状态。
func update_racers(racers: Array[Racer], time: float) -> void:
	var count := mini(racers.size(), MAX_BLOBS)
	for i: int in range(MAX_BLOBS):
		if i < count:
			var racer: Racer = racers[i]
			var speed := racer.current_speed()
			var direction := Vector2.from_angle(racer.angle)
			if speed > 1.0:
				direction = racer.velocity / speed
			_positions[i] = racer.position + racer.draw_shake_offset()
			_radii[i] = racer.blob_radius
			_dirs[i] = direction
			_stretches[i] = clampf(speed / Tuning.BASE_MAX_SPEED, 0.0, 1.2) * 0.26
			_tints[i] = racer.blob_tint
			_phases[i] = racer.blob_phase
		else:
			_positions[i] = Vector2.ZERO
			_radii[i] = 0.0
			_dirs[i] = Vector2.RIGHT
			_stretches[i] = 0.0
			_tints[i] = 0.0
			_phases[i] = 0.0

	_material.set_shader_parameter("blob_count", count)
	_material.set_shader_parameter("blob_pos", _positions)
	_material.set_shader_parameter("blob_radius", _radii)
	_material.set_shader_parameter("blob_dir", _dirs)
	_material.set_shader_parameter("blob_stretch", _stretches)
	_material.set_shader_parameter("blob_tint", _tints)
	_material.set_shader_parameter("blob_phase", _phases)
	_material.set_shader_parameter("time", time)


## 让这张 quad 精确覆盖当前摄像机看到的屏幕矩形（支持旋转/缩放/抖动的相机）。
## 同时把“屏幕 UV -> 世界坐标”的映射传给 shader（canvas_item 里没有 MODEL_MATRIX）。
func follow_view(canvas_transform: Transform2D, viewport_size: Vector2) -> void:
	var inverse := canvas_transform.affine_inverse()
	var axis_x := inverse.x * viewport_size.x
	var axis_y := inverse.y * viewport_size.y
	transform = Transform2D(axis_x, axis_y, inverse.origin)
	if _material == null:
		return
	_material.set_shader_parameter("view_origin", inverse.origin)
	_material.set_shader_parameter("view_axis_x", axis_x)
	_material.set_shader_parameter("view_axis_y", axis_y)