"""生成 Poga Poga 的全部音频资产（可复现）。

产物：
  assets/sfx/winwin.wav    加速拟声「win win~」（TTS + 可爱化后期）
  assets/sfx/winwin2.wav   加速拟声变体 2（同音高、不同语气）
  assets/sfx/winwin3.wav   加速拟声变体 3（同音高、不同语气）
  assets/sfx/pooo.wav      减速拟声「poo~」
  assets/sfx/poga.wav      碰撞拟声「poga」+ 低频闷响
  assets/sfx/tired.wav     低耐力喘息（循环）
  assets/sfx/gasp.wav      耐力清空的一次性喘息
  assets/sfx/ui_click.wav  按键点击
  assets/sfx/ui_confirm.wav 确认/开赛
  assets/sfx/ui_back.wav   返回
  assets/music/forest_theme.ogg  柔和森林风 BGM（音乐盒 + 软铺底 + 轻风鸟鸣，循环）

拟声优先调用 Qwen3-TTS（qwen3-tts-flash，DashScope 兼容接口），凭证从环境变量
QW_API_KEY 或 E:/dsh-home/.credentials.yaml 读取；失败时回退到程序化拟声。
TTS 原始结果缓存在 tools/.tts_cache/（已 gitignore）。

用法：python tools/gen_audio.py
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import urllib.request
import wave

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
SFX_DIR = ROOT / "assets" / "sfx"
MUSIC_DIR = ROOT / "assets" / "music"
CACHE_DIR = ROOT / "tools" / ".tts_cache"

SR = 44100
PEAK = 0.80

TTS_URL = "https://maas.qianwenaiapi.com/api/v1/services/aigc/multimodal-generation/generation"
TTS_VOICE = "Cherry"


# ============================================================ 基础工具


def _db_to_gain(db: float) -> float:
    return 10.0 ** (db / 20.0)


def _write_wav(path: pathlib.Path, samples: np.ndarray, sr: int = SR) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.clip(samples, -1.0, 1.0)
    if data.ndim == 1:
        data = data[:, None]
    pcm16 = (data * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(data.shape[1])
        handle.setsampwidth(2)
        handle.setframerate(sr)
        handle.writeframes(pcm16.tobytes())
    print(f"  {path.relative_to(ROOT)}  {data.shape[0] / sr:.2f}s  {path.stat().st_size / 1024:.1f}KB")


def _read_wav(path: pathlib.Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as handle:
        sr = handle.getframerate()
        channels = handle.getnchannels()
        frames = handle.readframes(handle.getnframes())
    data = np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768.0
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    return data, sr


def _resample(data: np.ndarray, src_sr: int, dst_sr: int) -> np.ndarray:
    if src_sr == dst_sr or data.size == 0:
        return data
    count = max(1, int(round(data.size / float(src_sr) * dst_sr)))
    src_t = np.arange(data.size) / float(src_sr)
    dst_t = np.arange(count) / float(dst_sr)
    return np.interp(dst_t, src_t, data).astype(np.float32)


def _trim_silence(data: np.ndarray, threshold_db: float = -38.0, pad_ms: float = 8.0) -> np.ndarray:
    if data.size == 0:
        return data
    threshold = 10 ** (threshold_db / 20.0) * max(1e-6, float(np.max(np.abs(data))))
    loud = np.flatnonzero(np.abs(data) > threshold)
    if loud.size == 0:
        return data
    pad = int(pad_ms / 1000.0 * SR)
    return data[max(0, int(loud[0]) - pad) : min(data.size, int(loud[-1]) + pad)]


def _normalize(data: np.ndarray, peak: float = PEAK) -> np.ndarray:
    top = float(np.max(np.abs(data))) if data.size else 0.0
    if top < 1e-6:
        return data
    return (data / top * peak).astype(np.float32)


def _fade_edges(data: np.ndarray, ms_in: float = 4.0, ms_out: float = 10.0) -> np.ndarray:
    out = data.copy()
    n_in = min(int(ms_in / 1000.0 * SR), out.size)
    n_out = min(int(ms_out / 1000.0 * SR), out.size)
    if n_in > 0:
        out[:n_in] *= np.linspace(0.0, 1.0, n_in)
    if n_out > 0:
        out[-n_out:] *= np.linspace(1.0, 0.0, n_out)
    return out


def _make_loop(data: np.ndarray, fade_ms: float = 28.0) -> np.ndarray:
    """把尾部和头部做等功率交叉淡化，得到可无缝循环的片段。"""
    n = min(int(fade_ms / 1000.0 * SR), data.size // 3)
    if n <= 1:
        return data
    head = data[:n].copy()
    tail = data[-n:].copy()
    t = np.linspace(0.0, 1.0, n)
    blended = head * np.sqrt(t) + tail * np.sqrt(1.0 - t)
    out = data[:-n].copy()
    out[:n] = blended
    return out


def _fft_filter(data: np.ndarray, cutoff: float, highpass: bool, order: float = 2.0) -> np.ndarray:
    if data.size < 8:
        return data
    spectrum = np.fft.rfft(data)
    freqs = np.fft.rfftfreq(data.size, 1.0 / SR)
    if highpass:
        response = 1.0 / (1.0 + (cutoff / np.maximum(freqs, 1.0)) ** (2.0 * order))
    else:
        response = 1.0 / (1.0 + (freqs / max(cutoff, 1.0)) ** (2.0 * order))
    return np.fft.irfft(spectrum * response, n=data.size).astype(np.float32)


def _lowpass(data: np.ndarray, cutoff: float, order: float = 2.0) -> np.ndarray:
    return _fft_filter(data, cutoff, False, order)


def _highpass(data: np.ndarray, cutoff: float, order: float = 2.0) -> np.ndarray:
    return _fft_filter(data, cutoff, True, order)


def _high_shelf(data: np.ndarray, cutoff: float, gain_db: float) -> np.ndarray:
    if data.size < 8:
        return data
    spectrum = np.fft.rfft(data)
    freqs = np.fft.rfftfreq(data.size, 1.0 / SR)
    weight = 1.0 / (1.0 + (cutoff / np.maximum(freqs, 1.0)) ** 2.0)
    spectrum *= 1.0 + (_db_to_gain(gain_db) - 1.0) * weight
    return np.fft.irfft(spectrum, n=data.size).astype(np.float32)


def _noise_burst(length: int, cutoff: float, gain: float, decay: float) -> np.ndarray:
    rng = np.random.default_rng(1234)
    noise = _lowpass(rng.normal(0.0, 1.0, length).astype(np.float32), cutoff, 1.5)
    env = np.exp(-np.arange(length) / max(1.0, decay * SR)).astype(np.float32)
    return noise * env * gain


def _place(track: np.ndarray, data: np.ndarray, start: float) -> None:
    i = int(start * SR)
    if i >= track.size or data.size == 0:
        return
    end = min(track.size, i + data.size)
    track[i:end] += data[: end - i]


# ============================================================ Qwen TTS


def _read_qwen_key() -> str | None:
    key = os.environ.get("QW_API_KEY")
    if key:
        return key
    for candidate in (pathlib.Path("E:/dsh-home/.credentials.yaml"), pathlib.Path.home() / ".credentials.yaml"):
        try:
            text = candidate.read_text(encoding="utf-8")
        except OSError:
            continue
        match = re.search(r"QW_API_KEY:\s*(\S+)", text)
        if match:
            return match.group(1)
    return None


def _tts_request(text: str, voice: str = TTS_VOICE) -> bytes | None:
    key = _read_qwen_key()
    if not key:
        return None
    payload = {
        "model": "qwen3-tts-flash",
        "input": {"text": text, "voice": voice},
        "parameters": {"format": "wav"},
    }
    request = urllib.request.Request(
        TTS_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            data = json.loads(response.read())
        audio_url = data["output"]["audio"]["url"]
        with urllib.request.urlopen(audio_url, timeout=120) as response:
            return response.read()
    except Exception as exc:  # noqa: BLE001 - 网络失败时回退到程序化音效
        print(f"  TTS 失败（{text!r}）：{type(exc).__name__}: {exc}")
        return None


def _tts_cached(name: str, text: str, voice: str = TTS_VOICE) -> np.ndarray | None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache = CACHE_DIR / f"{name}.wav"
    if not cache.exists():
        raw = _tts_request(text, voice)
        if raw is None:
            return None
        cache.write_bytes(raw)
    data, sr = _read_wav(cache)
    return _trim_silence(_resample(data, sr, SR), -40.0, 6.0)


# ============================================================ 拟声后期


def _pitch_up(data: np.ndarray, factor: float) -> np.ndarray:
    """重采样变调（同时变短）：把 TTS 人声变成小生物的感觉。"""
    count = max(1, int(round(data.size / max(factor, 0.01))))
    return np.interp(np.linspace(0, data.size - 1, count), np.arange(data.size), data).astype(np.float32)


def _fallback_winwin() -> np.ndarray:
    total = int(0.46 * SR)
    out = np.zeros(total, dtype=np.float32)
    for start, base in ((0.00, 620.0), (0.21, 760.0)):
        n = int(0.16 * SR)
        t = np.arange(n) / SR
        freq = base * (1.0 + 0.22 * t / 0.16)
        phase = 2 * np.pi * np.cumsum(freq) / SR
        env = np.exp(-t * 16.0) * np.minimum(1.0, t / 0.008)
        tone = np.sin(phase) + 0.35 * np.sin(2 * phase) + 0.12 * np.sin(3 * phase)
        i = int(start * SR)
        out[i : i + n] += (tone * env).astype(np.float32) * 0.8
    return _fade_edges(_make_loop(_normalize(out, 0.85), 22.0), 2.0, 2.0)


def _fallback_pooo() -> np.ndarray:
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    freq = 330.0 * np.exp(-3.2 * t) + 110.0
    phase = 2 * np.pi * np.cumsum(freq) / SR
    tone = 0.8 * np.sin(phase) + 0.2 * np.sin(2 * phase)
    env = np.exp(-t * 3.0) * np.minimum(1.0, t / 0.02)
    out = _normalize((tone * env + _noise_burst(n, 900.0, 0.25, 0.12)).astype(np.float32), 0.82)
    return _fade_edges(_make_loop(out, 24.0), 2.0, 2.0)


def _fallback_poga() -> np.ndarray:
    n = int(0.24 * SR)
    t = np.arange(n) / SR
    thump = np.tanh(np.sin(2 * np.pi * np.cumsum(180.0 * np.exp(-10.0 * t) + 70.0) / SR) * 2.2)
    thump *= np.exp(-t * 14.0)
    click = _noise_burst(n, 3800.0, 0.6, 0.01)
    out = _normalize((thump * 0.9 + click).astype(np.float32), 0.88)
    return _fade_edges(out, 1.5, 14.0)


def _make_winwin_variant(cache_name: str, text: str) -> np.ndarray:
    """同一条“win win”后期链：固定 1.62 变调，保证三个变体音高一致、语气不同。"""
    source = _tts_cached(cache_name, text)
    if source is None:
        print(f"  使用程序化回退：{cache_name}")
        return _fallback_winwin()
    out = _pitch_up(source, 1.62)
    out = _trim_silence(out, -36.0, 4.0)
    out = np.concatenate([out, np.zeros(int(0.05 * SR), dtype=np.float32)])[: int(0.52 * SR)]
    t = np.arange(out.size) / SR
    chirp = (np.sin(2 * np.pi * (640.0 * (1.0 + 0.35 * np.exp(-t * 26.0))) * t)
             * np.exp(-t * 18.0)).astype(np.float32) * 0.18
    squeak = (np.sin(2 * np.pi * np.cumsum(1850.0 + 520.0 * np.exp(-t * 30.0)) / SR)
              * np.exp(-t * 22.0)).astype(np.float32) * 0.10
    out = out + chirp + squeak
    out = _high_shelf(out, 1800.0, 3.0)
    out = _lowpass(out, 8200.0, 1.2)
    out = _normalize(out, 0.85)
    return _fade_edges(out, 2.0, 2.0)


def make_winwin() -> np.ndarray:
    return _make_winwin_variant("winwin", "win win~")


def make_winwin2() -> np.ndarray:
    return _make_winwin_variant("winwin2", "win! win!")


def make_winwin3() -> np.ndarray:
    return _make_winwin_variant("winwin3", "wi~ win~")


def make_pooo() -> np.ndarray:
    source = _tts_cached("poo", "poo~")
    if source is None:
        print("  使用程序化回退：pooo")
        return _fallback_pooo()
    out = _pitch_up(source, 1.30)
    out = _trim_silence(out, -38.0, 5.0)
    t = np.arange(out.size) / SR
    body = np.sin(2 * np.pi * (170.0 * np.exp(-2.2 * t) + 95.0) * t).astype(np.float32)
    out = out + body * np.exp(-t * 3.5) * 0.20
    out = np.concatenate([out, np.zeros(int(0.04 * SR), dtype=np.float32)])
    out = _lowpass(out, 3800.0, 1.4)
    out = _normalize(out, 0.82)
    return _fade_edges(_make_loop(out, 26.0), 2.0, 2.0)


def make_poga() -> np.ndarray:
    source = _tts_cached("poga", "poga!")
    if source is None:
        print("  使用程序化回退：poga")
        return _fallback_poga()
    voice = _pitch_up(_trim_silence(source, -36.0, 3.0), 1.28)[: int(0.30 * SR)]
    voice = np.concatenate([voice, np.zeros(max(0, int(0.30 * SR) - voice.size), dtype=np.float32)])
    n = voice.size
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * np.cumsum(150.0 * np.exp(-9.0 * t) + 62.0) / SR)
    thump = np.tanh(thump * 2.0) * np.exp(-t * 16.0)
    out = voice * 0.85 + thump.astype(np.float32) * 0.55 + _noise_burst(n, 4200.0, 0.5, 0.012)
    out = _lowpass(out, 6500.0, 1.2)
    out = _normalize(out, 0.88)
    return _fade_edges(out, 1.5, 12.0)


# ============================================================ UI 音效


def _breath_pulse(duration: float, center: float, gain: float, bright: float) -> np.ndarray:
    """一小口柔软的呼吸：带共振峰的滤波噪声 + 轻微音高，像小动物轻轻喘气。"""
    n = int(duration * SR)
    if n <= 0:
        return np.zeros(0, dtype=np.float32)
    rng = np.random.default_rng(int(center))
    noise = rng.normal(0.0, 1.0, n).astype(np.float32)
    head = _lowpass(noise, center * 2.4, 1.4)
    formant = _lowpass(noise, center, 1.8) - _lowpass(noise, center * 0.55, 1.2)
    tone = np.sin(2 * np.pi * center * 0.72 * np.arange(n) / SR) * 0.25
    env = np.sin(np.pi * np.linspace(0.0, 1.0, n)) ** 2
    out = (head * 0.35 + formant * bright + tone) * env * gain
    return out.astype(np.float32)


def make_tired() -> np.ndarray:
    """低耐力：两声很轻的“呼—呼”喘息，软、短、循环无缝，不刺耳。"""
    total = int(0.82 * SR)
    out = np.zeros(total, dtype=np.float32)
    for start_sec, dur, center, gain, bright in (
        (0.00, 0.26, 620.0, 0.55, 0.55),
        (0.34, 0.30, 540.0, 0.45, 0.45),
    ):
        pulse = _breath_pulse(dur, center, gain, bright)
        _place(out, pulse, start_sec)
    air = _highpass(np.random.default_rng(31).normal(0.0, 1.0, total).astype(np.float32), 1800.0, 1.0)
    air = _lowpass(air, 4200.0, 1.0)
    out += air * np.sin(np.pi * np.linspace(0.0, 1.0, total)) ** 2 * 0.025
    out = _normalize(out, 0.5)
    return _fade_edges(_make_loop(out, 60.0), 6.0, 6.0)


def make_gasp() -> np.ndarray:
    """耐力清空：一声短促可爱的“吱！”，像小史莱姆被吓了一下。"""
    n = int(0.34 * SR)
    tt = np.arange(n) / SR
    freq = 980.0 + 720.0 * np.sin(np.pi * np.clip(tt / 0.18, 0.0, 1.0)) - 160.0 * tt
    phase = 2 * np.pi * np.cumsum(freq) / SR
    squeak = (np.sin(phase) + 0.35 * np.sin(phase * 2.02) + 0.12 * np.sin(phase * 3.01)) * np.exp(-tt * 7.0)
    squeak *= np.minimum(1.0, tt / 0.008)
    out = squeak.astype(np.float32)
    _place(out, _breath_pulse(0.22, 1200.0, 0.35, 0.4), 0.02)
    out = _highpass(out, 180.0, 1.0)
    out = _lowpass(out, 6200.0, 1.0)
    out = _normalize(out, 0.62)
    return _fade_edges(out, 2.0, 24.0)


def make_ui_click() -> np.ndarray:
    n = int(0.07 * SR)
    t = np.arange(n) / SR
    freq = 1450.0 * np.exp(-t * 40.0) + 900.0
    tone = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 46.0)
    out = tone + _noise_burst(n, 6000.0, 0.18, 0.004)
    return _fade_edges(_normalize(out.astype(np.float32), 0.55), 1.0, 12.0)


def _two_note_sfx(notes: list[tuple[float, float, float]], peak: float) -> np.ndarray:
    total = int((notes[-1][0] + notes[-1][2] + 0.06) * SR)
    out = np.zeros(total, dtype=np.float32)
    for start, freq, dur in notes:
        m = int(dur * SR)
        tt = np.arange(m) / SR
        env = np.exp(-tt * 6.0) * np.minimum(1.0, tt / 0.01)
        tone = np.sin(2 * np.pi * freq * tt) + 0.22 * np.sin(2 * np.pi * freq * 2.0 * tt)
        i = int(start * SR)
        out[i : i + m] += (tone * env).astype(np.float32) * 0.5
    return _fade_edges(_normalize(out, peak), 1.0, 30.0)


def make_ui_confirm() -> np.ndarray:
    return _two_note_sfx([(0.00, 880.0, 0.12), (0.10, 1318.5, 0.16)], 0.55)


def make_ui_back() -> np.ndarray:
    return _two_note_sfx([(0.00, 987.8, 0.10), (0.08, 659.3, 0.14)], 0.5)


# ============================================================ BGM（音乐盒 / 原声感）


def _mallet(freq: float, dur: float, gain: float = 1.0, decay: float = 1.6,
            bright: float = 0.35) -> np.ndarray:
    """柔和音乐盒 / 木琴音色：正弦载波 + 衰减的 FM 调制，避免方波的电子感。"""
    n = int(dur * SR)
    if n <= 0:
        return np.zeros(0, dtype=np.float32)
    t = np.arange(n) / SR
    mod_index = bright * 2.2 * np.exp(-t * 4.0)
    phase = 2 * np.pi * freq * t
    tone = np.sin(phase + mod_index * np.sin(2 * np.pi * freq * 2.0 * t))
    tone += 0.22 * np.sin(2 * phase) * np.exp(-t * 6.0)
    tone += 0.08 * np.sin(3 * phase) * np.exp(-t * 8.0)
    env = np.exp(-t * decay) * np.minimum(1.0, t / 0.006)
    return (tone * env * gain).astype(np.float32)


def _soft_pad(freq: float, dur: float, gain: float, detune: float = 0.0) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    vibrato = 1.0 + 0.0015 * np.sin(2 * np.pi * 0.22 * t)
    phase = 2 * np.pi * freq * vibrato * t + detune
    tone = 0.55 * np.sin(phase) + 0.22 * np.sin(2.003 * phase) + 0.10 * np.sin(3.007 * phase)
    env = np.minimum(1.0, t / 1.4) * np.clip((dur - t) / 1.8, 0.0, 1.0)
    return (tone * env * gain).astype(np.float32)


def _soft_reverb(stereo: np.ndarray, amount: float = 0.24) -> np.ndarray:
    """指数衰减噪声卷积混响：比延迟反馈更自然、更“木头房间”。"""
    rng = np.random.default_rng(77)
    length = int(0.95 * SR)
    t = np.arange(length) / SR
    impulse = rng.normal(0.0, 1.0, length).astype(np.float32) * np.exp(-t * 3.4)
    impulse = _lowpass(impulse, 5200.0, 1.0)
    impulse /= max(1e-6, float(np.sqrt(np.sum(impulse ** 2))))
    out = np.zeros_like(stereo)
    for ch in range(stereo.shape[1]):
        wet = np.fft.irfft(
            np.fft.rfft(stereo[:, ch], n=stereo.shape[0] + length - 1)
            * np.fft.rfft(impulse, n=stereo.shape[0] + length - 1)
        )[: stereo.shape[0]]
        out[:, ch] = stereo[:, ch] * (1.0 - amount) + wet * amount
    return out.astype(np.float32)


def make_forest_theme() -> np.ndarray:
    """C 大调、音乐盒 + 软铺底 + 轻风鸟鸣；刻意避开低音长音和方波，减少“渗人感”。"""
    bpm = 76.0
    beat = 60.0 / bpm
    bar = beat * 4.0
    bars = 16
    n = int(bar * bars * SR)
    left = np.zeros(n, dtype=np.float32)
    right = np.zeros(n, dtype=np.float32)

    chords = [
        (130.81, [261.63, 329.63, 392.00, 493.88]),  # Cmaj7
        (110.00, [220.00, 261.63, 329.63, 392.00]),  # Am7
        (87.31, [174.61, 220.00, 261.63, 329.63]),   # Fmaj7
        (98.00, [196.00, 246.94, 293.66, 329.63]),   # G6
    ]

    for bar_index in range(bars):
        root, chord = chords[bar_index % len(chords)]
        start = bar_index * bar
        for j, freq in enumerate(chord):
            pad = _soft_pad(freq * 2.0, bar * 1.05, 0.028, detune=j * 0.35)
            pan = -0.3 + 0.2 * j
            _place(left, pad * (1.0 - max(0.0, pan)), start)
            _place(right, pad * (1.0 + min(0.0, pan)), start)
        _place(left, _mallet(root, beat * 1.4, 0.05, 2.6, 0.12), start)
        _place(right, _mallet(root, beat * 1.4, 0.04, 2.6, 0.12), start + 0.01)

    melody_bars = [
        [(0.0, 523.25, 1.4), (1.5, 659.25, 1.0), (2.5, 783.99, 1.2)],
        [(0.0, 880.00, 1.0), (1.0, 659.25, 1.4), (3.0, 523.25, 1.6)],
        [(0.0, 587.33, 1.2), (1.5, 523.25, 0.9), (2.5, 440.00, 1.4)],
        [(0.0, 493.88, 1.6), (2.0, 587.33, 1.0), (3.0, 659.25, 1.2)],
        [(0.0, 523.25, 1.4), (1.5, 783.99, 1.0), (2.5, 880.00, 1.2)],
        [(0.0, 659.25, 1.0), (1.0, 523.25, 1.4), (2.5, 440.00, 1.6)],
        [(0.0, 392.00, 1.2), (1.5, 440.00, 1.0), (2.5, 523.25, 1.4)],
        [(0.0, 493.88, 1.4), (2.0, 659.25, 1.2), (3.0, 587.33, 1.0)],
    ] * 2
    for bar_index, phrase in enumerate(melody_bars[:bars]):
        start = bar_index * bar
        for offset, freq, length in phrase:
            note = _mallet(freq, beat * length * 1.2, 0.16, 1.5, 0.28)
            _place(left, note * 0.85, start + offset * beat)
            _place(right, note, start + offset * beat + 0.014)

    for bar_index in range(bars):
        _root, chord = chords[bar_index % len(chords)]
        for step in range(8):
            freq = chord[step % len(chord)] * (2.0 if step >= 4 else 1.0)
            start = bar_index * bar + step * beat * 0.5
            note = _mallet(freq, beat * 0.9, 0.055, 2.3, 0.18)
            _place(left, note * (0.8 if step % 2 == 0 else 0.55), start)
            _place(right, note * (0.55 if step % 2 == 0 else 0.8), start + 0.006)

    rng = np.random.default_rng(4242)
    wind = _lowpass(rng.normal(0.0, 1.0, n).astype(np.float32), 850.0, 1.0)
    wind2 = _lowpass(rng.normal(0.0, 1.0, n).astype(np.float32), 760.0, 1.0)
    lfo = 0.30 + 0.20 * np.sin(2 * np.pi * 0.028 * np.arange(n) / SR + 0.7)
    left += wind * lfo * 0.035
    right += wind2 * lfo * 0.035

    for bar_index in (3, 7, 11, 14):
        for k in range(2):
            start = bar_index * bar + (1.2 + 0.5 * k) * beat
            m = int(0.10 * SR)
            tt = np.arange(m) / SR
            freq = 2300.0 + 300.0 * k
            chirp = np.sin(2 * np.pi * (freq + 400.0 * tt) * tt) * np.exp(-tt * 16.0)
            _place(left, chirp.astype(np.float32) * 0.035, start)
            _place(right, chirp.astype(np.float32) * 0.045, start + 0.02)

    stereo = np.stack([left, right], axis=1)
    stereo = _soft_reverb(stereo, 0.26)
    stereo = np.stack([_highpass(stereo[:, 0], 45.0, 1.0), _highpass(stereo[:, 1], 45.0, 1.0)], axis=1)
    stereo = np.stack([_lowpass(stereo[:, 0], 9000.0, 1.0), _lowpass(stereo[:, 1], 9000.0, 1.0)], axis=1)
    stereo = np.tanh(stereo * 0.8)
    peak = float(np.max(np.abs(stereo)))
    if peak > 0:
        stereo = stereo / peak * 0.55

    # 循环接缝：尾 2s 与头 2s 等功率交叉淡化
    fade = int(2.0 * SR)
    t = np.linspace(0.0, 1.0, fade)[:, None]
    head = stereo[:fade].copy()
    tail = stereo[-fade:].copy()
    stereo = stereo[:-fade].copy()
    stereo[:fade] = head * np.sqrt(t) + tail * np.sqrt(1.0 - t)
    return stereo.astype(np.float32)


# ============================================================ 主流程


def _find_ffmpeg() -> str | None:
    from shutil import which

    found = which("ffmpeg")
    if found:
        return found
    for path in (r"D:\下载\ffmpeg-9.0.2-full_build\bin\ffmpeg.exe", r"C:\ffmpeg\bin\ffmpeg.exe"):
        if pathlib.Path(path).exists():
            return path
    return None


def _encode_ogg(wav_path: pathlib.Path, ogg_path: pathlib.Path) -> bool:
    ffmpeg = _find_ffmpeg()
    if not ffmpeg:
        print("  找不到 ffmpeg，保留 wav")
        return False
    cmd = [ffmpeg, "-y", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "5", str(ogg_path)]
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="ignore")
    if result.returncode != 0:
        print("  ffmpeg 编码失败：", result.stderr[-400:])
        return False
    wav_path.unlink(missing_ok=True)
    return True


def main() -> None:
    print("生成史莱姆拟声（Qwen3-TTS，失败自动回退）…")
    _write_wav(SFX_DIR / "winwin.wav", make_winwin())
    _write_wav(SFX_DIR / "winwin2.wav", make_winwin2())
    _write_wav(SFX_DIR / "winwin3.wav", make_winwin3())
    _write_wav(SFX_DIR / "pooo.wav", make_pooo())
    _write_wav(SFX_DIR / "poga.wav", make_poga())
    _write_wav(SFX_DIR / "tired.wav", make_tired())
    _write_wav(SFX_DIR / "gasp.wav", make_gasp())

    print("生成按键音效…")
    _write_wav(SFX_DIR / "ui_click.wav", make_ui_click())
    _write_wav(SFX_DIR / "ui_confirm.wav", make_ui_confirm())
    _write_wav(SFX_DIR / "ui_back.wav", make_ui_back())

    print("生成背景音乐…")
    theme = make_forest_theme()
    wav_path = MUSIC_DIR / "forest_theme.wav"
    _write_wav(wav_path, theme)
    ogg_path = MUSIC_DIR / "forest_theme.ogg"
    if _encode_ogg(wav_path, ogg_path):
        print(f"  {ogg_path.relative_to(ROOT)}  {ogg_path.stat().st_size / 1024:.1f}KB")


if __name__ == "__main__":
    main()