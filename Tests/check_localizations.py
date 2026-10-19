"""Verify translation coverage and formatting without reading clipboard history."""
import json
import re
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'Pasteback'
translations = json.loads((root / 'Resources/Localizations.json').read_text())
expected = {'en', 'zh-Hans', 'ja', 'fr', 'de', 'ko'}
for key, variants in translations.items():
    assert set(variants) == expected, key
    assert all(isinstance(value, str) and value.strip() for value in variants.values()), key
    formats = [re.findall(r'%(?:d|@)', value) for value in variants.values()]
    assert all(value == formats[0] for value in formats), key
for source in root.rglob('*.swift'):
    for literal in re.findall(r'tr(?:Format)?\(("(?:[^"\\]|\\.)*")', source.read_text()):
        key = json.loads(literal)
        assert key in translations, (source.name, key)
print(f'PASS: {len(translations)} strings × {len(expected)} languages; all referenced keys and format placeholders covered.')
