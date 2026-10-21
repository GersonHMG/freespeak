import 'package:flutter/material.dart';

import '../decks/languages.dart';
import '../theme/lingo_theme.dart';

/// The languages a learner can say they speak, as one plain list: a flag
/// and the language's own name ("Español", "中文"), nothing else -- a
/// learner scans for their language, not for details about it. The
/// languages with ready-made cards ([kKnownNativeLangs]), then "Another
/// language" ([kUnlistedLang]) for everyone else, who writes their own.
///
/// Used by the first-launch question and by Settings. Rows inside a
/// [Column] -- the caller scrolls it.
class LanguageList extends StatelessWidget {
  const LanguageList({required this.onChoose, this.selected, super.key});

  final ValueChanged<String> onChoose;

  /// The language currently chosen, marked with a check. Null for none.
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final code in [...kKnownNativeLangs, kUnlistedLang])
          _LanguageTile(
            code: code,
            selected: code == selected,
            onTap: () => onChoose(code),
          ),
      ],
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.code,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? LingoColors.indigoContainer : LingoColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Text(languageFlag(code), style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    code == kUnlistedLang
                        ? 'Another language'
                        : nativeLanguageName(code),
                    style: lingoFont(size: 17, weight: FontWeight.w700),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: LingoColors.indigo),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
