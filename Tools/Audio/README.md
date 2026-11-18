# Audio tools

Run with uv (no global Python needed):

    uv run --with numpy --with soundfile python Tools/Audio/spectrum.py Assets/Audio
    uv run --with numpy --with soundfile python Tools/Audio/synth_tones.py Assets/Audio/v2
    uv run --with numpy --with soundfile --with scipy python Tools/Audio/dewhistle.py in.mp3 out.ogg

- `spectrum.py`: brightness (spectral centroid), energy above 4 and 8 kHz, and a "tonal" whistle score per file. Anything with a high tonal score above 1 kHz, or more than 25% energy above 4 kHz, will sound shrill.
- `synth_tones.py`: the cockpit warning/lock tones (seamless 2 s loops).
- `dewhistle.py`: notches narrow tonal spikes above 600 Hz and rolls off fizz above 9 kHz. It writes OGG in blocks (libsndfile crashes on large single writes).
