import 'package:flutter/material.dart';

import '../decks/deck_models.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';
import '../theme/lingo_theme.dart';
import 'cue_player.dart';

/// The grade cues' player: one for the whole app rather than one per
/// [GradeButtons]. A tap grades the card, the next card replaces the
/// buttons, and a player disposed with them cut the cue off before it was
/// ever heard -- which is exactly what it did. Same pattern as
/// playTapSound().
final _cuePlayer = newCuePlayer();

Future<void> _playCue(Grade grade) async {
  try {
    await playCue(_cuePlayer, GradeButtons.soundFor(grade));
  } catch (err) {
    debugPrint('[GradeButtons] cue failed: $err');
  }
}

/// The three self-grade buttons under every flashcard: Wrong, Partial,
/// Perfect -- the labels for [Grade.difficult], [Grade.medium] and
/// [Grade.easy]. Only the labels changed; the stored grade names did not,
/// so earlier reviews still read the same.
///
/// The learner's tap is the grade -- [suggested], when a score gave one, is
/// only drawn as the solid button, never applied for them. Each button
/// plays its own cue (assets/sounds/buttons_sound/) the moment it is
/// tapped, without waiting on the grade being saved.
class GradeButtons extends StatefulWidget {
  const GradeButtons({required this.onGrade, this.suggested, super.key});

  final ValueChanged<Grade> onGrade;

  /// The button a score pre-selects, or null before there is a score.
  final Grade? suggested;

  static String labelFor(Grade grade) => switch (grade) {
    Grade.difficult => 'Wrong',
    Grade.medium => 'Partial',
    Grade.easy => 'Perfect',
  };

  static IconData iconFor(Grade grade) => switch (grade) {
    Grade.difficult => Icons.close_rounded,
    Grade.medium => Icons.remove_rounded,
    Grade.easy => Icons.check_rounded,
  };

  /// Plays [grade]'s cue on its own, e.g. for a grade given without the
  /// buttons ("I don't know" is Wrong).
  static Future<void> playCue(Grade grade) => _playCue(grade);

  static String soundFor(Grade grade) => switch (grade) {
    Grade.difficult => 'sounds/buttons_sound/wrong.wav',
    Grade.medium => 'sounds/buttons_sound/partial.wav',
    Grade.easy => 'sounds/buttons_sound/perfect.wav',
  };

  @override
  State<GradeButtons> createState() => _GradeButtonsState();
}

class _GradeButtonsState extends State<GradeButtons> {
  /// Each grade wears the colour of the score band that suggests it, so a
  /// green score lights up a green Perfect.
  static const Map<Grade, ScoreBand> _band = {
    Grade.difficult: ScoreBand.red,
    Grade.medium: ScoreBand.orange,
    Grade.easy: ScoreBand.green,
  };

  void _tap(Grade grade) {
    _playCue(grade);
    widget.onGrade(grade);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final (i, grade) in Grade.values.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _GradeButton(
              label: GradeButtons.labelFor(grade),
              icon: GradeButtons.iconFor(grade),
              color: colorForBand(theme, _band[grade]!),
              suggested: grade == widget.suggested,
              onTap: () => _tap(grade),
            ),
          ),
        ],
      ],
    );
  }
}

/// One grade: an icon over its label in a rounded tile tinted with the
/// grade's colour. The suggested one is solid, so it reads at a glance as
/// "the score thinks this".
class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.suggested,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = suggested ? Colors.white : color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: suggested ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withValues(alpha: suggested ? 1 : 0.35),
          width: 1.5,
        ),
        boxShadow: suggested
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: foreground, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: lingoFont(
                    size: 14,
                    weight: FontWeight.w700,
                    color: foreground,
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
