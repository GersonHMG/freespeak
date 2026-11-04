import 'package:flutter/material.dart';

import '../decks/deck_store_scope.dart';
import '../pronunciation/asr_model_store.dart';
import '../pronunciation/asr_models.dart';
import '../theme/lingo_theme.dart';

/// The first-launch step after the language question: no speech model ships
/// with the app, so this asks the learner to download one -- or skip it, and
/// do it later from Home's warning or Settings.
///
/// The download belongs to [store], not to this screen, so skipping (or
/// leaving) while it runs lets it finish in the background; Home's
/// [SpeechModelBanner] shows how far it has got.
class SpeechModelSetupScreen extends StatefulWidget {
  const SpeechModelSetupScreen({super.key, required this.store, this.onDone});

  final AsrModelStore store;

  /// Called on "Start practising" and on "Skip for now". Pops the screen
  /// when null.
  final VoidCallback? onDone;

  @override
  State<SpeechModelSetupScreen> createState() => _SpeechModelSetupScreenState();
}

class _SpeechModelSetupScreenState extends State<SpeechModelSetupScreen> {
  /// The model the cards have selected. Starts on whichever is already
  /// downloading, so coming back to this screen mid-download shows it.
  late AsrModel _choice = kAsrModels.firstWhere(
    widget.store.isDownloading,
    orElse: () => selectedAsrModel.value,
  );

  void _done() {
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _download() async {
    final model = _choice;
    final decks = DeckStoreScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.store.download(model);
      // Picked here on purpose, so it is the one scoring uses -- whatever
      // was selected before had nothing on disk anyway.
      await saveAsrModel(decks, model);
    } on AsrDownloadCancelled {
      return;
    } catch (err) {
      debugPrint('[SpeechModelSetupScreen] downloading ${model.name}: $err');
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'The download stopped. Check your connection and try again -- '
            'it picks up where it left off.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LingoColors.background,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) {
            final store = widget.store;
            final busy = kAsrModels.any(store.isDownloading);
            final ready = store.isDownloaded(_choice);
            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 36,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        _Hero(ready: ready),
                        const SizedBox(height: 20),
                        Text(
                          ready ? "You're all set" : 'Download a speech model',
                          textAlign: TextAlign.center,
                          style: lingoFont(size: 24, weight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          ready
                              ? 'Free Speak can now listen and score your '
                                    'pronunciation, even offline.'
                              : 'Free Speak listens on your phone, so your '
                                    'voice never leaves it. Download a model '
                                    'once to get your speaking scored.',
                          textAlign: TextAlign.center,
                          style: lingoFont(
                            size: 15,
                            weight: FontWeight.w500,
                            color: LingoColors.mutedInk,
                          ),
                        ),
                        const SizedBox(height: 24),
                        for (final model in kAsrModels) ...[
                          _ModelOption(
                            model: model,
                            selected: model == _choice,
                            recommended: model == kWhisperTiny,
                            downloaded: store.isDownloaded(model),
                            // Locked while a download runs: one at a time.
                            onTap: busy
                                ? null
                                : () => setState(() => _choice = model),
                          ),
                          const SizedBox(height: 8),
                        ],
                        const Spacer(),
                        const SizedBox(height: 16),
                        if (store.progressOf(_choice) case final progress?)
                          _Progress(
                            model: _choice,
                            progress: progress,
                            onCancel: () => store.cancel(_choice),
                          )
                        else
                          _PrimaryButton(
                            label: ready
                                ? 'Start practising'
                                : 'Download · ${megabytes(_choice.totalBytes)}',
                            icon: ready
                                ? Icons.arrow_forward_rounded
                                : Icons.download_rounded,
                            onPressed: busy
                                ? null
                                : ready
                                ? _done
                                : _download,
                          ),
                        const SizedBox(height: 8),
                        if (!ready)
                          TextButton(
                            onPressed: _done,
                            style: TextButton.styleFrom(
                              foregroundColor: LingoColors.mutedInk,
                              textStyle: lingoFont(
                                size: 15,
                                weight: FontWeight.w600,
                              ),
                            ),
                            child: Text(
                              busy
                                  ? 'Continue in the background'
                                  : 'Skip for now',
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Wi-Fi recommended. You can change this later in '
                          'Settings.',
                          textAlign: TextAlign.center,
                          style: lingoFont(
                            size: 12,
                            weight: FontWeight.w500,
                            color: LingoColors.mutedInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// "123 MB", in the decimal megabytes app stores and file managers show.
String megabytes(int bytes) => '${(bytes / (1000 * 1000)).round()} MB';

/// A soft disc with a waveform, which turns into a check once the model is
/// on the phone.
class _Hero extends StatelessWidget {
  const _Hero({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: LingoColors.indigoContainer,
          shape: BoxShape.circle,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Icon(
            ready ? Icons.check_rounded : Icons.graphic_eq_rounded,
            key: ValueKey(ready),
            size: 36,
            color: LingoColors.indigo,
          ),
        ),
      ),
    );
  }
}

class _ModelOption extends StatelessWidget {
  const _ModelOption({
    required this.model,
    required this.selected,
    required this.recommended,
    required this.downloaded,
    required this.onTap,
  });

  final AsrModel model;
  final bool selected;
  final bool recommended;
  final bool downloaded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: LingoColors.surface,
        borderRadius: radius,
        border: Border.all(
          color: selected ? LingoColors.indigo : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              model.name,
                              style: lingoFont(
                                size: 15,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (recommended) ...[
                            const SizedBox(width: 8),
                            const _Pill('Recommended'),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        model.summary,
                        style: lingoFont(
                          size: 13,
                          weight: FontWeight.w500,
                          color: LingoColors.mutedInk,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                downloaded
                    ? Icon(
                        Icons.check_circle_rounded,
                        size: 22,
                        color: LingoColors.indigo,
                      )
                    : Text(
                        megabytes(model.totalBytes),
                        style: lingoFont(
                          size: 13,
                          weight: FontWeight.w600,
                          color: selected
                              ? LingoColors.indigo
                              : LingoColors.mutedInk,
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: LingoColors.indigoContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: lingoFont(
          size: 11,
          weight: FontWeight.w700,
          color: LingoColors.indigo,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: LingoColors.indigo,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: lingoFont(size: 16, weight: FontWeight.w700),
      ),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

/// Takes the primary button's place while the chosen model downloads.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.model,
    required this.progress,
    required this.onCancel,
  });

  final AsrModel model;
  final double progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final muted = lingoFont(
      size: 13,
      weight: FontWeight.w600,
      color: LingoColors.mutedInk,
    );
    final total = model.totalBytes;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: LingoColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${(progress * 100).floor()}%',
                      style: lingoFont(size: 15, weight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Text(
                      '${megabytes((progress * total).round())} of '
                      '${megabytes(total)}',
                      style: muted,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: LingoColors.ringTrack,
                    color: LingoColors.indigo,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Stop download',
            onPressed: onCancel,
            icon: Icon(Icons.close_rounded, color: LingoColors.mutedInk),
          ),
        ],
      ),
    );
  }
}
