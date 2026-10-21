// Language names for the codes decks store (`decks.native_lang`,
// `decks.target_lang`, ISO 639-1). Screens show these instead of naming a
// language themselves, so nothing in the UI assumes a particular pair: a
// deck says which languages it is in, and the labels follow.
//
// The languages a learner can choose are [kKnownNativeLangs] -- the ones
// the bundled decks are translated into ([kStarterDeckAssets],
// seed_deck.dart) -- and [kUnlistedLang], "Another language". The names and
// flags below cover more, for decks and labels.

/// The pair a new deck gets when nothing else says otherwise -- the "My
/// cards" fallback deck before the learner has chosen a language.
const String kDefaultNativeLang = 'es';
const String kDefaultTargetLang = 'en';

/// How a card's prompt side is labelled everywhere it is studied or
/// written: "your language", never the language's name. The learner knows
/// what they speak; naming it on every card (and every deck) is noise, and
/// wrong for a deck in a language they no longer have set. Only the places
/// that are about choosing the language -- the first-launch question and
/// Settings -- name it.
const String kYourLanguage = 'Your language';

/// "Undetermined" (ISO 639-2): "Another language", the picker's last row,
/// for a learner whose language has no starter deck. They start with an
/// empty deck of their own, and labels say "your language" rather than a
/// code.
const String kUnlistedLang = 'und';

/// The languages a learner can say they speak, in the order the picker
/// lists them: the ones the bundled decks are translated into. English is
/// left out: it is the language being learned.
const List<String> kKnownNativeLangs = ['es', 'pt', 'fr', 'zh', 'hi', 'ar'];

const Map<String, (String english, String native)> _names = {
  'ar': ('Arabic', 'العربية'),
  'bn': ('Bengali', 'বাংলা'),
  'de': ('German', 'Deutsch'),
  'en': ('English', 'English'),
  'es': ('Spanish', 'Español'),
  'fr': ('French', 'Français'),
  'hi': ('Hindi', 'हिन्दी'),
  'id': ('Indonesian', 'Bahasa Indonesia'),
  'it': ('Italian', 'Italiano'),
  'ja': ('Japanese', '日本語'),
  'ko': ('Korean', '한국어'),
  'pt': ('Portuguese', 'Português'),
  'ru': ('Russian', 'Русский'),
  'tr': ('Turkish', 'Türkçe'),
  'ur': ('Urdu', 'اردو'),
  'vi': ('Vietnamese', 'Tiếng Việt'),
  'zh': ('Chinese', '中文'),
};

/// The English name of language [code] -- "Your language" for
/// [kUnlistedLang], or the code itself upper-cased when it is not one the
/// app knows, a label that still says something rather than nothing.
String languageName(String code) {
  if (code == kUnlistedLang) return 'Your language';
  return _names[code]?.$1 ?? code.toUpperCase();
}

/// What the language calls itself ("Español", "中文"), for the language
/// picker, where a learner looks for their own language's name. Falls back
/// to [languageName].
String nativeLanguageName(String code) =>
    _names[code]?.$2 ?? languageName(code);

const Map<String, String> _flags = {
  'ar': '🇸🇦',
  'bn': '🇧🇩',
  'de': '🇩🇪',
  'en': '🇬🇧',
  'es': '🇪🇸',
  'fr': '🇫🇷',
  'hi': '🇮🇳',
  'id': '🇮🇩',
  'it': '🇮🇹',
  'ja': '🇯🇵',
  'ko': '🇰🇷',
  // The Portuguese starter deck is written in Brazilian Portuguese.
  'pt': '🇧🇷',
  'ru': '🇷🇺',
  'tr': '🇹🇷',
  'ur': '🇵🇰',
  'vi': '🇻🇳',
  'zh': '🇨🇳',
};

/// A flag for language [code] -- the country most associated with it, which
/// is a stand-in, not a claim that the language belongs to one country. A
/// globe for [kUnlistedLang] or a language without one.
String languageFlag(String code) => _flags[code] ?? '🌐';
