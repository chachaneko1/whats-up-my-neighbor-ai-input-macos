"""Offline ASR smoke test for public, transcribed English audio.

No microphone access or network calls occur here. Audio and model files must
already be available locally. The measured wall time includes model loading.
"""

import argparse
import hashlib
import json
import re
import subprocess
import time
import unicodedata
import wave
from pathlib import Path


NUMBER_WORDS = dict(zip("zero one two three four five six seven eight nine".split(),
                        map(str, range(10))))


def words(text: str, normalize_numbers: bool = False) -> list[str]:
    text = unicodedata.normalize("NFKC", text).lower()
    text = re.sub(r"[^a-z0-9']+", " ", text)
    tokens = text.split()
    return [NUMBER_WORDS.get(token, token) for token in tokens] if normalize_numbers else tokens


def word_error_rate(reference: str, hypothesis: str,
                    normalize_numbers: bool = False) -> tuple[int, int, float]:
    ref, hyp = words(reference, normalize_numbers), words(hypothesis, normalize_numbers)
    previous = list(range(len(hyp) + 1))
    for i, token in enumerate(ref, start=1):
        current = [i]
        for j, candidate in enumerate(hyp, start=1):
            current.append(min(current[-1] + 1, previous[j] + 1,
                               previous[j - 1] + (token != candidate)))
        previous = current
    errors = previous[-1]
    return errors, len(ref), errors / len(ref) if ref else float("nan")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def combine_wav(manifest: dict, sample_dir: Path, output: Path) -> float:
    output.parent.mkdir(parents=True, exist_ok=True)
    target_format = None
    with wave.open(str(output), "wb") as destination:
        for index, example in enumerate(manifest["examples"]):
            source = sample_dir / example["file"]
            with wave.open(str(source), "rb") as audio:
                fmt = (audio.getnchannels(), audio.getsampwidth(),
                       audio.getframerate(), audio.getcomptype())
                if target_format is None:
                    target_format = fmt
                    destination.setparams(audio.getparams())
                if fmt != target_format:
                    raise ValueError(f"Audio formats differ: {source}")
                destination.writeframes(audio.readframes(audio.getnframes()))
            if index + 1 < len(manifest["examples"]):
                destination.writeframes(b"\0" * int(0.4 * fmt[2]) * fmt[0] * fmt[1])
    with wave.open(str(output), "rb") as audio:
        return audio.getnframes() / audio.getframerate()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--model", required=True, action="append", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--max-context", type=int,
                        help="whisper-cli -mc; 0 disables previous text context")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    combined = args.output / "combined-48k.wav"
    duration = combine_wav(manifest, args.manifest.parent, combined)
    converted = args.output / "combined-16k.wav"
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                    "-i", str(combined), "-ac", "1", "-ar", "16000",
                    "-c:a", "pcm_s16le", str(converted)], check=True)
    reference = " ".join(row["reference"] for row in manifest["examples"])
    results = []
    for model in args.model:
        if not model.is_file():
            raise FileNotFoundError(model)
        prefix = args.output / model.stem
        command = ["/usr/bin/time", "-l", "whisper-cli", "-m", str(model), "-f", str(converted),
                   "-l", "en", "-t", "4", "-otxt", "-of", str(prefix), "-np"]
        if args.max_context is not None:
            command += ["-mc", str(args.max_context)]
        start = time.perf_counter()
        process = subprocess.run(command, text=True, capture_output=True)
        wall = time.perf_counter() - start
        (args.output / f"{model.stem}.stderr.txt").write_text(process.stderr)
        if process.returncode:
            raise RuntimeError(f"{model.name} failed with exit {process.returncode}")
        hypothesis = Path(f"{prefix}.txt").read_text().strip()
        errors, count, wer = word_error_rate(reference, hypothesis)
        number_errors, _, number_wer = word_error_rate(reference, hypothesis, normalize_numbers=True)
        rss_match = re.search(r"(\d+)\s+maximum resident set size", process.stderr)
        result = {"model": model.name, "model_sha256": sha256(model),
                  "max_context": args.max_context,
                  "wall_seconds_cold": round(wall, 2),
                  "peak_resident_bytes": int(rss_match.group(1)) if rss_match else None,
                  "audio_seconds": round(duration, 2), "realtime_factor_cold": round(wall / duration, 3),
                  "reference_words": count, "word_errors": errors,
                  "word_error_rate": round(wer, 4),
                  "number_normalized_word_errors": number_errors,
                  "number_normalized_word_error_rate": round(number_wer, 4),
                  "transcript": hypothesis}
        results.append(result)
        print(json.dumps(result, ensure_ascii=False), flush=True)
    report = {"dataset": manifest["dataset"], "revision": manifest["revision"],
              "rows": [row["row"] for row in manifest["examples"]],
              "speaker_ids": sorted({row["speaker_id"] for row in manifest["examples"]}),
              "method": "Concatenated read speech with 0.4 s silence between clips; cold CLI run; lowercase punctuation-insensitive word error rate",
              "reference": reference, "results": results}
    (args.output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
