// A standalone entrypoint for iterating on [SessionCompleteScreen] without
// playing through a whole session first:
//
//     flutter run -t lib/dev/session_complete_preview.dart
//
// The screen is trivially previewable because it reads no scopes -- unlike
// SessionScreen, which needs a loaded PhononTts and a MispronounceDetector
// above it, SessionCompleteScreen takes four plain ints and nothing else. So
// this file needs no engines, no model weights, and no microphone.
//
// It is a development tool, not a feature: nothing in the app imports it, and
// because it is a separate entrypoint it is never compiled into the real app
// binary. Run it on a real device rather than the emulator when judging the
// completion cue -- the emulator's audio is not worth trusting.

import 'package:flutter/material.dart';

import '../screens/session_complete_screen.dart';

void main() => runApp(const _PreviewApp());

/// The size of a real session -- kDefaultTierCounts (2 easy, 2 medium, 1
/// hard) sums to five, so every preset is a five-phrase set.
const int _sessionPhraseCount = 5;

/// One set of numbers to hand [SessionCompleteScreen], named by what it is
/// meant to show.
class _Preset {
  const _Preset(
    this.label, {
    required this.totalPoints,
    required this.maxPossible,
    this.sentencesAttempted = _sessionPhraseCount,
  });

  final String label;
  final int totalPoints;
  final int maxPossible;
  final int sentencesAttempted;
}

// The ring's colour is driven by totalPoints / maxPossible, so these walk
// that ratio across every stop the palette defines. 0% is listed separately
// from 5% on purpose: at exactly zero there is no arc to colour at all, only
// the bare track, so the red end of the scale is only visible just above it.
const List<_Preset> _presets = [
  _Preset('100% — full green ring', totalPoints: 500, maxPossible: 500),
  _Preset('75% — yellow-green', totalPoints: 375, maxPossible: 500),
  _Preset('50% — yellow', totalPoints: 250, maxPossible: 500),
  _Preset('25% — orange', totalPoints: 125, maxPossible: 500),
  _Preset('5% — red sliver', totalPoints: 25, maxPossible: 500),
  _Preset('0% — bare track, no arc', totalPoints: 0, maxPossible: 500),
  _Preset(
    'Nothing attempted — every phrase skipped',
    totalPoints: 0,
    maxPossible: 0,
    sentencesAttempted: 0,
  ),
];

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Session complete preview',
      debugShowCheckedModeBanner: false,
      // Mirrors main.dart, so the preview shows the colours the real app
      // will. Kept as a copy rather than reaching into main.dart: this file
      // is a dev tool and should not be a reason to reshape the real app.
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F62FE)),
      ),
      home: const _PresetPicker(),
    );
  }
}

class _PresetPicker extends StatelessWidget {
  const _PresetPicker();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Session complete preview')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _presets.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Each opens the real screen, so the entrance animation and '
                  'the completion sound play exactly as they do in a session. '
                  '"Back to Home" returns here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }

            final preset = _presets[index - 1];
            return FilledButton.tonal(
              // A fresh route every time, which is what replays the animation
              // and the cue -- reusing one instance would show them only once.
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SessionCompleteScreen(
                    totalPoints: preset.totalPoints,
                    maxPossible: preset.maxPossible,
                    sentencesAttempted: preset.sentencesAttempted,
                    totalPhrases: _sessionPhraseCount,
                    cardsTodayBeforeSession: 0,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(preset.label),
              ),
            );
          },
        ),
      ),
    );
  }
}
