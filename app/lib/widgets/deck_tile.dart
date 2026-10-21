import 'package:flutter/material.dart';

import '../decks/deck_models.dart';
import '../theme/lingo_theme.dart';
import 'deck_look.dart';

/// One deck in a list: its icon tile ([DeckIconTile]), its name, a line of
/// [subtitle], and [trailing] -- by default a lock on decks the learner
/// cannot edit (the bundled starter decks). [onTap] null draws it dimmed and
/// untappable.
class DeckTile extends StatelessWidget {
  const DeckTile({
    required this.deck,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    super.key,
  });

  final Deck deck;
  final String subtitle;
  final VoidCallback? onTap;

  /// Shown before the chevron in place of the lock.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Material(
          color: LingoColors.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  DeckIconTile.of(deck),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deck.name,
                          style: lingoFont(size: 16, weight: FontWeight.w700),
                        ),
                        Text(
                          subtitle,
                          style: lingoFont(
                            size: 12,
                            weight: FontWeight.w500,
                            color: LingoColors.mutedInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, right: 4),
                      child: trailing,
                    )
                  else if (!deck.isEditable)
                    Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: LingoColors.navInactive,
                      ),
                    ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: LingoColors.navInactive,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String cardCount(int n) => '$n ${n == 1 ? 'card' : 'cards'}';

/// A deck's progress as a ring: [percent] of the cards shown so far whose
/// last grade was Perfect, or a dash before any card has been shown.
class DeckProgressRing extends StatelessWidget {
  const DeckProgressRing({required this.percent, super.key});

  final int? percent;

  @override
  Widget build(BuildContext context) {
    final value = percent;
    return Semantics(
      label: value == null ? 'Not started' : '$value% perfect',
      excludeSemantics: true,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: (value ?? 0) / 100,
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
                backgroundColor: LingoColors.indigoContainer,
                color: LingoColors.indigo,
              ),
            ),
            Text(
              value == null ? '–' : '$value%',
              style: lingoFont(
                size: value == 100 ? 10 : 11,
                weight: FontWeight.w700,
                color: value == null ? LingoColors.mutedInk : LingoColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
