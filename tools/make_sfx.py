#!/usr/bin/env python3
"""효과음 만들기 (직접 합성 — 외부 음원 없음, 트릭컬 느낌의 귀여운 소리) → assets/sfx/<이름>.ogg

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


def lowpass(x, a=0.15):
    """한 극 저역 통과 (부드럽게)"""
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc)
        y[i] = acc
    return y


def marimba(f, d=0.35, bright=1.0):
    """나무 건반: 짧은 '톡' 소리 (배음 1 · 3.93 · 9.2)"""
    out = np.zeros(int(SR * d))
    for m, amp, c in ((1, 1.0, 6), (3.93, 0.35 * bright, 18), (9.2, 0.08 * bright, 40)):
        out += amp * tone(f * m, d) * env(d, a=0.002, curve=c)

    return out


def kalimba(f, d=0.5):
    out = np.zeros(int(SR * d))
    for m, amp, c in ((1, 1.0, 5), (5.4, 0.12, 30), (2.0, 0.15, 12)):
        out += amp * tone(f * m, d) * env(d, a=0.002, curve=c)
    return out


def pop(f=700, d=0.09):
    """물방울 '뽁'"""
    return tone(lambda x: f * (1 + 2.5 * np.exp(-x * 60)), d) * env(d, a=0.001, curve=7)


def boing(f0, f1, d, vib=3.0):
    x = t(d)
    fr = f0 + (f1 - f0) * (x / d) ** 0.6
    return tone(lambda xx: f0 + (f1 - f0) * (xx / d) ** 0.6, d, "sine", vib) * env(d, a=0.004, curve=4)


def bonk(f0=320, f1=110, d=0.13):
    """만화 '통!' (높은 데서 뚝 떨어지는 짧은 소리)"""
    return tone(lambda x: f1 + (f0 - f1) * np.exp(-x * 40), d) * env(d, a=0.001, curve=8)


def slide(f0, f1, d, wave_="tri", vib=0.0):
    return tone(lambda x: f0 + (f1 - f0) * x / d, d, wave_, vib)


def sparkle(n=6, base=2093, span=0.4, seed=3):
    r = np.random.default_rng(seed)
    notes = [base * 2 ** (k / 12) for k in (0, 4, 7, 12, 16, 19, 24)]
    return seq(*[(span * i / n, 0.35 * kalimba(notes[r.integers(0, len(notes))], 0.3)) for i in range(n)])


C5, D5, E5, G5, A5, C6, D6, E6, G6, C7 = 523, 587, 659, 784, 880, 1047, 1175, 1319, 1568, 2093


def main():
    """트릭컬 느낌: 나무 건반·칼림바·뽁·통!·띠용 — 통통 튀고 귀여운 소리 (임시, 직접 합성)"""
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    # UI
    save("click", marimba(1760, 0.07), 0.45)
    save("tick", marimba(2349, 0.05, 0.5), 0.3)
    save("buy", seq((0, marimba(C6, 0.25)), (0.06, marimba(G6, 0.3)), (0.0, 0.5 * pop(900))), 0.6)
    save("sell", seq((0, marimba(E6, 0.22)), (0.07, marimba(A5, 0.3)), (0.05, 0.4 * pop(500))), 0.5)
    save("reroll", seq(*[(0.035 * i, 0.7 * marimba(f, 0.18)) for i, f in enumerate([C6, E6, D6, G6, E6, C7])],
                       (0, 0.25 * noise(0.25, lp=10) * env(0.25, a=0.05, curve=4))), 0.5)
    save("levelup", seq(*[(0.07 * i, kalimba(f, 0.45)) for i, f in enumerate([C5, E5, G5, C6, E6])], (0.3, 0.6 * sparkle(5, C7, 0.3))), 0.6)
    save("merge", seq((0, 0.8 * boing(400, 1200, 0.22, 2.0)), (0.16, marimba(G6, 0.35)), (0.2, marimba(C7, 0.45)), (0.18, 0.5 * pop(1200))), 0.6)
    save("star3", seq(*[(0.08 * i, marimba(f, 0.45)) for i, f in enumerate([C5, E5, G5, C6, E6, G6])],
                      (0.5, kalimba(C7, 0.9)), (0.5, 0.7 * kalimba(E6 * 2, 0.9)), (0.55, 0.8 * sparkle(9, C7, 0.7, 5))), 0.7)
    save("equip", seq((0, kalimba(2637, 0.25)), (0.05, kalimba(3136, 0.3)), (0, 0.5 * pop(1500, 0.05))), 0.45)
    save("ready", seq((0, marimba(G5, 0.25)), (0.1, marimba(C6, 0.4))), 0.5)
    save("round", seq((0, marimba(C6, 0.3)), (0.12, marimba(E6, 0.3)), (0.24, marimba(G6, 0.3)), (0.36, kalimba(C7, 0.7))), 0.55)
    # 전투 (자주 나므로 작고 짧게)
    save("hit", mix(bonk(300, 120, 0.11), 0.25 * noise(0.05, lp=4) * env(0.05, curve=10)), 0.5)
    save("hit_magic", mix(0.7 * slide(1800, 900, 0.12, "tri") * env(0.12, curve=6), 0.4 * kalimba(2637, 0.15)), 0.4)
    save("crit", mix(bonk(500, 140, 0.16), 0.6 * pop(1100, 0.1), 0.3 * noise(0.07, lp=3) * env(0.07, curve=9)), 0.6)
    save("skill", mix(0.8 * boing(500, 1500, 0.3, 4.0), seq((0.15, 0.6 * kalimba(G6, 0.4)))), 0.5)
    save("ultimate", mix(0.8 * bonk(220, 60, 0.5), seq((0.06, 0.8 * boing(300, 1400, 0.35, 3.0)), (0.3, sparkle(8, C6 * 2, 0.5, 9)))), 0.7)
    save("death", mix(slide(950, 260, 0.5, "tri", 2.5) * env(0.5, a=0.01, curve=3)), 0.4)
    save("win", seq(*[(0.1 * i, marimba(f, 0.4)) for i, f in enumerate([C6, E6, G6])], (0.3, kalimba(C7, 1.0)), (0.3, 0.6 * kalimba(G6, 1.0)),
                    (0.35, 0.6 * sparkle(7, C7, 0.6, 2))), 0.65)
    # 패배: '빠밤빠~' 처지는 트롬본 느낌 (네모파를 부드럽게)
    wah = lambda f0, f1, d: lowpass(slide(f0, f1, d, "square", 1.5), 0.08) * env(d, a=0.03, curve=2.5)
    save("lose", seq((0, wah(392, 380, 0.3)), (0.3, wah(370, 360, 0.3)), (0.6, wah(349, 330, 0.3)), (0.9, wah(330, 300, 0.9))), 0.5)
    print("효과음 %d개" % len([f for f in os.listdir(OUT) if f.endswith(".ogg")]))


if __name__ == "__main__":
    main()
