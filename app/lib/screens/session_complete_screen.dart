// Shown once the learner has been through every phrase in the session --
// what they earned, and the way back to the home screen.
//
// The trophy's entrance, the accuracy ring filling in, and the points
// counting up are the same idea PulsingWordmark uses for the loader (an
// AnimationController driving a Tween via CurvedAnimation, no external
// package), but one-shot rather than looping: a completion screen should
// read as "done," not "still working."

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/daily_activity.dart';
import '../data/practice_history_scope.dart';
import '../scoring/feedback_sounds.dart';
import '../widgets/confetti_overlay.dart';

/// The session summary screen: accuracy, how many sentences were
/// attempted, and a way back to [HomeScreen].
class SessionCompleteScreen extends StatefulWidget {
  const SessionCompleteScreen({
    required this.totalPoints,
    required this.maxPossible,
    required this.sentencesAttempted,
    required this.totalPhrases,
    required this.cardsTodayBeforeSession,
    this.awardsPoints = true,
    super.key,
  });

  /// Sum of every sentence's earned points this session -- see
  /// [SessionScore.totalPoints].
  final int totalPoints;

  /// What [totalPoints] would be had every attempt made scored 100% -- see
  /// [SessionScore.maxPossible]. Zero when nothing was ever recorded (every
  /// phrase was skipped unattempted), in which case there is no percentage
  /// to show, and the accuracy ring stays empty.
  final int maxPossible;

  /// How many distinct sentences got at least one recorded attempt.
  final int sentencesAttempted;

  /// The size of the phrase set the learner just finished.
  final int totalPhrases;

  /// Points already earned today, snapshotted before this session's own
  /// attempts were recorded -- what tells "this session is the one that
  /// crossed the daily goal" apart from "the goal was already met earlier
  /// today," so the goal-reached celebration fires at most once per day.
  final int cardsTodayBeforeSession;

  /// Whether this session's points actually counted toward the daily goal
  /// and streak -- off for a Practice-tab session (see
  /// [SessionScreen.awardsPoints]), which suppresses the "pts" framing and
  /// the daily-goal celebration, since neither happened.
  final bool awardsPoints;

  @override
  State<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends State<SessionCompleteScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..forward();

  // The trophy lands first, quick and springy...
  late final Animation<double> _trophyScale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.55, curve: Curves.elasticOut),
  );
  late final Animation<double> _trophyFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.35, curve: Curves.easeOut),
  );

  // ...and the points count up, and the accuracy ring fills in step with
  // them, while it settles -- one motion instead of three competing ones.
  late final Animation<double> _pointsProgress = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
  );

  // Own player, not SessionScreen's -- that one is disposed the moment this
  // screen replaces it, so the completion cue needs a player that outlives
  // it.
  final FeedbackSoundPlayer _sound = FeedbackSoundPlayer();

  // The counting cue starts when the points/ring animation actually starts
  // moving (see _pointsProgress's Interval, below) rather than at t=0 --
  // guarded so the once-past-the-threshold listener only ever fires it once.
  bool _startedCountingSound = false;

  // Whether today's goal is met as of this session finishing -- drives the
  // persistent "you've hit today's goal" text, shown every session made
  // after the goal is reached, not just the one that reached it.
  bool? _goalMetToday;

  // Whether *this session* is the one that pushed today's cards from below
  // the goal to at or past it -- drives the one-time celebration (sound +
  // confetti). Compared against [SessionCompleteScreen.cardsTodayBeforeSession]
  // so hitting an already-met goal again later the same day stays quiet.
  bool? _justReachedGoal;

  bool _startedGoalCheck = false;
  bool _celebrated = false;
  bool _showConfetti = false;

  @override
  void initState() {
    super.initState();
    // Neither cue plays here at t=0 any more -- both wait for the count
    // animation to actually finish. See _maybeCelebrate.
    _controller.addListener(_maybeStartCountingSound);
    _controller.addStatusListener(_onControllerStatusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only ever want this fetch to fire once; didChangeDependencies is where
    // the scope lookup is safe to do, but re-querying on every rebuild is
    // not what "once" means.
    if (_startedGoalCheck) return;
    _startedGoalCheck = true;
    if (!widget.awardsPoints) {
      // This session never touched the daily goal, so there is nothing to
      // check -- and nothing to celebrate.
      setState(() {
        _goalMetToday = false;
        _justReachedGoal = false;
      });
      _maybeCelebrate();
      return;
    }
    loadDailyActivity(PracticeHistoryScope.of(context))
        .then((activity) {
          if (!mounted) return;
          final metToday = activity.cardsToday >= kDefaultDailyGoalTarget;
          final metBeforeThisSession =
              widget.cardsTodayBeforeSession >= kDefaultDailyGoalTarget;
          setState(() {
            _goalMetToday = metToday;
            _justReachedGoal = metToday && !metBeforeThisSession;
          });
          _maybeCelebrate();
        })
        .catchError((Object err) {
          // Fail closed -- a lookup failure should be silence, not a
          // celebration for a goal that was never confirmed reached.
          debugPrint(
            '[SessionCompleteScreen] daily activity lookup failed: $err',
          );
          setState(() {
            _goalMetToday = false;
            _justReachedGoal = false;
          });
        });
  }

  void _maybeStartCountingSound() {
    if (_startedCountingSound || _controller.value < 0.35) return;
    _startedCountingSound = true;
    _sound.playCounting();
  }

  void _onControllerStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) _maybeCelebrate();
  }

  /// Plays the finish cue -- and, if *this session* is the one that just
  /// pushed today's points past the goal, the goal-reached cue and a
  /// confetti burst -- once both the count animation has finished and the
  /// daily-goal lookup has resolved, whichever comes last. Guarded so it
  /// only ever fires once, and never again for a goal already met earlier
  /// today.
  void _maybeCelebrate() {
    if (_celebrated) return;
    if (_controller.status != AnimationStatus.completed) return;
    final justReachedGoal = _justReachedGoal;
    if (justReachedGoal == null) return; // still waiting on the lookup

    _celebrated = true;
    _sound.playSessionFinish();
    if (justReachedGoal) {
      _sound.playGoalReached();
      setState(() => _showConfetti = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _sound.dispose();
    super.dispose();
  }

  double get _accuracy =>
      widget.maxPossible > 0 ? widget.totalPoints / widget.maxPossible : 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasAttempts = widget.maxPossible > 0;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Session Complete!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 32),
                    FadeTransition(
                      opacity: _trophyFade,
                      child: SizedBox(
                        width: 148,
                        height: 148,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _pointsProgress,
                              builder: (context, _) => CustomPaint(
                                size: const Size.square(148),
                                painter: _AccuracyRingPainter(
                                  progress: _accuracy * _pointsProgress.value,
                                  trackColor: colors.surfaceContainerHighest,
                                ),
                              ),
                            ),
                            ScaleTransition(
                              scale: _trophyScale,
                              child: CircleAvatar(
                                radius: 56,
                                backgroundColor: colors.primaryContainer,
                                child: Icon(
                                  Icons.emoji_events_rounded,
                                  size: 56,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    AnimatedBuilder(
                      animation: _pointsProgress,
                      builder: (context, _) {
                        // Accuracy is the headline: the app counts cards, not
                        // points (the points behind it only weight accuracy
                        // by difficulty).
                        final label =
                            '${(_accuracy * 100 * _pointsProgress.value).round()}%';
                        return Text(
                          label,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    FadeTransition(
                      opacity: _pointsProgress,
                      child: Text(
                        !hasAttempts
                            ? 'No attempts recorded this session'
                            : widget.awardsPoints
                            ? 'average accuracy'
                            : 'Practice session -- not counted toward your daily goal',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FadeTransition(
                      opacity: _pointsProgress,
                      child: Text(
                        '${widget.sentencesAttempted} / ${widget.totalPhrases} '
                        'sentences practiced',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (_goalMetToday == true) ...[
                      const SizedBox(height: 16),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 400),
                        builder: (context, opacity, child) =>
                            Opacity(opacity: opacity, child: child),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.emoji_events_rounded,
                                size: 18,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "You've hit today's daily goal!",
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 48),
                    FilledButton(
                      // Pops every route on the practice Navigator up to and
                      // including HomeScreen -- see LoadingScreen, which builds
                      // HomeScreen as that Navigator's first (and only fixed)
                      // route.
                      onPressed: () =>
                          Navigator.of(context)
                              .popUntil((route) => route.isFirst),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        child: Text('Back to Home'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showConfetti)
            Positioned.fill(
              child: ConfettiOverlay(
                onComplete: () {
                  if (mounted) setState(() => _showConfetti = false);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The ring around the trophy: a full [trackColor] circle underneath, and a
/// solid-coloured arc on top running clockwise from the top, [progress] of
/// the way around -- empty at 0% accuracy, a complete circle at 100%.
///
/// The arc's colour is [progress] itself read off a red -> orange -> yellow
/// -> green scale (see [_colorForAccuracy]), the same value at every point
/// around the arc -- a 30% ring is solid orange-red all the way along, not a
/// gradient that happens to still be red-ish at the 30% mark. Low accuracy
/// reads as "the ring is red," not "the ring hasn't reached green yet."
class _AccuracyRingPainter extends CustomPainter {
  const _AccuracyRingPainter({
    required this.progress,
    required this.trackColor,
    this.strokeWidth = 10,
  });

  /// 0-1. How far around the circle the coloured arc reaches, and what
  /// picks its colour.
  final double progress;

  final Color trackColor;
  final double strokeWidth;

  static const double _twoPi = 2 * math.pi;
  static const double _startAngle = -math.pi / 2; // 12 o'clock

  // Accuracy -> colour, at the stops the design calls out explicitly: 0% red,
  // 25% orange, 50% yellow, 100% green. Between two stops the colour is a
  // straight lerp, so e.g. 75% lands two-thirds of the way from yellow to
  // green.
  static const List<double> _stops = [0, 0.25, 0.5, 1];
  static const List<Color> _stopColors = [
    Color(0xFFE53935), // red, at 0%
    Color(0xFFFB8C00), // orange, at 25%
    Color(0xFFFDD835), // yellow, at 50%
    Color(0xFF43A047), // green, at 100%
  ];

  static Color _colorForAccuracy(double accuracy) {
    final t = accuracy.clamp(0.0, 1.0);
    for (var i = 0; i < _stops.length - 1; i++) {
      final upper = _stops[i + 1];
      if (t <= upper) {
        final lower = _stops[i];
        final localT = (t - lower) / (upper - lower);
        return Color.lerp(_stopColors[i], _stopColors[i + 1], localT)!;
      }
    }
    return _stopColors.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final ringRect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;

    final arcPaint = Paint()
      ..color = _colorForAccuracy(clamped)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(ringRect, _startAngle, _twoPi * clamped, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _AccuracyRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.trackColor != trackColor;
}
