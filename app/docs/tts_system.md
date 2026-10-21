# Text to speech

How a sentence becomes the voice the learner imitates, with a time span for
every word and syllable.

## Idea

The voice is **Phonon** (`phonon-31m-en`, Apache-2.0), a small speech model
that runs on the phone. It reads **text**, not phonemes. It reports no
timings of its own, so the times of the words are read from inside the model:
one of its attention heads follows the text as the audio is generated.
Syllables are then cut out of each word from the loudness of the audio.

## Overview

```text
   Sentence "I think so"
        |
        v
  +-----------------+
  |     Phonon      |  text -> 24 kHz audio, one frame every 80 ms,
  |  (on device)    |  paced about 17% slower than natural
  +-----------------+
        |                 \
        |  audio           \  attention of head (3, 0) over the text,
        |                   \ at every frame
        v                    v
  +-----------------+   +-------------------------+
  | Loudness of the |   |  Word boundaries where  |
  | audio           |-->|  the attention moves on |
  +-----------------+   +-------------------------+
        |                         |
        |                         |  I [0.00, 0.21]  think [0.21, 0.55] ...
        v                         v
  +-----------------+   +-------------------------+
  | Syllable cuts   |<--| Match Phonon's words to |
  | at loudness dips|   | the sentence's words    |
  +-----------------+   +-------------------------+
        |
        v
  Highlight while playing, replay one word, play a word syllable by
  syllable, play slower (time-stretched)
```

The phonemes shown on screen and used for scoring come from eSpeak-NG, not
from Phonon. The two are independent.

## 1. Notation

| Symbol | Meaning |
|---|---|
| $T$ | Number of text tokens Phonon reads |
| $k$ | Index of a generated audio frame |
| $\Delta$ | Frame length, 80 ms (1920 samples at 24 kHz) |
| $a_{kj}$ | Attention of the alignment head from frame $k$ to token $j$, softmaxed over the text |
| $w$ | Index of a word, $1, \dots, W$ |
| $\lambda$ | Look-ahead of the head, in seconds |

## 2. Pace

Phonon has a conditioning input for how long it makes speech last. The app
sets it so that speech comes out about 17% slower than the model's natural
pace. The slowing is the model's own, so it sounds natural; anything slower
than that (the "slow" button, rate 0.7) is a time stretch of the finished
audio (§6).

## 3. Word times

The alignment head is layer 3, head 0. It was picked from all 48 heads as the
one whose attention moves forward through the text most steadily over 40
test sentences.

At frame $k$, the head's attention is summed per word, with punctuation left
out:

$$
P_{kw} = \frac{\sum_{j \in w} a_{kj}}{\sum_{w'} \sum_{j \in w'} a_{kj}}.
$$

The expected word index is kept from going backwards:

$$
e_k = \max_{k' \le k} \sum_w w \, P_{k'w}.
$$

The boundary between words $w - 1$ and $w$ is where $e$ crosses
$w - \tfrac12$, interpolated between the centres of the two frames around
the crossing, $t_k = (k + \tfrac12)\,\Delta$. The head reads ahead of the
audio, so every boundary is moved later by $\lambda = 0.19$ s, the value
measured at the app's pace.

Then three corrections:

- The **first word's start** and the **last word's end** come from the
  audio's short-time energy, where speech begins and ends.
- At **punctuation only**, a boundary moves to the nearest silence of at
  least 80 ms within 350 ms, since a pause is where a comma is heard.
- A word the attention never reaches borrows its times from a neighbour.

## 4. Matching Phonon's words to the sentence's

Phonon rewrites some text before reading it: *3* becomes *three*, *9:30*
becomes *nine thirty*, *$5* becomes *five dollars*. So its words and the
sentence's words do not always line up one to one.

Words are matched where they agree (letters and digits only, case ignored).
These matches are anchors. Each run of sentence words between two anchors
takes the span of the spoken words between the same anchors, shared out in
proportion to the words' lengths.

## 5. Syllables

The model times words, not sounds, so syllables are found in the audio.
A syllable is built around a vowel, its loudest part, so the loudness dips
between syllables.

A word of $K$ syllables (counted from its eSpeak phonemes) is cut at
$K - 1$ dips of the short-time energy (20 ms windows, 10 ms hop). Dips also
happen inside a syllable, at a stop consonant's closure, so each cut is only
searched for near where it is expected: the word's span shared out by the
syllables' phonemes, vowels counting double. Within that window the cut goes
to the quietest point, with a mild pull toward the expected one. No syllable
is shorter than 50 ms.

## 6. Slow playback

Slower playback keeps the pitch by waveform-similarity overlap-add (WSOLA):
the output is built from overlapping windowed frames of the input, read at
a hop of $r$ times the hop they are written at ($r = 0.7$ for "slow"). Each
frame is shifted by up to one pitch period to wherever it best continues the
one before it.

## 7. Accuracy and cost

Word boundaries, judged against Vosk forced alignment on 40 sentences
(235 boundaries), at the app's pace:

| Mean error | Median | 90th percentile | Within 50 ms |
|---|---|---|---|
| 70 ms | 57 ms | 128 ms | 47% |

At the model's natural pace the mean error is 51 ms. The judge itself is
coarse (30 ms frames), so part of the error is the judge's.

| | Value |
|---|---|
| Model size | 64.5 MB (8-bit weights) and a 0.26 MB voice |
| Speed on a Windows desktop | 0.13 to 0.24 s of compute per second of audio |
| Speed on a phone | not measured yet |
| Same text, same audio | yes (fixed seed) |
| Phones it runs on | 64-bit ARM with the ARMv8.2 dot-product and half-precision extensions |

## 8. Limitations

- **Text in, not phonemes.** The voice may say a word differently from the
  eSpeak phonemes the app shows and scores against.
- **Word times are approximate.** About 70 ms mean error, measured on a
  desktop, not yet on a phone.
- **Syllables are guessed from loudness**, not from the model, so a word
  with no clear dip between syllables is cut at the expected point instead.
- **The runtime is a fork.** The attention probe and word timing live in a
  local fork of Phonon's `ptts` runtime that is not published yet; the app
  ships its prebuilt library.
- **Older phones are left out.** ARM chips without the ARMv8.2 extensions
  cannot run it.
