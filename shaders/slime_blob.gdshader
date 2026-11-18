shader_type canvas_item;
render_mode unshaded;

// 黏液体（metaball）渲染：把多只史莱姆的躯体合成一坨连续的黏液。
// 只有眼睛由各自的 Racer 节点绘制在上面（“融合后只露眼睛”）。
//
// 工作方式：
// - BlobLayer 是一个盖住摄像机的 1x1 白色 Sprite2D，每帧把自己的 transform 设成
//   “屏幕矩形在世界里的位置”，因此片元里用 MODEL_MATRIX * VERTEX 就能拿到世界坐标；
// - 每个粘液体用一个平方反比场 1/q 叠加，q 是（沿速度方向拉长后的）到中心的归一化距离平方；
// - 场值 > 1.0 的区域连成一片：多个躯体靠近时自然融合，拉开时自然断开。

uniform vec4 body_color : source_color = vec4(0.09, 0.09, 0.09, 1.0);
uniform vec4 tint_color : source_color = vec4(0.55, 0.55, 0.55, 1.0);
uniform vec4 rim_color : source_color = vec4(0.85, 0.85, 0.85, 1.0);

// 本 quad 覆盖的屏幕矩形在世界里的位置/朝向（GDScript 每帧根据相机算好传进来）
uniform vec2 view_origin = vec2(0.0);
uniform vec2 view_axis_x = vec2(1.0, 0.0);
uniform vec2 view_axis_y = vec2(0.0, 1.0);

uniform int blob_count : hint_range(0, 10) = 0;
uniform vec2 blob_pos[10];
uniform float blob_radius[10];
uniform vec2 blob_dir[10];
uniform float blob_stretch[10];
uniform float blob_tint[10];
uniform float blob_phase[10];
uniform float time : hint_range(0.0, 1000.0) = 0.0;

void fragment() {
	// canvas_item 着色器里没有 MODEL_MATRIX，世界坐标由 UV 与视图矩形参数还原
	vec2 world = view_origin + UV.x * view_axis_x + UV.y * view_axis_y;
	float field = 0.0;
	float tint_acc = 0.0;
	for (int i = 0; i < 10; i++) {
		if (i >= blob_count) {
			break;
		}
		vec2 vdir = blob_dir[i];
		vec2 perp = vec2(-vdir.y, vdir.x);
		vec2 d = world - blob_pos[i];
		float stretch = blob_stretch[i];
		float rx = blob_radius[i] * (1.0 + stretch);
		float ry = blob_radius[i] * (1.0 - stretch * 0.55);
		float along = dot(d, vdir) / max(rx, 0.001);
		float lat = dot(d, perp) / max(ry, 0.001);
		float q = along * along + lat * lat;
		// 蠕动呼吸：每只史莱姆的半径轻微起伏
		float breathe = 1.0 + 0.035 * sin(time * 5.5 + blob_phase[i]);
		q *= breathe;
		float weight = 1.0 / max(q, 0.0005);
		field += weight;
		tint_acc += weight * blob_tint[i];
	}

	if (field <= 1.0) {
		COLOR = vec4(0.0);
	} else {
		float tint = clamp(tint_acc / field, 0.0, 1.0);
		vec3 body = mix(body_color.rgb, tint_color.rgb, tint);
		// 边缘 1~1.55 的场值区段画成浅色轮廓，形成黑白像素的“高光边”
		float body_mask = smoothstep(1.0, 1.34, field);
		vec3 col = mix(rim_color.rgb, body, body_mask);
		COLOR = vec4(col, 1.0);
	}
}