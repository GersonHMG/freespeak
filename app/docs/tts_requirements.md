# TTS model requirements

What a text-to-speech model must provide to replace Kokoro as the voice of
the app, and why each requirement exists.

## Purpose

The synthesized voice is the reference the learner imitates. Beyond playing
it, the app highlights each word as it is spoken, cuts single words and
syllables out of a phrase, and plays phrases slowed down. Every requirement
below comes from one of those uses. Kokoro, the current model, is the
reference point for the numbers.

Requirements fall into three groups:

- **Hard** (§2–§6): a model that fails one of these cannot be used as is.
- **Strong** (§7–§10): a model that fails one can still be used, but with
  extra work or worse quality.
- **Budgets** (§11): size and memory limits.

## 1. Notation

- A phrase is spoken as the phoneme sequence $p_1, \dots, p_n$, produced by
  the app's own G2P (eSpeak, American English).
- The model outputs a waveform of $N$ samples at sample rate $r$, so the
  phrase lasts $T = N / r$ seconds.
- $\tau_k$ is the moment phoneme $p_k$ starts in the waveform, with
  $\tau_1 \ge 0$ and $\tau_{n+1} = T$.
- Word $w$ covers phonemes $i_w$ to $j_w$. It starts at
  $\tau^{\text{start}}_w = \tau_{i_w}$ and ends at
  $\tau^{\text{end}}_w = \tau_{j_w+1}$.

## 2. Timing of the spoken audio (hard)

The app must know **when each word is spoken** in the synthesized audio.
If syllable mode is kept, it must also know **when each phoneme is spoken**.

### What the times are used for

| Use | Needs | How it uses the times |
|---|---|---|
| Word highlighting | Word times | At playback time $t$, highlight the $w$ with $\tau^{\text{start}}_w \le t < \tau^{\text{end}}_w$ |
| Tap a word to hear it | Word times | Cut $[\tau^{\text{start}}_w - 40\text{ ms},\ \tau^{\text{end}}_w + 40\text{ ms}]$ |
| Slow phrase | Word times | Stretch the audio by $1/\rho$ and scale every time to $\tau / \rho$, with $\rho = 0.7$ |
| Syllable mode | Phoneme times | A syllable over phonemes $a..b$ is cut from $[\tau_a - 15\text{ ms},\ \tau_{b+1} + 15\text{ ms}]$ |

Only syllable mode needs times inside a word. The other three need only each
word's two edges.

### Accuracy

- **Word edges** must be within about 40 ms of the true boundary. A larger
  error clips a consonant or lets in the neighbouring word.
- **Phoneme boundaries**, for syllable mode, must be within about 15 ms.
- **Every word** of the phrase must get a time, not only the words a
  recognizer happened to catch.
- **The times must add up to the audio.** The last boundary must land at the
  end of the speech, give or take trailing silence. Otherwise every timing
  drifts.

### Where the times can come from

**Ideal: the model's own durations.** If the model decides how many frames
$d_k$ to spend on each input token before it generates audio, at $f$ frames
per second, then

$$
\tau_k = \frac{1}{f} \sum_{m < k} d_m, \qquad \frac{1}{f}\sum_{m=1}^{n} d_m = T.
$$

These times are exact, because they are the model's own plan. They cost
nothing extra. Kokoro works this way, with $f = 40$ frames per second
(24 000 samples per second, 600 samples per frame).

**Fallback: alignment after synthesis.** A model that generates audio frame
by frame has no such plan, so the times must be recovered from the audio
afterwards.

| Source of the times | Gives | Cost |
|---|---|---|
| Speech recognizer (Vosk) on the synthesized audio | Word times | One extra recognition pass per phrase. Recognized words must be matched back to the phrase, and missed words filled in, e.g. by splitting the gap between their neighbours by phoneme count. |
| Phoneme aligner on the synthesized audio | Phoneme times, within about 10–30 ms | A second acoustic model in the APK |
| Even split of each word's span over its phonemes | Phoneme times, poorly | None, but vowels last several times longer than stops, so syllable cuts land mid-sound |

So a model without durations is acceptable only if syllable mode is dropped
or a phoneme aligner is added.

## 3. Phoneme input (hard)

The model must accept IPA in eSpeak's phoneme inventory, rather than raw
text.

- **The voice says what the learner is scored on.** The app's G2P gives the
  phonemes that are displayed and used as the scoring reference. If the
  model converted text to sounds by itself, it could pronounce a word
  differently from what the learner is graded against.
- **Word times can be tied to phonemes.** With duration output (§2), word
  $w$'s position in the phoneme string maps directly onto the model's input
  tokens. The tokens of $p_{i_w}, \dots, p_{j_w}$ are the word.
- **Bad audio can be traced.** Synthesizing from a fixed phoneme string shows
  whether a mistake comes from the G2P or from the model.

If word times come from alignment after synthesis, the second point no
longer applies, but the first still does.

## 4. On-device and offline (hard)

- Runs on 64-bit ARM Android phones with no network connection.
- Loads through ONNX Runtime or a plain C library that Dart can call.
- Runs away from the UI thread, and can stay loaded for the whole session.
- Older ARM chips and the x86_64 emulator are nice to have. Kokoro's
  quantized model does not run on the emulator.

## 5. Licence (hard)

The weights and the voices must allow **commercial use** and
**redistribution inside the APK**, e.g. Apache-2.0 or MIT. Non-commercial
licences (CC BY-NC) and gated weights that cannot be redistributed rule a
model out.

## 6. Pronunciation quality (hard)

- **Faithful.** It speaks the given phonemes and stress exactly, with no
  stylistic liberties. Learners copy it.
- **Complete.** No skipped, repeated or invented words. The word error rate
  on hard sentences should be no worse than Kokoro's 3.5%.
- **Natural on single words.** The practice screen and flashcards play
  isolated words, not only sentences.

## 7. Speed (strong)

Let the real-time factor be

$$
\text{RTF} = \frac{\text{synthesis time}}{T}.
$$

The first phrase of a session is synthesized while the loading screen is
shown, and the rest are queued in the background, one at a time, while the
learner works. Synthesis must stay ahead of the learner, so $\text{RTF}$
should be **well below 1 on a mid-range phone, ideally $\le 0.3$**. Phrases
range from one word to one sentence, at most about 500 phonemes.

## 8. Cuttable audio (strong)

- No long or random silence at the start or end of the waveform.
- Phonemes blend little enough that a syllable cut with 15 ms of padding
  still sounds like that syllable.

## 9. Determinism (strong)

The same phonemes should give the same audio every time. The app caches
phrases and compares runs while debugging, so random sampling during
generation is a liability.

## 10. Output format (strong)

Mono audio with float samples at a fixed, known sample rate. 24 kHz matches
the existing audio handling (WAV output, clips, time stretch).

## 11. Budgets

- **Size:** the model plus one voice, about **100 MB at most**. Kokoro uses
  92 MB plus a 0.5 MB voice. APK size has already ruled out other models.
- **Memory:** fits in RAM alongside the Vosk recognizer.
- **Voice:** one clear American English voice is enough. More voices, a
  British English option, or streaming are not required.

## 12. Screening checklist

| # | Question | Ruled out if no |
|---|---|---|
| 1 | Does it give word times, and phoneme times for syllable mode (§2)? | Unless an aligner is added and its cost accepted |
| 2 | Does it accept IPA input (§3)? | Yes |
| 3 | Does it run on-device on ARM through ONNX Runtime or a C library (§4)? | Yes |
| 4 | Is the licence commercial-friendly and redistributable (§5)? | Yes |
| 5 | Is its pronunciation faithful and complete (§6)? | Yes |
| 6 | Is the RTF well below 1 on a phone (§7)? | Measure first |
| 7 | Is it at most about 100 MB (§11)? | Measure first |

### Kokoro and Phonon against the checklist

| Model | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| Kokoro (current) | ✓ phoneme durations | ✓ | ✓ ONNX | ✓ Apache-2.0 | ✓ | ✓ | ✓ 92 MB |
| phonon-40m-en | ✗ no times | ✗ text only | ✓ C library, newer ARM chips only | ✗ CC BY-NC, gated | ✓ better scores than Kokoro | unknown | ✓ 60–75 MB |
