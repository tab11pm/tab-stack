"""Balance/cache checks using synthetic data; never reads credentials or uses network."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from decimal import Decimal

spec = importlib.util.spec_from_file_location('deepseek_widget', Path(__file__).resolve().parents[1] / 'config/shoji-shell/deepseek-widget.py')
widget = importlib.util.module_from_spec(spec)
spec.loader.exec_module(widget)


class BalanceChecks(unittest.TestCase):
    def test_disabled_does_not_read_credentials(self):
        with patch.dict(os.environ, {'SHOJI_ENABLE_DEEPSEEK': '0'}), patch.object(Path, 'read_text', side_effect=AssertionError('Read credentials')), patch.object(widget, 'refresh', side_effect=AssertionError('Queried account')):
            self.assertEqual(widget.main()['state'], 'disabled')

    def test_currency_and_invalid_numbers(self):
        self.assertEqual(widget.parse_balance({'balance_infos': [
            {'currency': 'CNY', 'total_balance': '30'}, {'currency': 'USD', 'total_balance': '2.25'}]}), ('USD', Decimal('2.25')))
        for value in ('NaN', 'Infinity', True, None):
            with self.assertRaises(ValueError): widget.amount(value)
        with self.assertRaises(ValueError): widget.parse_balance({'balance_infos': []})

    def test_spend_estimate_and_topups(self):
        ledger = widget.track(None, Decimal('10'), 1)
        ledger = widget.track(ledger, Decimal('8'), 2)
        self.assertEqual(ledger['spent'], '2')
        self.assertEqual(widget.track(ledger, Decimal('12'), 3)['spent'], '2')

    def test_cache_key_currency_isolation_and_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / 'state'
            def fetch(currency, balance):
                return lambda: {'balance_infos': [{'currency': currency, 'total_balance': balance}]}
            first = widget.refresh('synthetic-key-one', state, fetch('USD', '10'), 1000)
            cached = widget.refresh('synthetic-key-one', state, lambda: self.fail('Cache missed'), 2000)
            self.assertEqual(first, cached)
            self.assertEqual(widget.refresh('synthetic-key-one', state, fetch('USD', '8'), 62000)['spent'], 2)
            changed = widget.refresh('synthetic-key-one', state, fetch('CNY', '30'), 123000)
            self.assertEqual(changed['spent'], 0)
            self.assertEqual(widget.refresh('synthetic-key-two', state, fetch('USD', '7'), 124000)['spent'], 0)
            for file in state.iterdir():
                self.assertEqual(file.stat().st_mode & 0o777, 0o600)
                self.assertNotIn('synthetic-key', file.read_text())

    def test_errors_never_echo_credentials(self):
        with patch.dict(os.environ, {'SHOJI_ENABLE_DEEPSEEK': '1', 'DEEPSEEK_API_KEY': 'synthetic-key'}), patch.object(widget, 'refresh', side_effect=RuntimeError('synthetic-key')):
            self.assertNotIn('synthetic-key', str(widget.main()))


if __name__ == '__main__': unittest.main()
