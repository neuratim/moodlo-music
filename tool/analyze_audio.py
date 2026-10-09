"""Measures what can be heard in a section's renders: length, tempo, key and energy.

A section listed in `sections.json` with `"metadata": "measured"` has no written
brief, so its filterable facts come from the audio itself. The prompt library
stays authoritative for its own tracks; their declared tempo and energy are
what this tool calibrates against, and the report says how well it agrees.

    python -m pip install -r tool/requirements.txt
    python tool/analyze_audio.py motivation

Writes `analysis/<section>.json`, which `tool/prepare_music.dart` reads. Every
value is a measurement of one render, so A and B are measured separately.
"""

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

FRAME = 2048
HOP = 512
PITCHES = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
# Krumhansl–Kessler key profiles.
MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
RATE = 22050
ROOT = Path(__file__).resolve().parents[1]
RENDER = re.compile(r"^(\d{3})([b-z])?-(.+)\.mp3$", re.IGNORECASE)


def load(path):
    """Mono audio at RATE, box-filtered before resampling so nothing aliases into the analysis band."""
    data, rate = sf.read(path, dtype="float32", always_2d=True)
    mono = data.mean(axis=1)
    seconds = len(mono) / rate
    if rate != RATE:
        width = max(1, int(round(rate / RATE)))
        if width > 1:
            mono = np.convolve(mono, np.ones(width, dtype=np.float32) / width, mode="same")
        count = int(round(len(mono) * RATE / rate))
        mono = np.interp(np.linspace(0, len(mono) - 1, count), np.arange(len(mono)), mono).astype(np.float32)
    return mono, seconds


def spectrogram(signal):
    frames = 1 + max(0, (len(signal) - FRAME) // HOP)
    window = np.hanning(FRAME).astype(np.float32)
    magnitudes = np.empty((frames, FRAME // 2 + 1), dtype=np.float32)
    for start in range(0, frames, 512):
        stop = min(frames, start + 512)
        chunk = np.stack([signal[i * HOP : i * HOP + FRAME] for i in range(start, stop)])
        magnitudes[start:stop] = np.abs(np.fft.rfft(chunk * window, axis=1))
    return magnitudes


def onset_envelope(magnitudes):
    compressed = np.log1p(10 * magnitudes)
    flux = np.maximum(0, np.diff(compressed, axis=0)).sum(axis=1)
    local = np.convolve(flux, np.ones(16) / 16, mode="same")
    return np.maximum(0, flux - local)


def tempo(envelope):
    """Autocorrelation of the onset envelope, weighted by a log-normal prior around 120 BPM."""
    centred = envelope - envelope.mean()
    spectrum = np.fft.rfft(centred, n=2 * len(centred))
    correlation = np.fft.irfft(spectrum * np.conj(spectrum))[: len(centred)]
    correlation /= correlation[0] or 1
    candidates = np.arange(55.0, 200.5, 0.5)
    lags = 60 * RATE / HOP / candidates
    score = np.interp(lags, np.arange(len(correlation)), correlation)
    # A beat is also felt at half and double speed; reward agreement with both.
    score += 0.5 * np.interp(2 * lags, np.arange(len(correlation)), correlation)
    score += 0.25 * np.interp(lags / 2, np.arange(len(correlation)), correlation)
    prior = np.exp(-0.5 * (np.log2(candidates / 120) / 0.9) ** 2)
    return float(candidates[int(np.argmax(score * prior))])


def key(magnitudes):
    frequencies = np.fft.rfftfreq(FRAME, 1 / RATE)
    band = (frequencies >= 65) & (frequencies <= 2100)
    classes = np.round(12 * np.log2(frequencies[band] / 440) + 69).astype(int) % 12
    energy = (magnitudes[:, band] ** 2).sum(axis=0)
    chroma = np.bincount(classes, weights=energy, minlength=12)
    chroma = chroma / (chroma.sum() or 1)
    best = (-2.0, 0, "major")
    for tonic in range(12):
        for mode, profile in (("major", MAJOR), ("minor", MINOR)):
            value = float(np.corrcoef(chroma, np.roll(profile, tonic))[0, 1])
            if value > best[0]:
                best = (value, tonic, mode)
    return f"{PITCHES[best[1]]} {best[2]}", round(best[0], 3)


def features(path):
    signal, seconds = load(path)
    magnitudes = spectrogram(signal)
    envelope = onset_envelope(magnitudes)
    rms = np.sqrt(np.mean(signal.astype(np.float64) ** 2)) or 1e-9
    frequencies = np.fft.rfftfreq(FRAME, 1 / RATE)
    power = magnitudes.sum(axis=1)
    centroid = float(np.mean((magnitudes * frequencies).sum(axis=1) / np.maximum(power, 1e-9)))
    threshold = envelope.mean() + envelope.std()
    peaks = np.sum((envelope[1:-1] > threshold) & (envelope[1:-1] >= envelope[:-2]) & (envelope[1:-1] >= envelope[2:]))
    measured_key, key_confidence = key(magnitudes)
    return {
        "bpm": tempo(envelope),
        "centroidHz": round(centroid, 1),
        "key": measured_key,
        "keyConfidence": key_confidence,
        "loudnessDb": round(float(20 * np.log10(rms)), 2),
        "onsetsPerSecond": round(float(peaks / seconds), 3),
        "onsetStrength": round(float(envelope.mean() / (np.mean(power) or 1)), 5),
        "seconds": round(seconds, 2),
    }


def vector(measured):
    return np.array(
        [measured["bpm"], measured["onsetsPerSecond"], measured["onsetStrength"], measured["centroidHz"], measured["loudnessDb"]]
    )


def prompt_renders():
    """Every A render of a prompt track that exists locally, published or still in intake."""
    prompts = {row["id"]: row for row in json.loads((ROOT / "prompt_catalogue.json").read_text(encoding="utf-8"))["prompts"]}
    renders = {}
    for path in sorted((ROOT / "tracks").glob("[0-9][0-9][0-9]/[0-9][0-9][0-9]-a.mp3")):
        renders[path.parent.name] = path
    for path in sorted((ROOT / "unprocessed").glob("*.mp3")):
        match = RENDER.match(path.name)
        if match and not match.group(2):
            renders.setdefault(match.group(1), path)
    return {track: (path, prompts[track]) for track, path in renders.items() if track in prompts}


def calibrate(report):
    """Least-squares energy scale fitted to the prompt library's declared energy."""
    rows = []
    for track, (path, prompt) in sorted(prompt_renders().items()):
        measured = features(path)
        rows.append((track, measured, prompt))
    matrix = np.stack([vector(measured) for _, measured, _ in rows])
    mean, spread = matrix.mean(axis=0), matrix.std(axis=0) + 1e-9
    design = np.column_stack([(matrix - mean) / spread, np.ones(len(rows))])
    declared = np.array([prompt["energy"] for _, _, prompt in rows], dtype=float)
    weights, *_ = np.linalg.lstsq(design, declared, rcond=None)
    predicted = np.clip(np.rint(design @ weights), 1, 4)
    tempo_ratio = [measured["bpm"] / prompt["bpm"] for _, measured, prompt in rows]
    key_exact = sum(measured["key"] == prompt["key"] for _, measured, prompt in rows)
    report["calibration"] = {
        "energyExact": int(np.sum(predicted == declared)),
        "energyWithinOne": int(np.sum(np.abs(predicted - declared) <= 1)),
        "keyExact": key_exact,
        "tempoWithinTenPercent": int(sum(0.9 <= ratio <= 1.1 or 0.9 <= ratio * 2 <= 1.1 or 0.9 <= ratio / 2 <= 1.1 for ratio in tempo_ratio)),
        "tracks": len(rows),
    }
    # A key is only published when the estimator agrees with the library's
    # declared keys often enough to be worth filtering by; otherwise it stays
    # in the report as an estimate and never reaches the catalogue.
    report["publishKeys"] = key_exact >= 0.6 * len(rows)
    return lambda measured: int(np.clip(np.rint(np.append((vector(measured) - mean) / spread, 1) @ weights), 1, 4))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("section")
    arguments = parser.parse_args()
    sections = {row["id"]: row for row in json.loads((ROOT / "sections.json").read_text(encoding="utf-8"))["sections"]}
    section = sections.get(arguments.section)
    if section is None or section.get("metadata") != "measured":
        sys.exit(f"{arguments.section} is not a measured section in sections.json.")
    report = {}
    energy = calibrate(report)
    intake = ROOT / section["intake"]
    output = ROOT / "analysis" / f"{section['id']}.json"
    existing = json.loads(output.read_text(encoding="utf-8")) if output.exists() else {"renders": {}}
    renders = dict(existing.get("renders", {}))
    for path in sorted(intake.glob("*.mp3")):
        match = RENDER.match(path.name)
        if match is None:
            sys.exit(f"{path.name} must be NNN-Title.mp3 or NNNb-Title.mp3.")
        measured = features(path)
        measured["energy"] = energy(measured)
        measured["bpm"] = int(round(measured["bpm"]))
        measured["keyEstimate"] = measured.pop("key")
        measured["key"] = measured["keyEstimate"] if report["publishKeys"] else None
        renders[
            f"{section['prefix']}{match.group(1)}-{(match.group(2) or 'a').lower()}"
        ] = {
            **measured,
            "file": path.name,
        }
        print(f"{path.name}: {measured['bpm']} BPM, {measured['keyEstimate']}, energy {measured['energy']}", flush=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(
            {
                "calibration": report["calibration"],
                "publishKeys": report["publishKeys"],
                "renders": dict(sorted(renders.items())),
                "schema": 1,
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(json.dumps(report["calibration"]))


if __name__ == "__main__":
    main()
