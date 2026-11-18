"""生成玩家史莱姆的三段程序化音效（16-bit / 单声道 / 44100Hz）。

- winwin.wav：加速时的「win~ win~」上行双音（可循环）
- pooo.wav  ：刹车时的「Pooo~」下行气声（可循环）
- poga.wav  ：碰撞时的「Poga」短促打击音（一次性）

输出目录：assets/sfx/（相对工程根）。运行：
    python tools/gen_slime_sfx.py
"""

from __future__ import annotations

import os
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "sfx")
PEAK = 0.89  # 约 -1 dBFS，留余量避免削波


def _t(duration: float) -> np.ndarray:
    return np.arange(int(SR * duration)) / SR


def _envelope(n: int, attack: float, decay: float, sustain: float = 0.0) -> np.ndarray:
    a = max(1, int(attack * SR))
    d = max(1, int(decay * SR))
    env = np.ones(n) * sustain
    env[: min(a, n)] = np.linspace(0.0, 1.0, min(a, n))
    tail_start = min(a, n)
    tail = np.linspace(1.0, 0.0, min(d, n - tail_start)) if n - tail_start > 0 else np.array([])
    if tail.size:
        env[tail_start : tail_start + tail.size] = tail * (1.0 - sustain) + sustain * tail
    return env


def _lowpass(x: np.ndarray, alpha: float) -> np.ndarray:
    y = np.empty_like(x)
    acc = 0.0
    for i in range(x.size):
        acc += alpha * (x[i] - acc)
        y[i] = acc
    return y


def _normalize(x: np.ndarray) -> np.ndarray:
    peak = float(np.max(np.abs(x))) or 1.0
    return x / peak * PEAK


def _fade_edges(x: np.ndarray, ms: float = 6.0) -> np.ndarray:
    n = max(1, int(SR * ms / 1000.0))
    n = min(n, x.size // 2)
    if n <= 0:
        return x
    x = x.copy()
    x[:n] *= np.linspace(0.0, 1.0, n)
    x[-n:] *= np.linspace(1.0, 0.0, n)
    return x


def make_winwin() -> np.ndarray:
    """上行双音「win~ win~」，带轻微颤音与气声，0.52s 可循环。"""
    duration = 0.52
    n = int(SR * duration)
    t = _t(duration)
    out = np.zeros(n)
    rng = np.random.default_rng(7)

    def chirp(start: float, length: float, f0: float, f1: float) -> np.ndarray:
        seg = _t(length)
        freq = np.linspace(f0, f1, seg.size)
        vibrato = 1.0 + 0.035 * np.sin(2 * np.pi * 22.0 * seg)
        phase = 2 * np.pi * np.cumsum(freq * vibrato) / SR
        tone = np.sin(phase) + 0.32 * np.sin(2 * phase) + 0.12 * np.sin(3 * phase)
        env = _envelope(seg.size, 0.012, length * 0.9, 0.0)
        breath = _lowpass(rng.normal(0.0, 1.0, seg.size), 0.18) * 0.10
        start_i = int(start * SR)
        seg_out = (tone + breath) * env
        out[start_i : start_i + seg_out.size] += seg_out
        return seg_out

    chirp(0.02, 0.17, 640.0, 880.0)
    chirp(0.25, 0.19, 760.0, 990.0)
    out = _normalize(out)
    return _fade_edges(out, 8.0)


def make_pooo() -> np.ndarray:
    """下行「Pooo~」：起始有一点点气声爆点，然后下沉，0.55s 可循环。"""
    duration = 0.55
    n = int(SR * duration)
    t = _t(duration)
    rng = np.random.default_rng(11)

    freq = 320.0 * np.exp(-2.2 * t) + 95.0
    phase = 2 * np.pi * np.cumsum(freq) / SR
    tone = 0.75 * np.sin(phase) + 0.22 * np.sin(2 * phase) + 0.08 * np.sin(3 * phase)
    breath = _lowpass(rng.normal(0.0, 1.0, n), 0.05) * 0.55
    puff = _lowpass(rng.normal(0.0, 1.0, n), 0.35)
    puff_env = _envelope(n, 0.008, 0.16, 0.0)
    env = _envelope(n, 0.02, duration * 0.85, 0.0)
    out = (tone + breath * 0.5) * env + puff * puff_env * 0.5
    out = _normalize(out)
    return _fade_edges(out, 10.0)


def make_poga() -> np.ndarray:
    """「Poga」：先一记闷响，再跟一个短促高频撞击。"""
    duration = 0.22
    n = int(SR * duration)
    t = _t(duration)
    rng = np.random.default_rng(23)

    # po：低频闷响
    freq = 210.0 * np.exp(-7.0 * t) + 80.0
    phase = 2 * np.pi * np.cumsum(freq) / SR
    thump = np.tanh(np.sin(phase) * 2.2) * _envelope(n, 0.004, 0.10, 0.0)

    # ga：拍击（噪声瞬态 + 一点方形质感）
    click_t = np.clip(t - 0.055, 0.0, None)
    click_env = np.exp(-70.0 * click_t) * (t >= 0.055)
    click = (rng.normal(0.0, 1.0, n) * 0.6 + np.sign(np.sin(2 * np.pi * 430.0 * t)) * 0.35) * click_env

    out = thump * 0.9 + click * 0.55
    out = _normalize(out)
    return _fade_edges(out, 5.0)


def write_wav(name: str, samples: np.ndarray) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    pcm = np.clip(samples, -1.0, 1.0)
    pcm16 = (pcm * 32767.0).astype(np.int16)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm16.tobytes())
    print(f"{path}  {pcm16.size / SR:.2f}s  {os.path.getsize(path) / 1024:.1f}KB")


def main() -> None:
    write_wav("winwin.wav", make_winwin())
    write_wav("pooo.wav", make_pooo())
    write_wav("poga.wav", make_poga())


if __name__ == "__main__":
    main()