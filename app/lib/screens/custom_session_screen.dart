import 'package:flutter/material.dart';

import '../decks/deck_models.dart';
import '../decks/deck_store_scope.dart';
import '../theme/lingo_theme.dart';
import '../widgets/mode_badge.dart';
import 'recall_review_screen.dart';

/// Sets up a custom Recall session: which cards (a random mix, the ones the
/// learner wrote, or the ones they last got Wrong or Partial) and how many.
///
/// Practice only: the session logs every grade and counts toward the daily
/// goal, but no card's due date moves -- the daily queue stays the
/// scheduler's. See ReviewSession.practice.
class CustomSessionScreen extends StatefulWidget {
  const CustomSessionScreen({required this.deckId, super.key});

  final int deckId;

  /// The session sizes on offer; null is "all".
  static const List<int?> sizes = [10, 20, 50, null];

  @override
  State<CustomSessionScreen> createState() => _CustomSessionScreenState();
}

class _CustomSessionScreenState extends State<CustomSessionScreen> {
  CustomPick _pick = CustomPick.random;
  int? _size = 10;
  bool _isStarting = false;

  /// How many cards each pick has to offer, for the subtitles and to
  /// disable an empty one.
  Map<CustomPick, int>? _available;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _countAvailable();
  }

  Future<void> _countAvailable() async {
    final store = DeckStoreScope.of(context);
    final counts = {
      for (final pick in CustomPick.values)
        pick: (await store.customCards(widget.deckId, pick)).length,
    };
    if (mounted) setState(() => _available = counts);
  }

  static String _title(CustomPick pick) => switch (pick) {
    CustomPick.random => 'Random mix',
    CustomPick.added => 'Cards I added',
    CustomPick.missed => 'Cards I got wrong',
  };

  static String _description(CustomPick pick) => switch (pick) {
    CustomPick.random => 'Any cards from the deck',
    CustomPick.added => 'Your own cards, newest first',
    CustomPick.missed => 'Last graded Wrong or Partial',
  };

  static IconData _icon(CustomPick pick) => switch (pick) {
    CustomPick.random => Icons.shuffle_rounded,
    CustomPick.added => Icons.edit_note_rounded,
    CustomPick.missed => Icons.replay_rounded,
  };

  Future<void> _start() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);
    final cards = await DeckStoreScope.of(context)
        .customCards(widget.deckId, _pick, count: _size);
    if (!mounted) return;
    setState(() => _isStarting = false);
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('No cards to practice.')));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RecallReviewScreen.custom(deckId: widget.deckId, cards: cards),
      ),
    );
    // Grades may have changed which cards count as missed.
    if (mounted) _countAvailable();
  }

  @override
  Widget build(BuildContext context) {
    final available = _available;
    final chosen = available?[_pick] ?? 0;
    return Scaffold(
      backgroundColor: LingoColors.background,
      appBar: AppBar(
        backgroundColor: LingoColors.background,
        elevation: 0,
        centerTitle: true,
        title: const ModeBadge(label: 'CUSTOM'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const _Label('CARDS'),
            const SizedBox(height: 8),
            for (final pick in CustomPick.values) ...[
              _PickTile(
                title: _title(pick),
                subtitle: available == null
                    ? _description(pick)
                    : '${_description(pick)} · ${available[pick]} '
                          '${available[pick] == 1 ? 'card' : 'cards'}',
                icon: _icon(pick),
                selected: pick == _pick,
                enabled: available == null || available[pick]! > 0,
                onTap: () => setState(() => _pick = pick),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
            const _Label('HOW MANY'),
            const SizedBox(height: 8),
            SegmentedButton<int?>(
              showSelectedIcon: false,
              segments: [
                for (final size in CustomSessionScreen.sizes)
                  ButtonSegment(
                    value: size,
                    label: Text(size == null ? 'All' : '$size'),
                  ),
              ],
              selected: {_size},
              onSelectionChanged: (selection) =>
                  setState(() => _size = selection.single),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _isStarting || chosen == 0 ? null : _start,
              style: FilledButton.styleFrom(
                backgroundColor: LingoColors.indigo,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: lingoFont(size: 16, weight: FontWeight.w700),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start'),
            ),
            const SizedBox(height: 12),
            Text(
              "Practice only: grades count toward today's goal, "
              "but due dates don't change.",
              textAlign: TextAlign.center,
              style: lingoFont(
                size: 13,
                weight: FontWeight.w500,
                color: LingoColors.mutedInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: lingoFont(
      size: 11,
      weight: FontWeight.w700,
      color: LingoColors.mutedInk,
      letterSpacing: 1.2,
    ),
  );
}

class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected ? LingoColors.indigoContainer : LingoColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? LingoColors.indigo : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: LingoColors.indigo),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: lingoFont(size: 15, weight: FontWeight.w700),
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
                if (selected)
                  Icon(Icons.check_circle_rounded, color: LingoColors.indigo),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
