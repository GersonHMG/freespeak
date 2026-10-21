import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/daily_activity.dart';
import '../data/practice_history_scope.dart';
import '../decks/deck_store_scope.dart';
import '../theme/lingo_theme.dart';
import '../widgets/cards_per_day_card.dart';
import '../widgets/tap_sound.dart';
import 'deck_picker_screen.dart';
import 'debug/debug_menu.dart';
import 'my_progress_screen.dart';
import 'practice_mode_screen.dart';

/// The app's tab shell: Home, My Progress, and More as persistent tabs
/// behind one bottom nav, rather than screens pushed on top of it -- so the
/// nav bar stays put while moving between them. [IndexedStack] keeps all
/// three alive underneath, so switching tabs doesn't re-trigger their
/// loading state.
class HomeScreen extends StatefulWidget {
  const HomeScreen({this.dailyGoalTarget = kDefaultDailyGoalTarget, super.key});

  /// Cards per day for a day to count as goal met in the "Cards per day"
  /// panel.
  final int dailyGoalTarget;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  void _selectTab(int index) => setState(() => _tabIndex = index);

  @override
  Widget build(BuildContext context) {
    // Back from Progress or More returns to Home first, like any tabbed
    // app; only back from Home itself leaves the app.
    return PopScope(
      canPop: _tabIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _selectTab(0);
      },
      child: Scaffold(
        backgroundColor: LingoColors.background,
        // Swiping right from the left edge opens this for free -- Scaffold
        // wires up the edge-drag gesture whenever a drawer is present.
        drawer: kDebugMode ? const DebugMenu() : null,
        body: IndexedStack(
          index: _tabIndex,
          children: [
            _HomeTab(dailyGoalTarget: widget.dailyGoalTarget),
            const MyProgressScreen(),
            const PracticeModeScreen(),
          ],
        ),
        bottomNavigationBar: _BottomNav(
          selectedIndex: _tabIndex,
          onSelect: _selectTab,
        ),
      ),
    );
  }
}

/// The Home tab's content: this week's activity, and the big Play card into
/// [SessionLoadingScreen].
class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.dailyGoalTarget});

  final int dailyGoalTarget;

  /// This week before the history has loaded.
  static const _noCards = [0, 0, 0, 0, 0, 0, 0];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The day cards count cards from both modes, so this
            // rebuilds on writes to either store: a scored pronunciation
            // attempt (or the debug menu's Clear Data) and a graded Recall
            // card. Without the second, today's count would stay stale after a
            // Recall sitting until something else moved it.
            ListenableBuilder(
              listenable: Listenable.merge([
                PracticeHistoryScope.of(context).changes,
                DeckStoreScope.of(context).changes,
              ]),
              builder: (context, _) {
                final history = PracticeHistoryScope.of(context);
                return FutureBuilder<DailyActivity>(
                  future: loadDailyActivity(
                    history,
                    goalTarget: dailyGoalTarget,
                  ),
                  builder: (context, snapshot) {
                    final activity = snapshot.data;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TopBar(currentStreak: activity?.currentStreak ?? 0),
                        const SizedBox(height: 20),
                        CardsPerDayCard(
                          cardsPerDay: activity?.cardsPerDay ?? _noCards,
                          goalTarget: dailyGoalTarget,
                        ),
                        const SizedBox(height: 20),
                        // The two modes: Recall, the main one, and the
                        // pronunciation session. Each asks for a deck next.
                        const _RecallCard(),
                        const SizedBox(height: 20),
                        _ShortcutCard(
                          leading: const _MicIcon(),
                          title: 'Pronunciation',
                          subtitle: "We'll listen and check your pronunciation",
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DeckPickerScreen(
                                purpose: DeckPurpose.pronunciation,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// "Good {time of day}" greeting, the app name, and a streak pill.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.currentStreak});

  final int currentStreak;

  static String _greeting() {
    final hour = TimeOfDay.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: lingoFont(
                  size: 13,
                  weight: FontWeight.w400,
                  color: LingoColors.mutedInk,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Free Speak',
                style: lingoFont(size: 18, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: LingoColors.streakContainer,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 16,
                color: LingoColors.streak,
              ),
              const SizedBox(width: 6),
              Text(
                '$currentStreak day streak',
                style: lingoFont(
                  size: 14,
                  weight: FontWeight.w600,
                  color: LingoColors.streak,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The big call to action into [SessionScreen].
class _PlayCard extends StatelessWidget {
  const _PlayCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;

  /// Null draws the card dimmed and untappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LingoColors.accentCard,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                playMenuTapSound();
                onTap!();
              },
        child: Opacity(
          opacity: onTap == null ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: lingoFont(
                          size: 24,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: lingoFont(
                          size: 14,
                          weight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 32,
                    color: LingoColors.accentCard,
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

/// The main mode's card: how many Recall cards are due across every deck,
/// and the way into choosing one.
class _RecallCard extends StatelessWidget {
  const _RecallCard();

  @override
  Widget build(BuildContext context) {
    final decks = DeckStoreScope.of(context);
    // Listens for itself: the due count drops as cards are graded, while
    // this const card is never rebuilt by its parent.
    return ListenableBuilder(
      listenable: decks.changes,
      builder: (context, _) => FutureBuilder<int>(
        future: decks.deckSummaries().then(
          (summaries) =>
              summaries.fold<int>(0, (sum, deck) => sum + deck.dueCount),
        ),
        builder: (context, snapshot) {
          final due = snapshot.data ?? 0;
          // Always tappable: the deck picker shows what each deck has, and
          // a sitting with nothing due starts on more cards anyway.
          return _PlayCard(
            title: 'Recall cards',
            subtitle: due == 0
                ? 'All caught up — choose a deck to practice'
                : '$due ${due == 1 ? 'card' : 'cards'} due today',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const DeckPickerScreen(purpose: DeckPurpose.recall),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The Pronunciation entry's icon: a solid indigo square (with the mic) in
/// front of a paler one peeking out behind it.
class _MicIcon extends StatelessWidget {
  const _MicIcon();

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size + 8,
      height: _size + 8,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                color: LingoColors.indigoContainer,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                color: LingoColors.indigo,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row card: a leading icon, title (and optional subtitle), and a
/// chevron. [onTap] of null renders the row disabled (dimmed, untappable) --
/// used for a shortcut with nothing behind it yet.
class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: LingoColors.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 1,
      shadowColor: LingoColors.ink.withValues(alpha: 0.06),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: enabled
            ? () {
                playMenuTapSound();
                onTap!();
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
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
                        style: lingoFont(size: 16, weight: FontWeight.w600),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: lingoFont(
                            size: 12,
                            weight: FontWeight.w400,
                            color: LingoColors.mutedInk,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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

/// Visual bottom nav matching the mockup, and the app's actual tab switcher
/// -- it stays on screen across all three tabs since [HomeScreen] owns it
/// once, above an [IndexedStack], rather than each tab pushing its own
/// screen over it.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: LingoColors.surface,
          border: Border(top: BorderSide(color: LingoColors.ringTrack)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _NavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              selected: selectedIndex == 0,
              onTap: () => _select(context, 0),
            ),
            _NavItem(
              icon: Icons.bar_chart_rounded,
              label: 'Progress',
              selected: selectedIndex == 1,
              onTap: () => _select(context, 1),
            ),
            _NavItem(
              icon: Icons.more_horiz_rounded,
              label: 'More',
              selected: selectedIndex == 2,
              onTap: () => _select(context, 2),
            ),
          ],
        ),
      ),
    );
  }

  void _select(BuildContext context, int index) {
    if (index == selectedIndex) return;
    playMenuTapSound();
    onSelect(index);
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? LingoColors.indigo : LingoColors.navInactive;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: lingoFont(
                size: 11,
                weight: selected ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
