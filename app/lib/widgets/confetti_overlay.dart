// A brief, one-shot burst of falling confetti -- built from
// AnimationController + CustomPainter, the same way the rest of this app's
// animations are (see PulsingWordmark, SessionCompleteScreen's accuracy
// ring), rather than pulling in a third-party confetti package for one
// celebration screen.

import 'dart:math';

import 'package:flutter/material.dart';

class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key, this.onComplete});

  /// Called once, when the burst finishes -- lets the caller remove this
  /// widget instead of leaving a static, no-longer-animating overlay behind.
  final VoidCallback? onComplete;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  static const _pieceCount = 40;
  static const _colors = [
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  late final List<_ConfettiPiece> _pieces = _generatePieces();

  List<_ConfettiPiece> _generatePieces() {
    final random = Random();
    return [
      for (var i = 0; i < _pieceCount; i++)
        _ConfettiPiece(
          startX: random.nextDouble(),
          // Staggered starts, so the whole burst doesn't fall as one rigid
          // sheet -- each piece gets its own slice of the animation before
          // it starts moving.
          fallDelay: random.nextDouble() * 0.3,
          fallSpeed: 0.7 + random.nextDouble() * 0.5,
          drift: (random.nextDouble() - 0.5) * 0.4,
          spinSpeed: (random.nextDouble() - 0.5) * 8,
          size: 6 + random.nextDouble() * 6,
          color: _colors[random.nextInt(_colors.length)],
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onComplete?.call();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(
            pieces: _pieces,
            progress: _controller.value,
          ),
        ),
      ),
    );
  }
}

class _ConfettiPiece {
  const _ConfettiPiece({
    required this.startX,
    required this.fallDelay,
    required this.fallSpeed,
    required this.drift,
    required this.spinSpeed,
    required this.size,
    required this.color,
  });

  /// 0-1, fraction of the overlay's width.
  final double startX;

  /// 0-1, fraction of the animation this piece waits before it starts
  /// falling.
  final double fallDelay;

  final double fallSpeed;

  /// How far this piece sways side to side while falling, as a fraction of
  /// the overlay's width.
  final double drift;

  /// Full rotations over the piece's fall.
  final double spinSpeed;

  final double size;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.pieces, required this.progress});

  final List<_ConfettiPiece> pieces;

  /// 0-1, the overlay's own animation progress -- not each piece's, since
  /// pieces start at staggered offsets into it (see [_ConfettiPiece.fallDelay]).
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      final local = ((progress - piece.fallDelay) / (1 - piece.fallDelay))
          .clamp(0.0, 1.0);
      if (local <= 0) continue;

      final fallProgress = (local * piece.fallSpeed).clamp(0.0, 1.0);
      final y = fallProgress * size.height;
      final x =
          piece.startX * size.width +
          sin(fallProgress * pi * 2) * piece.drift * size.width * 0.5;

      // Fades out only in the last stretch, so a piece is fully visible for
      // most of its fall rather than dissolving the moment it starts.
      const fadeStart = 0.75;
      final opacity = local <= fadeStart
          ? 1.0
          : (1 - (local - fadeStart) / (1 - fadeStart)).clamp(0.0, 1.0);
      if (opacity <= 0) continue;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(local * piece.spinSpeed);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: piece.size,
          height: piece.size * 0.5,
        ),
        Paint()..color = piece.color.withValues(alpha: opacity),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
