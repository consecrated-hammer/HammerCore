#!/usr/bin/env python3
"""The curated bank rejects ambiguous choices, bad tags and unsafe chat text."""
import copy
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('quiz_generator', ROOT / 'tools/generate_quiz.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class QuizDataTests(unittest.TestCase):
    def setUp(self):
        self.row = dict(id='test-sourced-question', question='Which place is this?', correct='A place',
                        wrong=['Another place', 'A third place', 'Somewhere else'], era='both',
                        difficulty='hard', categories=['lore', 'geography'], source='https://example.org/fact')

    def rejected(self, change):
        row = copy.deepcopy(self.row)
        row.update(change)
        with self.assertRaises((AssertionError, KeyError, TypeError)):
            module.validate([row])

    def test_safe_row_and_multiple_tags(self):
        module.validate([self.row])
        files = module.render([self.row])
        lore = files[ROOT / 'src/Quiz_lore.lua']
        self.assertIn('DecodeQuiz', lore)
        self.assertEqual(sum(text.count('    { ') for text in files.values()), 1)
        for value in (self.row['question'], self.row['correct'], self.row['id'], self.row['source']):
            self.assertNotIn(value, lore)
        self.assertEqual(module.pack(self.row), module.pack(copy.deepcopy(self.row)))

    def test_duplicates_and_ambiguous_choices(self):
        with self.assertRaises(AssertionError):
            module.validate([self.row, self.row])
        self.rejected(dict(wrong=['a place', 'A third place', 'Somewhere else']))
        self.rejected(dict(wrong=['Only one']))

    def test_chat_control_characters(self):
        self.rejected(dict(question='Injected\n/run command'))
        self.rejected(dict(correct='|Hplayer:someone|h'))

    def test_scope_and_metadata(self):
        self.rejected(dict(era='vanilla'))
        self.rejected(dict(difficulty='impossible'))
        self.rejected(dict(categories=['unknown']))
        self.rejected(dict(source='file:///etc/passwd'))
        self.rejected({'class': 'NEWCLASS'})
        self.rejected({'race': 'NewRace'})

    def test_client_specific_wording_can_overlap_only_across_clients(self):
        first, second = copy.deepcopy(self.row), copy.deepcopy(self.row)
        first.update(era='classic')
        second.update(id='test-other-client', era='retail')
        module.validate([first, second])
        second['era'] = 'both'
        with self.assertRaises(AssertionError):
            module.validate([first, second])

    def test_missing_fields_and_wrong_types_are_reported(self):
        self.rejected({'question': None})
        self.rejected({'wrong': 'abc'})
        self.rejected({'categories': 'lore'})
        row = copy.deepcopy(self.row)
        del row['source']
        with self.assertRaisesRegex(AssertionError, 'missing fields'):
            module.validate([row])

    def test_quote_budget_is_shared_by_all_questions_from_a_page(self):
        first, second = copy.deepcopy(self.row), copy.deepcopy(self.row)
        first['question'] = 'Who says "one two three four five six seven eight nine ten eleven twelve thirteen"?'
        second.update(id='test-second-quote', question='Who shouts "a b c d e f g h i j k l m"?')
        with self.assertRaisesRegex(AssertionError, '25 words'):
            module.validate([first, second])

    def test_retired_questions_are_kept_out_of_the_bank(self):
        retired = dict(self.row, id='test-retired', question='Which other place is this?', retired=True)
        module.validate([self.row, retired])
        files = module.render([self.row, retired])
        self.assertEqual(sum(text.count('    { ') for text in files.values()), 1)
        self.rejected(dict(retired='yes'))

    def test_ledger_keeps_shipped_ids(self):
        import tempfile
        rows = [self.row]
        missing, new = module.ledger_problems(rows, [])
        self.assertEqual((missing, new), ([], ['test-sourced-question']))
        missing, new = module.ledger_problems(rows, ['test-sourced-question', 'gone-question'])
        self.assertEqual((missing, new), (['gone-question'], []))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'ids.txt'
            module.write_ledger(['a-one'], ['b-two'], path)
            self.assertEqual(module.read_ledger(path), ['a-one', 'b-two'])
            self.assertTrue(path.read_text().startswith('#'))

    def test_shipped_bank_matches_ledger(self):
        rows = []
        for path in sorted((ROOT / 'data/quiz').glob('*.jsonl')):
            rows.extend(__import__('json').loads(line) for line in path.read_text().splitlines() if line.strip())
        missing, new = module.ledger_problems(rows, module.read_ledger())
        self.assertEqual((missing, new), ([], []))

if __name__ == '__main__':
    unittest.main()
