"""Post-hoc reporting without rerunning models; preserve raw run records."""
import argparse
import json
from pathlib import Path
from .core import character_error_rate


def evaluate(run_directory, reference, output):
    from opencc import OpenCC
    metadata = json.loads((run_directory / 'run.json').read_text())
    raw = json.loads((run_directory / 'asr.json').read_text())
    target = json.loads(reference.read_text())
    hypothesis = ''.join(row['text'] for row in raw)
    converter = OpenCC('t2s')
    data = {'source_run': run_directory.name, 'raw_CER': metadata['character_error_rate'],
            't2s_CER': character_error_rate(converter.convert(target['text']), converter.convert(hypothesis)),
            'normalization': 'OpenCC t2s plus NFKC/alphanumeric; numbers not normalized',
            'speaker_score': metadata['controlled_evaluation'],
            'same_raw_results': True}
    with output.open('x') as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
    print(json.dumps({'run': run_directory.name, 'raw_CER': data['raw_CER'], 't2s_CER': data['t2s_CER']}))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', required=True, type=Path)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    evaluate(args.run, args.reference, args.output)
