"""Fetch five Indian-born speakers from GMU's Speech Accent Archive.

For local evaluation only. Source audio is CC BY-NC-SA 4.0 and is written
under the ignored build directory; it is not redistributed with this repo.
"""

import argparse
import html
import json
import re
import subprocess
from pathlib import Path


SPEAKERS = ("hindi11", "marathi1", "tamil2", "telugu1", "bengali6")


def fetch(url: str, output: Path | None = None) -> bytes:
    command = ["curl", "-fsSL", "--retry", "2", url]
    if output:
        command += ["-o", str(output)]
        subprocess.run(command, check=True)
        return b""
    return subprocess.check_output(command)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    records = []
    for speaker in SPEAKERS:
        page = f"https://accent.gmu.edu/samples/{speaker}/"
        source = fetch(page).decode("utf-8")
        match = re.search(r"<h3>Elicitation Paragraph</h3>(.*?)</aside>", source, re.S)
        if not match or "india" not in source.lower():
            raise RuntimeError(f"Reference or India metadata missing: {page}")
        reference = html.unescape(re.sub(r"<[^>]+>", "", match.group(1))).strip()
        audio_url = f"https://accent.gmu.edu/audio/{speaker}.mp3"
        mp3 = args.output / f"{speaker}.mp3"
        wav = args.output / f"{speaker}.wav"
        fetch(audio_url, mp3)
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(mp3),
                        "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(wav)], check=True)
        records.append({"row": speaker, "speaker_id": speaker, "reference": reference,
                        "file": wav.name, "source_page": page, "audio_url": audio_url})
        print(speaker, wav.stat().st_size, len(reference.split()), flush=True)
    manifest = {"dataset": "George Mason University Speech Accent Archive",
                "revision": "accessed 2026-10-14", "license": "CC BY-NC-SA 4.0", "examples": records}
    (args.output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    for row in records:
        one = dict(manifest, examples=[row])
        (args.output / f"manifest-{row['row']}.json").write_text(json.dumps(one, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
