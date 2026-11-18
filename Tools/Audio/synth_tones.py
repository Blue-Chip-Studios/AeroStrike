import sys, os
import numpy as np, soundfile as sf
SR = 44100
out = sys.argv[1]

def lowpass(x, fc):
    # zero-phase-ish FFT brickwall with smooth roll-off (loop-safe: circular)
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1/SR)
    X *= 1 / np.sqrt(1 + (f / fc) ** 6)
    return np.fft.irfft(X, len(x))

def tone(freq, t, bright=0.35):
    # warm "square-ish": odd harmonics, decaying fast; plus sub-octave for weight
    y = np.sin(2*np.pi*freq*t)
    for k in (3, 5, 7):
        y += (bright / k) * np.sin(2*np.pi*freq*k*t)
    y += 0.45 * np.sin(2*np.pi*freq/2*t)
    return y

def env_pulses(t, rate, duty, att=0.006, rel=0.02):
    ph = (t * rate) % 1.0
    on = duty
    e = np.clip(ph / (att*rate), 0, 1) * np.clip((on - ph) / (rel*rate), 0, 1)
    return e

def norm(y, peak=0.85):
    return y / (np.abs(y).max() + 1e-9) * peak

def save(name, y):
    sf.write(os.path.join(out, name), norm(y).astype(np.float32), SR, format="OGG", subtype="VORBIS")
    print("wrote", name)

L = 2.0
t = np.arange(int(SR*L)) / SR  # all rates/freqs chosen as multiples of 0.5 Hz -> seamless 2 s loops

# Missile inbound (far): alternating 620/780 Hz, 4 beeps/s
alt = ((t*4) % 2 < 1)
y = np.where(alt, tone(620, t), tone(780, t)) * env_pulses(t, 4, 0.7)
save("missile_warning_v2.ogg", lowpass(y, 2600))

# Missile inbound (close): same pair, 8 beeps/s, grittier
alt = ((t*8) % 2 < 1)
y = np.where(alt, tone(620, t, 0.5), tone(780, t, 0.5)) * env_pulses(t, 8, 0.75, 0.004, 0.012)
save("missile_warning_fast_v2.ogg", lowpass(y, 2800))

# Enemy lock (not yet fired): slow steady low beeps, 2/s at 520 Hz
y = tone(520, t, 0.3) * env_pulses(t, 2, 0.35)
save("locked_warning_v2.ogg", lowpass(y, 2200))

# Our lock achieved: continuous tone 900 Hz with gentle 6 Hz warble + sub
vib = 1 + 0.01*np.sin(2*np.pi*6*t)
ph = 2*np.pi*np.cumsum(900*vib)/SR
y = np.sin(ph) + 0.25*np.sin(3*ph)/3 + 0.5*np.sin(ph/2)
save("lock_tone_v2.ogg", lowpass(y, 2400))
