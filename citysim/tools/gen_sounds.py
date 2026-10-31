"""Generates the game's sounds in assets/audio/ (CC0, synthesised here).

Ambient beds are built in the frequency domain, so they loop seamlessly;
events placed on them (cars, birds, drops) wrap around the loop end. Effects
are short synthesised hits. The music is a gentle 64 s loop. Needs numpy and
ffmpeg (libvorbis). Run:  python3 tools/gen_sounds.py
"""
import os
import subprocess
import tempfile
import wave
import numpy as np

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(1031)


def write_ogg(name, data, rate, quality=3):
    data = np.asarray(data, dtype=np.float64)
    peak = np.max(np.abs(data))
    if peak > 0:
        data = data / peak * 0.89
    stereo = data.ndim == 2
    pcm = (np.clip(data, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        path = tmp.name
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())
    dest = os.path.join(OUT, name)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", str(quality), dest], check=True)
    os.remove(path)
    print("wrote", name, os.path.getsize(dest) // 1024, "KB")


def shaped_noise(n, rate, lo, hi, tilt=0.0):
    """Loopable noise band-limited to lo..hi Hz (soft edges), optional 1/f^tilt."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / rate)
    band = 1.0 / (1.0 + (lo / np.maximum(f, 1e-3)) ** 4) / (1.0 + (f / hi) ** 4)
    band *= 1.0 / np.maximum(f, 20.0) ** tilt
    out = np.fft.irfft(spec * band, n)
    return out / np.max(np.abs(out))


def lfo(n, rate, hz, depth, phase=0.0):
    """Slow modulation that completes whole cycles over the loop."""
    t = np.arange(n) / rate
    cycles = max(1, round(hz * n / rate))
    return 1.0 - depth * 0.5 * (1.0 + np.sin(2 * np.pi * cycles * t / (n / rate) + phase))


def add_wrapped(buf, event, start):
    n = len(buf)
    idx = (np.arange(len(event)) + start) % n
    np.add.at(buf, idx, event)


def env(n, attack, decay, rate):
    t = np.arange(n) / rate
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / max(decay, 1e-4))


# --- Ambient beds -----------------------------------------------------------------

def amb_city():
    rate, sec = 22050, 16
    n = rate * sec
    hum = shaped_noise(n, rate, 30, 380, 0.8) * 0.9 + shaped_noise(n, rate, 300, 2500, 0.5) * 0.12
    hum *= lfo(n, rate, 0.12, 0.35)
    # Passing cars: band-passed noise swells with a slight pitch drift.
    for _ in range(9):
        length = int(rate * rng.uniform(2.0, 3.5))
        car = shaped_noise(length, rate, rng.uniform(120, 220), rng.uniform(900, 1600), 0.6)
        t = np.linspace(-1, 1, length)
        car *= np.exp(-t * t * 5.0) * rng.uniform(0.25, 0.5)
        add_wrapped(hum, car, int(rng.uniform(0, n)))
    write_ogg("amb_city.ogg", hum, rate)


def chirp(rate, f0, f1, dur, harm=0.3):
    n = int(rate * dur)
    t = np.arange(n) / rate
    freq = f0 + (f1 - f0) * (t / dur)
    ph = 2 * np.pi * np.cumsum(freq) / rate
    tone = np.sin(ph) + harm * np.sin(2 * ph)
    return tone * np.sin(np.pi * t / dur) ** 2


def amb_birds():
    rate, sec = 22050, 18
    n = rate * sec
    bed = shaped_noise(n, rate, 200, 3000, 0.9) * 0.08 * lfo(n, rate, 0.1, 0.6)
    for _ in range(26):
        start = int(rng.uniform(0, n))
        base = rng.uniform(2600, 4200)
        song = np.zeros(int(rate * 1.2))
        pos = 0
        for k in range(int(rng.integers(2, 6))):
            d = rng.uniform(0.05, 0.14)
            c = chirp(rate, base * rng.uniform(0.9, 1.1), base * rng.uniform(1.05, 1.4), d)
            end = min(pos + len(c), len(song))
            song[pos:end] += c[: end - pos]
            pos += len(c) + int(rate * rng.uniform(0.02, 0.08))
            if pos >= len(song):
                break
        add_wrapped(bed, song * rng.uniform(0.08, 0.22), start)
    write_ogg("amb_birds.ogg", bed, rate)


def amb_night():
    rate, sec = 22050, 16
    n = rate * sec
    bed = shaped_noise(n, rate, 80, 900, 1.0) * 0.08
    t = np.arange(n) / rate
    for voice in range(4):
        f = rng.uniform(3800, 5200)
        rate_hz = rng.uniform(14, 22)
        pulse = (np.sin(2 * np.pi * rate_hz * t + rng.uniform(0, 6)) > 0.6).astype(float)
        gate = (np.sin(2 * np.pi * round(rng.uniform(0.3, 0.6) * sec) / sec * t + rng.uniform(0, 6)) > -0.2).astype(float)
        bed += np.sin(2 * np.pi * f * t) * pulse * gate * rng.uniform(0.03, 0.06)
    write_ogg("amb_night.ogg", bed, rate)


def amb_rain():
    rate, sec = 22050, 12
    n = rate * sec
    hiss = shaped_noise(n, rate, 400, 9000, 0.3) * 0.5 + shaped_noise(n, rate, 60, 500, 0.8) * 0.25
    for _ in range(900):
        length = int(rate * 0.012)
        drop = rng.standard_normal(length) * env(length, 0.0005, 0.003, rate) * rng.uniform(0.05, 0.25)
        add_wrapped(hiss, drop, int(rng.uniform(0, n)))
    write_ogg("amb_rain.ogg", hiss, rate)


def amb_wind():
    rate, sec = 22050, 16
    n = rate * sec
    w = shaped_noise(n, rate, 120, 900, 1.2) * lfo(n, rate, 0.18, 0.7) + shaped_noise(n, rate, 600, 2400, 0.8) * 0.15 * lfo(n, rate, 0.31, 0.8, 1.3)
    write_ogg("amb_wind.ogg", w, rate)


# --- Effects ----------------------------------------------------------------------

def tone(rate, freq, dur, decay, partials=((1, 1.0),), attack=0.002):
    n = int(rate * dur)
    t = np.arange(n) / rate
    out = np.zeros(n)
    for mult, amp in partials:
        out += np.sin(2 * np.pi * freq * mult * t) * amp
    return out * env(n, attack, decay, rate)


def sfx():
    rate = 44100
    # Soft UI tick.
    click = tone(rate, 1450, 0.06, 0.012, ((1, 1.0), (2.7, 0.25))) + tone(rate, 720, 0.06, 0.02) * 0.4
    write_ogg("ui_click.ogg", click, rate, 4)
    # Panel open: short airy swish.
    n = int(rate * 0.22)
    sw = shaped_noise(n, rate, 900, 6000, 0.2) * np.sin(np.pi * np.arange(n) / n) ** 2
    write_ogg("ui_open.ogg", sw * 0.6, rate, 4)
    # Road laid: asphalt thump with a gravelly tail.
    n = int(rate * 0.45)
    thump = tone(rate, 70, 0.45, 0.09, ((1, 1.0), (2.1, 0.3))) + shaped_noise(n, rate, 200, 3000, 0.4) * env(n, 0.002, 0.08, rate) * 0.5
    write_ogg("build_road.ogg", thump, rate, 4)
    # Building placed: two wooden knocks and a low settle.
    knock = tone(rate, 420, 0.12, 0.03, ((1, 1.0), (2.3, 0.4), (4.1, 0.15)))
    n = int(rate * 0.5)
    place = np.zeros(n)
    place[: len(knock)] += knock
    place[int(rate * 0.13): int(rate * 0.13) + len(knock)] += knock * 0.8
    place += tone(rate, 95, 0.5, 0.12) * 0.6
    write_ogg("build_place.ogg", place, rate, 4)
    # Bulldoze: rumble and crunch.
    n = int(rate * 0.7)
    crunch = shaped_noise(n, rate, 60, 1800, 0.6) * env(n, 0.01, 0.2, rate)
    crunch += shaped_noise(n, rate, 1500, 7000, 0.2) * env(n, 0.001, 0.05, rate) * 0.4
    write_ogg("bulldoze.ogg", crunch, rate, 4)
    # Zone paint: soft brush.
    n = int(rate * 0.18)
    brush = shaped_noise(n, rate, 1200, 5000, 0.3) * np.sin(np.pi * np.arange(n) / n)
    write_ogg("zone_paint.ogg", brush * 0.5, rate, 4)
    # Coins.
    coin = np.zeros(int(rate * 0.5))
    c1 = tone(rate, 1975, 0.35, 0.09, ((1, 1.0), (2.76, 0.3)))
    c2 = tone(rate, 2637, 0.35, 0.12, ((1, 1.0), (2.76, 0.3)))
    coin[: len(c1)] += c1
    coin[int(rate * 0.07): int(rate * 0.07) + len(c2)] += c2
    write_ogg("coin.ogg", coin, rate, 4)
    # Notification: two-note bell.
    bell = ((1, 1.0), (2.0, 0.35), (2.76, 0.2), (5.4, 0.08))
    note = np.zeros(int(rate * 1.0))
    b1 = tone(rate, 880, 0.9, 0.35, bell)
    b2 = tone(rate, 1318.5, 0.8, 0.3, bell)
    note[: len(b1)] += b1
    note[int(rate * 0.12): int(rate * 0.12) + len(b2)] += b2 * 0.8
    write_ogg("notify.ogg", note, rate, 4)
    # Milestone: rising major arpeggio with a held chord.
    fan = np.zeros(int(rate * 2.2))
    for k, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        t0 = int(rate * 0.12 * k)
        x = tone(rate, f, 1.8, 0.7, bell)
        fan[t0: t0 + len(x)] += x * (0.8 if k < 3 else 1.0)
    write_ogg("milestone.ogg", fan, rate, 4)
    # Error: short low double buzz.
    n = int(rate * 0.25)
    t = np.arange(n) / rate
    buzz = np.sign(np.sin(2 * np.pi * 150 * t)) * 0.3 * env(n, 0.003, 0.05, rate)
    err = np.zeros(int(rate * 0.4))
    err[:n] += buzz
    err[int(rate * 0.13): int(rate * 0.13) + n] += buzz
    write_ogg("error.ogg", np.convolve(err, np.ones(8) / 8, "same"), rate, 4)


# --- Music ------------------------------------------------------------------------

def music():
    """64 s loop at 75 bpm: Cmaj7 - Am7 - Fmaj7 - G6, soft electric piano,
    arpeggios and a pad. Notes running past the end wrap to the start."""
    rate = 44100
    bpm = 75.0
    beat = 60.0 / bpm
    bars = 20
    n = int(round(rate * beat * 4 * bars))
    left = np.zeros(n)
    right = np.zeros(n)
    chords = [
        [48, 55, 59, 64, 67],   # Cmaj7
        [45, 52, 55, 60, 64],   # Am7
        [41, 48, 52, 57, 60],   # Fmaj7
        [43, 50, 55, 59, 64],   # G6
    ]

    def midi(m):
        return 440.0 * 2 ** ((m - 69) / 12.0)

    def epiano(freq, dur, vel):
        m = int(rate * dur)
        t = np.arange(m) / rate
        x = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-t * 3.0)
        x += 0.08 * np.sin(2 * np.pi * freq * 3.01 * t) * np.exp(-t * 6.0)
        return x * env(m, 0.004, dur * 0.45, rate) * vel

    def pad(freq, dur, vel):
        m = int(rate * dur)
        t = np.arange(m) / rate
        x = np.sin(2 * np.pi * freq * t) + 0.5 * np.sin(2 * np.pi * freq * 1.003 * t) + 0.3 * np.sin(2 * np.pi * freq * 2.0 * t)
        a = np.clip(t / 1.2, 0, 1) * np.clip((dur - t) / 1.2, 0, 1)
        return x * a * vel

    def put(x, start, pan):
        add_wrapped(left, x * (1.0 - pan), start)
        add_wrapped(right, x * pan, start)

    arp = [0, 2, 3, 4, 3, 2, 1, 2]
    for bar in range(bars):
        chord = chords[bar % 4]
        t_bar = bar * 4 * beat
        put(pad(midi(chord[0] - 12), 4 * beat, 0.16), int(t_bar * rate), 0.5)
        for m in chord[1:4]:
            put(pad(midi(m), 4 * beat, 0.05), int(t_bar * rate), 0.35 + 0.1 * (m % 3))
        # Chord on beat 1, arpeggio in eighths after the intro bars.
        for m in chord[1:]:
            put(epiano(midi(m), beat * 3.5, 0.1), int(t_bar * rate), 0.45)
        if bar >= 2:
            for k in range(8):
                note = chord[arp[k]] + (12 if bar % 8 >= 4 else 0)
                put(epiano(midi(note), beat * 1.6, 0.07 + 0.02 * (k % 2 == 0)), int((t_bar + k * beat * 0.5) * rate), 0.25 + 0.5 * (k / 7.0))
        # A simple melody every other phrase.
        if bar % 8 in (4, 5, 6):
            mel = [chord[4] + 12, chord[3] + 12, chord[4] + 12, chord[2] + 12]
            for k, m in enumerate(mel):
                put(epiano(midi(m), beat * 2.0, 0.09), int((t_bar + k * beat) * rate), 0.6)
    # Gentle room: a few wrapped echoes.
    for delay, gain in ((0.23, 0.25), (0.41, 0.15), (0.67, 0.08)):
        d = int(rate * delay)
        left += np.roll(right, d) * gain
        right += np.roll(left, d) * gain
    write_ogg("music_calm.ogg", np.stack([left, right], axis=1), rate, 2)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    amb_city()
    amb_birds()
    amb_night()
    amb_rain()
    amb_wind()
    sfx()
    music()
