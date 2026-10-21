// The More tab: the practice sessions -- revisiting missed words and
// sentences, or typing in anything to practice on demand -- then the
// learner's decks, then Settings and About.

import 'package:flutter/material.dart';

import '../data/daily_activity.dart';
import '../data/practice_history_scope.dart';
import '../theme/lingo_theme.dart';
import '../widgets/tap_sound.dart';
import 'about_screen.dart';
import 'custom_practice_screen.dart';
import 'decks_screen.dart';
import 'revisit_screen.dart';
import 'settings_screen.dart';

class PracticeModeScreen extends StatelessWidget {
  const PracticeModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = PracticeHistoryScope.of(context);

    return Scaffold(
      backgroundColor: LingoColors.background,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: ListenableBuilder(
            listenable: history.changes,
            builder: (context, _) => FutureBuilder<DailyActivity>(
              future: loadDailyActivity(history),
              builder: (context, snapshot) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(currentStreak: snapshot.data?.currentStreak ?? 0),
                    const SizedBox(height: 20),
                    Text(
                      'PRACTICE',
                      style: lingoFont(
                        size: 11,
                        weight: FontWeight.w700,
                        color: LingoColors.mutedInk,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SessionCard(
                      icon: Icons.mic_rounded,
                      title: 'Revisit mispronunciations',
                      subtitle: 'Words and sentences you missed',
                      badge: FutureBuilder<int>(
                        future: Future.wait([
                          history.mispronouncedWordCount(),
                          history.mispronouncedSentenceCount(),
                        ]).then((counts) => counts[0] + counts[1]),
                        builder: (context, snapshot) {
                          final count = snapshot.data ?? 0;
                          return count == 0
                              ? const SizedBox.shrink()
                              : _CountBadge(count: count);
                        },
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const RevisitScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SessionCard(
                      icon: Icons.add_rounded,
                      title: 'Custom practice',
                      subtitle: 'Practice any word or sentence you choose',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const CustomPracticeScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'DECKS',
                      style: lingoFont(
                        size: 11,
                        weight: FontWeight.w700,
                        color: LingoColors.mutedInk,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SessionCard(
                      icon: Icons.style_rounded,
                      title: 'My decks',
                      subtitle: 'Make decks and write their cards',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DecksScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'APP',
                      style: lingoFont(
                        size: 11,
                        weight: FontWeight.w700,
                        color: LingoColors.mutedInk,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SessionCard(
                      icon: Icons.settings_rounded,
                      title: 'Settings',
                      subtitle: 'Your language',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SessionCard(
                      icon: Icons.info_outline_rounded,
                      title: 'About',
                      subtitle: 'An early version: some phrases may be wrong',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AboutScreen(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// "More" / "Practice, decks and settings" heading, and the streak pill -- the same
/// shape as the Home and Progress tabs' headers.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.currentStreak});

  final int currentStreak;

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
                'More',
                style: lingoFont(
                  size: 13,
                  weight: FontWeight.w400,
                  color: LingoColors.mutedInk,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Practice, decks and settings',
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

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LingoColors.surface,
      borderRadius: BorderRadius.circular(22),
      elevation: 1,
      shadowColor: LingoColors.ink.withValues(alpha: 0.06),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          playMenuTapSound();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: LingoColors.indigoContainer,
                child: Icon(icon, color: LingoColors.indigo),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: lingoFont(size: 17, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: lingoFont(
                        size: 13,
                        weight: FontWeight.w400,
                        color: LingoColors.mutedInk,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 8), badge!],
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: LingoColors.errorContainer,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '$count',
        style: lingoFont(
          size: 13,
          weight: FontWeight.w700,
          color: LingoColors.onErrorContainer,
        ),
      ),
    );
  }
}
