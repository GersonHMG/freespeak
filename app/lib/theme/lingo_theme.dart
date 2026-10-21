// The palette and type lifted from the "Lingo Node Home" mockup, shared by
// every screen that adopts that redesign (currently the home tab shell and
// My Progress). Kept out of the app's [ThemeData] deliberately -- screens
// that haven't been redesigned yet should keep using Material's defaults
// rather than inherit this look wholesale.
//
// Night mode: every colour is a getter that reads [LingoColors.dark], which
// FreeSpeakApp (main.dart) sets from [lingoThemeMode] and the system's
// brightness. Flipping it rebuilds the whole tree once, so nothing that
// reads a colour needs to listen for the change itself.

import 'package:flutter/material.dart';

/// The learner's light / dark / follow-the-system choice. Loaded from, and
/// saved to, the `theme_mode` setting (see theme_setting.dart).
final ValueNotifier<ThemeMode> lingoThemeMode = ValueNotifier(ThemeMode.system);

class LingoColors {
  const LingoColors._();

  /// Whether the night palette is in use. Set by FreeSpeakApp only.
  static bool dark = false;

  static Color _pick(int light, int night) => Color(dark ? night : light);

  static Color get background => _pick(0xFFEDECF6, 0xFF13131D);
  static Color get surface => _pick(0xFFFFFFFF, 0xFF1F1F2D);
  static Color get ink => _pick(0xFF1C1C2E, 0xFFECECF5);
  static Color get mutedInk => _pick(0xFF8A8A9E, 0xFF9C9CB2);
  static Color get indigo => _pick(0xFF4B5583, 0xFF7F8BC9);
  static Color get indigoContainer => _pick(0xFFE1E0F5, 0xFF2D3050);
  static Color get ringTrack => _pick(0xFFEDEDF5, 0xFF2A2A3C);
  static Color get accentCard => _pick(0xFF5B6795, 0xFF3E4877);
  static Color get errorContainer => _pick(0xFFFDE2E2, 0xFF4A2326);
  static Color get onErrorContainer => _pick(0xFFE0575B, 0xFFFF8A8E);
  static Color get navInactive => _pick(0xFFB7B7C9, 0xFF5E5E76);

  /// The streak pill's fill and its flame/text.
  static Color get streakContainer => _pick(0xFFF5E4DA, 0xFF3D2A20);
  static Color get streak => _pick(0xFFB55A2C, 0xFFF0A070);
}

TextStyle lingoFont({
  required double size,
  required FontWeight weight,
  Color? color,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: 'Manrope',
  fontSize: size,
  fontWeight: weight,
  // The bundled Manrope is one variable font; its weight axis has to be set
  // explicitly, since [fontWeight] alone doesn't move it.
  fontVariations: [FontVariation.weight(weight.value.toDouble())],
  color: color ?? LingoColors.ink,
  letterSpacing: letterSpacing,
);

/// The white rounded card every stat box on these screens sits in.
BoxDecoration lingoCardDecoration({double radius = 26}) => BoxDecoration(
  color: LingoColors.surface,
  borderRadius: BorderRadius.circular(radius),
  boxShadow: [
    BoxShadow(
      color: (LingoColors.dark ? Colors.black : LingoColors.ink).withValues(
        alpha: LingoColors.dark ? 0.3 : 0.06,
      ),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ],
);
