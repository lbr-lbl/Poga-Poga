shader_type canvas_item;
// 全屏像素化 + 色阶量化后处理：把世界层压成低分辨率、低色阶的像素画面。
// UI 层在 PixelLayer 之上，因此不受影响，保持清晰。
// 注意：本 shader 依赖 hint_screen_texture（引擎会自动复制后台缓冲）。

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
// 像素块大小（屏幕像素），2.0 表示每 2x2 像素合并
uniform float pixel_size : hint_range(1.0, 6.0) = 2.0;
// 色彩量化级数，越低越“黑白”
uniform float levels : hint_range(2.0, 16.0) = 7.0;

void fragment() {
	vec2 screen_size = vec2(textureSize(screen_texture, 0));
	vec2 block = screen_size / max(pixel_size, 1.0);
	vec2 uv = floor(SCREEN_UV * block) / block;
	// 采样块中心，减少边缘抖动
	uv += 0.5 / block;
	vec3 color = texture(screen_texture, uv).rgb;
	color = floor(color * levels + 0.5) / levels;
	COLOR = vec4(color, 1.0);
}