"""Writes src/hitsound.lua: the hitmarker sound as a Lua string, so the mod carries it without a file
of the sound beside the scripts.

Usage: python tools/build_sound.py [source]

The source is a sound file; ffmpeg cuts the first hit from it (0.400 to 0.540 s for the file the sound
came from), drops every tag, makes it mono 16-bit 44.1 kHz and raises it to a peak of -1 dB. With no
source, tools/sound/hitmarker.wav (already made that way) is used as it is. The WAV must be the plain
44-byte form: RIFF, fmt and data and nothing else, as src/sound.lua reads the samples from byte 45.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WAV = ROOT / "tools" / "sound" / "hitmarker.wav"
OUT = ROOT / "src" / "hitsound.lua"


def make(source):
    cut = "atrim=0.400:0.540,asetpts=PTS-STARTPTS,afade=t=in:d=0.002,afade=t=out:st=0.130:d=0.010,aresample=44100"
    raw = WAV.with_suffix(".raw.wav")
    subprocess.run(["ffmpeg", "-hide_banner", "-y", "-i", str(source), "-af", cut, "-ac", "1", "-c:a", "pcm_s16le",
                    "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(raw)], check=True, capture_output=True)
    probe = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(raw), "-af", "volumedetect", "-f", "null", "-"],
                           capture_output=True, text=True).stderr
    peak = float(probe.split("max_volume:")[1].split("dB")[0])
    subprocess.run(["ffmpeg", "-hide_banner", "-y", "-i", str(raw), "-af", f"volume={-1 - peak}dB", "-c:a", "pcm_s16le",
                    "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(WAV)], check=True, capture_output=True)
    raw.unlink()


def main():
    if len(sys.argv) > 1:
        make(Path(sys.argv[1]))
    data = WAV.read_bytes()
    assert data[:4] == b"RIFF" and data[8:16] == b"WAVEfmt " and data[36:40] == b"data", "a plain 44-byte WAV"
    lines = []
    for i in range(0, len(data), 64):
        lines.append('"' + "".join(f"\\{b}" for b in data[i:i + 64]) + '"')
    OUT.write_text(
        "-- The hitmarker sound: a mono 16-bit 44.1 kHz WAV, written by tools/build_sound.py. Do not edit.\n"
        "return table.concat({\n\t" + ",\n\t".join(lines) + ",\n})\n",
        encoding="utf-8", newline="\n")
    print(OUT, len(data), "bytes")


if __name__ == "__main__":
    main()
