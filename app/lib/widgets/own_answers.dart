// The learner's own ways to say a card's prompt (Note.ownReferences):
// saving one, with its cue, and asking for one. Shared by the Recall card
// and the card editor, so both save, sound and refuse duplicates alike.

import 'package:flutter/material.dart';

import '../decks/deck_store.dart';
import 'cue_player.dart';

final _addedPlayer = newCuePlayer();

Future<void> _playAdded() async {
  try {
    await playCue(_addedPlayer, 'sounds/buttons_sound/new_answer_added.wav');
  } catch (err) {
    debugPrint('[ownAnswers] cue failed: $err');
  }
}

/// Saves [text] as one of [noteId]'s ways to say it, and plays the
/// new-answer cue when it was saved. Returns whether it was: false for a
/// wording the card already has, which is said in a snackbar.
Future<bool> saveOwnAnswer(
  BuildContext context,
  DeckStore store,
  int noteId,
  String text,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final added = await store.addOwnReference(noteId, text);
    if (added) {
      _playAdded();
    } else {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('The card already has that one.')),
        );
    }
    return added;
  } catch (err) {
    debugPrint('[ownAnswers] saving failed: $err');
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Could not save that. Try again.')),
      );
    return false;
  }
}

/// Asks for another way to say it in [targetLanguage], the field starting
/// with [initial] (e.g. the answer the learner just wrote) to save as is or
/// edit; null if cancelled or left blank.
Future<String?> askForOwnAnswer(
  BuildContext context,
  String targetLanguage, {
  String? initial,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _AddAnswerDialog(targetLanguage: targetLanguage, initial: initial),
  );
}

/// Confirms removing one of the learner's own ways to say it.
Future<bool> confirmRemoveOwnAnswer(BuildContext context, String text) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove this way to say it?'),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class _AddAnswerDialog extends StatefulWidget {
  const _AddAnswerDialog({required this.targetLanguage, this.initial});

  final String targetLanguage;
  final String? initial;

  @override
  State<_AddAnswerDialog> createState() => _AddAnswerDialogState();
}

class _AddAnswerDialogState extends State<_AddAnswerDialog> {
  // The cursor at the end, ready to touch up before saving.
  late final TextEditingController _typed = TextEditingController.fromValue(
    TextEditingValue(
      text: widget.initial ?? '',
      selection: TextSelection.collapsed(offset: widget.initial?.length ?? 0),
    ),
  );

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  void _save() {
    final text = _typed.text.trim();
    if (text.isNotEmpty) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Another way to say it'),
      content: TextField(
        controller: _typed,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          hintText: 'In ${widget.targetLanguage}',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _typed.text.trim().isEmpty ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
