// "Revisit mispronunciations": the learner's missed words and missed
// sentences, worst first, as two tabs of one screen. A word opens a
// single-word drill that runs until they leave it; a sentence re-runs as a
// one-phrase session.

import 'package:flutter/material.dart';

import '../data/practice_history_scope.dart';
import '../data/practice_history_store.dart';
import '../widgets/mispronounced_sentence_tile.dart';
import '../widgets/mispronounced_word_tile.dart';
import 'practice_screen.dart';
import 'session_screen.dart';

class RevisitScreen extends StatelessWidget {
  const RevisitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Revisit mispronunciations'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Words'),
              Tab(text: 'Sentences'),
            ],
          ),
        ),
        body: const TabBarView(children: [_MissedWords(), _MissedSentences()]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(text, style: Theme.of(context).textTheme.bodyMedium));
}

class _MissedWords extends StatelessWidget {
  const _MissedWords();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MispronouncedWord>>(
      future: PracticeHistoryScope.of(context).mispronouncedWords(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final words = snapshot.data ?? const <MispronouncedWord>[];
        if (words.isEmpty) return const _Empty('No missed words yet.');

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: words.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final word = words[index];
            return MispronouncedWordTile(
              word: word,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PracticeScreen.singleWord(
                    word.word,
                    // The recognizer's shortlist for this drill: the word
                    // itself plus its nearest rivals from the same list.
                    decoys: [
                      for (final other in words.take(6))
                        if (other.word != word.word) other.word,
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MissedSentences extends StatelessWidget {
  const _MissedSentences();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MispronouncedSentence>>(
      future: PracticeHistoryScope.of(context).mispronouncedSentences(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final sentences = snapshot.data ?? const <MispronouncedSentence>[];
        if (sentences.isEmpty) {
          return const _Empty('No sentences to revisit yet.');
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: sentences.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final sentence = sentences[index];
            return MispronouncedSentenceTile(
              sentence: sentence,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SessionScreen(
                    phrases: [sentence.sentence],
                    awardsPoints: false,
                    // Done here means back to this list, not a scorecard
                    // for a session of one sentence.
                    showsSummary: false,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
