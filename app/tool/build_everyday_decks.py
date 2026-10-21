"""Builds the bundled everyday-use decks, one per deck per native language.

The English side of each deck is assets/sentences/everyday_<deck>_en.csv
(id, pattern_no, pattern, sentence, starter_pattern); its translation into a
native language is assets/sentences/everyday_<deck>_<code>.tsv (id, text),
row for row. Each pair becomes assets/decks/everyday_<deck>_<code>_en.json in
the seed-deck format lib/decks/seed_deck.dart reads: the native sentence is
the prompt, the English one the reference.

Run from the project root:

  python tool/build_everyday_decks.py             # every deck and language
  python tool/build_everyday_decks.py --lang fr   # just one language

lib/decks/seed_deck.dart's kStarterDeckAssets lists the decks in the same
order as DECKS below; keep the two in step.
"""
import argparse
import csv
import io
import json
import pathlib
import sys

SENTENCES = pathlib.Path('assets/sentences')
OUT = pathlib.Path('assets/decks')

# (file name part, deck name), in the order the app lists them.
DECKS = [
    ('common_phrases', 'Common phrases'),
    ('travel_survival', 'Travel & survival'),
    ('food_ordering', 'Food & ordering'),
    ('work_meetings', 'Work & meetings'),
    ('phrasal_verbs', 'Phrasal verbs'),
    ('idioms_fillers', 'Idioms & fillers'),
]
LANGS = ['es', 'pt', 'fr', 'zh', 'hi', 'ar']


def read_english(slug):
    path = SENTENCES / f'everyday_{slug}_en.csv'
    with io.open(path, encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def read_native(slug, code):
    path = SENTENCES / f'everyday_{slug}_{code}.tsv'
    with io.open(path, encoding='utf-8') as f:
        rows = list(csv.reader(f, delimiter='\t', quoting=csv.QUOTE_NONE))
    if rows[0] != ['id', 'text']:
        sys.exit(f'{path}: header {rows[0]}, expected id, text')
    return {row[0]: row[1].strip() for row in rows[1:]}


def build(slug, name, code):
    english = read_english(slug)
    native = read_native(slug, code)
    if set(native) != {row['id'] for row in english}:
        sys.exit(f'{slug}/{code}: ids differ from the English file')
    notes = []
    for row in english:
        note = {
            'source_ref': row['id'],
            'pattern': row['pattern'],
            'native': native[row['id']],
            'references': [row['sentence']],
        }
        if row['starter_pattern']:
            note['starter_pattern'] = row['starter_pattern']
        notes.append(note)
    return {
        'name': name,
        'source': 'starter',
        'native_lang': code,
        'target_lang': 'en',
        'notes': notes,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--lang', choices=LANGS)
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    for code in [args.lang] if args.lang else LANGS:
        for slug, name in DECKS:
            deck = build(slug, name, code)
            out = OUT / f'everyday_{slug}_{code}_en.json'
            with io.open(out, 'w', encoding='utf-8', newline='\n') as f:
                json.dump(deck, f, ensure_ascii=False, indent=2)
                f.write('\n')
            print(f'wrote {len(deck["notes"])} notes to {out}', file=sys.stderr)


if __name__ == '__main__':
    main()
