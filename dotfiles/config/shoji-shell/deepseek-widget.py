#!/usr/bin/env python3
"""Read-only balance polling; observed decreases are estimates, not invoices."""
from decimal import Decimal
import fcntl
import hashlib
import json
import os
from pathlib import Path
import tempfile
import sys
import time
import urllib.error
import urllib.request

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'shoji-shell'
STATE = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'shoji-shell/deepseek'


def amount(value):
    if isinstance(value, bool) or not isinstance(value, (str, int, float)):
        raise ValueError('Invalid balance')
    result = Decimal(str(value))
    if not result.is_finite():
        raise ValueError('Invalid balance')
    return result


def parse_balance(data):
    rows = data['balance_infos']
    if not isinstance(rows, list) or not rows:
        raise ValueError('No balance')
    # Do not combine currencies or convert them with an invented exchange rate.
    row = next((r for r in rows if r.get('currency') == 'USD'), rows[0])
    if row['currency'] not in ('USD', 'CNY'):
        raise ValueError('Unknown currency')
    return row['currency'], amount(row['total_balance'])


def track(previous, credit, now):
    if previous is None:
        return {'balance': str(credit), 'spent': '0', 'since': now}
    spent = amount(previous['spent']) + max(Decimal(0), amount(previous['balance']) - credit)
    return {'balance': str(credit), 'spent': str(spent), 'since': previous['since']}


def refresh(key, directory=STATE, fetch=None, now=None):
    now = int(time.time() * 1000) if now is None else now
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    identity = hashlib.sha256(key.encode()).hexdigest()
    lockpath = directory / (identity + '.lock')
    with lockpath.open('a') as lock:
        os.chmod(lockpath, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = directory / (identity + '.json')
        try:
            previous = json.loads(path.read_text())
        except (OSError, ValueError):
            previous = None
        if previous and 0 <= now - previous['fetchedAt'] < 60000:
            return previous['payload']
        if fetch is None:
            request = urllib.request.Request('https://api.deepseek.com/user/balance', headers={
                'Authorization': 'Bearer ' + key, 'Accept': 'application/json'})
            # Credentials never follow redirects to another host.
            class NoRedirect(urllib.request.HTTPRedirectHandler):
                def redirect_request(self, *args, **kwargs):
                    return None
            with urllib.request.build_opener(NoRedirect).open(request, timeout=15) as response:
                data = json.load(response)
        else:
            data = fetch()
        currency, credit = parse_balance(data)
        ledger = track(previous.get('ledger') if previous and previous.get('currency') == currency else None, credit, now)
        payload = {'state': 'available', 'credit': float(credit), 'currency': currency,
                   'spent': float(amount(ledger['spent'])), 'since': ledger['since'], 'fetchedAt': now}
        record = {'currency': currency, 'ledger': ledger, 'fetchedAt': now, 'payload': payload}
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', dir=directory, delete=False) as stream:
                temporary = Path(stream.name)
                json.dump(record, stream, allow_nan=False)
            temporary.replace(path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        return payload


def main():
    if os.environ.get('SHOJI_ENABLE_DEEPSEEK') != '1':
        return {'state': 'disabled', 'error': 'DeepSeek integration is disabled'}
    try:
        key = os.environ.get('DEEPSEEK_API_KEY', '').strip()
        if not key:
            keypath = Path(os.environ.get('DEEPSEEK_API_KEY_FILE') or CONFIG / 'deepseek-api-key')
            key = keypath.read_text().strip() if keypath.exists() else ''
        if not key:
            return {'state': 'missing', 'error': 'Добавьте ключ DeepSeek API'}
        return refresh(key)
    except urllib.error.HTTPError as error:
        return {'state': 'auth' if error.code in (401, 403) else 'unavailable',
                'error': 'Проверьте ключ API' if error.code in (401, 403) else 'DeepSeek недоступен'}
    except Exception:
        # Exceptions and raw responses may contain credentials; emit only a fixed message.
        return {'state': 'unavailable', 'error': 'DeepSeek недоступен'}


if __name__ == '__main__':
    if os.environ.get('SHOJI_ENABLE_DEEPSEEK') != '1':
        sys.exit('DeepSeek integration is disabled; opt in locally first')
    print(json.dumps(main(), ensure_ascii=False, allow_nan=False))
