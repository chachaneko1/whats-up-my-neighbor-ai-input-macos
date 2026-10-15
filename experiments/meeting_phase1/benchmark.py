"""Run the predeclared two-order, short/long controlled smoke matrix."""
import argparse
import json
from pathlib import Path
import subprocess
import sys


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--short-fixtures', type=Path, required=True)
    p.add_argument('--long-fixtures', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--diarizer-model', required=True)
    p.add_argument('--asr-model', default='tiny')
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    results = []
    for group, fixture in [('long', args.long_fixtures), ('short', args.short_fixtures)]:
        for order in ['alternating', 'blocked']:
            name = f'{group}-{order}'
            destination = args.output / name
            command = [sys.executable, '-m', 'experiments.meeting_phase1.run',
                       '--audio', str(fixture / f'{order}.wav'), '--reference', str(fixture / f'{order}-reference.json'),
                       '--output', str(destination), '--diarizer', 'wespeaker',
                       '--diarizer-model', args.diarizer_model, '--asr-model', args.asr_model]
            print(f'Running {name}', flush=True)
            with (args.output / f'{name}.log').open('w') as log:
                completed = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
            if completed.returncode:
                results.append({'name': name, 'pipeline_success': False})
            else:
                metadata = json.loads((destination / 'run.json').read_text())
                purity = metadata['controlled_evaluation']['purity']
                results.append({'name': name, 'pipeline_success': True, 'speakers': metadata['speaker_count'],
                                'purity_not_DER': purity, 'raw_CER': metadata['character_error_rate'],
                                'controlled_smoke_passed': metadata['speaker_count'] == 2 and purity is not None and purity >= .95})
            (args.output / 'summary.json').write_text(json.dumps({'natural_meeting_validated': False,
                                                               'results': results}, indent=2))
    print(json.dumps(results, indent=2))

if __name__ == '__main__':
    main()
