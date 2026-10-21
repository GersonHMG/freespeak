import 'package:flutter/material.dart';

import '../decks/deck_store_scope.dart';
import '../decks/seed_deck.dart';
import '../theme/lingo_theme.dart';
import '../widgets/language_list.dart';
import 'add_card_screen.dart';
import 'home_screen.dart';

/// The first-launch question: what language does the learner speak?
///
/// A language with a starter deck gets that deck and goes straight to Home.
/// "Another language" gets an empty deck and a short page inviting the
/// learner to write their own cards -- the app has nothing to show them
/// yet, and an empty Recall card on Home with no explanation would read as
/// broken. Either way the choice is saved, so this is asked once; Settings
/// changes it later.
class LanguageOnboardingScreen extends StatefulWidget {
  const LanguageOnboardingScreen({super.key});

  @override
  State<LanguageOnboardingScreen> createState() =>
      _LanguageOnboardingScreenState();
}

class _LanguageOnboardingScreenState extends State<LanguageOnboardingScreen> {
  bool _isSaving = false;

  /// Set once "Another language" is chosen: the "make your own cards" page
  /// shows instead of the list.
  int? _ownCardsDeck;

  Future<void> _choose(String code) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final deckId = await chooseNativeLanguage(
        DeckStoreScope.of(context),
        code,
        bundle: DefaultAssetBundle.of(context),
      );
      if (!mounted) return;
      if (kStarterDeckAssets.containsKey(code)) {
        _goHome();
      } else {
        setState(() {
          _ownCardsDeck = deckId;
          _isSaving = false;
        });
      }
    } catch (err) {
      debugPrint('[LanguageOnboardingScreen] choosing failed: $err');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not set that up. Try again.')),
      );
    }
  }

  void _goHome() => Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
  );

  Future<void> _addFirstCard(int deckId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AddCardScreen(deckId: deckId)),
    );
    if (mounted) _goHome();
  }

  @override
  Widget build(BuildContext context) {
    final ownDeck = _ownCardsDeck;
    return Scaffold(
      backgroundColor: LingoColors.background,
      body: SafeArea(
        child: ownDeck != null
            ? _OwnCardsIntro(
                onAddCard: () => _addFirstCard(ownDeck),
                onLater: _goHome,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                children: [
                  Text(
                    'What language do you speak?',
                    style: lingoFont(size: 26, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 20),
                  AbsorbPointer(
                    absorbing: _isSaving,
                    child: LanguageList(onChoose: _choose),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Shown after "Another language": the app is built around the learner's
/// own cards, so this asks for the first one.
class _OwnCardsIntro extends StatelessWidget {
  const _OwnCardsIntro({required this.onAddCard, required this.onLater});

  final VoidCallback onAddCard;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.post_add_rounded, size: 56, color: LingoColors.indigo),
          const SizedBox(height: 20),
          Text(
            'Make your own cards',
            textAlign: TextAlign.center,
            style: lingoFont(size: 24, weight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            "There are no ready-made cards in your language yet. Write a "
            "sentence you use every day and how you'd say it in English -- "
            "your cards become your daily practice.",
            textAlign: TextAlign.center,
            style: lingoFont(
              size: 15,
              weight: FontWeight.w500,
              color: LingoColors.mutedInk,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onAddCard,
            style: FilledButton.styleFrom(
              backgroundColor: LingoColors.indigo,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: lingoFont(size: 16, weight: FontWeight.w700),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add my first card'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onLater, child: const Text('Maybe later')),
        ],
      ),
    );
  }
}
