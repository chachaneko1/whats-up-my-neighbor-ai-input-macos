"""Download official public Chinese WeSpeaker weights, extract only known files."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile


def prepare(directory):
    directory.mkdir(parents=True, exist_ok=False)
    listing = directory / 'source.json'
    subprocess.run(['curl', '-fsSL', '--max-time', '120',
                    'https://modelscope.cn/api/v1/datasets/wenet/wespeaker_pretrained_models/oss/tree', '-o', str(listing)], check=True)
    entry = next(x for x in json.loads(listing.read_text())['Data'] if x['Key'] == 'cnceleb_resnet34.tar.gz')
    archive = directory / 'model.tar.gz'
    subprocess.run(['curl', '-fsSL', '--retry', '2', '--max-time', '180', entry['Url'], '-o', str(archive)], check=True)
    with tarfile.open(archive) as stream:
        selected = [m for m in stream.getmembers() if m.isfile() and Path(m.name).name in ('avg_model.pt', 'config.yaml')]
        if len(selected) != 2:
            raise ValueError('Expected exactly one config and one model')
        for member in selected:
            (directory / Path(member.name).name).write_bytes(stream.extractfile(member).read())
    (directory / 'checksums.json').write_text(json.dumps({name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
        for name in ['model.tar.gz', 'avg_model.pt', 'config.yaml']}, indent=2))
    print('Prepared official WeSpeaker Chinese model; no audio uploaded.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    prepare(parser.parse_args().output)
