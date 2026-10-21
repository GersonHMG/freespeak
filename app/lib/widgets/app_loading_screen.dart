import 'package:flutter/material.dart';

/// Full branded loading screen: an app-mark tile, title/subtitle, three
/// staggered pulsing dots, and an indeterminate progress bar sliding along
/// the bottom.
class AppLoadingScreen extends StatefulWidget {
  const AppLoadingScreen({
    super.key,
    this.title = 'Free Speak',
    this.subtitle = 'Warming up your lesson…',
  });

  final String title;
  final String subtitle;

  @override
  State<AppLoadingScreen> createState() => _AppLoadingScreenState();
}

class _AppLoadingScreenState extends State<AppLoadingScreen>
    with TickerProviderStateMixin {
  static const _background = Color(0xFFF2F1F7);
  static const _mark = Color(0xFF4D5A86);
  static const _titleColor = Color(0xFF1C1C28);
  static const _subtitleColor = Color(0xFF8A8AA0);
  static const _track = Color(0xFFDCDBEC);

  static const _dotDuration = Duration(milliseconds: 1100);
  static const _barDuration = Duration(milliseconds: 1600);
  static const _dotStagger = Duration(milliseconds: 150);

  late final AnimationController _dotsController = AnimationController(
    vsync: this,
    duration: _dotDuration,
  )..repeat();

  late final AnimationController _barController = AnimationController(
    vsync: this,
    duration: _barDuration,
  )..repeat();

  // Mirrors the CSS keyframes translateX(-100% -> 20% -> 220%), which are
  // fractions of the fill bar's own width, matching FractionalTranslation.
  late final Animation<double> _barPosition = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: -1.0,
        end: 0.2,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.2,
        end: 2.2,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 50,
    ),
  ]).animate(_barController);

  @override
  void dispose() {
    _dotsController.dispose();
    _barController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _AppMark(),
                const SizedBox(height: 28),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _titleColor,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _subtitleColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PulsingDot(
                      controller: _dotsController,
                      delay: Duration.zero,
                    ),
                    const SizedBox(width: 10),
                    _PulsingDot(
                      controller: _dotsController,
                      delay: _dotStagger,
                    ),
                    const SizedBox(width: 10),
                    _PulsingDot(
                      controller: _dotsController,
                      delay: _dotStagger * 2,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 64,
            child: Center(
              child: SizedBox(
                width: 180,
                height: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: ColoredBox(
                    color: _track,
                    child: AnimatedBuilder(
                      animation: _barPosition,
                      builder: (context, child) => FractionalTranslation(
                        translation: Offset(_barPosition.value, 0),
                        child: child,
                      ),
                      child: FractionallySizedBox(
                        widthFactor: 0.6,
                        heightFactor: 1,
                        alignment: Alignment.centerLeft,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _mark,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rounded-square app mark: the launcher icon itself, so the first
/// thing on screen matches what the learner just tapped.
class _AppMark extends StatelessWidget {
  const _AppMark();

  /// The icon's own teal, for its glow.
  static const _brand = Color(0xFF1CC4D1);
  static const double _size = 88;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _brand.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.asset(
          'assets/branding/icon.png',
          // The source is 1024px; decode it at the size it is drawn.
          cacheWidth: (_size * MediaQuery.devicePixelRatioOf(context)).round(),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// One dot of the three-dot loader, breathing between 35%/100% opacity and
/// 85%/100% scale on an 1.1s loop, offset from its siblings by [delay].
class _PulsingDot extends StatelessWidget {
  const _PulsingDot({required this.controller, required this.delay});

  final AnimationController controller;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final delayFraction =
        delay.inMilliseconds / controller.duration!.inMilliseconds;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        var phase = controller.value - delayFraction;
        phase -= phase.floorToDouble();
        final wave = phase <= 0.5 ? phase / 0.5 : (1 - phase) / 0.5;
        final eased = Curves.easeInOut.transform(wave);
        return Opacity(
          opacity: 0.35 + 0.65 * eased,
          child: Transform.scale(scale: 0.85 + 0.15 * eased, child: child),
        );
      },
      child: const _Dot(),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Color(0xFF4D5A86),
        shape: BoxShape.circle,
      ),
    );
  }
}
