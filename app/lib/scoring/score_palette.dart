// One colour per [ScoreBand], shared by word colouring and sentence
// colouring -- the single place `0xFFB26A00` (the amber used for "orange")
// is defined, instead of it being copied wherever a band needs painting.

import 'package:flutter/material.dart';

import 'score_band.dart';

/// The colour [band] renders as, in [theme].
///
/// Green defers to the theme's primary colour rather than a literal green:
/// it already carries the app's own hue, and a hand-picked green would fight
/// it in a themed build. Orange and red are fixed -- an amber and the
/// theme's error colour -- since both need to read as "attention" regardless
/// of what the primary happens to be.
Color colorForBand(ThemeData theme, ScoreBand band) => switch (band) {
  ScoreBand.green => theme.colorScheme.primary,
  ScoreBand.orange => const Color(0xFFB26A00),
  ScoreBand.red => theme.colorScheme.error,
};
