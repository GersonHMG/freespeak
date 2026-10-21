import 'package:flutter/material.dart';

import '../tts/phrase_player.dart';

/// Plays the given phrase through the screen's [PhrasePlayer], and pulses
/// while it sounds.
///
/// A small circular icon button, deliberately overshadowed by the much
/// larger record button beside it -- hearing the phrase is a supporting
/// action, saying it is the point of the screen.
///
/// Playback state lives in the player rather than here, because the phrase
/// audio, the word highlight, and tap-to-hear-a-word all have to agree — and
/// they cannot if this widget owns its own AudioPlayer.
class HearButton extends StatelessWidget {
  const HearButton({super.key, required this.text, required this.player});

  final String? text;
  final PhrasePlayer player;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final child = player.isGenerating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : _PulsingIcon(
                active: player.isPlaying,
                icon: player.isPlaying ? Icons.stop : Icons.volume_up,
              );

        return SizedBox(
          width: _size,
          height: _size,
          child: OutlinedButton(
            onPressed: () {
              final phrase = text;
              if (phrase != null) player.toggle(phrase);
            },
            style: OutlinedButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              side: BorderSide(color: colorScheme.outlineVariant),
              foregroundColor: colorScheme.onSurfaceVariant,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// The icon pulses for as long as audio is playing.
class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon({required this.active, required this.icon});

  final bool active;
  final IconData icon;

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  @override
  void didUpdateWidget(_PulsingIcon old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(
        begin: 1,
        end: 1.35,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Icon(widget.icon),
    );
  }
}
