import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/decks/answer_match.dart';
import 'package:lingo_node/decks/deck_models.dart';

void main() {
  group('matchAnswer', () {
    test('an answer that only differs in case, punctuation or contractions '
        'is a full match', () {
      final match = matchAnswer('i AM hungry!', ["I'm hungry."])!;
      expect(match.score, 1);
      expect(match.suggestedGrade, Grade.easy);
    });

    test('a typo still suggests Perfect', () {
      // D = 0.1 (hungy for hungry), W = 0.3 + 0.3 + 1 = 1.6.
      final match = matchAnswer('I am hungy', ['I am hungry'])!;
      expect(match.score, closeTo(1 - 0.1 / 1.6, 1e-9));
      expect(match.suggestedGrade, Grade.easy);
    });

    test('a dropped article costs a function word', () {
      // D = 0.3 (a), W = 0.3+0.3+1+0.3+1+0.3+1+1 = 5.2.
      final match = matchAnswer('I would like to buy new car', [
        'I would like to buy a new car',
      ])!;
      expect(match.score, closeTo(1 - 0.3 / 5.2, 1e-9));
      expect(match.suggestedGrade, Grade.easy);
    });

    test('a missing content word suggests Partial', () {
      // D = 1 (train), W = 1 + 0.3 + 0.3 + 1 + 1 = 3.6.
      final match = matchAnswer('Where is the station', [
        'Where is the train station',
      ])!;
      expect(match.score, closeTo(1 - 1 / 3.6, 1e-9));
      expect(match.suggestedGrade, Grade.medium);
    });

    test('a different content word in a short answer suggests nothing', () {
      // D = 1, W = 1.6: too far to call Partial, not far enough to call
      // Wrong -- it could be a new way of saying it.
      final match = matchAnswer('I am thirsty', ['I am hungry'])!;
      expect(match.score, closeTo(0.375, 1e-9));
      expect(match.suggestedGrade, isNull);
    });

    test('another form of the right word costs half a word', () {
      // D = 0.3 (have for am) + 0.5 (hunger for hungry), W = 1.6.
      final match = matchAnswer('I have hunger', ["I'm hungry."])!;
      expect(match.score, closeTo(0.5, 1e-9));
      expect(match.suggestedGrade, isNull);
    });

    test('a negation is not a slip', () {
      expect(
        matchAnswer('I am not hungry', ['I am hungry'])!.suggestedGrade,
        isNot(Grade.easy),
      );
    });

    test('an answer with nothing in common suggests Wrong', () {
      final match = matchAnswer('The cat sleeps', ['I am hungry'])!;
      expect(match.score, 0);
      expect(match.suggestedGrade, Grade.difficult);
    });

    test('takes the closest of the ways to say it', () {
      final match = matchAnswer("I'm hungry", [
        'I am starving',
        'I am hungry',
      ])!;
      expect(match.referenceIndex, 1);
      expect(match.score, 1);
    });

    test('is null with nothing to compare', () {
      expect(matchAnswer('', ['I am hungry']), isNull);
      expect(matchAnswer('?!', ['I am hungry']), isNull);
      expect(matchAnswer('I am hungry', []), isNull);
    });
  });

  group('expandContraction', () {
    test('spells out contractions', () {
      expect(expandContraction("don't"), ['do', 'not']);
      expect(expandContraction("can't"), ['can', 'not']);
      expect(expandContraction("we're"), ['we', 'are']);
      expect(expandContraction("it's"), ['it', 'is']);
    });

    test("leaves a possessive 's alone", () {
      expect(expandContraction("john's"), ["john's"]);
    });
  });

  group('sameRoot', () {
    test('matches forms of one word', () {
      expect(sameRoot('walk', 'walking'), isTrue);
      expect(sameRoot('hunger', 'hungry'), isTrue);
    });

    test('does not match words that only start alike', () {
      expect(sameRoot('start', 'stand'), isFalse);
      expect(sameRoot('went', 'go'), isFalse);
    });
  });

  group('isTypo', () {
    test('allows one letter off in a mid-length word', () {
      expect(isTypo('hungy', 'hungry'), isTrue);
      expect(isTypo('hungyr', 'hungry'), isFalse); // Two swaps.
    });

    test('allows two in a long word', () {
      expect(isTypo('restarant', 'restaurant'), isTrue);
    });

    test('does not count short words or two function words', () {
      expect(isTypo('in', 'on'), isFalse);
      expect(isTypo('the', 'she'), isFalse);
      expect(isTypo('with', 'what'), isFalse);
      expect(isTypo('this', 'these'), isFalse);
    });
  });
}
