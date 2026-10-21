// "Custom practice": type any word or sentence and drill it, rather than
// picking from what a past session already flagged. A single word (no
// spaces) becomes a [PracticeScreen.singleWord] drill, split into syllables
// it can play slowly as Word Rematch does; anything with a space
// is treated as a sentence and run as a one-phrase [SessionScreen].
//
// Neither path saves its attempt (saveAttempt: false): arbitrary typed-in
// text isn't real pronunciation history, and must not show up later in the
// mispronounced-words/-sentences lists or feed Word Rematch.

import 'package:flutter/material.dart';

import 'practice_screen.dart';
import 'session_screen.dart';

class CustomPracticeScreen extends StatefulWidget {
  const CustomPracticeScreen({super.key});

  @override
  State<CustomPracticeScreen> createState() => _CustomPracticeScreenState();
}

class _CustomPracticeScreenState extends State<CustomPracticeScreen> {
  final TextEditingController _controller = TextEditingController();
  String _text = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isSentence => _text.trim().contains(RegExp(r'\s'));

  void _start() {
    final text = _text.trim();
    if (text.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _isSentence
            ? SessionScreen(
                phrases: [text],
                awardsPoints: false,
                saveAttempt: false,
                showsSummary: false,
              )
            : PracticeScreen.singleWord(
                text,
                saveAttempt: false,
                showsSyllables: true,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canStart = _text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Custom practice')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Type a word or a full sentence to practice it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (value) => setState(() => _text = value),
              onSubmitted: (_) => _start(),
              decoration: const InputDecoration(
                hintText: 'e.g. "pronunciation" or "She sells seashells"',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: canStart ? _start : null,
              child: Text(_isSentence ? 'Start sentence' : 'Start word'),
            ),
          ],
        ),
      ),
    );
  }
}
