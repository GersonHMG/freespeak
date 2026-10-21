import 'dart:async';

import 'package:flutter/material.dart';

import '../data/daily_activity.dart';
import '../data/practice_history_scope.dart';
import '../pronunciation/pronunciation_result.dart';
import '../pronunciation/pronunciation_scope.dart';
import '../pronunciation/recorder.dart';
import '../pronunciation/user_attempt_player.dart';
import '../scoring/feedback_sounds.dart';
import '../scoring/sentence_score.dart';
import '../scoring/session_score.dart';
import '../tts/phonon_tts_scope.dart';
import '../tts/phrase_player.dart';
import '../widgets/attempt_playback_bar.dart';
import '../widgets/copy_text_button.dart';
import '../widgets/hear_button.dart';
import '../widgets/mode_badge.dart';
import '../widgets/phoneme_comparison.dart';
import '../widgets/record_button.dart';
import '../widgets/slow_hear_button.dart';
import '../widgets/spoken_text.dart';
import '../widgets/step_progress.dart';
import '../widgets/warning_sound.dart';
import 'session_complete_screen.dart';

/// The session screen: one phrase at a time, with the option to hear it, to
/// record yourself saying it, or to skip ahead to the next one.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    required this.phrases,
    this.awardsPoints = true,
    this.saveAttempt = true,
    this.showsSummary = true,
    this.autoPlay = false,
    super.key,
  });

  /// The session's phrase set -- a random sample of the sentence dataset,
  /// picked once by [LoadingScreen] before this screen is shown.
  final List<String> phrases;

  /// Whether finishing this session should count toward the daily goal and
  /// streak. Off for the Practice tab's "Revisit sentences" -- re-running a
  /// sentence there is meant as low-stakes repetition, not a second way to
  /// earn the same points; on for the real "Let's start" session this
  /// screen otherwise backs.
  final bool awardsPoints;

  /// Whether a scored attempt here should be written to
  /// [PracticeHistoryStore] at all. Off for Custom Practice: a sentence
  /// typed in on the spot isn't real pronunciation history and must not
  /// show up later in the mispronounced-sentences list.
  final bool saveAttempt;

  /// Whether reaching the end of [phrases] is a session that *completes*.
  ///
  /// On for a real session: it is a run through a set, and finishing it earns
  /// a summary of how the set went. Off for the one-phrase screens that
  /// borrow this one -- Revisit sentences and Custom Practice -- where the
  /// learner opened a single sentence from a list and finishing means going
  /// back to that list, not being shown a scorecard for a "session" of one.
  ///
  /// Also what decides whether leaving asks first. A summary is progress that
  /// can be lost and is worth confirming; a single revisited sentence is not,
  /// and prompting for it turns a back button into a chore.
  final bool showsSummary;

  /// Whether each phrase speaks itself the moment it appears. On for a real
  /// session, whose loading screen has already synthesized every phrase so
  /// the audio starts instantly; off for the one-phrase screens, where the
  /// first play would sit through seconds of synthesis instead.
  final bool autoPlay;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  List<String> get _phrases => widget.phrases;
  final PronunciationRecorder _recorder = PronunciationRecorder();
  final UserAttemptPlayer _attemptPlayer = UserAttemptPlayer();
  final SessionScore _sessionScore = SessionScore();
  final FeedbackSoundPlayer _feedbackSound = FeedbackSoundPlayer();
  int _phraseIndex = 0;
  bool _isRecording = false;
  bool _isScoring = false;
  PronunciationResult? _result;
  PhrasePlayer? _player;

  // Which word (by ordinal, matching PronunciationResult.words) the last tap
  // landed on. A second tap on the same word plays what the learner said
  // instead of the reference again; any other tap starts the cycle over.
  int? _lastTappedWord;

  // The IPA transcription shown under the phrase, cached per phrase index so
  // switching phrases doesn't keep re-running the phonemizer on every
  // rebuild.
  Future<String>? _phonemesFuture;
  int? _phonemesFutureIndex;

  // Snapshotted the moment this screen (this session) is created, before any
  // of its own attempts can have been recorded -- so SessionCompleteScreen
  // can tell a fresh crossing of the daily goal apart from a goal that was
  // already met earlier today, without repeating the celebration for every
  // session made after the first one that reached it.
  Future<int>? _cardsTodayAtStart;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Built here rather than in initState: the scope lookup needs a context
    // that is already wired into the tree.
    if (_player == null) {
      _player = PhrasePlayer(PhononTtsScope.of(context));
      _autoPlayCurrent();
    }
    _cardsTodayAtStart ??= loadDailyActivity(PracticeHistoryScope.of(context))
        .then((activity) => activity.cardsToday);
  }

  Future<String> _phonemesFor(BuildContext context, String phrase) {
    if (_phonemesFutureIndex != _phraseIndex) {
      _phonemesFutureIndex = _phraseIndex;
      _phonemesFuture = PhononTtsScope.of(context).phonemesFor(phrase);
    }
    return _phonemesFuture!;
  }

  @override
  void dispose() {
    _player?.dispose();
    _recorder.dispose();
    _attemptPlayer.dispose();
    _feedbackSound.dispose();
    super.dispose();
  }

  /// Tapping a word plays the reference the first time, and — if the word was
  /// actually said in the last attempt — what the learner said the second
  /// time. A third tap starts the cycle over rather than replaying "what I
  /// said" indefinitely.
  Future<void> _handleWordTap(int wordOrdinal) async {
    if (wordOrdinal != _lastTappedWord) {
      _lastTappedWord = wordOrdinal;
      await _player?.playWord(wordOrdinal);
      return;
    }

    _lastTappedWord = null;
    final played = await _attemptPlayer.playWord(wordOrdinal);
    if (!played && mounted) {
      _showMessage("You didn't say this word — nothing to play back.");
    }
  }

  /// Starts recording. Called the moment the record button is pressed down.
  Future<void> _startRecording() async {
    if (_isScoring || _isRecording) return;

    // Hearing the phrase while recording it would put the synthesizer's
    // voice into the attempt and score that instead.
    await _player?.stop();
    // Slotted by phrase, not just "the current attempt" -- a later phrase's
    // recording must not overwrite this one's file while it can still be
    // gone back to. See [PronunciationRecorder.start].
    final started = await _recorder.start(slot: _phraseIndex);
    if (!mounted) return;
    if (!started) {
      _showMessage('Microphone permission is needed to score your speech.');
      return;
    }
    // The previous attempt's colouring, and its word clips, belong to the
    // previous attempt.
    _attemptPlayer.attach(null);
    setState(() {
      _isRecording = true;
      _result = null;
      _lastTappedWord = null;
    });
  }

  /// Abandons the in-progress recording without scoring it. Called when the
  /// learner drags the record button away before releasing.
  void _cancelRecording() {
    if (!_isRecording) return;
    _recorder.cancel();
    setState(() => _isRecording = false);
  }

  /// Stops recording and scores the attempt. Called when the learner
  /// releases the record button without having dragged it away first.
  Future<void> _stopAndScoreRecording() async {
    if (!_isRecording) return;

    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isScoring = path != null;
    });
    if (path == null) {
      _showMessage('That was too short to score — hold while you speak.');
      return;
    }

    try {
      final phrase = _phrases[_phraseIndex];
      final result = await PronunciationScope.of(context).score(path, phrase);
      if (!mounted) return;
      _attemptPlayer.attach(result);

      // Nothing heard is a microphone problem, not a 0% performance -- it
      // must not spend one of this sentence's decaying attempts, or a bad
      // mic would permanently cap what the sentence can ever earn. The
      // outcome itself only feeds the running total at the top of the
      // screen (via _sessionScore, which AnimatedBuilder below watches) --
      // nothing here needs to keep it.
      if (result.spokenText.isNotEmpty) {
        final score = rateSentence(result, phrase);
        _sessionScore.record(_phraseIndex, score);
        unawaited(_feedbackSound.playFor(score.band));
        if (widget.saveAttempt) {
          // Fire-and-forget: a persistence write must not delay the score
          // appearing on screen, and there is nothing useful to do if it
          // fails beyond what recordAttempt already logs.
          unawaited(
            PracticeHistoryScope.of(context)
                .recordAttempt(
                  result: result,
                  score: score,
                  awardsPoints: widget.awardsPoints,
                )
                .catchError((Object err) {
                  debugPrint('[SessionScreen] failed to save attempt: $err');
                }),
          );
        }
      }

      setState(() {
        _result = result;
        _isScoring = false;
      });
    } catch (err) {
      debugPrint('[SessionScreen] scoring failed: $err');
      if (!mounted) return;
      setState(() => _isScoring = false);
      // Most often the recognizer's weights are still downloading on a first
      // run, which is worth saying rather than failing silently.
      _showMessage('Could not score that attempt. Try again in a moment.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _isLastPhrase => _phraseIndex == _phrases.length - 1;

  /// Skip to the next phrase -- or, on the last one, end the session.
  /// Recorded or not, reaching the end of the set is what "finished" means
  /// here, the same as skipping any other phrase requires no attempt at it.
  Future<void> _handleSkip() async {
    if (_isRecording) _recorder.cancel();

    if (_isLastPhrase) {
      // The session is over; nothing further will read [_attemptPlayer]'s
      // state, but leaving it pointed at this phrase's attempt would be
      // wrong if anything ever did.
      _attemptPlayer.attach(null);

      // Only reachable with a summary to show: the one-phrase revisit and
      // custom-practice screens (showsSummary: false) have no "Skip
      // phrase"/"Finish" button at all -- see the build method.
      //
      // Kicked off back in didChangeDependencies, long before this point in
      // a real session -- this await should never actually wait on the
      // database at this point, just read back an already-resolved value.
      final cardsTodayBeforeSession =
          await (_cardsTodayAtStart ?? Future.value(0));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SessionCompleteScreen(
            totalPoints: _sessionScore.totalPoints,
            maxPossible: _sessionScore.maxPossible,
            sentencesAttempted: _sessionScore.sentencesAttempted,
            totalPhrases: _phrases.length,
            cardsTodayBeforeSession: cardsTodayBeforeSession,
            awardsPoints: widget.awardsPoints,
          ),
        ),
      );
      return;
    }

    _switchToPhrase(_phraseIndex + 1);
  }

  /// Moves to [newIndex], a fresh, unattempted phrase.
  void _switchToPhrase(int newIndex) {
    _attemptPlayer.attach(null);

    setState(() {
      _isRecording = false;
      _isScoring = false;
      _result = null;
      _lastTappedWord = null;
      _player?.reset();
      _phraseIndex = newIndex;
    });
    _autoPlayCurrent();
  }

  /// Speaks the current phrase once it is on screen, if [SessionScreen.autoPlay]
  /// asks for it. After the frame, so the audio lines up with the phrase
  /// actually being visible rather than with the route still animating in
  /// from nothing.
  void _autoPlayCurrent() {
    if (!widget.autoPlay) return;
    final index = _phraseIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Moved on (or left) before the frame landed -- that phrase's turn is
      // over.
      if (!mounted || index != _phraseIndex || _isRecording) return;
      _player?.play(_phrases[index]);
    });
  }

  /// The phrase's text style, stepped down as it gets longer.
  ///
  /// The phrase area has a fixed height (it sits in an [Expanded] above a
  /// record button that must stay put, not scroll away while the learner's
  /// finger is already down on it -- see [SessionScreen]'s header). A long
  /// phrase set at a single large size would overflow that box instead, so
  /// length picks the style instead of one being pinned for every phrase.
  ///
  /// Thresholds are from the actual dataset (`assets/data_en.csv`): 50
  /// characters is its median-ish length and keeps ~85% of phrases at full
  /// size, 80 covers the next ~12%, and 130 covers all but a long tail of
  /// under a hundred outliers -- the one in the screenshot this was written
  /// for is 175 characters and lands in that last, smallest step.
  TextStyle? _phraseStyleFor(ThemeData theme, String phrase) {
    final style = switch (phrase.length) {
      <= 50 => theme.textTheme.headlineMedium,
      <= 80 => theme.textTheme.headlineSmall,
      <= 130 => theme.textTheme.titleLarge,
      _ => theme.textTheme.titleMedium,
    };
    return style?.copyWith(fontWeight: FontWeight.w800);
  }

  Future<void> _confirmExit() async {
    playWarningSound();
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave session?'),
        content: const Text("Your progress for this session will be lost."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (shouldLeave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final phrase = _phrases[_phraseIndex];
    final player = _player!;

    return PopScope(
      // Intercept every pop attempt -- the AppBar back arrow and the system
      // back gesture/button both go through this the same way -- so leaving
      // always goes through the confirmation dialog below, regardless of how
      // much progress this session has.
      //
      // Nothing to lose without a summary at the end of it, so a one-phrase
      // revisit leaves the moment it is asked to.
      canPop: !widget.showsSummary,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        // Back arrow pops to HomeScreen; it's the standard, expected affordance
        // alongside the system back gesture/button.
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          title: const ModeBadge(label: 'SESSION'),
          actions: [CopyTextButton(text: phrase)],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // One segment per phrase in the set -- filled up to the one
                // being practiced now.
                // No running points total: the session counts cards toward
                // the daily goal, and each attempt shows its own accuracy.
                StepProgress(total: _phrases.length, current: _phraseIndex),

                // Main phrase area, vertically centered.
                Expanded(
                  child:
                      // Centred while it fits, scrollable when it does not. A
                      // long phrase already pushes this box (see
                      // [_phraseStyleFor]); its IPA, which runs longer than the
                      // spelling it came from, is what makes the overflow
                      // reachable rather than theoretical.
                      LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _result != null
                                      ? 'TAP HIGHLIGHTED WORDS FOR TIPS'
                                      : 'READ AT NATURAL CADENCE',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                AnimatedBuilder(
                                  animation: player,
                                  builder: (context, _) => Column(
                                    children: [
                                      SpokenText(
                                        text: phrase,
                                        spokenWord: player.spokenWord,
                                        onWordTap: _handleWordTap,
                                        result: _result,
                                        textAlign: TextAlign.center,
                                        style: _phraseStyleFor(theme, phrase),
                                      ),
                                      // Before a result: the reference's phonemes and a
                                      // reminder of how tapping works. After one: neither
                                      // is the point any more -- the playback bar and the
                                      // pills on the phrase above are.
                                      if (_result == null) ...[
                                        const SizedBox(height: 16),
                                        FutureBuilder<String>(
                                          future: _phonemesFor(context, phrase),
                                          builder: (context, snapshot) {
                                            final phonemes = snapshot.data;
                                            if (phonemes == null ||
                                                phonemes.isEmpty) {
                                              return const SizedBox.shrink();
                                            }
                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: colorScheme
                                                      .outlineVariant,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                '[$phonemes]',
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontFamily: 'monospace',
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        // Only once the reference has actually been
                                        // heard — before that there is no "again" to
                                        // speak of, and the hint would be a promise the
                                        // screen has not earned yet.
                                        Text(
                                          player.isReady
                                              ? 'Tap a word again to hear yourself'
                                              : 'Tap to speak at your natural pace',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ] else ...[
                                        const SizedBox(height: 16),
                                        // The same slot the reference-only pill had
                                        // before the attempt, now that there is
                                        // something to hold it against.
                                        PhonemeComparison(result: _result!),
                                        const SizedBox(height: 20),
                                        AttemptPlaybackBar(
                                          player: _attemptPlayer,
                                          onHearReference: () =>
                                              player.toggle(phrase),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Need another try? Tap re-record or continue',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                ),

                // Hear the pronunciation -- a small supporting action -- next
                // to the much larger record button, the point of the screen.
                Row(
                  children: [
                    HearButton(text: phrase, player: player),
                    const SizedBox(width: 12),
                    SlowHearButton(text: phrase, player: player),
                    const SizedBox(width: 16),
                    Expanded(
                      child: RecordButton(
                        isRecording: _isRecording,
                        isScoring: _isScoring,
                        hasPreviousAttempt: _result != null,
                        onRecordStart: _startRecording,
                        onRecordStop: _stopAndScoreRecording,
                        onRecordCancel: _cancelRecording,
                      ),
                    ),
                  ],
                ),
                // A one-phrase revisit/custom-practice run has nothing to
                // skip through and no "Done" button -- finishing it means
                // leaving via the back arrow, same as the rest of those
                // screens. Only a real, multi-phrase session needs a way to
                // skip ahead or finish into a summary.
                if (widget.showsSummary) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _handleSkip,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(!_isLastPhrase ? 'Skip phrase' : 'Finish'),
                        const SizedBox(width: 8),
                        Icon(
                          _isLastPhrase ? Icons.check : Icons.arrow_forward,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
