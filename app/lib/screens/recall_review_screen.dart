import 'dart:async';

import 'package:flutter/material.dart';

import '../data/practice_history_scope.dart';
import '../decks/answer_match.dart';
import '../decks/deck_models.dart';
import '../decks/deck_store_scope.dart';
import '../decks/languages.dart';
import '../decks/recall_settings.dart';
import '../decks/review_session.dart';
import '../pronunciation/pronunciation_result.dart';
import '../pronunciation/pronunciation_scope.dart';
import '../pronunciation/recorder.dart';
import '../scoring/feedback_sounds.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';
import '../scoring/sentence_score.dart';
import '../tts/phonon_tts_scope.dart';
import '../tts/phrase_player.dart';
import '../theme/lingo_theme.dart';
import '../widgets/confetti_overlay.dart';
import '../widgets/copy_text_button.dart';
import '../widgets/flash_card.dart';
import '../widgets/grade_buttons.dart';
import '../widgets/hear_button.dart';
import '../widgets/mode_badge.dart';
import '../widgets/own_answers.dart';
import '../widgets/record_button.dart';
import '../widgets/review_done_view.dart';
import '../widgets/spoken_text.dart';
import '../widgets/warning_sound.dart';

/// Recall mode: today's Recall cards for one deck, each in three steps.
///
///  1. **Answer.** The learner sees the prompt in their language and writes
///     their own English version -- typed, or dictated with the mic in the
///     field (speech to text only: nothing is scored) -- and sends it, which
///     turns the card over. "I don't know" turns it over too, and grades it
///     Wrong on the spot: there is nothing to compare.
///  2. **Grade.** They compare with the reference translations and grade
///     themselves, answering "How close was your answer?". The app never decides whether a translation is right: a
///     sentence has many valid wordings, and the references are examples,
///     not an answer key. There is no going back to answer again -- the
///     first answer is the honest one.
///  3. **Say it.** The graded card stays turned over and asks the learner to
///     say its primary reference aloud: hold to record, as many tries as
///     they like, each scored like a pronunciation session (coloured words,
///     a percentage). "Next card" moves on, tried or not. Attempts are kept
///     for the mispronounced-word lists but do not count toward the daily
///     goal: the card already did.
///
/// The card's back lists the deck's references and then the learner's own
/// ways to say it ([Note.ownReferences]): "Add another way" writes one --
/// starting from the learner's own answer when the card does not have it
/// yet -- and a long press on one of theirs removes it. They are shown beside the references, never checked
/// against.
///
/// The card itself is a [FlashCard]: the front holds the prompt, the back
/// the reference translations -- and only those, so turning it over hides
/// the prompt, as a paper card would. The learner's typed answer sits below
/// the card, not on it.
///
/// Leaving with cards still to go asks first. Every grade is already saved,
/// so nothing is lost -- but walking out of a sitting by an accidental back
/// gesture is easy, and the cards left would only show up again tomorrow.
///
/// The daily sitting comes in rounds of [ReviewSession.roundLength] cards.
/// Finishing one -- or a custom session -- sets off confetti and a
/// celebration cue, and shows how it went (see [ReviewDoneView]).
///
/// Queue and grading are [ReviewSession]'s.
class RecallReviewScreen extends StatefulWidget {
  /// Today's cards for [deckId], then more, until the deck runs out.
  const RecallReviewScreen({required this.deckId, super.key})
    : customCards = null;

  /// A custom session over [cards]: practice only, so grades are logged but
  /// no due date moves (see ReviewSession.practice).
  const RecallReviewScreen.custom({
    required this.deckId,
    required List<StudyCard> cards,
    super.key,
  }) : customCards = cards;

  final int deckId;

  /// The cards of a custom session, or null for the daily one.
  final List<StudyCard>? customCards;

  @override
  State<RecallReviewScreen> createState() => _RecallReviewScreenState();
}

/// What the learner gave before the references were shown: their answer,
/// typed or dictated, or nothing ("I don't know").
class _Answer {
  const _Answer(this.text, {this.input = AnswerInput.typed});

  final String? text;

  /// Spoken when any of [text] came from dictation.
  final AnswerInput input;
}

class _RecallReviewScreenState extends State<RecallReviewScreen> {
  final PronunciationRecorder _recorder = PronunciationRecorder();
  final FeedbackSoundPlayer _feedbackSound = FeedbackSoundPlayer();
  final TextEditingController _typed = TextEditingController();
  PhrasePlayer? _player;
  ReviewSession? _session;

  /// Null while answering; set once the references are revealed.
  _Answer? _answer;

  /// Dictating into the answer field: recording, then turning the
  /// recording into text. [_dictated] remembers that some of the field
  /// came from the mic.
  bool _isDictating = false;
  bool _isTranscribing = false;
  bool _dictated = false;

  /// The card just graded, while its "say it" step is showing. The session
  /// has already moved its queue past it.
  StudyCard? _sayIt;

  /// The last scored attempt at [_sayIt]'s reference.
  PronunciationResult? _result;
  bool _isRecording = false;
  bool _isScoring = false;

  /// Counts cards shown, so each new one starts face up without turning --
  /// [FlashCard] is keyed by it.
  int _turn = 0;

  /// The confetti over a session just finished, until it has fallen.
  bool _celebrating = false;

  /// The learner's own ways to say it, by note, as changed this sitting --
  /// the session's cards were loaded before, and a card graded Wrong comes
  /// back as the same loaded copy.
  final Map<int, List<String>> _own = {};

  List<String> _ownFor(Note note) => _own[note.id] ?? note.ownReferences;

  Future<void> _addOwn(Note note, String text) async {
    final added = await saveOwnAnswer(
      context,
      DeckStoreScope.of(context),
      note.id,
      text,
    );
    if (!added || !mounted) return;
    setState(() => _own[note.id] = [..._ownFor(note), text.trim()]);
  }

  /// Whether the card already has [text] as a way to say it.
  bool _knows(Note note, String text) => [
    ...note.references,
    ..._ownFor(note),
  ].any((ref) => answerKey(ref) == answerKey(text));

  /// The grade [answer] pre-selects, from how closely it follows one of the
  /// card's ways to say it (see answer_match.dart) -- the learner's own
  /// included, so one they just saved counts at once. Null for "I don't
  /// know", and wherever wording alone cannot tell.
  Grade? _suggestionFor(Note note, _Answer answer) {
    final text = answer.text;
    if (text == null) return null;
    return matchAnswer(text, [
      ...note.references,
      ..._ownFor(note),
    ])?.suggestedGrade;
  }

  Future<void> _askForOwn(Note note) async {
    final typed = _answer?.text;
    final text = await askForOwnAnswer(
      context,
      _target,
      initial: typed != null && !_knows(note, typed) ? typed : null,
    );
    if (text != null && mounted) await _addOwn(note, text);
  }

  Future<void> _removeOwn(Note note, String text) async {
    final store = DeckStoreScope.of(context);
    if (!await confirmRemoveOwnAnswer(context, text) || !mounted) return;
    try {
      await store.removeOwnReference(note.id, text);
      if (!mounted) return;
      setState(
        () => _own[note.id] = [
          for (final own in _ownFor(note))
            if (own != text) own,
        ],
      );
    } catch (err) {
      debugPrint('[RecallReviewScreen] removing an answer failed: $err');
      if (mounted) _showMessage('Could not remove that. Try again.');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _player ??= PhrasePlayer(PhononTtsScope.of(context));
    if (_session == null) {
      final store = DeckStoreScope.of(context);
      final custom = widget.customCards;
      _session = custom == null
          ? ReviewSession(store, deckId: widget.deckId)
          : ReviewSession.practice(store, deckId: widget.deckId, cards: custom);
      _session!.load();
    }
  }

  @override
  void dispose() {
    if (_isDictating) _recorder.cancel();
    _player?.dispose();
    _session?.dispose();
    _recorder.dispose();
    _feedbackSound.dispose();
    _typed.dispose();
    super.dispose();
  }

  void _submitTyped() {
    final text = _typed.text.trim();
    if (text.isEmpty || _isDictating || _isTranscribing) return;
    FocusScope.of(context).unfocus();
    setState(
      () => _answer = _Answer(
        text,
        input: _dictated ? AnswerInput.spoken : AnswerInput.typed,
      ),
    );
  }

  /// "I don't know": the card turns over and is graded Wrong at once --
  /// there is no answer to compare, so no question to ask -- and goes
  /// straight to its "say it" step.
  Future<void> _dontKnow() async {
    unawaited(GradeButtons.playCue(Grade.difficult));
    if (_isDictating) _recorder.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _isDictating = false;
      _answer = const _Answer(null);
    });
    await _grade(Grade.difficult);
  }

  /// Mic in the answer field: the first tap starts listening, the second
  /// stops and writes what was heard into the field, after anything
  /// already there, to be edited before sending.
  Future<void> _toggleDictation() async {
    if (_isTranscribing) return;
    if (!_isDictating) {
      await _player?.stop();
      final started = await _recorder.start(slot: 'answer-$_turn');
      if (!mounted) return;
      if (!started) {
        _showMessage('Microphone permission is needed to hear you.');
        return;
      }
      setState(() => _isDictating = true);
      return;
    }

    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _isDictating = false;
      _isTranscribing = path != null;
    });
    if (path == null) {
      _showMessage('That was too short — tap the mic, speak, then tap again.');
      return;
    }
    try {
      final (_, transcript) = await PronunciationScope.of(context)
          .transcribe(path);
      if (!mounted) return;
      setState(() => _isTranscribing = false);
      final heard = transcript.text.trim();
      if (heard.isEmpty) {
        _showMessage("Didn't catch that — try again.");
        return;
      }
      final text = '${_typed.text.trim()} $heard'.trim();
      _typed.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _dictated = true;
    } catch (err) {
      debugPrint('[RecallReviewScreen] dictation failed: $err');
      if (!mounted) return;
      setState(() => _isTranscribing = false);
      _showMessage('Could not hear that. Try again in a moment.');
    }
  }

  Future<void> _grade(Grade grade) async {
    final answer = _answer;
    final session = _session!;
    final card = session.current;
    if (answer == null || card == null || session.isSaving) return;
    try {
      await session.grade(
        grade,
        input: answer.input,
        suggestedGrade: _suggestionFor(card.note, answer),
        answerText: answer.text,
      );
      if (!mounted) return;
      setState(() {
        _sayIt = card;
        _result = null;
      });
    } catch (err) {
      debugPrint('[RecallReviewScreen] saving the review failed: $err');
      if (mounted) _showMessage('Could not save that grade. Try again.');
    }
  }

  /// The card has turned to its back: say the main reference aloud, so the
  /// learner hears how it sounds before grading or saying it themselves --
  /// unless Settings turned that off ([speakOnFlip]).
  void _speakReference() {
    final card = _sayIt ?? _session?.current;
    if (!speakOnFlip.value) return;
    if (card == null || _isDictating || _isRecording) return;
    unawaited(_player?.play(card.note.primaryReference));
  }

  /// Ends the "say it" step: on to the next card, or the done view --
  /// celebrated, when it ends a session that showed any cards.
  void _next() {
    if (_isRecording) _recorder.cancel();
    _player?.stop();
    _typed.clear();
    _dictated = false;
    final session = _session!;
    final finished = session.current == null && session.reviewed > 0;
    if (finished) unawaited(_feedbackSound.playCelebration());
    setState(() {
      _celebrating = finished;
      _sayIt = null;
      _answer = null;
      _result = null;
      _isRecording = false;
      _turn++;
      _player?.reset();
    });
  }

  /// Another round of the daily sitting, from the done view.
  void _keepGoing() {
    setState(() => _celebrating = false);
    _session!.keepGoing();
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isScoring) return;
    await _player?.stop();
    final started = await _recorder.start(slot: _turn);
    if (!mounted) return;
    if (!started) {
      _showMessage('Microphone permission is needed to hear you.');
      return;
    }
    setState(() => _isRecording = true);
  }

  void _cancelRecording() {
    if (!_isRecording) return;
    _recorder.cancel();
    setState(() => _isRecording = false);
  }

  Future<void> _stopAndScore() async {
    final card = _sayIt;
    if (!_isRecording || card == null) return;
    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isScoring = path != null;
    });
    if (path == null) {
      _showMessage('That was too short — hold while you speak.');
      return;
    }

    final phrase = card.note.primaryReference;
    try {
      final result = await PronunciationScope.of(context).score(path, phrase);
      if (!mounted || _sayIt != card) return;
      if (result.spokenText.isEmpty) {
        // Nothing heard is a microphone problem, not a 0% attempt.
        setState(() => _isScoring = false);
        _showMessage("Didn't catch that — try again.");
        return;
      }
      final score = rateSentence(result, phrase);
      unawaited(_feedbackSound.playFor(score.band));
      unawaited(
        PracticeHistoryScope.of(context)
            .recordAttempt(result: result, score: score, awardsPoints: false)
            .catchError((Object err) {
              debugPrint('[RecallReviewScreen] failed to save attempt: $err');
            }),
      );
      setState(() {
        _result = result;
        _isScoring = false;
      });
    } catch (err) {
      debugPrint('[RecallReviewScreen] scoring failed: $err');
      if (!mounted) return;
      setState(() => _isScoring = false);
      _showMessage('Could not score that attempt. Try again in a moment.');
    }
  }

  Future<void> _confirmExit() async {
    playWarningSound();
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave session?'),
        content: const Text('Cards you graded are saved.'),
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

  /// The deck's target language, for labels -- whatever the deck says.
  String get _target =>
      languageName(_session?.deck?.targetLang ?? kDefaultTargetLang);

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session!,
      // Only a sitting with cards left asks before leaving: there is nothing
      // to walk out of while loading, or once the done view is showing.
      builder: (context, child) => PopScope(
        canPop: _session!.current == null && _sayIt == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmExit();
        },
        child: child!,
      ),
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          title: ModeBadge(
            label: widget.customCards == null ? 'RECALL' : 'CUSTOM',
          ),
        ),
        body: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ListenableBuilder(
                  listenable: _session!,
                  builder: (context, _) {
                    final session = _session!;
                    if (!session.isLoaded) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final sayIt = _sayIt;
                    final card = sayIt ?? session.current;
                    if (card == null) {
                      return ReviewDoneView(
                        reviewed: session.reviewed,
                        grades: session.grades,
                        isCustom: session.isPractice,
                        hasMore: session.hasMore,
                        onKeepGoing: _keepGoing,
                      );
                    }
                    final answer = _answer;
                    return Column(
                      children: [
                        Text(
                          '${session.remaining} left',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 16),
                                FlashCard(
                                  key: ValueKey(_turn),
                                  showBack: answer != null,
                                  onShownBack: _speakReference,
                                  front: _CardFront(
                                    text: card.note.nativeText,
                                    targetLanguage: _target,
                                  ),
                                  back: _CardBack(
                                    references: card.note.references,
                                    own: _ownFor(card.note),
                                    targetLanguage: _target,
                                    player: _player!,
                                    onAdd: () => _askForOwn(card.note),
                                    onRemove: (text) =>
                                        _removeOwn(card.note, text),
                                  ),
                                ),
                                if (answer != null) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.swipe_rounded,
                                        size: 16,
                                        color: LingoColors.mutedInk,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Swipe the card to see the question',
                                        style: lingoFont(
                                          size: 12,
                                          weight: FontWeight.w500,
                                          color: LingoColors.mutedInk,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (sayIt != null) ...[
                                  const SizedBox(height: 20),
                                  _SayIt(
                                    phrase: sayIt.note.primaryReference,
                                    result: _result,
                                  ),
                                ] else if (answer?.text != null) ...[
                                  const SizedBox(height: 20),
                                  _YourAnswer(
                                    text: answer!.text!,
                                    known: _knows(card.note, answer.text!),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (sayIt != null)
                          _sayItControls()
                        else if (answer == null)
                          _answerControls()
                        else ...[
                          const _GradeQuestion(),
                          const SizedBox(height: 12),
                          GradeButtons(
                            suggested: _suggestionFor(card.note, answer),
                            onGrade: session.isSaving ? (_) {} : _grade,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            if (_celebrating)
              Positioned.fill(
                child: ConfettiOverlay(
                  onComplete: () {
                    if (mounted) setState(() => _celebrating = false);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _answerControls() {
    return Column(
      children: [
        Container(
          decoration: lingoCardDecoration(radius: 18),
          child: TextField(
            controller: _typed,
            // Grows with the answer, up to five lines, then scrolls -- a
            // long or dictated answer stays readable and editable. Still
            // the single-line keyboard, so its key sends rather than
            // adding a line break.
            minLines: 1,
            maxLines: 5,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitTyped(),
            style: lingoFont(size: 16, weight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: _isDictating
                  ? 'Listening… tap the mic when done'
                  : _isTranscribing
                  ? 'Writing down what you said…'
                  : 'Type or say it in $_target',
              hintStyle: lingoFont(
                size: 16,
                weight: FontWeight.w500,
                color: LingoColors.mutedInk,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
              suffixIcon: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isTranscribing
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: _isDictating ? 'Stop' : 'Dictate',
                            color: _isDictating
                                ? LingoColors.onErrorContainer
                                : LingoColors.indigo,
                            icon: Icon(
                              _isDictating
                                  ? Icons.stop_circle_rounded
                                  : Icons.mic_rounded,
                            ),
                            onPressed: _toggleDictation,
                          ),
                    IconButton.filled(
                      tooltip: 'Check',
                      style: IconButton.styleFrom(
                        backgroundColor: LingoColors.indigo,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded),
                      onPressed: _submitTyped,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _PillButton(
            icon: Icons.help_outline_rounded,
            label: "I don't know",
            onPressed: _isTranscribing ? null : _dontKnow,
          ),
        ),
      ],
    );
  }

  Widget _sayItControls() {
    return Row(
      children: [
        _PillButton(
          icon: Icons.arrow_forward_rounded,
          label: 'Next card',
          onPressed: _isScoring ? null : _next,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: RecordButton(
            isRecording: _isRecording,
            isScoring: _isScoring,
            hasPreviousAttempt: _result != null,
            onRecordStart: _startRecording,
            onRecordStop: _stopAndScore,
            onRecordCancel: _cancelRecording,
          ),
        ),
      ],
    );
  }
}

/// A quiet secondary action -- I don't know, Next card -- as an
/// indigo-tinted pill, so it reads as a choice without competing with the
/// grade buttons or the record button.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: LingoColors.indigoContainer,
        foregroundColor: LingoColors.indigo,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: lingoFont(size: 14, weight: FontWeight.w700),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// The question the grade buttons answer, so Wrong / Partial / Perfect read
/// as a reply rather than a verdict to choose. Only an answer gets here:
/// "I don't know" is graded without asking.
class _GradeQuestion extends StatelessWidget {
  const _GradeQuestion();

  @override
  Widget build(BuildContext context) {
    return Text(
      'How close was your answer?',
      textAlign: TextAlign.center,
      style: lingoFont(size: 16, weight: FontWeight.w700),
    );
  }
}

/// The card's front: the prompt in the learner's language.
class _CardFront extends StatelessWidget {
  const _CardFront({required this.text, required this.targetLanguage});

  final String text;
  final String targetLanguage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Never names the prompt language -- see [kYourLanguage].
            const CardSideTag(kYourLanguage),
            const Spacer(),
            CopyTextButton(text: text, color: LingoColors.mutedInk),
          ],
        ),
        const SizedBox(height: 36),
        Text(
          text,
          textAlign: TextAlign.center,
          style: lingoFont(size: 26, weight: FontWeight.w800),
        ),
        const SizedBox(height: 36),
        Text(
          'HOW DO YOU SAY IT IN ${targetLanguage.toUpperCase()}?',
          textAlign: TextAlign.center,
          style: lingoFont(
            size: 11,
            weight: FontWeight.w700,
            color: LingoColors.mutedInk,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// The card's back: the ways to say it, and nothing in the native
/// language -- one at a time (see [_CardBackState]), with a button to add
/// another.
class _CardBack extends StatefulWidget {
  const _CardBack({
    required this.references,
    required this.own,
    required this.targetLanguage,
    required this.player,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> references;
  final List<String> own;
  final String targetLanguage;
  final PhrasePlayer player;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  /// How fast an up or down swipe must be to change the way shown, in
  /// logical pixels/second -- the same bar as the card's sideways swipe.
  static const double _swipeVelocity = 200;

  @override
  State<_CardBack> createState() => _CardBackState();
}

/// One way to say it at a time, at full size, rather than a list that
/// crowds the card: the deck's references, then the learner's own. Up and
/// down swipes, or the dots, move between them; sideways still turns the
/// card (FlashCard). Starts on the primary reference, the one read aloud.
class _CardBackState extends State<_CardBack> {
  int _index = 0;

  List<String> get _ways => [...widget.references, ...widget.own];

  @override
  void didUpdateWidget(_CardBack old) {
    super.didUpdateWidget(old);
    final count = widget.references.length + widget.own.length;
    if (widget.own.length > old.own.length) {
      // Just added: show it.
      _index = count - 1;
    } else if (_index >= count) {
      _index = count - 1;
    }
  }

  void _go(int index) {
    if (index < 0 || index >= _ways.length || index == _index) return;
    setState(() => _index = index);
  }

  void _onSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < _CardBack._swipeVelocity) return;
    // Up is the next one, as in a list.
    _go(velocity < 0 ? _index + 1 : _index - 1);
  }

  @override
  Widget build(BuildContext context) {
    final ways = _ways;
    final way = ways[_index];
    final isOwn = _index >= widget.references.length;
    final shown = Row(
      key: ValueKey(way),
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: way),
                if (isOwn) ...[
                  const WidgetSpan(child: SizedBox(width: 8)),
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: _YoursTag(),
                  ),
                ],
              ],
            ),
            style: lingoFont(size: 24, weight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 12),
        HearButton(text: way, player: widget.player),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CardSideTag(widget.targetLanguage, filled: true),
            const Spacer(),
            Text(
              ways.length == 1
                  ? 'ONE WAY TO SAY IT'
                  : 'WAY ${_index + 1} OF ${ways.length}',
              style: lingoFont(
                size: 10,
                weight: FontWeight.w700,
                color: LingoColors.mutedInk,
                letterSpacing: 1.2,
              ),
            ),
            // The way showing now, not the whole list.
            CopyTextButton(text: way, color: LingoColors.mutedInk),
          ],
        ),
        const SizedBox(height: 28),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragEnd: ways.length > 1 ? _onSwipe : null,
          onLongPress: isOwn ? () => widget.onRemove(way) : null,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.15),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, ?current],
              ),
              child: shown,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton.icon(
              onPressed: widget.onAdd,
              style: TextButton.styleFrom(
                foregroundColor: LingoColors.indigo,
                padding: EdgeInsets.zero,
                textStyle: lingoFont(size: 14, weight: FontWeight.w700),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add another way'),
            ),
            const Spacer(),
            if (ways.length > 1)
              _WayDots(count: ways.length, index: _index, onTap: _go),
          ],
        ),
      ],
    );
  }
}

/// Which way to say it is showing, one dot each; a tap on a dot shows it.
class _WayDots extends StatelessWidget {
  const _WayDots({
    required this.count,
    required this.index,
    required this.onTap,
  });

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            button: true,
            label: 'Way ${i + 1} of $count',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == index ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == index
                        ? LingoColors.indigo
                        : LingoColors.indigo.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Marks a way to say it as the learner's own. A long press removes it.
class _YoursTag extends StatelessWidget {
  const _YoursTag();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Yours. Press and hold to remove.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: LingoColors.indigoContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'YOURS',
          style: lingoFont(
            size: 9,
            weight: FontWeight.w800,
            color: LingoColors.indigo,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

/// A box under the card in the indigo tint, with a small heading -- what
/// "your answer" and "say it" are drawn in.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: LingoColors.indigoContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: lingoFont(
                    size: 11,
                    weight: FontWeight.w700,
                    color: LingoColors.mutedInk,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// What the learner typed, under the card.
///
/// A check says so when it is already one of the card's ways to say it;
/// otherwise "Add another way" on the card offers to save it.
class _YourAnswer extends StatelessWidget {
  const _YourAnswer({required this.text, required this.known});

  final String text;

  /// The card already has this wording (see answerKey).
  final bool known;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'YOUR ANSWER',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: lingoFont(size: 17, weight: FontWeight.w600)),
          if (known) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: LingoColors.indigo,
                ),
                const SizedBox(width: 6),
                Text(
                  'One of the ways to say it',
                  style: lingoFont(
                    size: 13,
                    weight: FontWeight.w600,
                    color: LingoColors.indigo,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The "say it" step: the sentence to say, coloured word by word once an
/// attempt is scored, with its score.
class _SayIt extends StatelessWidget {
  const _SayIt({required this.phrase, required this.result});

  final String phrase;
  final PronunciationResult? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = this.result;
    return _Panel(
      title: 'NOW SAY IT',
      trailing: result == null
          ? null
          : Text(
              '${result.overall}%',
              style: lingoFont(
                size: 15,
                weight: FontWeight.w800,
                color: colorForBand(
                  theme,
                  ScoreThresholds.standard.bandFor(result.overall.toDouble()),
                ),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpokenText(
            text: phrase,
            spokenWord: -1,
            result: result,
            style: lingoFont(size: 18, weight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            result == null
                ? 'Hold the microphone and say the sentence.'
                : 'Hold to try again, or go on to the next card.',
            style: lingoFont(
              size: 12,
              weight: FontWeight.w500,
              color: LingoColors.mutedInk,
            ),
          ),
        ],
      ),
    );
  }
}
