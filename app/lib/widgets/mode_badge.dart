import 'package:flutter/material.dart';

/// The small "• SESSION" / "• PRACTICE" pill shown in an app bar in place of
/// a plain title -- a label for the mode the learner is in, not a page
/// heading. Shared by [SessionScreen] and [PracticeScreen] so the two modes
/// read as siblings.
class ModeBadge extends StatelessWidget {
  const ModeBadge({super.key, required this.label});

  /// Upper-case mode name, e.g. `'SESSION'`.
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
