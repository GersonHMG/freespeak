import 'package:flutter/material.dart';

import '../decks/deck_models.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';
import '../theme/lingo_theme.dart';

/// What a card review screen shows once there is nothing left to show this
/// time: a round of the daily sitting or a custom session is done, or the
/// daily sitting has been through every card in the deck, or the deck has no
/// cards at all, when [reviewed] is 0.
///
/// A finished session shows how it went: the share of the cards shown that
/// were graded Perfect against those graded Wrong or Partial -- out of the
/// cards actually shown, a card shown twice counted twice, not out of the
/// deck.
class ReviewDoneView extends StatelessWidget {
  const ReviewDoneView({
    required this.reviewed,
    this.grades = const {},
    this.isCustom = false,
    this.hasMore = false,
    this.onKeepGoing,
    super.key,
  });

  final int reviewed;

  /// This session's grades, by kind.
  final Map<Grade, int> grades;

  /// A custom session: "Session complete" whatever is left in the deck,
  /// since the learner picked what it held.
  final bool isCustom;

  /// The daily sitting has more cards: offer [onKeepGoing]. Without more,
  /// the deck has been through the whole sitting: "All done".
  final bool hasMore;
  final VoidCallback? onKeepGoing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (reviewed == 0) {
      return _centered(context, [
        Text(
          'No cards here yet',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add some cards to this deck to study it.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        _backButton(context, filled: true),
      ]);
    }

    final deckDone = !isCustom && !hasMore;
    final perfect = grades[Grade.easy] ?? 0;
    final perfectPercent = (100 * perfect / reviewed).round();
    final keepGoing = !isCustom && hasMore ? onKeepGoing : null;
    return _centered(context, [
      Text(
        deckDone ? 'All done' : 'Session complete',
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        deckDone
            ? "You've been through every card in this deck "
                  '($reviewed reviewed).'
            : '$reviewed ${reviewed == 1 ? 'card' : 'cards'} reviewed.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 28),
      _ResultSplit(
        perfect: perfect,
        notPerfect: reviewed - perfect,
        perfectPercent: perfectPercent,
      ),
      const SizedBox(height: 32),
      if (keepGoing != null) ...[
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: keepGoing,
            child: const Text('Keep going'),
          ),
        ),
        const SizedBox(height: 8),
        _backButton(context, filled: false),
      ] else
        _backButton(context, filled: true),
    ]);
  }

  Widget _centered(BuildContext context, List<Widget> children) => Center(
    child: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );

  Widget _backButton(BuildContext context, {required bool filled}) {
    void back() => Navigator.of(context).pop();
    return filled
        ? FilledButton(onPressed: back, child: const Text('Back'))
        : TextButton(onPressed: back, child: const Text('Back'));
  }
}

/// Perfect against Wrong or Partial: both percentages over a two-part bar,
/// with the card counts under them.
class _ResultSplit extends StatelessWidget {
  const _ResultSplit({
    required this.perfect,
    required this.notPerfect,
    required this.perfectPercent,
  });

  final int perfect;
  final int notPerfect;

  /// Rounded once, here, and the other share is the rest -- so the two
  /// always add up to 100.
  final int perfectPercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final good = colorForBand(theme, ScoreBand.green);
    final bad = colorForBand(theme, ScoreBand.red);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: lingoCardDecoration(radius: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Share(
                  percent: perfectPercent,
                  label: 'Perfect',
                  count: perfect,
                  color: good,
                  align: CrossAxisAlignment.start,
                ),
              ),
              Expanded(
                child: _Share(
                  percent: 100 - perfectPercent,
                  label: 'Wrong or partial',
                  count: notPerfect,
                  color: bad,
                  align: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  if (perfect > 0)
                    Expanded(
                      flex: perfect,
                      child: ColoredBox(color: good),
                    ),
                  if (perfect > 0 && notPerfect > 0) const SizedBox(width: 3),
                  if (notPerfect > 0)
                    Expanded(
                      flex: notPerfect,
                      child: ColoredBox(color: bad),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Share extends StatelessWidget {
  const _Share({
    required this.percent,
    required this.label,
    required this.count,
    required this.color,
    required this.align,
  });

  final int percent;
  final String label;
  final int count;
  final Color color;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          '$percent%',
          style: lingoFont(size: 30, weight: FontWeight.w800, color: color),
        ),
        Text(label, style: lingoFont(size: 13, weight: FontWeight.w700)),
        Text(
          '$count ${count == 1 ? 'card' : 'cards'}',
          style: lingoFont(
            size: 12,
            weight: FontWeight.w500,
            color: LingoColors.mutedInk,
          ),
        ),
      ],
    );
  }
}
