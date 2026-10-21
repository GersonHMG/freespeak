import 'dart:async';

import 'package:flutter/material.dart';

import '../data/practice_history_scope.dart';
import '../data/practice_history_store.dart';
import '../decks/deck_store.dart';
import '../decks/deck_store_scope.dart';
import '../decks/recall_settings.dart';
import '../pronunciation/mispronounce_detector.dart';
import '../pronunciation/pronunciation_scope.dart';
import '../pronunciation/vosk_asr.dart';
import '../tts/phonon_tts.dart';
import '../tts/phonon_tts_scope.dart';
import '../theme/theme_setting.dart';
import '../widgets/app_loading_screen.dart';
import 'home_screen.dart';
import 'language_onboarding_screen.dart';

/// App gate: warms up the on-device Phonon TTS model, showing the wordmark
/// until it is ready, then hands off to [HomeScreen].
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  final PhononTts _tts = PhononTts();
  late final MispronounceDetector _detector = MispronounceDetector(
    asr: VoskAsr(),
    // Both sides of the comparison must speak the same dialect of IPA, so the
    // scorer borrows the synthesizer's own phonemizer rather than bringing a
    // second one that would disagree with it about, say, the flap in "water".
    phonemize: (word) => _tts.phonemizer.phonemize(word, _tts.lang),
  );
  final PracticeHistoryStore _history = PracticeHistoryStore();
  late final DeckStore _decks = DeckStore(_history);
  bool _ready = false;

  /// The nested Navigator below, so the system back button can reach it.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey();

  /// Whether to open on the "what language do you speak?" question rather
  /// than Home -- a first launch.
  bool _askLanguage = false;

  @override
  void initState() {
    super.initState();
    _warmUp();
  }

  Future<void> _warmUp() async {
    try {
      await _tts.load();
    } catch (err) {
      // Fail open so the app isn't stuck on the loader forever if the model
      // can't load; synthesis will retry and surface the error at press time.
      debugPrint('Failed to load Phonon TTS model: $err');
    }

    try {
      await _history.open();
    } catch (err) {
      // Same fail-open reasoning again -- a learner should be able to
      // practice even if their history can't be persisted this run.
      debugPrint('Failed to open practice history database: $err');
    }

    try {
      // No starter deck is imported up front any more: which one depends on
      // the language the learner speaks, asked once, here, before Home
      // (LanguageOnboardingScreen imports it). An install from before the
      // question is asked too; picking its language reuses its deck.
      _askLanguage = await _decks.nativeLanguage() == null;
    } catch (err) {
      debugPrint("Failed to read the learner's language: $err");
    }

    try {
      await loadThemeMode(_decks);
    } catch (err) {
      debugPrint('Failed to read the theme setting: $err');
    }

    try {
      await loadRecallSettings(_decks);
    } catch (err) {
      debugPrint('Failed to read the Recall settings: $err');
    }

    // Deliberately not awaited. On the first run after an install the
    // recognizer's weights are still being unzipped out of the bundle (~40 MB,
    // seconds), and holding the whole app on the loader for that would mean a
    // first run that cannot even hear the phrase before it can score one. The
    // record button reports its own readiness instead.
    unawaited(
      _detector.ready().catchError((Object err) {
        debugPrint('Failed to load speech recognizer: $err');
      }),
    );

    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _tts.dispose();
    _detector.dispose();
    _decks.dispose();
    _history.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return PhononTtsScope(
        tts: _tts,
        child: PronunciationScope(
          detector: _detector,
          child: PracticeHistoryScope(
            store: _history,
            child: DeckStoreScope(
              store: _decks,
              // A nested Navigator, rather than pushing on the app-level one,
              // so that routes pushed from HomeScreen (e.g. SessionScreen)
              // stay inside these scopes instead of escaping them as sibling
              // routes.
              //
              // The system back button only ever asks the app-level
              // Navigator, which holds nothing but this screen -- so without
              // the handler, back would close the app from any depth. It
              // hands the pop down to the nested Navigator instead, which
              // also lets the screens' own PopScopes (leave-session dialogs)
              // see it.
              child: NavigatorPopHandler(
                onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
                child: Navigator(
                  key: _navigatorKey,
                  onGenerateRoute: (settings) => MaterialPageRoute(
                    builder: (_) => _askLanguage
                        ? const LanguageOnboardingScreen()
                        : const HomeScreen(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return const AppLoadingScreen();
  }
}
