import 'package:flutter/material.dart';

import 'screens/loading_screen.dart';
import 'theme/lingo_theme.dart';

void main() {
  runApp(const FreeSpeakApp());
}

class FreeSpeakApp extends StatelessWidget {
  const FreeSpeakApp({super.key});

  static const _seed = Color(0xFF0F62FE);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: lingoThemeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Free Speak',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seed)),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _seed,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: mode,
        // The Lingo palette switches in one step (see LingoColors), so the
        // Material half switches in one step with it rather than fading.
        themeAnimationDuration: Duration.zero,
        builder: (context, child) {
          final dark =
              mode == ThemeMode.dark ||
              (mode == ThemeMode.system &&
                  MediaQuery.platformBrightnessOf(context) == Brightness.dark);
          if (dark != LingoColors.dark) {
            LingoColors.dark = dark;
            // Screens read LingoColors directly, not through an
            // InheritedWidget, so nothing below would rebuild on its own:
            // mark every element dirty once the frame is done.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              void rebuild(Element element) {
                element.markNeedsBuild();
                element.visitChildren(rebuild);
              }

              (context as Element).visitChildren(rebuild);
            });
          }
          return child!;
        },
        home: const LoadingScreen(),
      ),
    );
  }
}
