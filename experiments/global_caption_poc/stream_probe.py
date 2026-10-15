"""Replay a public sample into BlackHole and time whisper-stream text updates.

Check the device indices on this Mac before running. This test changes no
system default audio device and does not record any live microphone audio.
"""

import argparse
import json
import os
import re
import select
import subprocess
import time
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--audio", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--capture-index", type=int, required=True)
    parser.add_argument("--play-index", type=int, required=True)
    parser.add_argument("--step-ms", type=int, default=1000)
    parser.add_argument("--length-ms", type=int, default=4000)
    parser.add_argument("--tail-wait-seconds", type=float, default=2.0)
    args = parser.parse_args()
    command = ["whisper-stream", "-m", str(args.model), "-c", str(args.capture_index),
               "--step", str(args.step_ms), "--length", str(args.length_ms),
               "--keep", "200", "-t", "4", "-l", "en"]
    playback = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-re",
                "-i", str(args.audio), "-ac", "2", "-ar", "48000", "-f", "audiotoolbox",
                "-audio_device_index", str(args.play_index), "-"]
    stream = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT)
    assert stream.stdout is not None
    pending = b""
    events = []
    player = None
    playback_start = None
    playback_end = None
    deadline = time.monotonic() + 25
    try:
        while time.monotonic() < deadline:
            readable, _, _ = select.select([stream.stdout], [], [], 0.1)
            if readable:
                chunk = os.read(stream.stdout.fileno(), 4096)
                if not chunk:
                    break
                pending += chunk
                lines = re.split(b"[\r\n]", pending)
                pending = lines.pop()
                for raw in lines:
                    line = re.sub(rb"\x1b\[[0-9;]*[A-Za-z]", b"", raw).decode("utf-8", "replace").strip()
                    if "[Start speaking]" in line and player is None:
                        player = subprocess.Popen(playback, stdout=subprocess.DEVNULL,
                                                  stderr=subprocess.DEVNULL)
                        playback_start = time.monotonic()
                    if playback_start and line and not line.startswith(("whisper", "ggml", "main:", "init:", "[")):
                        events.append({"seconds_after_playback": round(time.monotonic() - playback_start, 2),
                                       "text": line})
            if player and player.poll() is not None and playback_end is None:
                playback_end = time.monotonic()
            if playback_end and time.monotonic() - playback_end > args.tail_wait_seconds:
                break
        if player is None:
            raise RuntimeError("whisper-stream did not become ready")
        if player.returncode not in (None, 0):
            raise RuntimeError(f"playback failed with exit {player.returncode}")
    finally:
        stream.terminate()
        try:
            stream.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            stream.kill()
            stream.communicate()
    result = {"model": args.model.name, "audio": args.audio.name,
              "step_ms": args.step_ms, "length_ms": args.length_ms,
              "playback_seconds": round(playback_end - playback_start, 2) if playback_end else None,
              "events": events}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
