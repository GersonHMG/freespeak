// A bench for the TTS pipeline. Text goes in; out come the phonemes the app
// shows and scores against, the audio Phonon speaks, and when it speaks each
// word. Tap a word to hear the clip cut for it -- the timings are only as good
// as that clip sounds.

import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../tts/espeak_phonemizer.dart';
import '../../tts/phonon_tts.dart';

class TtsDebugScreen extends StatefulWidget {
  // Passed in rather than read from PhononTtsScope: this screen is opened as a
  // pushed route, and the Navigator sits above the scope in the tree, so an
  // inherited lookup from here finds nothing.
  const TtsDebugScreen({super.key, required this.tts});

  final PhononTts tts;

  @override
  State<TtsDebugScreen> createState() => _TtsDebugScreenState();
}

class _TtsDebugScreenState extends State<TtsDebugScreen> {
  final TextEditingController _text = TextEditingController(
    text: 'The rain in Spain stays mainly in the plain',
  );
  final AudioPlayer _player = AudioPlayer();

  bool _busy = false;
  // Built on first use and kept: initialization unpacks the eSpeak data on a
  // cold install. Only used for the fixture capture — everything else goes
  // through the app's own phonemizer, so what this screen prints is exactly
  // what a session would show.
  EspeakPhonemizer? _capture;
  String? _error;
  String _phonemes = '';
  Speech? _speech;
  Duration? _elapsed;

  @override
  void dispose() {
    _text.dispose();
    _player.dispose();
    _capture?.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (err) {
      if (mounted) setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _speak() => _run(() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final timer = Stopwatch()..start();
    final speech = await widget.tts.speakTimed(text);
    final elapsed = timer.elapsed;
    final phonemes = await widget.tts.phonemesFor(text);
    if (!mounted) return;
    setState(() {
      _speech = speech;
      _elapsed = elapsed;
      _phonemes = phonemes;
    });
    await _player.play(DeviceFileSource(speech.path));
  });

  Future<void> _playWord(int index) async {
    final speech = _speech;
    if (speech == null) return;
    final path = await widget.tts.wordClip(speech, index);
    if (path != null) await _player.play(DeviceFileSource(path));
  }

  /// The phrases `test/fixtures/espeak_en_us.json` expects, kept in step with
  /// it by hand — this is the one place that has a real eSpeak to ask.
  static const List<String> _fixturePhrases = [
    'Hello world!',
    'the cat sat on a mat',
    r'It costs $5.99',
    'thirty little water bottles',
    'The rain in Spain stays mainly in the plain',
  ];

  /// Phonemizes every word of [_fixturePhrases] and puts the result on the
  /// clipboard, ready to paste over `test/fixtures/espeak_en_us.json`.
  ///
  /// A separate instance from the app's, so a capture is unaffected by
  /// anything the screen has been doing to the shared one.
  Future<void> _copyFixture() => _run(() async {
    final espeak = _capture ??= EspeakPhonemizer(voice: widget.tts.lang);

    // Same cleaning the phonemizer applies per word, so the keys match what
    // the tests will look up.
    final words = <String, String>{};
    for (final phrase in _fixturePhrases) {
      for (final word in phrase.split(RegExp(r'\s+'))) {
        final key = word
            .replaceAll(RegExp(r"[^A-Za-z0-9'.\-$€£¥%]"), '')
            .toLowerCase();
        if (key.isEmpty || words.containsKey(key)) continue;
        words[key] = await espeak.phonemize(word, widget.tts.lang);
      }
    }

    final json = const JsonEncoder.withIndent('  ').convert({
      '_comment': [
        'Captured on device by the TTS debugger. Do not hand-edit.',
        'Regenerate with the "Copy fixture JSON" button.',
      ],
      'phrases': _fixturePhrases,
      'words': words,
    });
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${words.length} words copied — paste over the fixture'),
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speech = _speech;
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');

    return Scaffold(
      appBar: AppBar(title: const Text('TTS debugger')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _text,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Text',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _speak,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.volume_up),
              label: const Text('Speak'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy || !EspeakPhonemizer.isSupported
                    ? null
                    : _copyFixture,
                icon: const Icon(Icons.download),
                label: const Text('Copy fixture JSON'),
              ),
            ),
            const SizedBox(height: 8),

            if (_error != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),

            if (_phonemes.isNotEmpty) ...[
              Text('Phonemes', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              SelectableText(
                _phonemes,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 18),
              ),
              const SizedBox(height: 16),
            ],

            if (speech != null) ...[
              Text(
                '${(speech.waveform.length / kSampleRate * 1000).round()} ms '
                'audio in ${_elapsed!.inMilliseconds} ms '
                '(a repeat comes from the cache)',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Words — tap to hear the clip',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < speech.words.length; i++)
                InkWell(
                  onTap: () => _playWord(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '${speech.words[i].text.padRight(14)} '
                      '${speech.words[i].start.inMilliseconds}-'
                      '${speech.words[i].end.inMilliseconds} ms   '
                      '${speech.words[i].phonemes}',
                      style: mono,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
