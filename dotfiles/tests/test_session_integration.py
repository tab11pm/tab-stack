"""Execute actual registered command expression and QML action functions in JS."""
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


def function_body(text, name):
    start = text.index('{', text.index('function ' + name + '('))
    depth = 1
    end = start + 1
    while depth:
        if text[end] == '{': depth += 1
        if text[end] == '}': depth -= 1
        end += 1
    return text[start + 1:end - 1]


def js(code):
    result = subprocess.run(['node', '-e', code], text=True, capture_output=True, check=True)
    return json.loads(result.stdout)


class IntegrationTests(unittest.TestCase):
    def test_registered_startup_command_selects_legacy_or_ready_without_stop(self):
        source = (ROOT / 'config/shojiwm/src/index.tsx').read_text()
        registration = source.split('COMPOSITOR.process.once("session-portals", {', 1)[1].split('runPolicy:', 1)[0]
        expression = registration.split('command:', 1)[1].strip().rstrip(',')
        for token, expected in [(None, ['bash', '/fixture/scripts/session-portals']), ('owned', ['python3', '/fixture/scripts/session_lifecycle.py', 'ready'])]:
            actual = js('const scripts="/fixture/scripts"; const COMPOSITOR={env:{get:()=>'+json.dumps(token)+'}}; console.log(JSON.stringify('+expression+'));')
            self.assertEqual(actual, expected)

    def harness(self, body):
        source = (ROOT / 'config/shoji-shell/HomeSystemCard.qml').read_text()
        methods = '\n'.join(f'function {name}('+('name' if name == 'requestAction' else '')+') {'+function_body(source, name)+'}' for name in ('requestAction', 'confirm'))
        return js('let error="", pending="", sessionId=""; const action={running:false, command:null}; const Qt={resolvedUrl:()=>"file:///fixture%20home/shojiwm/scripts/logout"}; '+methods+';'+body)

    def test_request_only_prompts_and_confirm_uses_native_helper_without_session_id(self):
        actual = self.harness('requestAction("logout"); const before={...action}; confirm(); console.log(JSON.stringify({before, action, pending, error}));')
        self.assertFalse(actual['before']['running'])
        self.assertEqual(actual['action']['command'], ['python3', '/fixture home/shojiwm/scripts/logout'])
        self.assertTrue(actual['action']['running'])
        self.assertEqual(actual['pending'], '')

    def test_duplicate_confirmation_and_existing_power_actions(self):
        actual = self.harness('requestAction("reboot"); confirm(); requestAction("poweroff"); confirm(); console.log(JSON.stringify(action));')
        self.assertEqual(actual['command'], ['systemctl', 'reboot'])
        for name in ('reboot', 'poweroff'):
            actual = self.harness(f'requestAction("{name}"); confirm(); console.log(JSON.stringify(action));')
            self.assertEqual(actual['command'], ['systemctl', name])

    def test_failed_helper_is_reported_and_stderr_is_retained(self):
        source = (ROOT / 'config/shoji-shell/HomeSystemCard.qml').read_text()
        handler = re.search(r'onExited: exitCode => \{([^\n]+)\}', source).group(1)
        actual = js('const root={error:"peer refused"}; const exitCode=1;'+handler+'; console.log(JSON.stringify(root));')
        self.assertEqual(actual['error'], 'peer refused')
