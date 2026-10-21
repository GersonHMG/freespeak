import 'package:flutter/material.dart';

import '../decks/deck_models.dart';
import '../decks/deck_store_scope.dart';
import '../theme/lingo_theme.dart';
import '../widgets/deck_look.dart';
import '../widgets/deck_tile.dart';
import '../widgets/mode_badge.dart';
import 'decks_screen.dart';
import 'recall_review_screen.dart';
import 'session_loading_screen.dart';

/// What the picked deck is for.
enum DeckPurpose {
  /// A Recall sitting over the deck's due cards.
  recall,

  /// A pronunciation session reading the deck's English sentences aloud.
  pronunciation,
}

/// The step between a game mode and playing it: choose the deck. The
/// learner's own decks come first, with a "Create a deck" row while they
/// hold no cards yet; the app's bundled decks sit behind one "Premade
/// decks" row ([PremadeDecksScreen]). Pronunciation also offers the
/// built-in everyday sentences, so it works with no deck at all.
class DeckPickerScreen extends StatelessWidget {
  const DeckPickerScreen({required this.purpose, super.key});

  final DeckPurpose purpose;

  @override
  Widget build(BuildContext context) {
    return _PickerScaffold(
      purpose: purpose,
      builder: (context, summaries) {
        final own = [
          for (final summary in summaries)
            if (summary.deck.isEditable) summary,
        ];
        final premade = [
          for (final summary in summaries)
            if (!summary.deck.isEditable) summary,
        ];
        final ownCards = own.fold(0, (sum, s) => sum + s.cardCount);
        return [
          _title('Choose a deck'),
          if (purpose == DeckPurpose.pronunciation)
            _EverydayTile(
              onTap: () => _open(context, const SessionLoadingScreen()),
            ),
          const _Section('YOUR DECKS'),
          for (final summary in own) _PickerDeckTile(summary, purpose),
          if (ownCards == 0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                'Cards you write yourself stick best. Add the words you '
                'actually need.',
                style: lingoFont(
                  size: 13,
                  weight: FontWeight.w500,
                  color: LingoColors.mutedInk,
                ),
              ),
            ),
            _CreateDeckTile(onTap: () => createDeckAndOpen(context)),
          ],
          if (premade.isNotEmpty) ...[
            const _Section('FROM THE APP'),
            _PremadeTile(
              decks: premade,
              purpose: purpose,
              onTap: () => _open(context, PremadeDecksScreen(purpose: purpose)),
            ),
          ],
        ];
      },
    );
  }
}

/// The app's bundled decks, one tile each -- what "Premade decks" in
/// [DeckPickerScreen] opens.
class PremadeDecksScreen extends StatelessWidget {
  const PremadeDecksScreen({required this.purpose, super.key});

  final DeckPurpose purpose;

  @override
  Widget build(BuildContext context) {
    return _PickerScaffold(
      purpose: purpose,
      builder: (context, summaries) => [
        _title('Premade decks'),
        for (final summary in summaries)
          if (!summary.deck.isEditable) _PickerDeckTile(summary, purpose),
      ],
    );
  }
}

/// Both picker screens' frame: the mode badge, and a list rebuilt from the
/// deck summaries whenever the decks change.
class _PickerScaffold extends StatelessWidget {
  const _PickerScaffold({required this.purpose, required this.builder});

  final DeckPurpose purpose;
  final List<Widget> Function(BuildContext, List<DeckSummary>) builder;

  @override
  Widget build(BuildContext context) {
    final decks = DeckStoreScope.of(context);
    return Scaffold(
      backgroundColor: LingoColors.background,
      appBar: AppBar(
        backgroundColor: LingoColors.background,
        elevation: 0,
        centerTitle: true,
        title: ModeBadge(
          label: switch (purpose) {
            DeckPurpose.recall => 'RECALL',
            DeckPurpose.pronunciation => 'PRONUNCIATION',
          },
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: decks.changes,
          builder: (context, _) => FutureBuilder<List<DeckSummary>>(
            future: decks.deckSummaries(),
            builder: (context, snapshot) {
              final summaries = snapshot.data;
              if (summaries == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                padding: const EdgeInsets.all(24),
                children: builder(context, summaries),
              );
            },
          ),
        ),
      ),
    );
  }
}

Widget _title(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: Text(text, style: lingoFont(size: 24, weight: FontWeight.w800)),
);

void _open(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

/// One deck, with what it has to offer for [purpose]; an empty deck is
/// dimmed and untappable.
class _PickerDeckTile extends StatelessWidget {
  const _PickerDeckTile(this.summary, this.purpose);

  final DeckSummary summary;
  final DeckPurpose purpose;

  @override
  Widget build(BuildContext context) {
    return DeckTile(
      deck: summary.deck,
      subtitle: _subtitle(),
      trailing: DeckProgressRing(percent: summary.progressPercent),
      onTap: summary.cardCount == 0
          ? null
          : () => _open(context, _destination()),
    );
  }

  String _subtitle() => switch (purpose) {
    _ when summary.cardCount == 0 => 'No cards yet',
    DeckPurpose.recall =>
      summary.dueCount == 0
          ? 'All caught up · ${cardCount(summary.cardCount)}'
          : '${summary.dueCount} due · ${cardCount(summary.cardCount)}',
    DeckPurpose.pronunciation => cardCount(summary.cardCount),
  };

  Widget _destination() => switch (purpose) {
    DeckPurpose.recall => RecallReviewScreen(deckId: summary.deck.id),
    DeckPurpose.pronunciation => SessionLoadingScreen(deckId: summary.deck.id),
  };
}

/// A small-caps heading over a group of tiles.
class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        text,
        style: lingoFont(
          size: 11,
          weight: FontWeight.w700,
          color: LingoColors.mutedInk,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// The one row standing for every bundled deck: the first few decks'
/// icons fanned out, how many there are, and (for Recall) what's due
/// across them.
class _PremadeTile extends StatelessWidget {
  const _PremadeTile({
    required this.decks,
    required this.purpose,
    required this.onTap,
  });

  final List<DeckSummary> decks;
  final DeckPurpose purpose;
  final VoidCallback onTap;

  static const double _icon = 36;
  static const double _step = 8;

  @override
  Widget build(BuildContext context) {
    final fanned = decks.take(3).toList();
    final due = decks.fold(0, (sum, s) => sum + s.dueCount);
    final count = '${decks.length} ${decks.length == 1 ? 'deck' : 'decks'}';
    final subtitle = switch (purpose) {
      DeckPurpose.recall =>
        due == 0 ? '$count · All caught up' : '$count · $due due',
      DeckPurpose.pronunciation => count,
    };
    return _ActionTile(
      color: LingoColors.indigoContainer,
      leading: SizedBox(
        width: _icon + 4 + _step * 2,
        height: _icon + 4 + _step,
        child: Stack(
          children: [
            for (var i = 0; i < fanned.length; i++)
              Positioned(
                left: i * _step,
                top: (fanned.length - 1 - i) * _step / 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: LingoColors.indigoContainer,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(_icon * 0.28 + 2),
                  ),
                  child: DeckIconTile.of(fanned[i].deck, size: _icon),
                ),
              ),
          ],
        ),
      ),
      title: 'Premade decks',
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}

/// "Create a deck", shown while the learner's own decks are empty: a
/// dashed outline rather than a filled card, so it reads as a slot to fill.
class _CreateDeckTile extends StatelessWidget {
  const _CreateDeckTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CustomPaint(
        foregroundPainter: _DashedBorder(color: LingoColors.navInactive),
        child: _ActionTile(
          color: Colors.transparent,
          bottomGap: 0,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: LingoColors.indigo,
              borderRadius: BorderRadius.circular(40 * 0.28),
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
          ),
          title: 'Create a deck',
          subtitle: 'Add your own words and sentences',
          onTap: onTap,
        ),
      ),
    );
  }
}

/// A rounded row: [leading], a title over a subtitle, and a chevron -- the
/// same shape as [DeckTile], for rows that aren't one deck.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.color,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.bottomGap = 10,
  });

  final Color color;
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
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
                Icon(
                  Icons.chevron_right_rounded,
                  color: LingoColors.navInactive,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed rounded-rectangle outline around the whole child.
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
          const Radius.circular(18),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// Pronunciation's deck-free option: the app's own everyday sentences.
class _EverydayTile extends StatelessWidget {
  const _EverydayTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: LingoColors.indigoContainer,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  Icons.record_voice_over_rounded,
                  color: LingoColors.indigo,
                  size: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Everyday sentences',
                        style: lingoFont(size: 16, weight: FontWeight.w700),
                      ),
                      Text(
                        'A fresh mix every session',
                        style: lingoFont(
                          size: 12,
                          weight: FontWeight.w500,
                          color: LingoColors.mutedInk,
                        ),
                      ),
                    ],
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
    );
  }
}
