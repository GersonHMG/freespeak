# Licensing

This package vendors **eSpeak-NG**, which is licensed under the **GNU General
Public License v3**. The full text is at
`third_party/espeak-ng/COPYING`; parts of the tree carry Apache-2.0, BSD-2 and
the Unicode licence instead, in the adjacent `COPYING.*` files.

Linking eSpeak-NG into an application brings that application under the GPL
v3. This was a deliberate decision for lingo_node, not an oversight: eSpeak-NG
is the app's only G2P, the phonemes it shows and scores pronunciation against,
and no permissively-licensed replacement covers every word the same way.

The Dart FFI wrapper in `lib/espeak_ng.dart` is adapted from
[flutter_kokoro_tts](https://github.com/ikeoffiah/kokoro_tts) (MIT, Pius
Ikeoffiah); that licence is kept as `LICENSE.flutter_kokoro_tts`. The Android
CMake setup and `config.h` come from the same package.

`assets/espeak_ng_data.zip` is eSpeak-NG's own data, also GPL v3. It has been
trimmed to what English needs — the `phon*` tables, `intonations`, `en_dict`
and the `lang/gmw/en*` voice definitions — which takes it from 9.2 MB to
0.5 MB. The untrimmed original (eSpeak-NG 1.52.0's `espeak-ng-data`) is not
in the repository.
