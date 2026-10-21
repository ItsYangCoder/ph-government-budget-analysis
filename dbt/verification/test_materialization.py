"""Offline control-flow checks; these do not simulate Databricks SQL execution."""
import unittest
from pathlib import Path
from types import SimpleNamespace
from jinja2 import Environment

ROOT = Path(__file__).resolve().parents[1]

class Returned(Exception):
    def __init__(self, value):
        self.value = value

class ScriptMaterializationTests(unittest.TestCase):
    def invoke(self, *, full_refresh=False, fail_step=None):
        events = []
        class Relation:
            def incorporate(self, **kwargs): return self
            def __str__(self): return 'catalog.schema.target'
        def statement(name, fetch_result=False, auto_begin=True, caller=None):
            if not fetch_result or auto_begin:
                raise AssertionError('Assertions must be fetched without a transaction')
            events.append((name, caller().strip()))
            if name == fail_step:
                raise RuntimeError('Simulated warehouse assertion failure')
            return ''
        def return_value(value): raise Returned(value)
        def compiler_error(message): raise ValueError(message)
        text = (ROOT / 'macros/materialization_script.sql').read_text()
        text = text.replace("{% materialization pondolens_script, adapter='databricks' %}", '{% macro execute_model() %}')
        text = text.replace('{% endmaterialization %}', '{% endmacro %}')
        env = Environment(extensions=['jinja2.ext.do'])
        ctx = dict(flags=SimpleNamespace(FULL_REFRESH=full_refresh), this=Relation(),
                   run_hooks=lambda *args, **kwargs: '', pre_hooks=[], post_hooks=[],
                   sql='SELECT 1\n-- pondolens:statement --\nSELECT ASSERT_TRUE(true)',
                   model=SimpleNamespace(name='sample'), log=lambda *args, **kwargs: '',
                   statement=statement, exceptions=SimpleNamespace(raise_compiler_error=compiler_error),
                   **{'return': return_value})
        try:
            env.from_string(text).make_module(ctx).execute_model()
        except Returned as result:
            self.assertIn('relations', result.value)
        return events

    def test_statements_are_sequential_and_fetched(self):
        events = self.invoke()
        self.assertEqual([name for name, _ in events], ['step_1', 'step_2', 'main'])
        self.assertEqual(events[0][1], 'SELECT 1')

    def test_failure_stops_before_main(self):
        with self.assertRaisesRegex(RuntimeError, 'assertion failure'):
            self.invoke(fail_step='step_2')

    def test_full_refresh_is_blocked_before_execution(self):
        with self.assertRaisesRegex(ValueError, 'Full refresh is disabled'):
            self.invoke(full_refresh=True)

if __name__ == '__main__':
    unittest.main()
