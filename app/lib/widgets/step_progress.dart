import 'package:flutter/material.dart';

/// One segment per step, filled up to (and including) [current] -- a step
/// indicator in place of a bare "N / total" count. [SessionScreen] uses it
/// for its phrase set, [PracticeScreen] for a word drill.
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.total, required this.current});

  final int total;

  /// Zero-based index of the step in progress.
  final int current;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= current
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
