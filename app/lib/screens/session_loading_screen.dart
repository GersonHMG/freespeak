import 'dart:async';

import 'package:flutter/material.dart';

import '../data/sample_sentences.dart';
import '../decks/deck_models.dart';
import '../decks/deck_store_scope.dart';
import '../tts/phonon_tts_scope.dart';
import '../widgets/app_loading_screen.dart';
import 'session_screen.dart';

/// The branded beat between tapping "Let's Play" and the first phrase: draws
/// a fresh sample of phrases (so every session is different, never a repeat
/// of what [LoadingScreen] warmed up with), then hands off to
/// [SessionScreen]. The first phrase's audio is synthesized here so it
/// speaks the instant the session opens; the rest are left generating in
/// the background, ahead of the learner. A minimum duration keeps the animation from flashing
/// by unread when that work happens to be quick.
///
/// With [deckId], the phrases are that deck's English sentences instead of
/// the built-in dataset: [deckSessionLength] of its cards at random.
class SessionLoadingScreen extends StatefulWidget {
  const SessionLoadingScreen({this.deckId, super.key});

  /// The deck to read from, or null for the everyday sentences.
  final int? deckId;

  /// How many of a deck's sentences one session reads -- the same as a
  /// session from the everyday sentences.
  static const int deckSessionLength = 5;

  static const Duration minDuration = Duration(milliseconds: 900);

  @override
  State<SessionLoadingScreen> createState() => _SessionLoadingScreenState();
}

class _SessionLoadingScreenState extends State<SessionLoadingScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Here rather than initState: the TTS engine comes from a scope lookup.
    if (_started) return;
    _started = true;
    _start();
  }

  Future<void> _start() async {
    final tts = PhononTtsScope.of(context);
    final stopwatch = Stopwatch()..start();
    var phrases = const <String>[];
    try {
      final deckId = widget.deckId;
      phrases = deckId == null
          ? await loadSampleSentences()
          : [
              for (final card in await DeckStoreScope.of(context).customCards(
                deckId,
                CustomPick.random,
                count: SessionLoadingScreen.deckSessionLength,
              ))
                card.note.primaryReference,
            ];
    } catch (err) {
      // Fail open, same reasoning as LoadingScreen's own warm-up: a bad
      // sample draw must not strand the learner on this screen.
      debugPrint('[SessionLoadingScreen] failed to sample phrases: $err');
    }
    if (phrases.isEmpty) phrases = fallbackSampleSentences;

    // Only the first phrase is waited on -- it is what speaks the moment the
    // session opens. The rest are queued behind it and keep generating while
    // the learner works on the first, which takes about as long as each one
    // does to synthesize. Fails open per phrase (see PhononTts.precompute):
    // one that could not be synthesized just retries when it is played.
    await tts.precompute(phrases.take(1));
    unawaited(tts.precompute(phrases.skip(1)));

    final remaining = SessionLoadingScreen.minDuration - stopwatch.elapsed;
    if (remaining > Duration.zero) await Future.delayed(remaining);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SessionScreen(phrases: phrases, autoPlay: true),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const AppLoadingScreen(subtitle: 'Loading your next phrase…');
  }
}
