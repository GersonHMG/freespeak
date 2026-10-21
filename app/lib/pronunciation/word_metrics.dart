// Edit distance, the one primitive the whole scorer is built on.
//
// The React Native app carried two identical copies of this (word-alignment.ts
// and score-system.ts); there is only ever one here. It keeps two rows instead
// of the full matrix — same result as the ported version, a fraction of the
// allocation.
//
// [alignRunes] is its sibling: the same recurrence, but keeping the whole
// matrix so the *path* can be recovered and not just its length. The scorer
// needs the path to say which reference word each edit belongs to; two rows
// cannot answer that, which is the only reason both exist.
//
// Nothing in lib/ calls [editDistance] any more — [alignRunes] answers every
// question the pipeline actually asks. It is kept as the independent scalar
// reference the path is checked against: the tests assert that counting
// [alignRunes]' non-match steps gives the same number this returns, which is
// only worth asserting while the two are separate implementations. Deleting
// it would leave that agreement untested and the path checked only against
// itself.

/// Levenshtein distance between two strings, counted over runes.
///
/// Runes rather than UTF-16 code units because both operands are IPA, where a
/// single phoneme can sit outside the BMP. Splitting one in half would count
/// one substitution as two.
int editDistance(String a, String b) {
  final s1 = a.runes.toList(growable: false);
  final s2 = b.runes.toList(growable: false);
  final n = s1.length;
  final m = s2.length;

  if (n == 0) return m;
  if (m == 0) return n;

  var previous = List<int>.generate(m + 1, (j) => j, growable: false);
  final current = List<int>.filled(m + 1, 0);

  for (var i = 1; i <= n; i++) {
    current[0] = i;
    for (var j = 1; j <= m; j++) {
      final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      final substitution = previous[j - 1] + cost;
      current[j] = deletion < insertion ? deletion : insertion;
      if (substitution < current[j]) current[j] = substitution;
    }
    previous = List<int>.of(current, growable: false);
  }
  return previous[m];
}

/// What one step of an edit path did.
enum EditOp {
  /// Both sides had the same rune. Costs nothing.
  match,

  /// Both sides had a rune, and they differed.
  substitute,

  /// `a` had a rune that `b` did not — a sound in the reference that was not
  /// said.
  delete,

  /// `b` had a rune that `a` did not — a sound said that the reference does
  /// not contain.
  insert,
}

/// One step of an edit path: which op, and the runes it consumed.
class EditStep {
  const EditStep({
    required this.op,
    required this.aIndex,
    required this.bIndex,
  });

  final EditOp op;

  /// Rune index into `a`, or -1 for [EditOp.insert], which consumes no `a`.
  final int aIndex;

  /// Rune index into `b`, or -1 for [EditOp.delete], which consumes no `b`.
  final int bIndex;

  @override
  String toString() => '${op.name}(a:$aIndex, b:$bIndex)';
}

/// The cheapest edit path turning `a` into `b`, in forward order.
///
/// Same recurrence and same rune-wise costing as [editDistance] — the number
/// of non-[EditOp.match] steps returned here equals what that would return —
/// but the full matrix is kept so the path can be walked afterwards. Steps
/// consume `a` strictly in order, so a caller tracking its own cursor into `a`
/// always knows where in the reference an [EditOp.insert] landed.
///
/// [freeEndGaps] makes runes of `b` before the first and after the last
/// alignment cost nothing, which is what the scorer wants: a learner who says
/// the phrase and then breathes, or whose recognizer prepends a stray word,
/// should not be charged for audio that sits outside the reference at all.
/// Those free runes are simply absent from the returned path — they belong to
/// no part of `a`, so there is nothing meaningful to report about them.
/// Reference runes are never free either way: a sound that was in the phrase
/// and did not get said is exactly the error being measured.
List<EditStep> alignRunes(String a, String b, {bool freeEndGaps = false}) {
  final s1 = a.runes.toList(growable: false);
  final s2 = b.runes.toList(growable: false);
  final n = s1.length;
  final m = s2.length;

  final cost = List.generate(
    n + 1,
    (_) => List<int>.filled(m + 1, 0),
    growable: false,
  );
  for (var j = 1; j <= m; j++) {
    cost[0][j] = freeEndGaps ? 0 : j;
  }
  for (var i = 1; i <= n; i++) {
    cost[i][0] = i;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final substitution =
          cost[i - 1][j - 1] + (s1[i - 1] == s2[j - 1] ? 0 : 1);
      final deletion = cost[i - 1][j] + 1;
      final insertion = cost[i][j - 1] + 1;
      var best = deletion < insertion ? deletion : insertion;
      if (substitution < best) best = substitution;
      cost[i][j] = best;
    }
  }

  // With free end gaps the path may finish anywhere in the last row, since
  // whatever is left of `b` past that point costs nothing to drop. Ties take
  // the largest column: same price either way, and consuming `b` as real
  // alignment tells the caller more than discarding it does.
  var endJ = 0;
  if (freeEndGaps) {
    for (var j = 1; j <= m; j++) {
      if (cost[n][j] <= cost[n][endJ]) endJ = j;
    }
  } else {
    endJ = m;
  }

  final steps = <EditStep>[];
  var i = n;
  var j = endJ;
  while (i > 0 || j > 0) {
    // Everything left of here is the free leading gap — outside `a` entirely.
    if (i == 0 && freeEndGaps) break;

    if (i > 0 && j > 0) {
      final same = s1[i - 1] == s2[j - 1];
      if (cost[i][j] == cost[i - 1][j - 1] + (same ? 0 : 1)) {
        steps.add(
          EditStep(
            op: same ? EditOp.match : EditOp.substitute,
            aIndex: i - 1,
            bIndex: j - 1,
          ),
        );
        i--;
        j--;
        continue;
      }
    }
    if (i > 0 && cost[i][j] == cost[i - 1][j] + 1) {
      steps.add(EditStep(op: EditOp.delete, aIndex: i - 1, bIndex: -1));
      i--;
      continue;
    }
    steps.add(EditStep(op: EditOp.insert, aIndex: -1, bIndex: j - 1));
    j--;
  }

  return steps.reversed.toList(growable: false);
}
