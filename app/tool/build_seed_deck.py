"""Builds the bundled Spanish -> English seed deck from Tatoeba.

Writes assets/decks/tatoeba_es_en.json: 100 notes, each a Spanish sentence
with every linked English translation that passes the filters below as its
reference translations (examples, not an answer key -- see the design doc).

Run from the project root:

  python tool/build_seed_deck.py

The Tatoeba exports (about 33 MB compressed) are downloaded once into
build/tatoeba/ and reused on later runs; pass --refresh to fetch them again.
The pick is seeded, so the same exports always give the same deck.

Filters, per English translation:
  * 3 to 8 words;
  * every word is in the bundled Vosk model's vocabulary -- a word Vosk can
    never output can never be heard clearly, whatever the learner does;
  * no names: a capitalised word after the first, or a first word from a
    list of the names Tatoeba uses most.
A Spanish sentence is kept if it has 2 to 12 words, no names by the same
rule, and at least one English translation passed. Primary English
references are unique across the deck.

Sentences with more English translations are preferred: on Tatoeba those
are the everyday ones many people translated. The final 100 are spread
evenly over English lengths 3 to 8.

Tatoeba content is CC BY 2.0 FR; the JSON carries the attribution and every
sentence id, so each note links back to its source.
"""
import argparse
import bz2
import collections
import csv
import datetime
import io
import json
import pathlib
import random
import re
import struct
import sys
import urllib.request
import zipfile

EXPORTS = 'https://downloads.tatoeba.org/exports/per_language'
FILES = {
    'spa': 'spa/spa_sentences.tsv.bz2',
    'eng': 'eng/eng_sentences.tsv.bz2',
    'links': 'spa/spa-eng_links.tsv.bz2',
}
VOSK_ZIP = 'assets/models/vosk/vosk-model-small-en-us-0.15.zip'
VOSK_GRAPH = 'vosk-model-small-en-us-0.15/graph/Gr.fst'

MIN_EN_WORDS, MAX_EN_WORDS = 3, 8
MIN_ES_WORDS, MAX_ES_WORDS = 2, 12
MAX_REFERENCES = 4
POOL_SIZE = 3000  # most-translated candidates the pick is drawn from

# The names Tatoeba's example sentences lean on, which the capitalisation
# rule cannot catch when they open a sentence.
NAMES = {
    'tom', 'mary', 'john', 'alice', 'jack', 'bob', 'bill', 'mike', 'ken',
    'jim', 'tony', 'lucy', 'emily', 'linda', 'dan', 'sami', 'layla', 'ziri',
    'rima', 'yanni', 'skura', 'taninna', 'mennad', 'baya', 'maria', 'juan',
    'pedro', 'pablo', 'carlos', 'ana', 'boston', 'london', 'paris', 'tokyo',
    'japan', 'america', 'spain', 'mexico', 'france', 'english', 'spanish',
}

EN_WORD = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)*")
ES_WORD = re.compile(r"[^\W\d_]+", re.UNICODE)


def download(data_dir, refresh):
    data_dir.mkdir(parents=True, exist_ok=True)
    paths = {}
    for key, rel in FILES.items():
        path = data_dir / pathlib.PurePosixPath(rel).name
        if refresh or not path.exists():
            url = f'{EXPORTS}/{rel}'
            print(f'downloading {url}', file=sys.stderr)
            urllib.request.urlretrieve(url, path)
        paths[key] = path
    return paths


def read_tsv(path):
    with bz2.open(path, 'rt', encoding='utf-8', newline='') as f:
        yield from csv.reader(f, delimiter='\t', quoting=csv.QUOTE_NONE)


def vosk_vocabulary():
    """The word list embedded in the model's Gr.fst, lower-cased.

    Gr.fst is an OpenFst binary whose header carries its symbol table:
    magic, name, available key, count, then (string, int64 key) pairs, each
    string an int32 length and its bytes.
    """
    with zipfile.ZipFile(VOSK_ZIP) as z:
        data = z.read(VOSK_GRAPH)
    at = data.find(struct.pack('<i', 2125658996))  # symbol-table magic
    if at < 0:
        sys.exit('no symbol table in Gr.fst')
    at += 4

    def string():
        nonlocal at
        (length,) = struct.unpack_from('<i', data, at)
        at += 4
        value = data[at:at + length].decode('utf-8')
        at += length
        return value

    string()  # table name
    _available, count = struct.unpack_from('<qq', data, at)
    at += 16
    words = set()
    for _ in range(count):
        words.add(string().lower())
        at += 8  # key
    return words


def en_words(text):
    return EN_WORD.findall(text)


def es_words(text):
    return ES_WORD.findall(text)


def has_name(words, keep_first):
    """A capitalised word after the first, or a known name anywhere."""
    for i, word in enumerate(words):
        if word.lower() in NAMES:
            return True
        if i > 0 and word[0].isupper() and not keep_first(word):
            return True
    return False


def english_ok(text, vocab):
    words = en_words(text)
    if not MIN_EN_WORDS <= len(words) <= MAX_EN_WORDS:
        return False
    # "I", "I'm", "I'll" are capitalised anywhere and are not names.
    if has_name(words, keep_first=lambda w: w == 'I' or w.startswith("I'")):
        return False
    return all(w.lower() in vocab for w in words)


def spanish_ok(text):
    words = es_words(text)
    if not MIN_ES_WORDS <= len(words) <= MAX_ES_WORDS:
        return False
    return not has_name(words, keep_first=lambda w: False)


def build(paths, count, seed):
    vocab = vosk_vocabulary()
    print(f'vosk vocabulary: {len(vocab)} words', file=sys.stderr)

    links = collections.defaultdict(set)
    for row in read_tsv(paths['links']):
        links[row[0]].add(row[1])
    wanted_en = set().union(*links.values())

    spanish = {
        row[0]: row[2]
        for row in read_tsv(paths['spa'])
        if row[0] in links and spanish_ok(row[2])
    }
    english = {
        row[0]: row[2]
        for row in read_tsv(paths['eng'])
        if row[0] in wanted_en and english_ok(row[2], vocab)
    }

    candidates = []
    for es_id, es_text in spanish.items():
        refs = sorted(
            {english[en_id]: en_id for en_id in links[es_id] if en_id in english}.items(),
            # Shortest first: the primary is the plainest wording.
            key=lambda item: (len(en_words(item[0])), item[0]),
        )
        if refs:
            candidates.append((es_id, es_text, refs[:MAX_REFERENCES], len(refs)))
    print(f'candidates: {len(candidates)}', file=sys.stderr)

    # Most-translated first; sentence id breaks ties so the order is stable.
    candidates.sort(key=lambda c: (-c[3], int(c[0])))

    seen_primary = set()
    by_length = collections.defaultdict(list)
    for es_id, es_text, refs, _ in candidates:
        primary = refs[0][0].lower()
        if primary in seen_primary:
            continue
        seen_primary.add(primary)
        by_length[len(en_words(refs[0][0]))].append((es_id, es_text, refs))
        if sum(map(len, by_length.values())) >= POOL_SIZE:
            break

    rng = random.Random(seed)
    lengths = list(range(MIN_EN_WORDS, MAX_EN_WORDS + 1))
    for length in lengths:
        rng.shuffle(by_length[length])
    picked = []
    # Round-robin over lengths so the deck is spread evenly across them,
    # topping up from the others if one length runs short.
    while len(picked) < count and any(by_length[n] for n in lengths):
        for length in lengths:
            if by_length[length] and len(picked) < count:
                picked.append(by_length[length].pop())
    if len(picked) < count:
        sys.exit(f'only {len(picked)} notes passed the filters')

    picked.sort(key=lambda p: (len(en_words(p[2][0][0])), int(p[0])))
    return {
        'name': 'Spanish starter',
        'source': 'tatoeba',
        'native_lang': 'es',
        'target_lang': 'en',
        'license': 'CC BY 2.0 FR',
        'attribution': 'Sentences from Tatoeba (https://tatoeba.org), '
        'CC BY 2.0 FR. Each note links to its source sentence.',
        'built_at': datetime.date.today().isoformat(),
        'notes': [
            {
                'source_ref': es_id,
                'native': es_text,
                'references': [text for text, _ in refs],
                'reference_refs': [en_id for _, en_id in refs],
            }
            for es_id, es_text, refs in picked
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--data-dir', default='build/tatoeba', type=pathlib.Path)
    parser.add_argument(
        '--out', default='assets/decks/tatoeba_es_en.json', type=pathlib.Path
    )
    parser.add_argument('--count', default=100, type=int)
    parser.add_argument('--seed', default=7, type=int)
    parser.add_argument('--refresh', action='store_true')
    args = parser.parse_args()

    deck = build(download(args.data_dir, args.refresh), args.count, args.seed)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with io.open(args.out, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(deck, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(f'wrote {len(deck["notes"])} notes to {args.out}', file=sys.stderr)


if __name__ == '__main__':
    main()
