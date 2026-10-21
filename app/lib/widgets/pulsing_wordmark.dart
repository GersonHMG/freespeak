import 'package:flutter/material.dart';

/// The wordmark shown while the app is loading: it breathes in and out,
/// scaling and fading on a loop.
class PulsingWordmark extends StatefulWidget {
  const PulsingWordmark({super.key, this.label = 'Ag', this.size = 300});

  /// Text shown at the center.
  final String label;

  /// Pixel size of the (square) canvas.
  final double size;

  @override
  State<PulsingWordmark> createState() => _PulsingWordmarkState();
}

class _PulsingWordmarkState extends State<PulsingWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _pulse = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: Center(
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.5, end: 1).animate(_pulse),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.08).animate(_pulse),
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontSize: widget.size * 0.37,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
