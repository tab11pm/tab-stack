#!/usr/bin/env python3
"""Power an external monitor off/on over DDC/CI (VCP d6). Writes only on an explicit UI action."""
import json
import re
import sys

from brightness import bus_for, internal, run


def power(mode, connector):
    if mode not in ('off', 'on') or not re.fullmatch(r'[A-Za-z0-9-]+', connector):
        raise ValueError('Некорректный запрос питания')
    if internal(connector):
        raise ValueError('Встроенный экран не выключается через DDC/CI')
    bus = bus_for(connector, run('detect', '--brief'))
    # The monitor must answer before we cut it: a silent one could not be woken by DDC.
    run('--bus', bus, 'getvcp', 'd6')
    run('--bus', bus, 'setvcp', 'd6', '5' if mode == 'off' else '1')


if __name__ == '__main__':
    if '--check' in sys.argv:
        try:
            power('off', 'eDP-1')
        except ValueError:
            pass
        else:
            raise SystemExit('internal screen must be refused')
        raise SystemExit(0)
    try:
        power(*sys.argv[1:3])
        print(json.dumps({'ok': True, 'error': ''}))
    except Exception as failure:
        print(json.dumps({'ok': False, 'error': str(failure) or 'DDC/CI недоступен'}))
