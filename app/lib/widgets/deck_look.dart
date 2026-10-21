// How a deck looks in a list: a line icon on a coloured, rounded tile. The
// learner picks both in the deck's settings; they are stored by name
// (decks.icon, decks.color), so the choices here can be reordered or added
// to without touching the database -- but a name, once shipped, must keep
// meaning the same thing.

import 'package:flutter/material.dart';

import '../decks/deck_models.dart';
import '../theme/lingo_theme.dart';

/// The icons a deck can wear, by stored name. [kDefaultDeckIcon] first.
const Map<String, IconData> kDeckIcons = {
  'cards': Icons.style_outlined,
  'book': Icons.menu_book_rounded,
  'chat': Icons.chat_bubble_outline_rounded,
  'idea': Icons.lightbulb_outline_rounded,
  'school': Icons.school_outlined,
  'work': Icons.work_outline_rounded,
  'travel': Icons.flight_rounded,
  'map': Icons.map_outlined,
  'home': Icons.home_outlined,
  'family': Icons.people_outline_rounded,
  'food': Icons.restaurant_rounded,
  'coffee': Icons.local_cafe_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'money': Icons.payments_outlined,
  'health': Icons.favorite_border_rounded,
  'sport': Icons.sports_soccer_rounded,
  'music': Icons.music_note_rounded,
  'movie': Icons.movie_outlined,
  'game': Icons.sports_esports_outlined,
  'tech': Icons.computer_rounded,
  'nature': Icons.eco_outlined,
  'pets': Icons.pets_rounded,
  'car': Icons.directions_car_outlined,
  'time': Icons.schedule_rounded,
  'puzzle': Icons.extension_outlined,
  'quote': Icons.format_quote_rounded,
};

const String kDefaultDeckIcon = 'cards';

/// The look each bundled starter deck wears until the learner picks one,
/// by deck name (tool/build_everyday_decks.py's DECKS): (icon, colour).
const Map<String, (String, String)> _kStarterDeckLooks = {
  'Common phrases': ('chat', 'indigo'),
  'Travel & survival': ('travel', 'teal'),
  'Food & ordering': ('food', 'coral'),
  'Work & meetings': ('work', 'blue'),
  'Phrasal verbs': ('puzzle', 'amber'),
  'Idioms & fillers': ('quote', 'pink'),
};

(String, String)? _starterLook(Deck deck) =>
    deck.source == DeckSource.starter ? _kStarterDeckLooks[deck.name] : null;

/// A tile colour: a pale fill with a deep icon in light mode, and the same
/// hue turned dark-on-light in night mode.
class DeckColor {
  const DeckColor(this.fill, this.ink, this.nightFill, this.nightInk);

  final int fill;
  final int ink;
  final int nightFill;
  final int nightInk;

  Color get tile => Color(LingoColors.dark ? nightFill : fill);
  Color get icon => Color(LingoColors.dark ? nightInk : ink);

  /// The solid swatch the picker shows for this colour.
  Color get swatch => Color(LingoColors.dark ? nightInk : ink);
}

/// The tile colours, by stored name. [kDefaultDeckColor] first.
const Map<String, DeckColor> kDeckColors = {
  'indigo': DeckColor(0xFFE1E0F5, 0xFF3C3489, 0xFF2D3050, 0xFFCECBF6),
  'teal': DeckColor(0xFFE1F5EE, 0xFF085041, 0xFF0B3B32, 0xFF9FE1CB),
  'coral': DeckColor(0xFFFAECE7, 0xFF712B13, 0xFF4A1F12, 0xFFF5C4B3),
  'pink': DeckColor(0xFFFBEAF0, 0xFF72243E, 0xFF4B1A2C, 0xFFF4C0D1),
  'amber': DeckColor(0xFFFAEEDA, 0xFF633806, 0xFF45290A, 0xFFFAC775),
  'green': DeckColor(0xFFEAF3DE, 0xFF27500A, 0xFF22380F, 0xFFC0DD97),
  'blue': DeckColor(0xFFE6F1FB, 0xFF0C447C, 0xFF0F2E4D, 0xFFB5D4F4),
  'gray': DeckColor(0xFFF1EFE8, 0xFF444441, 0xFF353533, 0xFFD3D1C7),
};

const String kDefaultDeckColor = 'indigo';

/// The stored names, or -- when unset or unknown (an emoji from before v10,
/// or a name since removed) -- a starter deck's own look, else the defaults.
String deckIconName(Deck deck) => kDeckIcons.containsKey(deck.icon)
    ? deck.icon!
    : _starterLook(deck)?.$1 ?? kDefaultDeckIcon;
String deckColorName(Deck deck) => kDeckColors.containsKey(deck.color)
    ? deck.color!
    : _starterLook(deck)?.$2 ?? kDefaultDeckColor;

/// A deck's icon tile -- or, with [icon] and [color] given, the tile for
/// those names (the picker's preview).
class DeckIconTile extends StatelessWidget {
  const DeckIconTile({
    required this.icon,
    required this.color,
    this.size = 40,
    super.key,
  });

  DeckIconTile.of(Deck deck, {double size = 40, Key? key})
    : this(
        icon: deckIconName(deck),
        color: deckColorName(deck),
        size: size,
        key: key,
      );

  final String icon;
  final String color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final look = kDeckColors[color] ?? kDeckColors[kDefaultDeckColor]!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: look.tile,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        kDeckIcons[icon] ?? kDeckIcons[kDefaultDeckIcon],
        size: size * 0.55,
        color: look.icon,
      ),
    );
  }
}
