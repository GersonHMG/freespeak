import 'package:flutter/material.dart';

import '../decks/deck_models.dart';
import '../decks/deck_store_scope.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';
import '../theme/lingo_theme.dart';
import '../widgets/grade_buttons.dart';
import '../widgets/mode_badge.dart';

/// The cards behind the Progress tab's "Cards practised" numbers: every
/// card graded at least once, most recent first, each with its prompt, its
/// answer and how many times it got each grade. The chips narrow it to the
/// cards that were ever given one grade -- "Wrong" lists what went wrong,
/// most often first.
class PractisedCardsScreen extends StatefulWidget {
  const PractisedCardsScreen({this.grade, super.key});

  /// The grade to start filtered on; null for every card.
  final Grade? grade;

  @override
  State<PractisedCardsScreen> createState() => _PractisedCardsScreenState();
}

/// Each grade wears the grade buttons' colour.
Color gradeColor(ThemeData theme, Grade grade) =>
    colorForBand(theme, switch (grade) {
      Grade.difficult => ScoreBand.red,
      Grade.medium => ScoreBand.orange,
      Grade.easy => ScoreBand.green,
    });

class _PractisedCardsScreenState extends State<PractisedCardsScreen> {
  late Grade? _grade = widget.grade;
  late final Future<List<PractisedCard>> _cards = DeckStoreScope.of(context)
      .practisedCards();

  List<PractisedCard> _filtered(List<PractisedCard> cards) {
    final grade = _grade;
    if (grade == null) return cards;
    return [
      for (final card in cards)
        if (card.grades[grade]! > 0) card,
    ]..sort((a, b) => b.grades[grade]!.compareTo(a.grades[grade]!));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LingoColors.background,
      appBar: AppBar(
        backgroundColor: LingoColors.background,
        elevation: 0,
        centerTitle: true,
        title: const ModeBadge(label: 'CARDS PRACTISED'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<PractisedCard>>(
          future: _cards,
          builder: (context, snapshot) {
            final all = snapshot.data;
            if (all == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final cards = _filtered(all);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        count: all.length,
                        selected: _grade == null,
                        onTap: () => setState(() => _grade = null),
                      ),
                      for (final grade in Grade.values)
                        _FilterChip(
                          label: GradeButtons.labelFor(grade),
                          icon: GradeButtons.iconFor(grade),
                          color: gradeColor(Theme.of(context), grade),
                          count: all.where((c) => c.grades[grade]! > 0).length,
                          selected: _grade == grade,
                          onTap: () => setState(() => _grade = grade),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: cards.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              all.isEmpty
                                  ? 'No cards practised yet.'
                                  : 'No cards with this grade.',
                              textAlign: TextAlign.center,
                              style: lingoFont(
                                size: 15,
                                weight: FontWeight.w600,
                                color: LingoColors.mutedInk,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: cards.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) =>
                              _PractisedTile(card: cards[i]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? LingoColors.indigo;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? accent : LingoColors.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: selected ? Colors.white : accent),
                  const SizedBox(width: 4),
                ],
                Text(
                  '$label $count',
                  style: lingoFont(
                    size: 13,
                    weight: FontWeight.w700,
                    color: selected ? Colors.white : LingoColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One practised card: prompt, answer, and its grade tally, the last grade
/// marked by the stripe down its side.
class _PractisedTile extends StatelessWidget {
  const _PractisedTile({required this.card});

  final PractisedCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: lingoCardDecoration(radius: 18),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: gradeColor(theme, card.lastGrade)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.nativeText,
                      style: lingoFont(size: 16, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      card.reference,
                      style: lingoFont(
                        size: 14,
                        weight: FontWeight.w500,
                        color: LingoColors.mutedInk,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final grade in Grade.values)
                          if (card.grades[grade]! > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  GradeButtons.iconFor(grade),
                                  size: 15,
                                  color: gradeColor(theme, grade),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${card.grades[grade]} '
                                  '${GradeButtons.labelFor(grade)}',
                                  style: lingoFont(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    color: gradeColor(theme, grade),
                                  ),
                                ),
                              ],
                            ),
                        Text(
                          _when(card.lastPractised),
                          style: lingoFont(
                            size: 12,
                            weight: FontWeight.w500,
                            color: LingoColors.mutedInk,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "today", "yesterday", "5 days ago".
  static String _when(DateTime at) {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(at.year, at.month, at.day)).inDays;
    return switch (days) {
      <= 0 => 'today',
      1 => 'yesterday',
      _ => '$days days ago',
    };
  }
}
