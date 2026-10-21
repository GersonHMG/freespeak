import 'package:flutter/material.dart';

import '../decks/deck_models.dart';
import '../decks/deck_store_scope.dart';
import '../decks/languages.dart';
import '../theme/lingo_theme.dart';
import '../widgets/text_prompt.dart';
import '../widgets/deck_look.dart';
import '../widgets/deck_tile.dart';
import '../widgets/mode_badge.dart';
import 'add_card_screen.dart';
import 'custom_session_screen.dart';

/// Asks for a name, makes a deck of the learner's own in their native
/// language, and opens it to add cards -- My decks' "New deck", and the
/// deck picker's "Create a deck".
Future<void> createDeckAndOpen(BuildContext context) async {
  final store = DeckStoreScope.of(context);
  final name = await promptForText(
    context,
    title: 'New deck',
    hint: 'Deck name',
    action: 'Create',
  );
  if (name == null || !context.mounted) return;
  final native = await store.nativeLanguage();
  final deckId = await store.createDeck(
    name: name,
    nativeLang: native ?? kDefaultNativeLang,
    targetLang: kDefaultTargetLang,
  );
  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => DeckScreen(deckId: deckId)));
}

/// My decks: every deck, and a button to make a new one. A deck the learner
/// made opens for editing; a starter deck opens read-only.
class DecksScreen extends StatelessWidget {
  const DecksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final decks = DeckStoreScope.of(context);
    return Scaffold(
      backgroundColor: LingoColors.background,
      appBar: AppBar(
        backgroundColor: LingoColors.background,
        elevation: 0,
        centerTitle: true,
        title: const ModeBadge(label: 'MY DECKS'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: LingoColors.indigo,
        foregroundColor: Colors.white,
        onPressed: () => createDeckAndOpen(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New deck'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: decks.changes,
          builder: (context, _) => FutureBuilder<List<DeckSummary>>(
            future: decks.deckSummaries(),
            builder: (context, snapshot) {
              final summaries = snapshot.data;
              if (summaries == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
                children: [
                  for (final summary in summaries)
                    DeckTile(
                      deck: summary.deck,
                      subtitle: cardCount(summary.cardCount),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DeckScreen(deckId: summary.deck.id),
                        ),
                      ),
                    ),
                  if (summaries.isEmpty)
                    Text(
                      'No decks yet. Make your first one.',
                      style: lingoFont(
                        size: 14,
                        weight: FontWeight.w500,
                        color: LingoColors.mutedInk,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One deck's cards. On the learner's own decks, "Add card" and a tap on a
/// card (to edit or delete it); on a starter deck, a read-only list. The
/// gear opens [DeckSettingsScreen].
class DeckScreen extends StatelessWidget {
  const DeckScreen({required this.deckId, super.key});

  final int deckId;

  @override
  Widget build(BuildContext context) {
    final store = DeckStoreScope.of(context);
    return ListenableBuilder(
      listenable: store.changes,
      builder: (context, _) => FutureBuilder<(Deck, List<Note>)>(
        future: () async {
          return (await store.deck(deckId), await store.notes(deckId));
        }(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            // Also the moment after the deck is deleted, before this page
            // is popped.
            return Scaffold(
              backgroundColor: LingoColors.background,
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final (deck, notes) = data;
          return Scaffold(
            backgroundColor: LingoColors.background,
            appBar: AppBar(
              backgroundColor: LingoColors.background,
              elevation: 0,
              title: Text(
                deck.name,
                style: lingoFont(size: 18, weight: FontWeight.w700),
              ),
              actions: [
                IconButton(
                  tooltip: 'Deck settings',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DeckSettingsScreen(deckId: deckId),
                    ),
                  ),
                ),
              ],
            ),
            floatingActionButton: deck.isEditable
                ? FloatingActionButton.extended(
                    backgroundColor: LingoColors.indigo,
                    foregroundColor: Colors.white,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AddCardScreen(deckId: deckId),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add card'),
                  )
                : null,
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
                children: [
                  Text(
                    '${languageFlag(deck.nativeLang)} '
                    '$kYourLanguage → '
                    '${languageName(deck.targetLang)} · '
                    '${cardCount(notes.length)}',
                    style: lingoFont(
                      size: 13,
                      weight: FontWeight.w500,
                      color: LingoColors.mutedInk,
                    ),
                  ),
                  if (!deck.isEditable) ...[
                    const SizedBox(height: 12),
                    _Notice(
                      "A starter deck: its cards can't be changed, but you "
                      'can add your own ways to say them. Make your own '
                      'deck to write cards.',
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (notes.isEmpty)
                    Text(
                      'No cards yet. Add your first one.',
                      style: lingoFont(
                        size: 14,
                        weight: FontWeight.w500,
                        color: LingoColors.mutedInk,
                      ),
                    ),
                  for (final note in notes)
                    _CardRow(
                      note: note,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AddCardScreen(
                            deckId: deckId,
                            note: note,
                            deckEditable: deck.isEditable,
                          ),
                        ),
                      ),
                      editable: deck.isEditable,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: LingoColors.indigoContainer.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(Icons.lock_outline_rounded, size: 18, color: LingoColors.indigo),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: lingoFont(size: 13, weight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

/// A card in a deck's list: the front over the main back.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.note,
    required this.onTap,
    required this.editable,
  });

  final Note note;
  final VoidCallback? onTap;

  /// An own deck's card, edited when tapped; a starter deck's only opens.
  final bool editable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: LingoColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.nativeText,
                        style: lingoFont(size: 15, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        note.references.isEmpty ? '' : note.primaryReference,
                        style: lingoFont(
                          size: 13,
                          weight: FontWeight.w500,
                          color: LingoColors.mutedInk,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    editable ? Icons.edit_rounded : Icons.chevron_right_rounded,
                    size: 18,
                    color: LingoColors.navInactive,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A deck's settings: its name (own decks), its icon and colour, how many
/// new cards a day, a
/// custom session over its cards, and deleting it (own decks).
class DeckSettingsScreen extends StatelessWidget {
  const DeckSettingsScreen({required this.deckId, super.key});

  final int deckId;

  static const int _minNewPerDay = 1;
  static const int _maxNewPerDay = 50;

  Future<void> _rename(BuildContext context, Deck deck) async {
    final store = DeckStoreScope.of(context);
    final name = await promptForText(
      context,
      title: 'Rename deck',
      hint: 'Deck name',
      action: 'Save',
      initial: deck.name,
    );
    if (name != null) await store.renameDeck(deck.id, name);
  }

  Future<void> _pickIcon(BuildContext context, Deck deck) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: LingoColors.surface,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => _LookSheet(deck: deck),
      );

  Future<void> _delete(BuildContext context, Deck deck) async {
    final store = DeckStoreScope.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete deck?'),
        content: Text(
          '"${deck.name}" and all its cards will be deleted. '
          'This cannot be undone.',
        ),
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
    if (confirmed != true) return;
    // Back past the deck's own page, which would otherwise rebuild over a
    // deck that no longer exists.
    navigator
      ..pop()
      ..pop();
    await store.deleteDeck(deck.id);
  }

  @override
  Widget build(BuildContext context) {
    final store = DeckStoreScope.of(context);
    return Scaffold(
      backgroundColor: LingoColors.background,
      appBar: AppBar(
        backgroundColor: LingoColors.background,
        elevation: 0,
        centerTitle: true,
        title: const ModeBadge(label: 'DECK SETTINGS'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store.changes,
          builder: (context, _) => FutureBuilder<Deck>(
            future: store.deck(deckId),
            builder: (context, snapshot) {
              final deck = snapshot.data;
              if (deck == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _SettingRow(
                    title: 'Name',
                    value: deck.name,
                    onTap: deck.isEditable
                        ? () => _rename(context, deck)
                        : null,
                  ),
                  _SettingRow(
                    title: 'Icon',
                    trailing: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: DeckIconTile.of(deck, size: 34),
                    ),
                    onTap: () => _pickIcon(context, deck),
                  ),
                  _SettingRow(
                    title: 'Languages',
                    value:
                        '$kYourLanguage → '
                        '${languageName(deck.targetLang)}',
                  ),
                  _SettingRow(
                    title: 'New cards per day',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Fewer',
                          icon: const Icon(Icons.remove_rounded),
                          onPressed: deck.newPerDay > _minNewPerDay
                              ? () => store.setNewPerDay(
                                  deck.id,
                                  deck.newPerDay - 1,
                                )
                              : null,
                        ),
                        Text(
                          '${deck.newPerDay}',
                          style: lingoFont(size: 15, weight: FontWeight.w700),
                        ),
                        IconButton(
                          tooltip: 'More',
                          icon: const Icon(Icons.add_rounded),
                          onPressed: deck.newPerDay < _maxNewPerDay
                              ? () => store.setNewPerDay(
                                  deck.id,
                                  deck.newPerDay + 1,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingRow(
                    title: 'Custom session',
                    value: 'Random, yours, or missed',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CustomSessionScreen(deckId: deck.id),
                      ),
                    ),
                  ),
                  if (deck.isEditable) ...[
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => _delete(context, deck),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: LingoColors.onErrorContainer,
                        side: BorderSide(color: LingoColors.onErrorContainer),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete deck'),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The icon picker: a preview of the tile, a row of colours, and the grid
/// of icons drawn in the chosen colour. Every tap is saved at once -- the
/// deck list behind updates as the learner picks -- so there is no Save
/// button to forget; closing the sheet keeps what was chosen.
class _LookSheet extends StatefulWidget {
  const _LookSheet({required this.deck});

  final Deck deck;

  @override
  State<_LookSheet> createState() => _LookSheetState();
}

class _LookSheetState extends State<_LookSheet> {
  late String _icon = deckIconName(widget.deck);
  late String _color = deckColorName(widget.deck);

  void _pick({String? icon, String? color}) {
    setState(() {
      _icon = icon ?? _icon;
      _color = color ?? _color;
    });
    DeckStoreScope.of(context)
        .setDeckLook(widget.deck.id, icon: _icon, color: _color);
  }

  @override
  Widget build(BuildContext context) {
    final heading = lingoFont(
      size: 11,
      weight: FontWeight.w700,
      color: LingoColors.mutedInk,
      letterSpacing: 1.2,
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DeckIconTile(icon: _icon, color: _color, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.deck.name,
                    style: lingoFont(size: 17, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('COLOR', style: heading),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final MapEntry(key: name, value: look)
                    in kDeckColors.entries)
                  Semantics(
                    label: name,
                    selected: name == _color,
                    button: true,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _pick(color: name),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: look.swatch,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: name == _color
                                ? LingoColors.ink
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: name == _color
                            ? Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: look.tile,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('ICON', style: heading),
            const SizedBox(height: 10),
            GridView.extent(
              maxCrossAxisExtent: 60,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final name in kDeckIcons.keys)
                  Semantics(
                    label: name,
                    selected: name == _icon,
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _pick(icon: name),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: name == _icon
                                ? LingoColors.indigo
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: DeckIconTile(icon: name, color: _color),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    this.value,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: LingoColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: trailing == null ? 14 : 4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: lingoFont(size: 15, weight: FontWeight.w600),
                  ),
                ),
                if (value != null)
                  Flexible(
                    child: Text(
                      value!,
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: lingoFont(
                        size: 14,
                        weight: FontWeight.w500,
                        color: LingoColors.mutedInk,
                      ),
                    ),
                  ),
                ?trailing,
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
      ),
    );
  }
}
