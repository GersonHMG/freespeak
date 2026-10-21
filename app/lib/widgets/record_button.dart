import 'package:flutter/material.dart';

/// Records the user speaking the phrase, and reports back while the attempt
/// is being scored.
///
/// Hold to record, exactly as long as the phrase takes to say, then release
/// to stop and score. Dragging away before releasing cancels instead --
/// the same gesture a voice message uses, so a learner who changes their
/// mind mid-recording doesn't have to let a bad attempt get scored.
///
/// Scoring is a model run over the recording -- seconds, not milliseconds --
/// so it gets a state of its own. Without one the button springs back to
/// "Hold to record" the instant the learner stops speaking and the app looks
/// like it did nothing with what it just heard.
class RecordButton extends StatefulWidget {
  const RecordButton({
    super.key,
    required this.isRecording,
    required this.onRecordStart,
    required this.onRecordStop,
    required this.onRecordCancel,
    this.isScoring = false,
    this.hasPreviousAttempt = false,
  });

  final bool isRecording;
  final bool isScoring;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordStop;
  final VoidCallback onRecordCancel;

  /// Whether this phrase already has a scored attempt -- changes only the
  /// idle label, to "Try again", not the hold/slide/release mechanics.
  final bool hasPreviousAttempt;

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton> {
  // Past this many logical pixels of horizontal drag, releasing cancels
  // instead of scoring -- far enough that an unsteady hold while speaking
  // doesn't accidentally throw the attempt away.
  static const double _cancelThreshold = 72;
  static const _padding = EdgeInsets.symmetric(vertical: 18);

  // Tracked locally rather than derived from widget.isRecording: that prop
  // only flips once the async start() call resolves, which lags a fast
  // tap-and-release past this gesture's own pointer-up.
  bool _isDown = false;
  double _dragDx = 0;

  bool get _isCancelling => _isDown && _dragDx.abs() > _cancelThreshold;

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.isScoring || _isDown) return;
    setState(() {
      _isDown = true;
      _dragDx = 0;
    });
    widget.onRecordStart();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isDown) return;
    setState(() => _dragDx += event.delta.dx);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_isDown) return;
    final cancelling = _isCancelling;
    setState(() {
      _isDown = false;
      _dragDx = 0;
    });
    if (cancelling) {
      widget.onRecordCancel();
    } else {
      widget.onRecordStop();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (!_isDown) return;
    setState(() {
      _isDown = false;
      _dragDx = 0;
    });
    widget.onRecordCancel();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (widget.isScoring) {
      // A muted fill rather than an interactive style, so the button reads
      // as busy rather than silently swallowing taps.
      return Container(
        padding: _padding,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: colorScheme.onSurfaceVariant),
          child: IconTheme.merge(
            data: IconThemeData(color: colorScheme.onSurfaceVariant),
            child: const Center(
              child: _RecordButtonContent(
                isScoring: true,
                isRecording: false,
                isCancelling: false,
              ),
            ),
          ),
        ),
      );
    }

    final Color background;
    final Color foreground;
    if (_isCancelling) {
      background = colorScheme.errorContainer;
      foreground = colorScheme.onErrorContainer;
    } else if (widget.isRecording || _isDown) {
      background = colorScheme.error;
      foreground = colorScheme.onError;
    } else {
      background = colorScheme.primary;
      foreground = colorScheme.onPrimary;
    }

    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: _padding,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: Center(
              child: _RecordButtonContent(
                isScoring: false,
                isRecording: widget.isRecording || _isDown,
                isCancelling: _isCancelling,
                hasPreviousAttempt: widget.hasPreviousAttempt,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordButtonContent extends StatelessWidget {
  const _RecordButtonContent({
    required this.isScoring,
    required this.isRecording,
    required this.isCancelling,
    this.hasPreviousAttempt = false,
  });

  final bool isScoring;
  final bool isRecording;
  final bool isCancelling;
  final bool hasPreviousAttempt;

  @override
  Widget build(BuildContext context) {
    final String label;
    if (isScoring) {
      label = 'Scoring...';
    } else if (isCancelling) {
      label = 'Release to cancel';
    } else if (isRecording) {
      label = 'Slide to cancel';
    } else {
      label = hasPreviousAttempt ? 'Try again' : 'Hold to record';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isScoring)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        else
          Icon(isRecording ? Icons.mic : Icons.mic_none),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
