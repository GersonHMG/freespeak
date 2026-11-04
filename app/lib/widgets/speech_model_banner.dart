import 'package:flutter/material.dart';

import '../pronunciation/asr_model_scope.dart';
import '../pronunciation/asr_models.dart';
import '../screens/speech_model_setup_screen.dart';
import '../theme/lingo_theme.dart';

/// Home's reminder that nothing can be scored yet: shown while the speech
/// model picked in Settings is not on the phone, and gone once it is. A
/// download in flight shows its progress instead. Tapping either opens
/// [SpeechModelSetupScreen].
///
/// Takes no space at all when there is nothing to say, or outside the app's
/// scopes (a screen under test).
class SpeechModelBanner extends StatelessWidget {
  const SpeechModelBanner({super.key, this.padding = EdgeInsets.zero});

  /// Around the banner when it shows -- so the gap it needs disappears with
  /// it.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final store = AsrModelScope.maybeOf(context);
    if (store == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: Listenable.merge([store, selectedAsrModel]),
      builder: (context, _) {
        if (store.isDownloaded(selectedAsrModel.value)) {
          return const SizedBox.shrink();
        }
        final downloading = kAsrModels.where(store.isDownloading).firstOrNull;
        final progress = downloading == null
            ? null
            : store.progressOf(downloading);

        return Padding(
          padding: padding,
          child: Material(
            color: LingoColors.streakContainer,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SpeechModelSetupScreen(store: store),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    Icon(
                      progress == null
                          ? Icons.mic_off_rounded
                          : Icons.downloading_rounded,
                      size: 20,
                      color: LingoColors.streak,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            progress == null
                                ? "Speaking can't be scored yet"
                                : 'Downloading speech model · '
                                      '${(progress * 100).floor()}%',
                            style: lingoFont(
                              size: 14,
                              weight: FontWeight.w700,
                              color: LingoColors.streak,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (progress == null)
                            Text(
                              'Download a speech model to get started',
                              style: lingoFont(
                                size: 12,
                                weight: FontWeight.w500,
                                color: LingoColors.streak,
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 4,
                                  color: LingoColors.streak,
                                  backgroundColor: LingoColors.streak
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: LingoColors.streak,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
