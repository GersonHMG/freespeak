# Recall grade suggestion

How the Recall card picks the grade it pre-selects, **Wrong**, **Partial** or
**Perfect**, after the learner answers.

## Purpose

The suggestion is only a pre-selection; the learner's tap is the grade. A
sentence can be translated in many ways, so the method measures only **how
closely the answer's wording follows one of the card's known ways to say
it**. It does not judge whether the meaning is right. Where wording alone
cannot tell a mistake from a new correct phrasing, it makes **no
suggestion**.

Typed and dictated answers are treated the same way. "I don't know" is
graded Wrong without any comparison.

## 1. Notation

- $a$ is the learner's answer.
- $R = \{r_1, \dots, r_K\}$ is the set of ways to say it: the card's own
  references and the learner's saved ones. A way saved during the session
  counts at once.
- $T$ maps a sentence to a sequence of words, described next.

## 2. Words

$T(x)$ is built in two steps.

1. **Normalize** $x$: lowercase it, remove punctuation (apostrophes stay),
   and collapse runs of spaces.
2. **Expand contractions**: *n't* → *not*, *'re* → *are*, *'ve* → *have*,
   *'ll* → *will*, *'m* → *am*, *'d* → *would*, and *can't* → *can not*,
   *won't* → *will not*, *let's* → *let us*.

A final *'s* becomes *is* only after a pronoun or question word (*it's*,
*that's*, *where's*…). In any other word, such as *John's*, it is left
alone, because it is a possessive.

For example, *"I'm hungry."* and *"i am hungry"* both give
$(\text{i}, \text{am}, \text{hungry})$.

## 3. Word weights

Let $F$ be a fixed set of English **function words**: articles,
determiners, personal pronouns, auxiliaries, common prepositions and
conjunctions. These are words a translation can drop, add or swap without
changing much of what it says. *Not* is deliberately excluded from $F$,
because a negation changes the meaning.

$$
c(w) =
\begin{cases}
0.3 & w \in F \\
1 & \text{otherwise}
\end{cases}
$$

## 4. Two word relations

Let $L(x, y)$ be the letter-level Levenshtein distance between $x$ and $y$,
and $\ell = \max(|x|, |y|)$ the length of the longer word.

**Misspelling.** $x \approx y$ means $x$ reads as $y$ misspelt:

$$
x \approx y \iff \ell \ge 4 \ \wedge\ \neg(x \in F \wedge y \in F) \ \wedge\ L(x, y) \le \tau(\ell),
\qquad
\tau(\ell) =
\begin{cases}
1 & \ell < 8 \\
2 & \ell \ge 8
\end{cases}
$$

The conditions exclude two kinds of pairs:

- Short words such as *in/on* or *the/she* are different words, not typos.
- A swap between two function words is a real slip, even if a cheap one.

**Shared root.** $x \sim y$ means $x$ and $y$ read as forms of one word. Let
$\lambda(x, y)$ be the length of their longest common prefix. Then

$$
x \sim y \iff \lambda(x, y) \ge 4 \ \wedge\ \lambda(x, y) \ge 0.6 \cdot \min(|x|, |y|).
$$

This stands in for a stemmer:

- *walk/walking* and *hunger/hungry* pass;
- *went/go* and *start/stand* do not.

## 5. Weighted alignment

Each pair of words $(x, y)$ has a swap cost:

$$
s(x, y) =
\begin{cases}
0 & x = y \\
0.1 & x \approx y \\
\min\big(0.5,\ \max(c(x), c(y))\big) & x \sim y \\
\max(c(x), c(y)) & \text{otherwise}
\end{cases}
$$

Let $A = T(a) = (x_1, \dots, x_p)$ and $B = T(r) = (y_1, \dots, y_q)$. The
alignment cost $D$ is a Levenshtein distance over words. Inserting or
deleting a word costs that word's weight, and swapping costs $s$:

$$
D(0, 0) = 0, \qquad
D(i, 0) = \sum_{u \le i} c(x_u), \qquad
D(0, j) = \sum_{v \le j} c(y_v),
$$

$$
D(i, j) = \min
\begin{cases}
D(i-1, j-1) + s(x_i, y_j) \\
D(i-1, j) + c(x_i) \\
D(i, j-1) + c(y_j)
\end{cases}
$$

and $D(a, r) = D(p, q)$.

So a typo or a dropped *the* costs little, another form of the right word
costs half a word, and a different content word costs a whole word.

## 6. Score

The cost is divided by the reference's own total weight

$$
W(r) = \sum_{j=1}^{q} c(y_j),
$$

so that one slip costs a short sentence more than a long one. The score
against one reference, and the overall score, are

$$
\operatorname{sim}(a, r) = \max\!\left(0,\ 1 - \frac{D(a, r)}{W(r)}\right),
\qquad
S = \max_{r \in R}\ \operatorname{sim}(a, r) \in [0, 1].
$$

There is no score when $T(a)$ is empty or $R$ is empty.

## 7. Suggestion

$$
g(S) =
\begin{cases}
\text{Perfect} & S \ge 0.9 \\
\text{Partial} & 0.6 \le S < 0.9 \\
\text{none} & 0.3 \le S < 0.6 \\
\text{Wrong} & S < 0.3
\end{cases}
$$

The **none** band is how the method stays honest about paraphrases. A score
in that range could come from a wrong answer or from a correct one worded
differently, so the method leaves the decision to the learner.

**Why a typo costs 0.1.** With a cost of 0.2, a single typo in a three-word
answer would give $S = 1 - 0.2/1.6 = 0.875$, which is Partial. With 0.1 it
gives $S = 0.9375$, which is Perfect.

## 8. Worked examples

| Answer $a$ | Closest $r$ | $D$ | $W(r)$ | $S$ | $g(S)$ |
|---|---|---|---|---|---|
| i AM hungry! | I'm hungry. | 0 | 1.6 | 1.000 | Perfect |
| I am hungy | I am hungry | 0.1 | 1.6 | 0.938 | Perfect |
| I would like to buy new car | I would like to buy a new car | 0.3 | 5.2 | 0.942 | Perfect |
| Where is the station | Where is the train station | 1 | 3.6 | 0.722 | Partial |
| I have hunger | I'm hungry. | 0.3 + 0.5 | 1.6 | 0.500 | none |
| I am thirsty | I am hungry | 1 | 1.6 | 0.375 | none |
| The cat sleeps | I am hungry | ≥ 1.6 | 1.6 | 0.000 | Wrong |

*I have hunger* is a word-for-word rendering of *tengo hambre*. The swap
*have → am* costs 0.3 because both are function words, and
*hunger → hungry* costs 0.5 because they share a root.

## 9. Measuring agreement

Each review records the suggestion $g$ (or none) and the grade the learner
actually gave, $\gamma$. Over the reviews where a suggestion was made,

$$
\text{agreement} = \frac{\#\{\, g = \gamma \,\}}{\#\{\, g \ne \text{none} \,\}}.
$$

The confusion matrix of $(g, \gamma)$ shows which band disagrees most, and
in which direction.

## 10. Limitations

- **Paraphrases.** A correct answer that shares few words with every
  $r \in R$ lands in *none*, or in *Wrong* if it shares almost none. Once the
  learner saves it as one of their own ways to say it, it joins $R$ and
  matches next time. The planned next step is a meaning comparison
  (sentence embeddings) used as a gate before the wording score.
- **The root relation is generous.** *station* $\sim$ *state*, so that swap
  costs 0.5 instead of 1.
- **A typo can hide a different word.** *ship* $\approx$ *shop*, so
  answering one for the other costs only 0.1.
- **English only.** $F$ and the contraction rules are English.
- **Recognition errors in dictated answers** count as wording errors. The
  recognizer's confidence does not adjust $S$ yet.
