// The Practice drill: one word at a time, hear it, say it, see how close it
// came -- either the same word for as long as the learner wants
// ([PracticeScreen.singleWord]) or one pass over a short list
// ([PracticeScreen.drill]).
//
// A trimmed sibling of [SessionScreen], not a mode flag on it. The session
// screen's swipe navigation, visited-frontier, per-index result cache, and
// exit confirmation all exist because a sentence set is something to move
// around in; a drill is not. What the two share -- the record button, the
// reference player, the attempt player, the scored-word colouring -- they
// share through the same widgets and the same scorer.
//
// Scoring is Vosk's, through [MispronounceDetector.score], returning a
// [PronunciationResult] whose single [ScoredWord] carries the accuracy and
// the clip timing for playback. This screen adds a vocabulary (the word plus
// a few decoys) -- an isolated word decoded against Vosk's full language
// model is easily replaced by a phonetic neighbour, which a sentence's
// context would have prevented. See [Asr.transcribe].

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/practice_history_scope.dart';
import '../data/practice_history_store.dart';
import '../pronunciation/phrase_tokens.dart';
import '../pronunciation/pronunciation_result.dart';
import '../pronunciation/pronunciation_scope.dart';
import '../pronunciation/recorder.dart';
import '../pronunciation/user_attempt_player.dart';
import '../scoring/feedback_sounds.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';
import '../scoring/sentence_score.dart';
import '../tts/phonon_tts_scope.dart';
import '../tts/phrase_player.dart';
import '../widgets/attempt_playback_bar.dart';
import '../widgets/hear_button.dart';
import '../widgets/mode_badge.dart';
import '../widgets/phoneme_comparison.dart';
import '../widgets/record_button.dart';
import '../widgets/slow_hear_button.dart';
import '../widgets/spoken_text.dart';
import '../widgets/step_progress.dart';
import '../widgets/syllable_strip.dart';
import '../widgets/warning_sound.dart';
import 'practice_complete_screen.dart';

class PracticeScreen extends StatefulWidget {
  /// Drill [word] until the learner taps Done. [decoys] are other words the
  /// recognizer may answer with -- ideally the learner's other missed words,
  /// so a wrong attempt has somewhere to land besides the target.
  ///
  /// [awardsPoints] defaults to false: unlike [PracticeScreen.drill] (which
  /// Word Rematch uses to actually earn points), this constructor backs the
  /// Practice tab's free-form word picker, which is meant for repetition
  /// rather than scoring.
  PracticeScreen.singleWord(
    String word, {
    List<String> decoys = const [],
    this.awardsPoints = false,
    this.saveAttempt = true,
    this.showsSyllables = false,
    super.key,
  }) : words = [word],
       decoys = decoys,
       isDrill = false,
       autoPlay = false;

  /// One pass over [words], then a summary. The words double as each
  /// other's decoys.
  const PracticeScreen.drill(
    this.words, {
    this.awardsPoints = true,
    this.saveAttempt = true,
    this.autoPlay = false,
    super.key,
  }) : decoys = const [],
       isDrill = true,
       showsSyllables = true;

  final List<String> words;
  final List<String> decoys;

  /// Drill mode moves through [words] once; single-word mode stays on
  /// [words.first] and counts attempts instead.
  final bool isDrill;

  /// Whether a scored attempt here should count toward the daily goal and
  /// streak. Off for the Practice tab's own modes (which are meant for
  /// low-stakes repetition, not scoring); on for Word Rematch, which is
  /// explicitly a way to earn points from struggling words.
  final bool awardsPoints;

  /// Whether a scored attempt here should be written to
  /// [PracticeHistoryStore] at all. Off for Custom Practice: a word typed in
  /// on the spot isn't real pronunciation history and must not show up
  /// later in the mispronounced-words list or Word Rematch.
  final bool saveAttempt;

  /// Whether the word is also shown split into syllables ("how · ev · er"),
  /// each playable on its own, with a button that plays them all slowed. On
  /// for Word Rematch and Custom Practice's single words.
  final bool showsSyllables;

  /// Whether each word speaks itself the moment it appears. On for Word
  /// Rematch, whose loading screen has already synthesized every word so the
  /// audio starts instantly.
  final bool autoPlay;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final PronunciationRecorder _recorder = PronunciationRecorder();
  final UserAttemptPlayer _attemptPlayer = UserAttemptPlayer();
  final FeedbackSoundPlayer _feedbackSound = FeedbackSoundPlayer();
  PhrasePlayer? _player;

  int _index = 0;
  int _attempts = 0;
  bool _isRecording = false;
  bool _isScoring = false;
  PronunciationResult? _result;
  SentenceScore? _score;

  /// Best accuracy per word this drill, for [PracticeCompleteScreen].
  final Map<String, int> _bestByWord = {};

  /// The points earned by each word's best attempt (the same attempt
  /// [_bestByWord] tracks) -- summed for [PracticeCompleteScreen]'s total
  /// when [PracticeScreen.awardsPoints] is on.
  final Map<String, int> _bestPointsByWord = {};

  // Which word the last tap landed on -- there is only one, so this is
  // effectively "was the reference already played for this attempt".
  int? _lastTappedWord;

  Future<String>? _phonemesFuture;
  int? _phonemesFutureIndex;

  String get _word => widget.words[_index];
  bool get _isLastWord => _index == widget.words.length - 1;

  /// Vosk's shortlist for this word; see [Asr.transcribe].
  ///
  /// Bare words only. Vosk looks every grammar entry up in the model's
  /// lexicon, which has "can" and no "can?" -- an entry it cannot find is
  /// silently unreachable, so a punctuated target would leave the shortlist
  /// unable to match the one word the drill is about. Stored words are
  /// already normalized; a word typed into Custom Practice is not.
  List<String> get _vocabulary {
    final shortlist = <String>[];
    for (final word in [
      _word,
      ...widget.isDrill ? widget.words : widget.decoys,
    ]) {
      final bare = normalizeWord(word);
      if (bare.isNotEmpty && !shortlist.contains(bare)) shortlist.add(bare);
    }
    return shortlist;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_player == null) {
      _player = PhrasePlayer(PhononTtsScope.of(context));
      _autoPlayCurrent();
      _prepareSyllables();
    }
  }

  /// Splits the word into syllables it can play slowly, when
  /// [PracticeScreen.showsSyllables] asks for it. Built as the word appears
  /// -- in Word Rematch from audio the loading screen has already
  /// synthesized, so the strip is there by the time the learner looks.
  void _prepareSyllables() {
    if (!widget.showsSyllables) return;
    unawaited(_player?.prepareSyllables(_word));
  }

  /// Speaks the current word once it is on screen, if
  /// [PracticeScreen.autoPlay] asks for it -- see SessionScreen's own.
  void _autoPlayCurrent() {
    if (!widget.autoPlay) return;
    final index = _index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index != _index || _isRecording) return;
      _player?.play(widget.words[index]);
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    _recorder.dispose();
    _attemptPlayer.dispose();
    _feedbackSound.dispose();
    super.dispose();
  }

  Future<String> _phonemes(BuildContext context) {
    if (_phonemesFutureIndex != _index) {
      _phonemesFutureIndex = _index;
      _phonemesFuture = PhononTtsScope.of(context).phonemesFor(_word);
    }
    return _phonemesFuture!;
  }

  /// First tap plays the reference, a second plays what the learner said (if
  /// anything was), a third starts over -- the same cycle as SessionScreen.
  Future<void> _handleWordTap(int wordOrdinal) async {
    if (wordOrdinal != _lastTappedWord) {
      _lastTappedWord = wordOrdinal;
      await _player?.playWord(wordOrdinal);
      return;
    }
    _lastTappedWord = null;
    final played = await _attemptPlayer.playWord(wordOrdinal);
    if (!played && mounted) {
      _showMessage("Nothing to play back yet -- record an attempt first.");
    }
  }

  Future<void> _startRecording() async {
    if (_isScoring || _isRecording) return;
    await _player?.stop();
    // One file per word so a drill's earlier recordings survive until the
    // summary; in single-word mode every attempt overwrites the last, which
    // is what "try again" means.
    final started = await _recorder.start(slot: 'practice_$_index');
    if (!mounted) return;
    if (!started) {
      _showMessage('Microphone permission is needed to score your speech.');
      return;
    }
    _attemptPlayer.attach(null);
    setState(() {
      _isRecording = true;
      _result = null;
      _score = null;
      _lastTappedWord = null;
    });
  }

  void _cancelRecording() {
    if (!_isRecording) return;
    _recorder.cancel();
    setState(() => _isRecording = false);
  }

  Future<void> _stopAndScoreRecording() async {
    if (!_isRecording) return;

    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isScoring = path != null;
    });
    if (path == null) {
      _showMessage('That was too short to score -- hold while you speak.');
      return;
    }

    try {
      final word = _word;
      final result = await PronunciationScope.of(context)
          .score(path, word, vocabulary: _vocabulary);
      if (!mounted) return;
      _attemptPlayer.attach(result);

      SentenceScore? score;
      // Nothing heard is a microphone problem, not a 0% -- the same rule the
      // session screen applies. It is not saved and does not count as an
      // attempt.
      if (result.spokenText.isNotEmpty) {
        score = rateSentence(result, word);
        _attempts++;
        final best = _bestByWord[word] ?? 0;
        if (score.accuracy > best) {
          _bestByWord[word] = score.accuracy;
          _bestPointsByWord[word] = score.points;
        }
        unawaited(_feedbackSound.playFor(score.band));
        if (widget.saveAttempt) {
          unawaited(
            PracticeHistoryScope.of(context)
                .recordAttempt(
                  result: result,
                  score: score,
                  source: AttemptSource.practice,
                  awardsPoints: widget.awardsPoints,
                )
                .catchError((Object err) {
                  debugPrint('[PracticeScreen] failed to save attempt: $err');
                }),
          );
        }
      }

      setState(() {
        _result = result;
        _score = score;
        _isScoring = false;
      });
    } catch (err) {
      debugPrint('[PracticeScreen] scoring failed: $err');
      if (!mounted) return;
      setState(() => _isScoring = false);
      _showMessage('Could not score that attempt. Try again in a moment.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Drill mode only: next word, or the summary. Single-word mode has no
  /// advance button -- the learner leaves via the back arrow instead.
  void _handleAdvance() {
    if (_isRecording) _recorder.cancel();

    if (_isLastWord) {
      _attemptPlayer.attach(null);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PracticeCompleteScreen(
            words: widget.words,
            bestAccuracyByWord: Map.unmodifiable(_bestByWord),
            totalPoints: widget.awardsPoints
                ? _bestPointsByWord.values.fold<int>(0, (a, b) => a + b)
                : null,
          ),
        ),
      );
      return;
    }
    _attemptPlayer.attach(null);
    setState(() {
      _isRecording = false;
      _isScoring = false;
      _result = null;
      _score = null;
      _lastTappedWord = null;
      _player?.reset();
      _index++;
    });
    _autoPlayCurrent();
    _prepareSyllables();
  }

  /// Warns before leaving a scored (Word Rematch) run early -- the earned
  /// points for words not yet reached would otherwise disappear with no
  /// notice, the same confirmation [SessionScreen] gives.
  Future<void> _confirmExit() async {
    playWarningSound();
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave rematch?'),
        content: const Text('Your progress in this rematch will be lost.'),
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

  String _hintFor(ScoreBand band) => switch (band) {
    ScoreBand.green => 'Nice, that matched.',
    ScoreBand.orange => 'Close. Listen again and try once more.',
    ScoreBand.red => 'Try slower, and match the reference.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final player = _player!;
    final result = _result;
    final score = _score;
    final heard = result?.words.isNotEmpty == true ? result!.words.first : null;

    final String advanceLabel;
    final IconData advanceIcon;
    if (_isLastWord) {
      advanceLabel = 'Finish';
      advanceIcon = Icons.check;
    } else {
      advanceLabel = 'Next word';
      advanceIcon = Icons.arrow_forward;
    }

    return PopScope(
      // Only Word Rematch (awardsPoints) is a scored run worth warning
      // about leaving early -- the Practice tab's free repetition modes
      // have no progress at stake, so they pop normally.
      canPop: !widget.awardsPoints,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          title: const ModeBadge(label: 'PRACTICE'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (widget.isDrill)
                  StepProgress(total: widget.words.length, current: _index)
                else
                  Text(
                    _attempts == 0 ? 'NO ATTEMPTS YET' : 'ATTEMPT $_attempts',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        result != null
                            ? 'TAP THE WORD TO COMPARE'
                            : 'SAY THIS WORD',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      AnimatedBuilder(
                        animation: player,
                        builder: (context, _) => SpokenText(
                          text: _word,
                          spokenWord: player.spokenWord,
                          onWordTap: _handleWordTap,
                          result: result,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (widget.showsSyllables) ...[
                        const SizedBox(height: 8),
                        SyllableStrip(player: player),
                      ],
                      const SizedBox(height: 16),
                      // Once there is an attempt to hold it against, the
                      // reference IPA on its own is the less useful half of
                      // the picture -- what the learner actually said next to
                      // it is what says which sound to change.
                      if (result != null)
                        PhonemeComparison(result: result)
                      else
                        FutureBuilder<String>(
                          future: _phonemes(context),
                          builder: (context, snapshot) {
                            final phonemes = snapshot.data;
                            if (phonemes == null || phonemes.isEmpty) {
                              return const SizedBox(height: 36);
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '[$phonemes]',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'monospace',
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 24),
                      if (score != null) ...[
                        Text(
                          '${score.accuracy}%',
                          style: theme.textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorForBand(theme, score.band),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _hintFor(score.band),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        // Vosk hears words, and naming the one it heard
                        // instead says what went wrong.
                        if (heard != null &&
                            !heard.wasSkipped &&
                            heard.spoken.toLowerCase() != _word.toLowerCase())
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'You said: "${heard.spoken}"',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ] else if (result != null) ...[
                        // A result with no score: the recognizer came back
                        // empty. Silence and a dead mic are two ways to get
                        // here, and so is an attempt that matched nothing in
                        // the shortlist (see [_vocabulary]) -- Vosk answers
                        // those with its
                        // unknown-word token, which [VoskAsr] strips. Naming
                        // the mic would send the learner to fix the one cause
                        // that usually is not the problem.
                        Text(
                          "Didn't catch that -- try again, a little slower.",
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ] else
                        Text(
                          player.isReady
                              ? 'Tap the word again to hear yourself'
                              : 'Tap the word to hear it',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      if (result != null) ...[
                        const SizedBox(height: 20),
                        AttemptPlaybackBar(
                          player: _attemptPlayer,
                          onHearReference: () => player.toggle(_word),
                        ),
                      ],
                    ],
                  ),
                ),
                Row(
                  children: [
                    HearButton(text: _word, player: player),
                    if (widget.showsSyllables) ...[
                      const SizedBox(width: 12),
                      SlowHearButton(
                        text: _word,
                        player: player,
                        bySyllable: true,
                      ),
                    ],
                    const SizedBox(width: 16),
                    Expanded(
                      child: RecordButton(
                        isRecording: _isRecording,
                        isScoring: _isScoring,
                        hasPreviousAttempt: result != null,
                        onRecordStart: _startRecording,
                        onRecordStop: _stopAndScoreRecording,
                        onRecordCancel: _cancelRecording,
                      ),
                    ),
                  ],
                ),
                // Single-word mode has no "Done" button -- the learner drills
                // the same word for as long as they want and leaves via the
                // back arrow. Only the drill (Word Rematch) advances through
                // a set and needs this.
                if (widget.isDrill) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _handleAdvance,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(advanceLabel),
                        const SizedBox(width: 8),
                        Icon(advanceIcon, size: 18),
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
