import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/lingo_theme.dart';

/// A two-sided card that turns over when [showBack] changes: [front] until
/// then, [back] after. Only the face turned toward the learner is built, so
/// what is on the other side is never on screen -- the Recall card's back
/// does not show the prompt, and its front does not give the answer away.
///
/// The turn is a rotation about the vertical axis with a little perspective:
/// the front turns away to edge-on, then the back turns in from edge-on, so
/// neither face is ever seen mirrored.
///
/// Once turned over, a sideways swipe turns it back to the front for a look
/// at the prompt, and another swipe returns to the back -- a peek, not a
/// change of [showBack]: nothing the card belongs to is undone.
class FlashCard extends StatefulWidget {
  const FlashCard({
    required this.front,
    required this.back,
    required this.showBack,
    this.onTapFront,
    this.onShownBack,
    super.key,
  });

  final Widget front;
  final Widget back;
  final bool showBack;

  /// Tapping the front, e.g. to turn it over. Null leaves it untappable.
  final VoidCallback? onTapFront;

  /// Called once the card has finished turning to its back because
  /// [showBack] became true -- not after a peek at the front and back.
  final VoidCallback? onShownBack;

  /// How fast a sideways swipe must be to count, in logical pixels/second.
  static const double _swipeVelocity = 200;

  static const Duration flipDuration = Duration(milliseconds: 420);

  @override
  State<FlashCard> createState() => _FlashCardState();
}

class _FlashCardState extends State<FlashCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: FlashCard.flipDuration,
    value: widget.showBack ? 1 : 0,
  );
  late final Animation<double> _angle = CurvedAnimation(
    parent: _turn,
    curve: Curves.easeInOutCubic,
  ).drive(Tween(begin: 0.0, end: math.pi));

  /// Turned back to the front by a swipe while [FlashCard.showBack].
  bool _peeking = false;

  @override
  void didUpdateWidget(FlashCard old) {
    super.didUpdateWidget(old);
    if (widget.showBack != old.showBack) {
      _peeking = false;
      if (widget.showBack) {
        _turn.forward().then((_) {
          if (mounted && widget.showBack && !_peeking) {
            widget.onShownBack?.call();
          }
        });
      } else {
        _turn.reverse();
      }
    }
  }

  void _onSwipe(DragEndDetails details) {
    if (!widget.showBack) return;
    if ((details.primaryVelocity ?? 0).abs() < FlashCard._swipeVelocity) {
      return;
    }
    setState(() => _peeking = !_peeking);
    _peeking ? _turn.reverse() : _turn.forward();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _angle,
      builder: (context, _) {
        final angle = _angle.value;
        final showingBack = angle > math.pi / 2;
        // The back turns in from edge-on (-90°) to flat (0°) rather than
        // continuing on to 180°, which would show it mirrored.
        final rotation = showingBack ? angle - math.pi : angle;
        final face = showingBack
            ? _Face(key: const ValueKey('back'), child: widget.back)
            : _Face(
                key: const ValueKey('front'),
                onTap: widget.onTapFront,
                child: widget.front,
              );
        final card = Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(rotation),
          child: face,
        );
        if (!widget.showBack) return card;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: _onSwipe,
          child: card,
        );
      },
    );
  }
}

/// One side: the white rounded card the redesigned screens use, tall enough
/// to read as a card even with one short word on it.
class _Face extends StatelessWidget {
  const _Face({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 240),
      decoration: lingoCardDecoration(radius: 28),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    );
  }
}

/// The small rounded tag in a card's top corner naming its side's language.
class CardSideTag extends StatelessWidget {
  const CardSideTag(this.label, {this.filled = false, super.key});

  final String label;

  /// The back's tag is solid, the front's tinted, so the sides read apart
  /// at a glance.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? LingoColors.indigo : LingoColors.indigoContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: lingoFont(
          size: 10,
          weight: FontWeight.w800,
          color: filled ? Colors.white : LingoColors.indigo,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
