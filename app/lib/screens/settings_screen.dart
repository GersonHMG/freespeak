import 'package:flutter/material.dart';

import '../decks/deck_store_scope.dart';
import '../decks/languages.dart';
import '../decks/recall_settings.dart';
import '../decks/seed_deck.dart';
import '../pronunciation/asr_model_scope.dart';
import '../pronunciation/asr_model_store.dart';
import '../pronunciation/asr_models.dart';
import '../theme/lingo_theme.dart';
import '../theme/theme_setting.dart';
import '../widgets/language_list.dart';
import '../widgets/mode_badge.dart';
import 'language_onboarding_screen.dart';

/// Settings: the language the learner speaks, light or night mode, whether
/// a Recall card speaks when it turns over, which speech model scores the
/// learner (and downloading it), and deleting everything. Changing it switches
/// Home to a deck in that language (see chooseNativeLanguage) -- the old
/// deck, its cards and their schedules all stay, and switching back picks
/// them up again.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final decks = DeckStoreScope.of(context);
    return Scaffold(
      backgroundColor: LingoColors.background,
      appBar: AppBar(
        backgroundColor: LingoColors.background,
        elevation: 0,
        centerTitle: true,
        title: const ModeBadge(label: 'SETTINGS'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: decks.changes,
          builder: (context, _) => FutureBuilder<String?>(
            future: decks.nativeLanguage(),
            builder: (context, snapshot) {
              final code = snapshot.data;
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const _Label('LANGUAGE'),
                  const SizedBox(height: 8),
                  _Row(
                    title: 'I speak',
                    value: code == null
                        ? 'Not chosen'
                        : code == kUnlistedLang
                        ? 'Another language'
                        : '${nativeLanguageName(code)} (${languageName(code)})',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _LanguagePage(selected: code),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _Label('APPEARANCE'),
                  const SizedBox(height: 8),
                  const _ThemeRow(),
                  const SizedBox(height: 24),
                  const _Label('RECALL CARDS'),
                  const SizedBox(height: 8),
                  const _SpeakOnFlipRow(),
                  if (AsrModelScope.maybeOf(context) case final models?) ...[
                    const SizedBox(height: 24),
                    const _Label('SPEECH RECOGNITION'),
                    const SizedBox(height: 8),
                    _SpeechModelList(store: models),
                  ],
                  const SizedBox(height: 32),
                  const _Label('DATA'),
                  const SizedBox(height: 8),
                  const _DeleteAllButton(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Light, night, or whatever the phone is set to -- applied as soon as it
/// is tapped.
class _ThemeRow extends StatelessWidget {
  const _ThemeRow();

  @override
  Widget build(BuildContext context) {
    final decks = DeckStoreScope.of(context);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: lingoThemeMode,
      builder: (context, mode, _) => SizedBox(
        width: double.infinity,
        child: SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_rounded),
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_rounded),
              label: Text('Night'),
            ),
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_rounded),
              label: Text('System'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (choice) => saveThemeMode(decks, choice.single),
        ),
      ),
    );
  }
}

/// Whether the card's main reference is read aloud once it turns over --
/// applied from the next card turned.
class _SpeakOnFlipRow extends StatelessWidget {
  const _SpeakOnFlipRow();

  @override
  Widget build(BuildContext context) {
    final decks = DeckStoreScope.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: speakOnFlip,
      builder: (context, on, _) => Material(
        color: LingoColors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          value: on,
          onChanged: (value) => saveSpeakOnFlip(decks, value),
          title: Text(
            'Read the answer aloud',
            style: lingoFont(size: 15, weight: FontWeight.w600),
          ),
          subtitle: Text(
            'When a card turns over',
            style: lingoFont(
              size: 13,
              weight: FontWeight.w500,
              color: LingoColors.mutedInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// The speech models scoring can use: one is picked, and each is downloaded
/// (or deleted) on request -- none ships with the app. Tapping a downloaded
/// model picks it; a download started while the picked model is missing
/// picks the new one when it finishes, so a first run needs one tap.
class _SpeechModelList extends StatelessWidget {
  const _SpeechModelList({required this.store});

  final AsrModelStore store;

  Future<void> _download(BuildContext context, AsrModel model) async {
    final decks = DeckStoreScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.download(model);
      if (!store.isDownloaded(selectedAsrModel.value)) {
        await saveAsrModel(decks, model);
      }
    } on AsrDownloadCancelled {
      return;
    } catch (err) {
      debugPrint('[SettingsScreen] downloading ${model.name} failed: $err');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not download ${model.name}. Check your connection '
            'and try again -- it picks up where it stopped.',
          ),
        ),
      );
    }
  }

  Future<void> _delete(BuildContext context, AsrModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${model.name}?'),
        content: Text(
          'This frees ${_megabytes(model.totalBytes)}. You can download it '
          'again at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await store.delete(model);
  }

  @override
  Widget build(BuildContext context) {
    final decks = DeckStoreScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, selectedAsrModel]),
      builder: (context, _) => Material(
        color: LingoColors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: RadioGroup<String>(
          groupValue: selectedAsrModel.value.id,
          onChanged: (id) {
            final model = asrModelById(id);
            if (store.isDownloaded(model)) saveAsrModel(decks, model);
          },
          child: Column(
            children: [
              for (final model in kAsrModels)
                _SpeechModelTile(
                  model: model,
                  downloaded: store.isDownloaded(model),
                  progress: store.progressOf(model),
                  onDownload: () => _download(context, model),
                  onCancel: () => store.cancel(model),
                  onDelete: () => _delete(context, model),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeechModelTile extends StatelessWidget {
  const _SpeechModelTile({
    required this.model,
    required this.downloaded,
    required this.progress,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

  final AsrModel model;
  final bool downloaded;

  /// 0-1 while downloading.
  final double? progress;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    final muted = lingoFont(
      size: 13,
      weight: FontWeight.w500,
      color: LingoColors.mutedInk,
    );
    return RadioListTile<String>(
      value: model.id,
      enabled: downloaded,
      title: Text(
        model.name,
        style: lingoFont(size: 15, weight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(model.summary, style: muted),
          const SizedBox(height: 2),
          Text(
            progress != null
                ? 'Downloading… ${(progress * 100).floor()}% of '
                      '${_megabytes(model.totalBytes)}'
                : downloaded
                ? 'Downloaded · ${_megabytes(model.totalBytes)}'
                : _megabytes(model.totalBytes),
            style: muted,
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress),
          ],
        ],
      ),
      secondary: progress != null
          ? IconButton(
              tooltip: 'Stop download',
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded),
            )
          : downloaded
          ? IconButton(
              tooltip: 'Delete ${model.name}',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            )
          : IconButton(
              tooltip: 'Download ${model.name}',
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded),
            ),
    );
  }
}

String _megabytes(int bytes) => '${(bytes / (1000 * 1000)).round()} MB';

/// "Delete all data": a warning that says what goes, and a Delete button
/// that only wakes up once "delete" is typed -- a tap alone, or two, is too
/// easy to make by accident for something that cannot be undone. Afterwards
/// the app starts over at the first-launch language question.
class _DeleteAllButton extends StatelessWidget {
  const _DeleteAllButton();

  static const String confirmWord = 'delete';

  Future<void> _confirm(BuildContext context) async {
    final decks = DeckStoreScope.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteAllDialog(),
    );
    if (confirmed != true) return;
    await decks.deleteAllData();
    // The theme choice was a setting too, and so was speaking on flip.
    lingoThemeMode.value = ThemeMode.system;
    speakOnFlip.value = true;
    selectedAsrModel.value = kWhisperTiny;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LanguageOnboardingScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _confirm(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: LingoColors.onErrorContainer,
        side: BorderSide(color: LingoColors.onErrorContainer),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      icon: const Icon(Icons.delete_forever_rounded),
      label: const Text('Delete all data'),
    );
  }
}

class _DeleteAllDialog extends StatefulWidget {
  const _DeleteAllDialog();

  @override
  State<_DeleteAllDialog> createState() => _DeleteAllDialogState();
}

class _DeleteAllDialogState extends State<_DeleteAllDialog> {
  final TextEditingController _typed = TextEditingController();

  bool get _confirmed =>
      _typed.text.trim().toLowerCase() == _DeleteAllButton.confirmWord;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: LingoColors.onErrorContainer,
        size: 32,
      ),
      title: const Text('Delete all data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This deletes all your decks and cards, your progress and '
            'streak, your pronunciation history and your settings. '
            'It cannot be undone.',
          ),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Type '),
                TextSpan(
                  text: _DeleteAllButton.confirmWord,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const TextSpan(text: ' to confirm.'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _typed,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: _DeleteAllButton.confirmWord,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: LingoColors.onErrorContainer,
            foregroundColor: Colors.white,
          ),
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete everything'),
        ),
      ],
    );
  }
}

/// The full-screen picker Settings opens for "I speak".
class _LanguagePage extends StatefulWidget {
  const _LanguagePage({required this.selected});

  final String? selected;

  @override
  State<_LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<_LanguagePage> {
  bool _isSaving = false;

  Future<void> _choose(String code) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await chooseNativeLanguage(
        DeckStoreScope.of(context),
        code,
        bundle: DefaultAssetBundle.of(context),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            code == kUnlistedLang
                ? 'Switched. Add your own cards from More → My decks.'
                : 'Switched to ${languageName(code)}.',
          ),
        ),
      );
    } catch (err) {
      debugPrint('[SettingsScreen] choosing a language failed: $err');
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not switch. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LingoColors.background,
      appBar: AppBar(
        backgroundColor: LingoColors.background,
        elevation: 0,
        centerTitle: true,
        title: const ModeBadge(label: 'I SPEAK'),
      ),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _isSaving,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              LanguageList(selected: widget.selected, onChoose: _choose),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: lingoFont(
      size: 11,
      weight: FontWeight.w700,
      color: LingoColors.mutedInk,
      letterSpacing: 1.2,
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.value, this.onTap});

  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LingoColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: lingoFont(size: 15, weight: FontWeight.w600),
                ),
              ),
              Text(
                value,
                style: lingoFont(
                  size: 14,
                  weight: FontWeight.w500,
                  color: LingoColors.mutedInk,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: LingoColors.navInactive,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
