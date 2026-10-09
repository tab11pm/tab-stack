#!/usr/bin/env python3
"""Laptop backlight or external DDC/CI. Writes only on an explicit UI action."""
import json
import math
import re
import subprocess
import sys
from pathlib import Path

BACKLIGHT_ROOT = Path('/sys/class/backlight')


def internal(connector):
    return bool(re.match(r'^(eDP|LVDS|DSI)-\d', connector))


def backlight_for(connector):
    devices = list(BACKLIGHT_ROOT.iterdir())
    matches = [device for device in devices if any(
        re.fullmatch(r'card\d+-' + re.escape(connector), parent.name)
        for parent in device.resolve().parents)]
    # Some firmware backlights have no DRM connector in their sysfs path.
    if not matches and len(devices) == 1 and not any(
            re.fullmatch(r'card\d+-(?:eDP|LVDS|DSI)-\d+', parent.name)
            for parent in devices[0].resolve().parents):
        matches = devices
    if not matches:
        raise ValueError('Подсветка встроенного экрана не найдена')
    priority = {'raw': 0, 'platform': 1, 'firmware': 2}
    return min(matches, key=lambda device: (
        priority.get((device / 'type').read_text().strip(), 3), device.name))


def backlight_level(device):
    current = int((device / 'brightness').read_text())
    maximum = int((device / 'max_brightness').read_text())
    if maximum <= 0 or not 0 <= current <= maximum:
        raise ValueError('Некорректный уровень подсветки ноутбука')
    return current, maximum


def laptop_brightness(mode, connector, percentage):
    device = backlight_for(connector)
    current, maximum = backlight_level(device)
    if mode == 'set':
        level = max(1, raw_level(float(percentage), maximum))
        subprocess.check_output(['brightnessctl', '--class=backlight', '--device=' + device.name,
                                 'set', str(level)], text=True, timeout=5,
                                stderr=subprocess.DEVNULL)
        current, maximum = backlight_level(device)
    return {'available': True, 'value': round(current * 100 / maximum), 'error': '',
            'connector': connector, 'bus': '', 'backend': 'backlight', 'device': device.name}


def run(*args):
    return subprocess.check_output(['ddcutil', '--skip-ddc-checks', *args], text=True, timeout=12,
                                   stderr=subprocess.DEVNULL)


def bus_for(connector, detection):
    for block in detection.split('\n\n'):
        bus = re.search(r'I2C bus:\s+/dev/i2c-(\d+)', block)
        drm = re.search(r'DRM connector:\s+(\S+)', block)
        if bus and drm and drm[1].endswith('-' + connector):
            return bus[1]
    raise ValueError('Монитор не найден через DDC/CI')


def brightness(output):
    match = re.search(r'^VCP 10 C (\d+) (\d+)$', output.strip(), re.MULTILINE)
    if not match or int(match[2]) <= 0:
        raise ValueError('Монитор не сообщает яркость')
    return int(match[1]), int(match[2])


def raw_level(percent, maximum):
    if not math.isfinite(percent) or not 0 <= percent <= 100:
        raise ValueError('Яркость должна быть от 0 до 100%')
    return round(percent * maximum / 100)


def main():
    mode, connector, *rest = sys.argv[1:]
    if mode not in ('get', 'set') or not re.fullmatch(r'[A-Za-z0-9-]+', connector):
        raise ValueError('Некорректный запрос яркости')
    if internal(connector):
        return laptop_brightness(mode, connector, rest[0] if rest else '0')
    bus = rest[1] if len(rest) > 1 else ''
    if bus and not re.fullmatch(r'\d+', bus):
        raise ValueError('Некорректная шина DDC/CI')
    if not bus:
        bus = bus_for(connector, run('detect', '--brief'))
    current, maximum = brightness(run('--bus', bus, 'getvcp', '10', '--terse'))
    if mode == 'set':
        level = raw_level(float(rest[0]), maximum)
        run('--bus', bus, 'setvcp', '10', str(level))
        current, maximum = brightness(run('--bus', bus, 'getvcp', '10', '--terse'))
    return {'available': True, 'value': round(current * 100 / maximum), 'error': '',
            'connector': connector, 'bus': bus}


if __name__ == '__main__':
    if '--check' in sys.argv:
        assert brightness('VCP 10 C 75 150\n') == (75, 150)
        assert raw_level(50, 150) == 75
        assert bus_for('DP-1', 'Display 1\n I2C bus: /dev/i2c-4\n DRM connector: card1-DP-1\n') == '4'
        try:
            raw_level(float('nan'), 100)
        except ValueError:
            pass
        else:
            raise AssertionError('Non-finite brightness accepted')
        calls = []
        def fake_run(*args):
            calls.append(args)
            return 'Display 1\n I2C bus: /dev/i2c-4\n DRM connector: card1-DP-1\n' if args[0] == 'detect' else 'VCP 10 C 75 150\n'
        run = fake_run
        sys.argv = [sys.argv[0], 'get', 'DP-1', '0', '']
        result = main()
        assert result['bus'] == '4' and result['value'] == 50
        calls.clear()
        sys.argv[-1] = result['bus']
        assert main()['value'] == 50
        assert calls == [('--bus', '4', 'getvcp', '10', '--terse')]
        # Exercise the real routing and backlight code against an isolated sysfs fixture.
        import tempfile
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)
            BACKLIGHT_ROOT = fixture / 'backlight'
            BACKLIGHT_ROOT.mkdir()
            device = fixture / 'card1-eDP-1' / 'intel_backlight'
            device.mkdir(parents=True)
            (BACKLIGHT_ROOT / device.name).symlink_to(device)
            (device / 'type').write_text('raw')
            (device / 'max_brightness').write_text('96000')
            (device / 'brightness').write_text('48000')
            sys.argv = [sys.argv[0], 'get', 'eDP-1', '0', '']
            calls.clear()
            assert main()['value'] == 50 and not calls
            writes = []
            def fake_backlight_write(args, **kwargs):
                writes.append(args)
                (device / 'brightness').write_text(args[-1])
                return ''
            with patch.object(subprocess, 'check_output', fake_backlight_write):
                sys.argv = [sys.argv[0], 'set', 'eDP-1', '25', '']
                assert main()['value'] == 25
                assert writes[-1] == ['brightnessctl', '--class=backlight', '--device=intel_backlight', 'set', '24000']
                sys.argv[3] = '0'
                main()
                assert writes[-1][-1] == '1'
                for invalid in ['nan', '-1', '101']:
                    sys.argv[3] = invalid
                    before = len(writes)
                    try:
                        main()
                    except ValueError:
                        pass
                    else:
                        raise AssertionError('Invalid backlight value accepted')
                    assert len(writes) == before
            try:
                backlight_for('eDP-2')
            except ValueError:
                pass
            else:
                raise AssertionError('Wrong internal connector selected')
        print('Laptop routing, read/write, range checks and external DDC checks passed.')
    else:
        try:
            result = main()
        except (OSError, ValueError, IndexError, subprocess.SubprocessError) as error:
            connector = sys.argv[2] if len(sys.argv) > 2 else ''
            failure = 'Нет доступа к подсветке ноутбука' if internal(connector) else 'Нет доступа к DDC/CI'
            if isinstance(error, FileNotFoundError) and internal(connector) and error.filename == 'brightnessctl':
                failure = 'Не найден brightnessctl для управления подсветкой ноутбука'
            result = {'available': False, 'value': 0, 'connector': connector,
                      'error': str(error) if isinstance(error, ValueError) else failure}
        print(json.dumps(result, ensure_ascii=False))
