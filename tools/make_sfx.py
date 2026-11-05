#!/usr/bin/env python3
"""효과음 만들기 (직접 합성 — 외부 음원 없음) → assets/sfx/<이름>.ogg

  python3 tools/make_sfx.py      (numpy, ffmpeg 필요)

짧은 UI·전투 효과음을 사인파·잡음·엔벨로프로 만든다. 게임은 가져오기 없이 그대로 읽는다 (assets/sfx/.gdignore).
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sfx")
SR = 44100
rng = np.random.default_rng(7)


def t(d):
    return np.linspace(0, d, int(SR * d), endpoint=False)


def env(d, a=0.005, r=None, curve=4.0):
    """빠르게 올라가 지수적으로 줄어드는 엔벨로프"""
    x = t(d)
    e = np.exp(-curve * x / d)
    att = np.clip(x / max(a, 1e-4), 0, 1)
    return e * att


def tone(f, d, wave_="sine", vib=0.0):
    x = t(d)
    if callable(f):
        ph = 2 * np.pi * np.cumsum(f(x)) / SR
    else:
        ph = 2 * np.pi * f * x
    if vib:
        ph += vib * np.sin(2 * np.pi * 6 * x)
    if wave_ == "sine":
        return np.sin(ph)
    if wave_ == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if wave_ == "square":
        return np.sign(np.sin(ph)) * 0.6
    return np.sin(ph)


def noise(d, lp=0.0):
    n = rng.uniform(-1, 1, int(SR * d))
    if lp > 0:
        # 간단한 저역 통과 (이동 평균)
        k = max(1, int(lp))
        n = np.convolve(n, np.ones(k) / k, mode="same")
    return n


def bell(f, d, partials=((1, 1.0), (2.01, 0.5), (3.0, 0.25), (4.2, 0.12))):
    out = np.zeros(int(SR * d))
    for m, amp in partials:
        out += amp * tone(f * m, d) * env(d, curve=4 + 2 * m)
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def seq(*items):
    """(시작 초, 소리) 목록을 이어 붙임"""
    n = max(int(s * SR) + len(p) for s, p in items)
    out = np.zeros(n)
    for s, p in items:
        i = int(s * SR)
        out[i:i + len(p)] += p
    return out


def save(name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    fade = min(len(x), int(0.004 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    data = (x * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "3",
                    os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(tmp)


def main():
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    # UI
    save("click", tone(1400, 0.05, "tri") * env(0.05, curve=8), 0.5)
    save("buy", seq((0, bell(1320, 0.18)), (0.07, bell(1760, 0.25))), 0.6)                     # 동전
    save("sell", seq((0, bell(1760, 0.15)), (0.07, bell(1175, 0.25))), 0.55)
    sw = noise(0.28, lp=6) * env(0.28, a=0.08, curve=3)
    save("reroll", mix(sw, 0.3 * tone(lambda x: 600 + 1400 * x / 0.28, 0.28, "tri") * env(0.28, a=0.05, curve=3)), 0.55)
    save("levelup", seq(*[(i * 0.08, bell(f, 0.35)) for i, f in enumerate([523, 659, 784, 1047])]), 0.6)
    save("merge", seq((0, bell(784, 0.3)), (0.06, bell(1175, 0.3)), (0.12, bell(1568, 0.5)),
                      (0.0, 0.25 * noise(0.5, lp=2) * env(0.5, a=0.02, curve=6))), 0.65)
    save("star3", seq(*[(i * 0.09, bell(f, 0.6)) for i, f in enumerate([523, 659, 784, 1047, 1319, 1568])],
                      (0.5, bell(2093, 0.9))), 0.7)
    save("equip", mix(bell(2400, 0.2, ((1, 1), (2.7, 0.6), (5.1, 0.3))), 0.4 * noise(0.04) * env(0.04, curve=10)), 0.5)
    save("ready", seq((0, bell(880, 0.2)), (0.1, bell(1320, 0.35))), 0.5)
    save("tick", tone(2000, 0.03, "sine") * env(0.03, curve=10), 0.35)
    save("round", seq((0, bell(660, 0.9, ((1, 1), (2.0, 0.6), (3.0, 0.3), (4.1, 0.2)))),
                      (0.18, bell(990, 0.9, ((1, 1), (2.0, 0.6), (3.0, 0.3))))), 0.6)
    # 전투
    save("hit", mix(noise(0.09, lp=3) * env(0.09, curve=9), 0.8 * tone(lambda x: 180 - 80 * x / 0.09, 0.09) * env(0.09, curve=7)), 0.55)
    save("hit_magic", mix(tone(lambda x: 1400 - 900 * x / 0.14, 0.14, "tri") * env(0.14, curve=6),
                          0.3 * noise(0.14, lp=1) * env(0.14, curve=8)), 0.45)
    save("crit", mix(noise(0.16, lp=2) * env(0.16, curve=7), tone(lambda x: 300 - 150 * x / 0.16, 0.16, "square") * env(0.16, curve=6),
                     0.5 * bell(2600, 0.16)), 0.65)
    save("skill", mix(tone(lambda x: 400 + 900 * x / 0.4, 0.4, "tri") * env(0.4, a=0.05, curve=3),
                      0.4 * noise(0.4, lp=8) * env(0.4, a=0.1, curve=3), 0.4 * bell(1568, 0.4)), 0.5)
    boom = mix(tone(lambda x: 90 - 50 * x, 0.9) * env(0.9, curve=3), 0.6 * noise(0.9, lp=20) * env(0.9, curve=4))
    save("ultimate", mix(boom, seq((0.05, 0.5 * bell(1047, 0.8)), (0.15, 0.5 * bell(1568, 0.8)))), 0.75)
    save("death", mix(tone(lambda x: 400 - 300 * x / 0.45, 0.45, "tri") * env(0.45, curve=4), 0.3 * noise(0.45, lp=12) * env(0.45, curve=5)), 0.45)
    save("win", seq(*[(i * 0.12, bell(f, 0.6)) for i, f in enumerate([523, 659, 784])], (0.36, bell(1047, 1.1))), 0.65)
    save("lose", seq((0, bell(440, 0.5)), (0.18, bell(392, 0.5)), (0.36, bell(311, 0.9))), 0.55)
    print("효과음 %d개" % len([f for f in os.listdir(OUT) if f.endswith(".ogg")]))


if __name__ == "__main__":
    main()
