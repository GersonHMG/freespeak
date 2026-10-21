// Renders a phrase with the word currently being spoken highlighted, and —
// once an attempt has been scored — each word coloured by how well it was
// said.
//
// Word index comes from the model's own `durations` output, so the highlight
// follows the synthesised speech rather than an estimate based on word length.
//
// Every scored word is coloured, correct ones included: a run of green words
// is the feedback that a clean read earns, not just the absence of red or
// orange ones. Every word stays tappable after scoring too, not only the ones
// that need work — a correct word answers a tap the same way it did before
// scoring, and a phrase said perfectly should not go quiet just because there
// is nothing left to fix.
//
// The two markings coexist on purpose: the score is the lasting state and the
// highlight sweeps across it while the phrase plays, so the learner can hear
// the correct version of the word they got wrong without losing sight of which
// one that was.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../pronunciation/category.dart';
import '../pronunciation/phrase_tokens.dart';
import '../pronunciation/pronunciation_result.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';

class SpokenText extends StatefulWidget {
  const SpokenText({
    super.key,
    required this.text,
    required this.spokenWord,
    this.onWordTap,
    this.result,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final String text;

  /// Index into the whitespace-separated words of [text], or -1 for none.
  final int spokenWord;

  /// Tapping a word reports its ordinal among the phrase's words (whitespace
  /// tokens excluded) — the same indexing [spokenWord] and [result] use. Null
  /// makes the text non-interactive; otherwise every word answers a tap,
  /// scored or not, correct or not.
  final ValueChanged<int>? onWordTap;

  /// The last scored attempt at this phrase, or null before there is one.
  final PronunciationResult? result;

  final TextStyle? style;

  final TextAlign textAlign;

  @override
  State<SpokenText> createState() => _SpokenTextState();
}

class _SpokenTextState extends State<SpokenText> {
  // Recognizers hold resources and must outlive a build, so they are kept per
  // token and rebuilt only when the text itself changes. Null for a
  // whitespace-only token: there is no word there to tap, and no ordinal to
  // report for one.
  List<TapGestureRecognizer?> _recognizers = const [];
  List<PhraseToken> _tokens = const [];

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(SpokenText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _rebuild();
  }

  void _rebuild() {
    for (final r in _recognizers) {
      r?.dispose();
    }
    // Shared with the scorer, so "word 3" means the same thing to both and the
    // colouring lands on the word it was computed for.
    _tokens = tokenizePhrase(widget.text);

    // Ordinal among words only — the same indexing player.playWord and
    // PronunciationResult.words use. Reporting the raw token index here would
    // drift from that the moment a phrase has irregular whitespace, since the
    // token list (unlike the word list) counts the gaps too.
    var ordinal = 0;
    _recognizers = [
      for (final token in _tokens)
        if (!token.isWord)
          null
        else
          () {
            final word = ordinal++;
            return TapGestureRecognizer()
              ..onTap = () => widget.onWordTap?.call(word);
          }(),
    ];
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = widget.style ?? theme.textTheme.headlineSmall;
    final result = widget.result;

    // [spokenWord] counts words, ignoring whitespace-only tokens; the token
    // list does not. They coincide for ordinary single-spaced text, so this
    // only matters for a phrase with an odd space in it — but it is one line.
    final spokenToken = _tokenIndexForWord(widget.spokenWord);

    return RichText(
      textAlign: widget.textAlign,
      text: TextSpan(
        style: base,
        children: [
          for (var i = 0; i < _tokens.length; i++)
            TextSpan(
              text: _tokens[i].raw,
              recognizer: widget.onWordTap == null ? null : _recognizers[i],
              style: _styleFor(
                theme: theme,
                base: base,
                isSpoken: i == spokenToken,
                score: result?.wordAt(_tokens[i].index),
              ),
            ),
        ],
      ),
    );
  }

  int _tokenIndexForWord(int wordOrdinal) {
    if (wordOrdinal < 0) return -1;
    var seen = 0;
    for (final token in _tokens) {
      if (!token.isWord) continue;
      if (seen == wordOrdinal) return token.index;
      seen++;
    }
    return -1;
  }

  /// The score's colour underneath, the playback highlight on top.
  TextStyle? _styleFor({
    required ThemeData theme,
    required TextStyle? base,
    required bool isSpoken,
    required ScoredWord? score,
  }) {
    var style = base;

    if (score != null) {
      style = style?.copyWith(
        color: _colorFor(theme, score),
        fontWeight: score.needsWork ? FontWeight.w700 : null,
        // A word that was not said at all is marked as missing rather than as
        // merely wrong — it is a different mistake and needs a different fix.
        decoration: score.wasSkipped ? TextDecoration.underline : null,
        decorationStyle: TextDecorationStyle.dotted,
      );
    }

    if (isSpoken) {
      style = (style ?? base)?.copyWith(
        fontWeight: FontWeight.w700,
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      );
    }
    return style;
  }

  Color _colorFor(ThemeData theme, ScoredWord score) {
    if (score.wasSkipped) return theme.colorScheme.error;
    return colorForBand(theme, _bandFor(score.category));
  }

  ScoreBand _bandFor(PronunciationCategory category) => switch (category) {
    PronunciationCategory.good => ScoreBand.green,
    PronunciationCategory.mediocre => ScoreBand.orange,
    PronunciationCategory.bad => ScoreBand.red,
  };
}
