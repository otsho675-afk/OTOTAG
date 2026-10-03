import runpy
from pathlib import Path

module = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'scripts/audit_sql_dump.py'))
parse = module['rows']
assert list(parse(r"(1, 'a,b; c', NULL),(2, 'it\'s', 'line\ntext')")) == [
    ['1', 'a,b; c', None], ['2', "it's", 'line\ntext']]
assert list(parse("('double''quote', 'Türkçe')")) == [["double'quote", 'Türkçe']]
print('SQL tuple parser fixtures passed')
