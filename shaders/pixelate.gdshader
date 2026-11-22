shader_type canvas_item;
// 电子游戏机（CRT）画面效果：像素化 + 色阶量化 + 扫描线 + 暗角 + 轻微曲面/闪烁。
// 只作用于世界层；HUD / UI 在更上层，保持清晰。
// 注意：依赖 hint_screen_texture（引擎会自动复制后台缓冲）。

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
// 像素块大小（屏幕像素），2.0 表示每 2x2 像素合并
uniform float pixel_size : hint_range(1.0, 6.0) = 2.0;
// 色彩量化级数，越低越“黑白”
uniform float levels : hint_range(2.0, 16.0) = 7.0;
// CRT 扫描线强度（0 = 关）
uniform float scanline_strength : hint_range(0.0, 0.5) = 0.14;
// 暗角强度
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.38;
// 屏幕轻微曲面（0 = 平面）
uniform float curvature : hint_range(0.0, 0.15) = 0.035;
// 荧光屏轻微闪烁
uniform float flicker_strength : hint_range(0.0, 0.1) = 0.012;
uniform float time : hint_range(0.0, 1000.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 screen_size = vec2(textureSize(screen_texture, 0));
	vec2 uv = SCREEN_UV;

	// 轻微桶形畸变，模拟球面 CRT
	vec2 centered = uv - 0.5;
	float radius2 = dot(centered, centered);
	uv = 0.5 + centered * (1.0 + curvature * radius2);

	// 像素化：按块取样，再色阶量化
	vec2 block = screen_size / max(pixel_size, 1.0);
	vec2 block_uv = floor(uv * block) / block + 0.5 / block;
	vec3 color = texture(screen_texture, block_uv).rgb;
	color = floor(color * levels + 0.5) / levels;

	// 扫描线：以物理像素行为周期（像素化后仍能看出横纹）
	float row = floor(SCREEN_UV.y * screen_size.y);
	float scanline = mod(row, 3.0) < 1.0 ? (1.0 - scanline_strength) : 1.0;
	color *= scanline;

	// 暗角
	float vignette = smoothstep(0.95, 0.32, length(centered) * 1.25);
	color *= mix(1.0 - vignette_strength, 1.0, vignette);

	// 轻微亮点抖动 + 荧光闪烁（保持灰度）
	float noise = (hash(block_uv * screen_size + vec2(time * 24.0, 0.0)) - 0.5) * 0.02;
	float flicker = 1.0 + flicker_strength * sin(time * 57.0);
	color = clamp(color * flicker + noise, 0.0, 1.0);

	COLOR = vec4(color, 1.0);
}