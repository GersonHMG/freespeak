# Pronunciation scoring

How an attempt at a sentence becomes a percentage, a colour per word, and
points.

## Idea

The score compares **sounds**, not spellings. The recording is turned into
the words a speech recognizer heard. Both those words and the sentence are
converted to phonemes by the same grapheme-to-phoneme function, and the score
is the share of the sentence's phonemes that survive an optimal alignment
with what was heard.

## Overview

Example: the sentence is "I think so" and the learner says "I tink so".

```text
   Learner speaks                           Sentence to practise
   "I tink so"                              "I think so"
        |                                         |
        v                                         |
  +------------+                                  |
  |    Vosk    |  speech -> words, and when       |
  +------------+  each word was said              |
        |                                         |
        |  heard: "i tink so"                     |
        |  (nothing heard -> no score)            |
        v                                         v
  +------------+                            +------------+
  |   eSpeak   |  words -> sounds           |   eSpeak   |
  +------------+                            +------------+
        |                                         |
        |  aɪ tɪŋk soʊ                            |  aɪ θɪŋk soʊ
        |                                         |
        +--------------------+--------------------+
                             |
                             v
                +-------------------------+
                |   Line up the sounds    |
                |   (edit distance)       |
                +-------------------------+
                             |
                             |  1 sound differs: θ -> t, in "think"
                             v
                +-------------------------+
                |  Count sounds kept,     |
                |  per word and in total  |
                +-------------------------+
                             |
     +---------------+-------+--------+--------------------+
     v               v                v                    v
  Word colour    Sentence score   Points              Replay clip
  I      100 %   8 of 9 sounds    89 x difficulty,    tap "think" to
  think   75 %   = 89 %, green,   less on each        hear yourself
  so     100 %   success sound    retry               (Vosk's times)
```

Both sides go through the same eSpeak, so spelling never matters, only
sounds. Everything shown to the learner comes from that one line-up of
sounds. The sections below give the exact rules.

## 1. Notation

- The reference sentence is the word sequence $w_1, \dots, w_n$.
- The recognizer returns heard words $v_1, \dots, v_m$, each with a time
  interval $[s_k, t_k]$ in the recording.
- If $m = 0$, nothing was heard. The attempt gets **no score**, rather than a
  score of 0.
- $G$ maps a word to its phoneme string over an alphabet $\Sigma$. The same
  $G$ is applied to both sides.
- $N$ cleans a phoneme string: it removes stress marks, punctuation and
  spaces, and lowercases it. Stress is dropped on purpose, so that a stress
  slip does not cost as much as a wrong sound.

Each word's phonemes are

$$
\rho_i = N(G(w_i)), \qquad \eta_k = N(G(v_k)),
$$

and $p_i = |\rho_i|$ is the length of $\rho_i$, counted in symbols. A
diphthong written with two symbols, such as /aɪ/, counts as two.

## 2. One sequence per side

Concatenate each side into one sequence:

$$
P = \rho_1 \rho_2 \cdots \rho_n, \qquad Q = \eta_1 \eta_2 \cdots \eta_m .
$$

Every symbol remembers its word:

- $o(i) \in \{1, \dots, n\}$ is the reference word that symbol $P_i$ belongs
  to;
- $\sigma(k) \in \{1, \dots, m\}$ is the heard word that symbol $Q_k$ belongs
  to.

Words are not paired up beforehand. The whole sentence is aligned at once,
so the method handles skipped words, extra words, and words run together
(*a napple* for *an apple*).

## 3. Alignment

This is the Levenshtein distance from $P$ to $Q$. A substitution, a deletion
(a sentence sound not said) and an insertion (an extra sound) each cost 1.
One change makes it fit speech: **free end gaps on $Q$**.

$$
C(0, j) = 0, \qquad C(i, 0) = i,
$$

$$
C(i, j) = \min
\begin{cases}
C(i-1, j-1) + [P_i \ne Q_j] & \text{match or substitution} \\
C(i-1, j) + 1 & \text{deletion} \\
C(i, j-1) + 1 & \text{insertion}
\end{cases}
$$

$$
d = \min_{0 \le j \le |Q|} C(|P|, j).
$$

Because $C(0, j) = 0$, heard sounds before the sentence starts are free.
Because $d$ takes the minimum over the last row, heard sounds after the
sentence ends are free too. That way a stray word picked up before the
sentence, or a breath after it, costs nothing. Sounds of $P$ are never free:
a sentence sound that was not said is exactly the error being measured.

The optimal path $\pi$ is recovered by backtracking from the chosen end
column. When several columns tie, the largest $j$ is taken, so that as much
of $Q$ as possible is aligned rather than discarded.

## 4. Charging errors to words

Every non-match step of $\pi$ is charged to one reference word:

- A **substitution** or **deletion** at $P_i$ is charged to $o(i)$.
- An **insertion** consumes no reference symbol. Let $c$ be the number of
  reference symbols consumed so far. The insertion is charged to $o(c+1)$,
  the word being said or, at a word boundary, the **next** word. After the
  last symbol it is charged to $o(|P|)$.

The rule at the boundary is deliberate. A sound added before a word belongs
to that word, not to the one that already finished correctly.

Let $e_i$ be the number of edits charged to word $w_i$. Every step is
charged exactly once, so

$$
\sum_{i=1}^{n} e_i = d .
$$

The heard words that supplied sounds to $w_i$ form the set

$$
H_i = \{\, \sigma(k) : \pi \text{ aligns } Q_k \text{ to a symbol charged to } w_i \,\}.
$$

- If $H_i = \varnothing$, the word was **skipped**.
- If $|H_i| > 1$, the word was spread across several heard words.

## 5. Scores

**Word accuracy**, the share of the word's sounds that survived, clamped:

$$
a_i = 100 \cdot \operatorname{clamp}\!\left( \frac{p_i - e_i}{p_i},\ 0,\ 1 \right).
$$

**Sentence accuracy** is a single ratio over the totals, not the mean of
the $a_i$:

$$
A = \operatorname{round}\!\left( 100 \cdot \operatorname{clamp}\!\left( \frac{\sum_i p_i - d}{\sum_i p_i},\ 0,\ 1 \right) \right).
$$

Two consequences:

- Words are weighted by their length $p_i$, so a mistake in a short word
  costs less than one in a long word.
- Because each $a_i$ is clamped but $A$ is not clamped per word, a word said
  far too long stops at $a_i = 0$, while the sentence still pays every extra
  edit.

**Unscorable words.** A word with $p_i = 0$ scores $a_i = 0$. It contributes
nothing to either sum, so it leaves $A$ unchanged. When $\sum_i p_i = 0$,
$A = 0$.

## 6. Bands

The same thresholds colour words and sentences:

$$
b(x) =
\begin{cases}
\text{green (good)} & x \ge 80 \\
\text{orange (mediocre)} & 60 \le x < 80 \\
\text{red (bad)} & x < 60
\end{cases}
$$

Word $w_i$ is coloured $b(a_i)$, and the sentence is coloured $b(A)$. The
success sound plays only when $b(A)$ is green.

## 7. Playback clip per word

Word $w_i$ is played back from the recording interval

$$
\left[\ \min_{k \in H_i} s_k,\ \ \max_{k \in H_i} t_k\ \right],
$$

or from no interval when $H_i = \varnothing$. Timing is read from the same
path as the scores, but nothing in the scores depends on it.

## 8. Points

**Difficulty multiplier** $\mu$, from the sentence's word count $n$:

$$
\mu(n) =
\begin{cases}
1.0 & n \le 8 \\
1.3 & 9 \le n \le 20 \\
1.6 & n \ge 21
\end{cases}
$$

**Raw points** for an attempt:

$$
r = \operatorname{round}(A \cdot \mu).
$$

**Retry decay.** For the $k$-th attempt at the same sentence in a session,

$$
\delta(k) =
\begin{cases}
1 & k = 1 \\
\max\!\left(0.8^{\,k-1},\ 0.4\right) & k \ge 2
\end{cases}
$$

$$
\text{award}_k = \operatorname{round}(r \cdot \delta(k)).
$$

Every attempt adds points, but each one less than the last. After the fifth
attempt, $0.8^{k-1}$ falls below the 0.4 floor, so each further attempt pays
40% of its raw points.

**Maximum shown.** The "out of" figure counts only attempts that were
actually made, as if each had scored 100:

$$
\sum_{\text{attempts}} \operatorname{round}(100 \cdot \mu \cdot \delta(k)).
$$

## 9. Worked example

The sentence is **"I think so"** and the learner says *tink*. The phonemes
are approximate.

| $w_i$ | $\rho_i$ | heard | $p_i$ | $e_i$ | $a_i$ | band |
|---|---|---|---|---|---|---|
| I | aɪ | aɪ | 2 | 0 | 100 | green |
| think | θɪŋk | tɪŋk | 4 | 1 | 75 | orange |
| so | soʊ | soʊ | 3 | 0 | 100 | green |

$$
A = \operatorname{round}\!\left(100 \cdot \tfrac{9 - 1}{9}\right) = 89 \quad \Rightarrow \quad \text{green}.
$$

The sentence has 3 words, so $\mu = 1$:

- first attempt: $r = 89$ points;
- second attempt at the same accuracy: $\operatorname{round}(89 \cdot 0.8) = 71$.

## 10. What the score measures

The heard side is $Q = N(G(v_1)) \cdots N(G(v_m))$. It depends on the audio
**only through the recognized word sequence** $v_1, \dots, v_m$, and each
$G(v_k)$ is a dictionary pronunciation. As a result:

- $A = 100$ exactly when the recognized words phonemize to $P$, apart from
  the free ends, whatever the accent.
- A word misrecognized as a different word is scored as if that other word
  had been said.
- The method can only detect a sound error if it changes the word the
  recognizer outputs. For example, *tink* in the worked example is only
  detected if the recognizer writes *tink* and not *think*.

Two further limits:

- Numbers are written differently by the two sides (*2:30* in the sentence,
  *two thirty* from the recognizer), so $G$ produces different sounds and
  sentences with digits score low.
- Both the recognizer and $G$ are US English.

Scoring the sounds directly from the audio was also tried: goodness of
pronunciation from a CTC phoneme model, and phoneme recognizers that output
$Q$ straight from the audio. It was dropped.
