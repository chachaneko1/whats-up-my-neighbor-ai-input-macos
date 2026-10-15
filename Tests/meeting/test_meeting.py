import json
import math
from pathlib import Path
import tempfile
import unittest
from experiments.meeting_phase1.core import (align, anonymous_turns, character_error_rate,
                                            coalesce, editor, markdown, save_outputs,
                                            speaker_score, timestamp)

class MeetingTests(unittest.TestCase):
    def test_time_validation_and_labels(self):
        rows = anonymous_turns([{'start': 4, 'end': 5, 'speaker': 'x'}, {'start': 0, 'end': 1, 'speaker': 'y'}])
        self.assertEqual([r['speaker'] for r in rows], ['A', 'B'])
        for a, b in [(-1, 2), (2, 1), (0, math.inf), (0, math.nan)]:
            with self.assertRaises(ValueError):
                anonymous_turns([{'start': a, 'end': b, 'speaker': 'x'}])
        self.assertEqual(timestamp(3599.9996), '01:00:00.000')

    def test_alignment_and_boundary_ambiguity(self):
        turns = [{'start': 0, 'end': 1, 'speaker': 'A'}, {'start': 1, 'end': 2, 'speaker': 'B'}]
        rows = align([{'start': 0, 'end': .8, 'text': '你好'}, {'start': .8, 'end': 1.2, 'text': '邊界'}, {'start': 3, 'end': 4, 'text': '無對齊'}], turns)
        self.assertEqual([r['speaker'] for r in rows], ['A', 'UNKNOWN', 'UNKNOWN'])
        self.assertTrue(rows[1]['needs_review'])

    def test_overlap_and_duplicate_turns(self):
        token = [{'start': 0, 'end': 1, 'text': '插話'}]
        rows = align(token, [{'start': 0, 'end': 1, 'speaker': 'A'}] * 3)
        self.assertEqual(rows[0]['speaker_coverage'], 1.)
        self.assertEqual(rows[0]['speaker'], 'A')
        rows = align(token, [{'start': 0, 'end': 1, 'speaker': 'A'}, {'start': .5, 'end': 1, 'speaker': 'B'}])
        self.assertEqual(rows[0]['speaker'], 'UNKNOWN')

    def test_coalescing_preserves_content_and_gaps(self):
        rows = align([{'start': 0, 'end': .5, 'text': '你'}, {'start': .5, 'end': 1, 'text': '好'}, {'start': 3, 'end': 4, 'text': '再見'}], [{'start': 0, 'end': 5, 'speaker': 'A'}])
        combined = coalesce(rows)
        self.assertEqual([r['text'] for r in combined], ['你好', '再見'])
        self.assertEqual(combined[0]['end'], 1)

    def test_scoring_uses_mapping_not_label_names(self):
        reference = [{'start': 0, 'end': 2, 'speaker': 'A'}, {'start': 2, 'end': 4, 'speaker': 'B'}]
        swapped = [{'start': 0, 'end': 2, 'speaker': 'B'}, {'start': 2, 'end': 4, 'speaker': 'A'}]
        self.assertEqual(speaker_score(reference, swapped)['purity'], 1.)
        collapsed = [{'start': 0, 'end': 4, 'speaker': 'X'}]
        self.assertEqual(speaker_score(reference, collapsed)['purity'], .5)
        self.assertIsNone(speaker_score(reference, [])['purity'])
        fragmented = [{'start': 0, 'end': 1, 'speaker': 'X'}, {'start': 1, 'end': 2, 'speaker': 'Y'}, {'start': 2, 'end': 4, 'speaker': 'Z'}]
        self.assertLess(speaker_score(reference, fragmented)['purity'], 1.)

    def test_exports_keep_identity_separate_and_escape_scripts(self):
        text = '</script><script>alert(1)</script>'
        document = {'speaker_names': {'A': '小明'}, 'segments': [{'id': '1', 'speaker': 'A', 'start': 0, 'end': 1, 'text': text, 'needs_review': False}]}
        output = editor(document)
        self.assertNotIn(text, output)
        self.assertIn('小明', markdown(document))
        self.assertEqual(document['segments'][0]['speaker'], 'A')
        with tempfile.TemporaryDirectory() as temp:
            save_outputs(document, temp)
            self.assertEqual(json.loads((Path(temp) / 'transcript.json').read_text())['segments'][0]['text'], text)
            self.assertTrue((Path(temp) / 'review.html').is_file())

    def test_noise_cluster_is_unknown_not_a_person(self):
        turns = anonymous_turns([{'start': 0, 'end': 1, 'speaker': '-1'}])
        self.assertEqual(turns[0]['speaker'], 'UNKNOWN')
        self.assertEqual(align([{'start': 0, 'end': 1, 'text': '不確定'}], turns)[0]['speaker'], 'UNKNOWN')
        score = speaker_score([{'start': 0, 'end': 1, 'speaker': 'A'}], turns)
        self.assertEqual(score['predicted_speaker_count'], 0)
        self.assertEqual(score['purity'], 0)

    def test_character_error_rate(self):
        self.assertEqual(character_error_rate('你好，ＡＩ！', '你好ai'), 0)
        self.assertEqual(character_error_rate('你好', '你'), .5)
        self.assertIsNone(character_error_rate('', '幻覺'))

if __name__ == '__main__':
    unittest.main()
