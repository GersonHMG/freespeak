import 'package:flutter/material.dart';

import '../decks/deck_models.dart';
import '../decks/deck_store_scope.dart';
import '../decks/languages.dart';
import '../pronunciation/phrase_tokens.dart';
import '../theme/lingo_theme.dart';
import '../widgets/mode_badge.dart';
import '../widgets/own_answers.dart';

/// Writes a new Recall card into a deck: the prompt in the deck's native
/// language and one or more translations into its target language. Labels
/// come from the deck (see languages.dart), so the screen names no language
/// itself. The first translation is the primary reference;
/// any others are further examples of how it can be said -- Recall never
/// checks an answer against them, so they only need to be good wordings,
/// not every possible one.
///
/// Adding: saving keeps the screen open with the form cleared, so several
/// cards can be added in a row; the back arrow leaves. A new card joins the
/// deck as new and is drawn at random like any other.
///
/// Editing ([note] given): the form starts filled in, saving rewrites the
/// card and closes, and the bin deletes it. An edited card keeps its
/// schedule -- fixing a card's wording is not a new card.
///
/// An existing card also lists the learner's own ways to say it, saved
/// while studying ([Note.ownReferences]), apart from the form: each is
/// added or removed on the spot, not by Save, and Save leaves them alone.
/// A starter deck's card ([deckEditable] false) opens the same way with the
/// form read-only -- its own ways to say it are the only part to change.
class AddCardScreen extends StatefulWidget {
  const AddCardScreen({
    required this.deckId,
    this.note,
    this.deckEditable = true,
    super.key,
  });

  final int deckId;

  /// The card to edit, or null to add new ones.
  final Note? note;

  /// False for a starter deck's card: prompt and references are shown, not
  /// edited.
  final bool deckEditable;

  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _prompt = TextEditingController(
    text: widget.note?.nativeText,
  );
  late final List<TextEditingController> _answers = [
    for (final reference in widget.note?.references ?? const [''])
      TextEditingController(text: reference),
  ];

  late List<String> _own = [...?widget.note?.ownReferences];

  bool get _isEditing => widget.note != null;
  bool get _canEdit => widget.deckEditable;

  Future<void> _addOwn() async {
    final note = widget.note!;
    final store = DeckStoreScope.of(context);
    final text = await askForOwnAnswer(context, _target);
    if (text == null || !mounted) return;
    if (await saveOwnAnswer(context, store, note.id, text) && mounted) {
      setState(() => _own = [..._own, text.trim()]);
    }
  }

  Future<void> _removeOwn(String text) async {
    final note = widget.note!;
    final store = DeckStoreScope.of(context);
    if (!await confirmRemoveOwnAnswer(context, text) || !mounted) return;
    await store.removeOwnReference(note.id, text);
    if (mounted) setState(() => _own = [..._own]..remove(text));
  }

  bool _isSaving = false;
  int _added = 0;

  /// The deck's target language, for the labels (the default stands in
  /// for the moment before it has loaded). The prompt side is always "your
  /// language" -- see [kYourLanguage].
  String _target = languageName(kDefaultTargetLang);
  bool _loadedDeck = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedDeck) return;
    _loadedDeck = true;
    DeckStoreScope.of(context).deck(widget.deckId).then((deck) {
      if (!mounted) return;
      setState(() {
        _target = languageName(deck.targetLang);
      });
    });
  }

  @override
  void dispose() {
    _prompt.dispose();
    for (final field in _answers) {
      field.dispose();
    }
    super.dispose();
  }

  void _addTranslation() =>
      setState(() => _answers.add(TextEditingController()));

  void _removeTranslation(int index) {
    final removed = _answers.removeAt(index);
    setState(() {});
    // After the frame, so the field is gone from the tree before its
    // controller is.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    final references = [
      for (final field in _answers)
        if (field.text.trim().isNotEmpty) field.text.trim(),
    ];
    final prompt = _prompt.text.trim();
    setState(() => _isSaving = true);
    final note = widget.note;
    if (note != null) {
      try {
        await DeckStoreScope.of(context)
            .updateNote(note.id, nativeText: prompt, references: references);
        if (mounted) Navigator.of(context).pop();
      } catch (err) {
        debugPrint('[AddCardScreen] saving the edit failed: $err');
        if (!mounted) return;
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save that card. Try again.')),
        );
      }
      return;
    }
    try {
      await DeckStoreScope.of(context).addNote(
        deckId: widget.deckId,
        nativeText: prompt,
        references: references,
        kind: phraseWords(prompt).length == 1
            ? NoteKind.word
            : NoteKind.sentence,
      );
      if (!mounted) return;
      _prompt.clear();
      for (final field in _answers.skip(1)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => field.dispose());
      }
      setState(() {
        _answers
          ..first.clear()
          ..removeRange(1, _answers.length);
        _added++;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Card added. Add another or go back.')),
        );
    } catch (err) {
      debugPrint('[AddCardScreen] saving failed: $err');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save that card. Try again.')),
      );
    }
  }

  Future<void> _delete() async {
    final note = widget.note!;
    final store = DeckStoreScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete card?'),
        content: const Text('The card and its history will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await store.deleteNote(note.id);
    if (mounted) Navigator.of(context).pop();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LingoColors.background,
      appBar: AppBar(
        backgroundColor: LingoColors.background,
        elevation: 0,
        centerTitle: true,
        title: ModeBadge(
          label: !_canEdit
              ? 'CARD'
              : _isEditing
              ? 'EDIT CARD'
              : 'NEW CARD',
        ),
        actions: [
          if (_isEditing && _canEdit)
            IconButton(
              tooltip: 'Delete card',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _isSaving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _Label(kYourLanguage.toUpperCase()),
              const SizedBox(height: 8),
              _Field(
                controller: _prompt,
                hint: 'A word or sentence in your language',
                validator: _required,
                enabled: _canEdit,
              ),
              const SizedBox(height: 24),
              _Label(
                _answers.length == 1
                    ? _target.toUpperCase()
                    : '${_target.toUpperCase()} (FIRST IS MAIN)',
              ),
              const SizedBox(height: 8),
              for (final (i, field) in _answers.indexed) ...[
                if (i > 0) const SizedBox(height: 10),
                _Field(
                  // Keyed by controller: removing a middle field must not
                  // hand its neighbour's text to the wrong row.
                  key: ObjectKey(field),
                  controller: field,
                  hint: i == 0
                      ? 'How you say it in $_target'
                      : 'Another way to say it',
                  validator: i == 0 ? _required : null,
                  onRemove: i == 0 || !_canEdit
                      ? null
                      : () => _removeTranslation(i),
                  enabled: _canEdit,
                ),
              ],
              if (_canEdit) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addTranslation,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Another translation'),
                  ),
                ),
              ],
              if (_isEditing) ...[
                const SizedBox(height: 24),
                const _Label('YOUR WAYS TO SAY IT'),
                const SizedBox(height: 8),
                for (final mine in _own) ...[
                  _OwnRow(text: mine, onRemove: () => _removeOwn(mine)),
                  const SizedBox(height: 8),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addOwn,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add your own way'),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_canEdit)
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: LingoColors.indigo,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: lingoFont(size: 16, weight: FontWeight.w700),
                  ),
                  icon: Icon(
                    _isEditing ? Icons.check_rounded : Icons.add_rounded,
                  ),
                  label: Text(_isEditing ? 'Save' : 'Add card'),
                ),
              if (_added > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '$_added ${_added == 1 ? 'card' : 'cards'} added',
                  textAlign: TextAlign.center,
                  style: lingoFont(
                    size: 13,
                    weight: FontWeight.w500,
                    color: LingoColors.mutedInk,
                  ),
                ),
              ],
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

/// One of the learner's own ways to say it, with its remove button.
class _OwnRow extends StatelessWidget {
  const _OwnRow({required this.text, required this.onRemove});

  final String text;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 18),
      decoration: BoxDecoration(
        color: LingoColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: lingoFont(size: 16, weight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close_rounded),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.validator,
    this.onRemove,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final FormFieldValidator<String>? validator;
  final VoidCallback? onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      validator: validator,
      textCapitalization: TextCapitalization.sentences,
      style: lingoFont(size: 16, weight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: lingoFont(
          size: 16,
          weight: FontWeight.w500,
          color: LingoColors.mutedInk,
        ),
        filled: true,
        fillColor: LingoColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        suffixIcon: onRemove == null
            ? null
            : IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close_rounded),
                onPressed: onRemove,
              ),
      ),
    );
  }
}
