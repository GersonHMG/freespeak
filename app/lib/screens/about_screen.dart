import 'package:flutter/material.dart';

import '../data/credits.dart';
import '../theme/lingo_theme.dart';
import '../widgets/mode_badge.dart';

/// About: what Free Speak is, and a plain warning that it is new -- the
/// bundled sentences and their translations can be wrong, and pronunciation
/// scores are a machine's estimate, not a teacher's verdict.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LingoColors.background,
      appBar: AppBar(
        backgroundColor: LingoColors.background,
        elevation: 0,
        centerTitle: true,
        title: const ModeBadge(label: 'ABOUT'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Free Speak',
              style: lingoFont(size: 24, weight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Practice speaking English, one sentence at a time.',
              style: lingoFont(
                size: 15,
                weight: FontWeight.w400,
                color: LingoColors.mutedInk,
              ),
            ),
            const SizedBox(height: 24),
            const _Notice(),
            const SizedBox(height: 24),
            const _Section(
              icon: Icons.translate_rounded,
              title: 'Phrases and translations',
              body:
                  'The ready-made decks were written for this app and '
                  'translated with the help of AI. Not every sentence has '
                  'been checked by a native speaker yet, so some phrases or '
                  'translations may sound unnatural or be wrong.',
            ),
            const SizedBox(height: 12),
            const _Section(
              icon: Icons.graphic_eq_rounded,
              title: 'Pronunciation scores',
              body:
                  'Scores come from speech recognition running on your '
                  'phone. It can mishear you, especially with background '
                  'noise or a quiet microphone, so treat a score as a hint, '
                  "not a teacher's verdict.",
            ),
            const SizedBox(height: 12),
            const _Section(
              icon: Icons.edit_note_rounded,
              title: 'Your own cards',
              body:
                  'Spotted a mistake on a card? You can add your own '
                  'answers to it, or make a deck of your own under '
                  'More → My decks.',
            ),
            const SizedBox(height: 24),
            const _CreditsCard(),
            const SizedBox(height: 12),
            const _LicensesRow(),
          ],
        ),
      ),
    );
  }
}

/// The open-source work the app is built on ([kCredits]): each project,
/// what it is used for, who made it, and its licence.
class _CreditsCard extends StatelessWidget {
  const _CreditsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: lingoCardDecoration(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Credits', style: lingoFont(size: 16, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Free Speak is free software under the GNU GPL v3, built on '
            'these open-source projects.',
            style: lingoFont(
              size: 14,
              weight: FontWeight.w400,
              color: LingoColors.mutedInk,
            ),
          ),
          for (final credit in kCredits) ...[
            const SizedBox(height: 14),
            Text(
              credit.by.isEmpty
                  ? credit.name
                  : '${credit.name} by ${credit.by}',
              style: lingoFont(size: 14, weight: FontWeight.w600),
            ),
            Text(
              '${credit.use} · ${credit.license}',
              style: lingoFont(
                size: 13,
                weight: FontWeight.w400,
                color: LingoColors.mutedInk,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens Flutter's licence page: the credits' full licence texts and every
/// Dart package's.
class _LicensesRow extends StatelessWidget {
  const _LicensesRow();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LingoColors.surface,
      borderRadius: BorderRadius.circular(22),
      elevation: 1,
      shadowColor: LingoColors.ink.withValues(alpha: 0.06),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => showLicensePage(
          context: context,
          applicationName: 'Free Speak',
          applicationLegalese: 'Free software under the GNU GPL v3.',
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: LingoColors.indigoContainer,
                child: Icon(
                  Icons.description_outlined,
                  size: 20,
                  color: LingoColors.indigo,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Open-source licenses',
                  style: lingoFont(size: 16, weight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: LingoColors.navInactive),
            ],
          ),
        ),
      ),
    );
  }
}

/// The early-version warning, set apart from the sections below it.
class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LingoColors.streakContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: LingoColors.streak),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This app is new',
                  style: lingoFont(
                    size: 17,
                    weight: FontWeight.w700,
                    color: LingoColors.streak,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Free Speak is an early version and still being improved. '
                  'Some phrases, translations or scores may be wrong. '
                  'Thanks for your patience while we fix them.',
                  style: lingoFont(size: 14, weight: FontWeight.w400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LingoColors.surface,
      borderRadius: BorderRadius.circular(22),
      elevation: 1,
      shadowColor: LingoColors.ink.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: LingoColors.indigoContainer,
              child: Icon(icon, size: 20, color: LingoColors.indigo),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: lingoFont(size: 16, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: lingoFont(
                      size: 14,
                      weight: FontWeight.w400,
                      color: LingoColors.mutedInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
