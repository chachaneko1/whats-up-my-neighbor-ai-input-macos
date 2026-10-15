"""Explicit local research pipeline, separate from the macOS app.

python -m experiments.meeting_phase1.run --help
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import wave

from .core import anonymous_turns, align, coalesce, save_outputs, speaker_score, character_error_rate


def normalize(source, destination, maximum_seconds):
    subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-n', '-i', str(source),
                    '-t', str(maximum_seconds + .1), '-vn', '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', str(destination)], check=True)
    with wave.open(str(destination)) as stream:
        duration = stream.getnframes() / stream.getframerate()
    if duration <= 0 or duration > maximum_seconds:
        raise ValueError(f'Audio duration must be 0–{maximum_seconds} seconds; received {duration:.2f}')
    return duration


def diarize(audio, backend, model, speaker_count=None):
    if backend == 'pyannote':
        if not Path(model).exists() and not os.environ.get('HF_TOKEN'):
            raise ValueError('pyannote needs an authorized local model or HF_TOKEN after accepting model conditions; no fallback was run')
        from pyannote.audio import Pipeline
        pipeline = Pipeline.from_pretrained(model, token=os.environ.get('HF_TOKEN'))
        output = pipeline(str(audio), **({'num_speakers': speaker_count} if speaker_count else {}))
        annotation = getattr(output, 'speaker_diarization', output)
        if hasattr(annotation, 'itertracks'):
            rows = [{'start': segment.start, 'end': segment.end, 'speaker': str(speaker)}
                    for segment, _, speaker in annotation.itertracks(yield_label=True)]
        else:
            rows = [{'start': segment.start, 'end': segment.end, 'speaker': str(speaker)} for segment, speaker in annotation]
    else:
        if speaker_count:
            raise ValueError('WeSpeaker baseline estimates count automatically; --speakers is supported only for pyannote')
        if not Path(model).is_dir():
            raise ValueError('Provide the local WeSpeaker model directory (avg_model.pt and config.yaml)')
        import torch
        import wespeaker
        torch.set_num_threads(2)
        torch.manual_seed(0)
        pipeline = wespeaker.load_model(model)
        pipeline.set_device('cpu')
        rows = [{'start': float(start), 'end': float(end), 'speaker': str(speaker)}
                for _, start, end, speaker in pipeline.diarize(str(audio), 'meeting')]
    return anonymous_turns(rows)


def transcribe(audio, model, allow_download):
    from faster_whisper import WhisperModel
    recognizer = WhisperModel(model, device='cpu', compute_type='int8', cpu_threads=2,
                              local_files_only=not allow_download)
    segments, info = recognizer.transcribe(str(audio), language='zh', beam_size=5,
                                          word_timestamps=True, vad_filter=True,
                                          condition_on_previous_text=False)
    tokens, raw = [], []
    for segment in segments:
        raw.append({'start': segment.start, 'end': segment.end, 'text': segment.text})
        if segment.words:
            tokens.extend({'start': word.start, 'end': word.end, 'text': word.word}
                          for word in segment.words if word.end > word.start and word.word.strip())
        elif segment.end > segment.start and segment.text.strip():
            tokens.append({'start': segment.start, 'end': segment.end, 'text': segment.text})
    return tokens, raw


def run(args):
    source, directory = args.audio.resolve(), args.output.resolve()
    if not source.is_file():
        raise ValueError('Audio input does not exist')
    directory.mkdir(parents=True, exist_ok=False)  # Never overwrite earlier results.
    started = time.perf_counter()
    metadata = {'schema_version': 1, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                'diarizer': args.diarizer, 'diarizer_model': args.diarizer_model,
                'asr': 'faster-whisper-local', 'asr_model': args.asr_model,
                'language': 'zh', 'audio_uploaded': False, 'forced_speaker_count': args.speakers,
                'torch_seed': 0,
                'versions': {name: importlib.metadata.version(name) for name in
                             ['faster-whisper', 'wespeaker', 'torch', 'torchaudio', 'scikit-learn', 'hdbscan', 'umap-learn', 'silero-vad']}}
    model_dir = Path(args.diarizer_model)
    metadata['diarizer_model_sha256'] = {name: hashlib.sha256((model_dir / name).read_bytes()).hexdigest() for name in ['avg_model.pt', 'config.yaml'] if (model_dir / name).is_file()}
    stage = 'normalize'
    try:
        with tempfile.TemporaryDirectory(prefix='neko-meeting-') as temp:
            audio = Path(temp) / 'normalized.wav'
            duration = normalize(source, audio, args.maximum_seconds)
            metadata['duration_seconds'] = duration
            stage = 'diarization'
            step = time.perf_counter()
            turns = diarize(audio, args.diarizer, args.diarizer_model, args.speakers)
            metadata['diarization_seconds'] = time.perf_counter() - step
            (directory / 'diarization.json').write_text(json.dumps(turns, indent=2))
            stage = 'transcription'
            step = time.perf_counter()
            tokens, raw = transcribe(audio, args.asr_model, args.download_models)
            metadata['transcription_seconds'] = time.perf_counter() - step
            (directory / 'asr.json').write_text(json.dumps(raw, ensure_ascii=False, indent=2))
            stage = 'alignment'
            document = {'schema_version': 1, 'speaker_names': {}, 'review_status': 'unreviewed',
                        'metadata': metadata, 'segments': coalesce(align(tokens, turns))}
            metadata['speaker_count'] = len({row['speaker'] for row in turns if row['speaker'] != 'UNKNOWN'})
            metadata['empty_transcript'] = not document['segments']
            metadata['unknown_segments'] = sum(row['needs_review'] for row in document['segments'])
            metadata['wall_seconds'] = time.perf_counter() - started
            if args.reference:
                reference = json.loads(args.reference.read_text())
                metadata['controlled_evaluation'] = speaker_score(reference['turns'], turns)
                metadata['character_error_rate'] = character_error_rate(
                    reference.get('text', ''), ''.join(row['text'] for row in raw))
                metadata['reference_kind'] = reference.get('kind', 'unspecified')
                metadata['reference_sha256'] = hashlib.sha256(args.reference.read_bytes()).hexdigest()
            save_outputs(document, directory)
            (directory / 'run.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
            print(json.dumps({'output': str(directory), 'speakers': metadata['speaker_count'],
                              'segments': len(document['segments']), 'seconds': round(metadata['wall_seconds'], 2)}))
    except Exception as error:
        (directory / 'failure.json').write_text(json.dumps({'stage': stage, 'type': type(error).__name__,
                                                          'message': str(error), 'metadata': metadata}, ensure_ascii=False, indent=2))
        raise


def main():
    parser = argparse.ArgumentParser(description='Local Chinese meeting research; no audio uploads or real-person identification')
    parser.add_argument('--audio', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='New directory only; contains private transcript outputs')
    parser.add_argument('--diarizer', choices=['wespeaker', 'pyannote'], required=True)
    parser.add_argument('--diarizer-model', required=True)
    parser.add_argument('--speakers', type=int, help='Known count for pyannote only; omitted means estimate')
    parser.add_argument('--asr-model', default='small', help='Local faster-whisper model/path; separate from app Groq model')
    parser.add_argument('--download-models', action='store_true', help='Permit ASR model download; no audio is sent')
    parser.add_argument('--reference', type=Path, help='Independent controlled reference for evaluation')
    parser.add_argument('--maximum-seconds', type=float, default=120)
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        parser.exit(1, f'Failed ({type(error).__name__}): {error}\n')

if __name__ == '__main__':
    main()
