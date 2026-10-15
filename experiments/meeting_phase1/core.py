"""Offline timeline, exports and evaluation; no model/network imports."""
from __future__ import annotations
import itertools
import json
import math
import unicodedata
from pathlib import Path


def interval(row):
    a, b = float(row['start']), float(row['end'])
    if not math.isfinite(a) or not math.isfinite(b) or a < 0 or b <= a:
        raise ValueError('Invalid audio time interval')
    return a, b


def overlap(a, b):
    return max(0., min(a[1], b[1]) - max(a[0], b[0]))


def anonymous_turns(turns):
    names, result = {}, []
    for row in sorted(turns, key=lambda x: interval(x)):
        start, end = interval(row)
        label = str(row['speaker'])
        if label in ('-1', 'UNKNOWN'):
            result.append({'start': start, 'end': end, 'speaker': 'UNKNOWN'})
            continue
        if label not in names:
            n = len(names)
            names[label] = chr(65 + n) if n < 26 else f'SPEAKER_{n + 1}'
        result.append({'start': start, 'end': end, 'speaker': names[label]})
    return result


def align(tokens, turns, minimum_coverage=.7, competing_coverage=.2):
    """Assign by union duration, not segment count. Ambiguity stays UNKNOWN."""
    rows = []
    for index, token in enumerate(tokens):
        a, b = interval(token)
        spans = {}
        for turn in turns:
            x, y = interval(turn)
            if overlap((a, b), (x, y)):
                spans.setdefault(turn['speaker'], []).append((max(a, x), min(b, y)))
        mass = {}
        for speaker, pieces in spans.items():
            total, last = 0., None
            for x, y in sorted(pieces):
                if last is None or x > last:
                    total += y - x
                elif y > last:
                    total += y - last
                last = max(last or y, y)
            mass[speaker] = total
        ranked = sorted(mass, key=lambda s: (-mass[s], s))
        best = mass[ranked[0]] / (b-a) if ranked else 0.
        second = mass[ranked[1]] / (b-a) if len(ranked) > 1 else 0.
        ambiguous = not ranked or ranked[0] == 'UNKNOWN' or best < minimum_coverage or second >= competing_coverage
        rows.append({'id': f'segment-{index + 1}', 'start': a, 'end': b,
                     'speaker': 'UNKNOWN' if ambiguous else ranked[0],
                     'text': str(token['text']), 'needs_review': ambiguous,
                     'speaker_coverage': round(best, 4),
                     'competing_speaker_coverage': round(second, 4)})
    return rows


def timestamp(value):
    ms = round(float(value) * 1000)
    return f'{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d}.{ms % 1000:03d}'


def markdown(document):
    names = document.get('speaker_names', {})
    rows = ['# 會議逐字稿', '', '> 自動辨識草稿；UNKNOWN 或需確認的片段請聽原音核對。', '']
    for row in document['segments']:
        label = names.get(row['speaker']) or row['speaker']
        text = row['text'].replace('\n', ' ').replace('\r', ' ')
        label = str(label).replace('\n', ' ').replace('\r', ' ')
        rows.append(f"[{timestamp(row['start'])}–{timestamp(row['end'])}] {label}: {text}" + (' 【需確認】' if row['needs_review'] else ''))
    return '\n'.join(rows) + '\n'


def editor(document):
    template = Path(__file__).with_name('editor.html').read_text()
    payload = json.dumps(document, ensure_ascii=False).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
    return template.replace('__DOCUMENT__', payload)


def save_outputs(document, directory):
    directory = Path(directory)
    (directory / 'transcript.json').write_text(json.dumps(document, ensure_ascii=False, indent=2) + '\n')
    (directory / 'transcript.md').write_text(markdown(document))
    (directory / 'review.html').write_text(editor(document))


def speaker_score(reference, hypothesis, collar=.25):
    """Controlled concatenation: purity on predicted time within known clip interiors.

    This is NOT DER: clip boundaries are not independently annotated speech activity.
    Labels are optimally mapped per file; absent/extra speakers are exposed separately.
    """
    expected = sorted({r['speaker'] for r in reference})
    predicted = sorted({r['speaker'] for r in hypothesis if r['speaker'] != 'UNKNOWN'})
    if len(predicted) > 8 or len(expected) > 8:
        raise ValueError('Controlled scorer supports at most eight labels')
    weights = {}
    total = 0.
    for ref in reference:
        a, b = interval(ref)
        if b - a <= collar * 2:
            continue
        for hyp in hypothesis:
            mass = overlap((a + collar, b - collar), interval(hyp))
            weights[hyp['speaker'], ref['speaker']] = weights.get((hyp['speaker'], ref['speaker']), 0.) + mass
            total += mass
    # Extra clusters cannot all be mapped onto one person and hide fragmentation.
    count = max(len(predicted), len(expected))
    targets = expected + [None] * (count - len(expected))
    best, mapping = 0., {}
    for candidate in set(itertools.permutations(targets, len(predicted))):
        score = sum(weights.get((p, t), 0.) for p, t in zip(predicted, candidate))
        if score > best or not mapping:
            best, mapping = score, dict(zip(predicted, candidate))
    return {'metric': 'speaker_purity_on_predicted_clip_interiors_not_DER',
            'purity': best / total if total else None,
            'scored_predicted_seconds': total, 'mismatched_seconds': total - best,
            'reference_speaker_count': len(expected), 'predicted_speaker_count': len(predicted),
            'best_label_mapping': mapping, 'collar_seconds': collar}


def character_error_rate(reference, hypothesis):
    def clean(text):
        return ''.join(c for c in unicodedata.normalize('NFKC', text).lower() if c.isalnum())
    a, b = clean(reference), clean(hypothesis)
    if not a:
        return None
    previous = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        current = [i]
        for j, y in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j-1] + (x != y)))
        previous = current
    return previous[-1] / len(a)


def coalesce(rows, max_span=10., max_gap=.8):
    result = []
    for row in rows:
        current = dict(row)
        if (result and result[-1]['speaker'] == current['speaker']
                and result[-1]['needs_review'] == current['needs_review']
                and 0 <= current['start'] - result[-1]['end'] <= max_gap
                and current['end'] - result[-1]['start'] <= max_span):
            result[-1]['end'] = current['end']
            result[-1]['text'] += current['text']
            result[-1]['speaker_coverage'] = min(result[-1]['speaker_coverage'], current['speaker_coverage'])
            result[-1]['competing_speaker_coverage'] = max(result[-1]['competing_speaker_coverage'], current['competing_speaker_coverage'])
        else:
            result.append(current)
    for i, row in enumerate(result, 1):
        row['id'] = f'segment-{i}'
    return result
