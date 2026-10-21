// Puts the times Phonon reports for the words it read onto the app's own
// words for the same text.
//
// The two lists differ wherever Phonon's text normalization rewrote the text
// before reading it: "3" is read as "three", "9:30" as "nine thirty", "$5" as
// "five dollars". So the words are matched where they agree (letters and
// digits only, case ignored), and each run of words that do not agree takes
// the span of the run of spoken words between the same two anchors, shared
// out in proportion to their lengths.

/// The [start, end) span of each of [target]'s words, given [spoken] words
/// with spans, or null for a target word nothing could be attributed to.
List<(Duration, Duration)?> alignWordTimes(
  List<String> target,
  List<(String, Duration, Duration)> spoken,
) {
  final a = [for (final w in target) _key(w)];
  final b = [for (final (w, _, _) in spoken) _key(w)];

  // Longest common subsequence of equal, non-empty keys.
  final lcs = List.generate(
    a.length + 1,
    (_) => List<int>.filled(b.length + 1, 0),
  );
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = a[i].isNotEmpty && a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] > lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final anchors = <(int, int)>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i].isNotEmpty && a[i] == b[j]) {
      anchors.add((i, j));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }

  final out = List<(Duration, Duration)?>.filled(target.length, null);
  var prevI = -1, prevJ = -1;
  for (final (ai, aj) in [...anchors, (target.length, spoken.length)]) {
    _fillGap(target, spoken, out, prevI + 1, ai, prevJ + 1, aj);
    if (ai < target.length) {
      final (_, start, end) = spoken[aj];
      out[ai] = (start, end);
    }
    prevI = ai;
    prevJ = aj;
  }
  return out;
}

/// Target words `[i0, i1)` take spoken words `[j0, j1)`'s span, split by
/// length. With no spoken words between, they get nothing.
void _fillGap(
  List<String> target,
  List<(String, Duration, Duration)> spoken,
  List<(Duration, Duration)?> out,
  int i0,
  int i1,
  int j0,
  int j1,
) {
  if (i0 >= i1 || j0 >= j1) return;
  final start = spoken[j0].$2;
  final end = spoken[j1 - 1].$3;
  final lengths = [
    for (var i = i0; i < i1; i++)
      _key(target[i]).length.clamp(1, 1 << 30).toInt(),
  ];
  final total = lengths.fold(0, (s, n) => s + n);
  final span = (end - start).inMicroseconds;
  var at = start;
  var done = 0;
  for (var k = 0; k < lengths.length; k++) {
    done += lengths[k];
    final next = start + Duration(microseconds: span * done ~/ total);
    out[i0 + k] = (at, next);
    at = next;
  }
}

String _key(String word) =>
    word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
