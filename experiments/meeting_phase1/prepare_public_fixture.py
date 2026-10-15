"""Prepare a known two-speaker Mandarin concatenation. NOT a natural meeting.

Downloads only small AISHELL-3 test clips from the publisher's HF repository.
Audio, transcripts and reference stay in the ignored build/ directory.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import wave

BASE = 'https://huggingface.co/datasets/AISHELL/AISHELL-3/resolve/main/'
CLIPS = {
 'A': ['SSB00090030', 'SSB00090138', 'SSB00090164', 'SSB00090176', 'SSB00090179', 'SSB00090221'],
 'B': ['SSB00110049', 'SSB00110115', 'SSB00110264', 'SSB00110278', 'SSB00110300', 'SSB00110326'],
}


def fetch(url, dest):
    subprocess.run(['curl', '--fail', '--silent', '--show-error', '--location', '--retry', '2',
                    '--max-time', '120', url, '-o', str(dest)], check=True)


def prepare(directory, split="test", minimum_bytes=0):
    directory.mkdir(parents=True, exist_ok=False)
    fetch(BASE + f'{split}/content.txt', directory / 'content.txt')
    fetch(BASE + 'README.md', directory / 'source_README.md')
    contents = {}
    for line in (directory / 'content.txt').read_text().splitlines():
        key, _, text = line.partition('\t')
        if not text:
            key, _, text = line.partition('|')
        if text:
            # AISHELL-3 alternates written words and pinyin; retain written tokens.
            contents[key.removesuffix('.wav')] = ''.join(text.split()[::2])
    # Select actual publisher file names instead of assuming contiguous numbering.
    for label, speaker in [('A', 'SSB0009'), ('B', 'SSB0011')]:
        listing = directory / f'{speaker}.json'
        fetch(f'https://huggingface.co/api/datasets/AISHELL/AISHELL-3/tree/main/{split}/wav/{speaker}?limit=100', listing)
        CLIPS[label] = [Path(x['path']).stem for x in json.loads(listing.read_text()) if x['path'].endswith('.wav') and x.get('size', 0) >= minimum_bytes][:6]
        if len(CLIPS[label]) < 6:
            raise ValueError('Not enough clips for the predeclared fixture')
    samples, records = {}, []
    for label, clips in CLIPS.items():
        for clip in clips:
            target = directory / f'{clip}.wav'
            url = BASE + f'{split}/wav/{clip[:7]}/{clip}.wav'
            fetch(url, target)
            normalized = directory / f'{clip}-16k.wav'
            subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-n', '-i', str(target), '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', str(normalized)], check=True)
            with wave.open(str(normalized)) as audio:
                samples[clip] = audio.readframes(audio.getnframes())
            records.append({'clip': clip, 'speaker': label, 'url': url,
                            'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'text': contents.get(clip, '')})
    (directory / 'provenance.json').write_text(json.dumps({'source': BASE, 'license_metadata': 'apache-2.0 (publisher dataset card)',
        'kind': 'controlled_concatenation_not_natural_meeting', 'split': split, 'minimum_source_bytes': minimum_bytes, 'clips': records}, ensure_ascii=False, indent=2))
    for order, labels in [('alternating', ['A', 'B'] * 6), ('blocked', ['A'] * 6 + ['B'] * 6)]:
        counts = {'A': 0, 'B': 0}
        cursor, turns, text = 0., [], []
        with wave.open(str(directory / f'{order}.wav'), 'wb') as out:
            out.setnchannels(1); out.setsampwidth(2); out.setframerate(16000)
            for label in labels:
                clip = CLIPS[label][counts[label]]
                counts[label] += 1
                data = samples[clip]
                duration = len(data) / 32000
                turns.append({'start': cursor, 'end': cursor + duration, 'speaker': label, 'clip': clip})
                text.append(contents.get(clip, ''))
                out.writeframes(data + b'\0' * 16000)  # 0.5 second silence between turns.
                cursor += duration + .5
        (directory / f'{order}-reference.json').write_text(json.dumps({'kind': 'controlled_concatenation_not_natural_meeting',
            'turns': turns, 'text': ''.join(text)}, ensure_ascii=False, indent=2))
    print(f'Prepared {len(records)} clips from two speakers; controlled, non-overlapping concatenations only.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--split', choices=['train', 'test'], default='test')
    parser.add_argument('--minimum-bytes', type=int, default=0)
    args = parser.parse_args()
    prepare(args.output, args.split, args.minimum_bytes)
