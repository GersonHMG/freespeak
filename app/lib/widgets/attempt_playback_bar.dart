// The scrub bar for "hear my last attempt", shown on the feedback screen once
// there is a scored recording.
//
// Reads state off [UserAttemptPlayer] via [AnimatedBuilder] the same way
// [HearButton] reads [PhrasePlayer] -- the player, not this widget, owns
// "is something playing", since scoring, per-word clips, and this bar all
// touch the same [AudioPlayer] underneath it.

import 'package:flutter/material.dart';

import '../pronunciation/user_attempt_player.dart';

class AttemptPlaybackBar extends StatelessWidget {
  const AttemptPlaybackBar({
    super.key,
    required this.player,
    this.onHearReference,
  });

  final UserAttemptPlayer player;

  /// Replays the reference pronunciation -- the trailing speaker icon. Null
  /// hides it, e.g. if the caller has no phrase to play.
  final VoidCallback? onHearReference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        if (!player.hasAttempt) return const SizedBox.shrink();

        // Scrubbing needs a known length; guard against 0 so the slider's
        // max is never 0 (Slider throws on that) before onDurationChanged
        // has fired for this recording.
        final durationMs = player.duration.inMilliseconds;
        final positionMs = player.position.inMilliseconds
            .clamp(0, durationMs == 0 ? 0 : durationMs)
            .toDouble();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: player.togglePlayback,
                icon: Icon(
                  player.isPlaying ? Icons.pause_circle : Icons.play_circle,
                ),
                iconSize: 32,
                color: colorScheme.primary,
                tooltip: player.isPlaying ? 'Pause' : 'Play your recording',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Your recording',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_format(player.position)} / '
                          '${_format(player.duration)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        value: positionMs,
                        max: durationMs == 0 ? 1 : durationMs.toDouble(),
                        onChanged: durationMs == 0
                            ? null
                            : (value) => player.seek(
                                Duration(milliseconds: value.round()),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              if (onHearReference != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onHearReference,
                  icon: const Icon(Icons.volume_up),
                  iconSize: 20,
                  color: colorScheme.onSurfaceVariant,
                  tooltip: 'Hear the correct pronunciation',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// `m:ss`, matching the level of precision a scrub bar needs -- unlike
  /// WordMapDebugScreen's millisecond-precise formatter, which exists to
  /// check a recognizer's word boundaries, not to be read at a glance.
  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
