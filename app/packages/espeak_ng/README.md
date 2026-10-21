# espeak_ng

eSpeak-NG reduced to a phonemizer: a word in, IPA out. No audio synthesis, no
model, no platform channel.

```dart
final espeak = Espeak()..initialize(dataPath: dir);
espeak.phonemize('thirty little water bottles'); // θˈɜːɾi lˈɪtəl ...
espeak.dispose();
```

`dataPath` is a real directory — eSpeak opens its data by path, so a Flutter
asset is not enough. The app unpacks `assets/espeak_ng_data.zip` itself; see
`lib/tts/espeak_data.dart` in lingo_node.

That zip carries English only (0.5 MB, down from 9.2 MB). To add a language,
rebuild it from eSpeak-NG 1.52.0's full `espeak-ng-data` keeping that
language's `*_dict` and `lang/**` entries alongside the shared `phon*` tables.
A copy of the untrimmed data may sit locally as
`assets/espeak_ng_data_full.zip.bak`; it is git-ignored.

## Why this exists

`flutter_kokoro_tts` has the same native build, but keeps it behind `lib/src/`
and exposes only a whole TTS pipeline whose `generate()` returns bare audio —
no phonemes, no token durations. lingo_node needs both: durations drive the
word timings, per-word clips and the pronunciation scorer. So the phonemizer
half is lifted out and the ONNX half left behind, which also drops a second
copy of ONNX Runtime from the build.

## Platforms

Android and iOS only. `espeakIsSupported` is false everywhere else, including
the test host — callers fall back to another phonemizer rather than meeting a
missing symbol.

## Licence

GPL v3, inherited from eSpeak-NG. See [LICENSE.md](LICENSE.md) — it affects
the whole application.
