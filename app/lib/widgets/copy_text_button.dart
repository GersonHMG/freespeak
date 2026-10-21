import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A small icon button that copies [text] to the clipboard, e.g. to look a
/// phrase up in a dictionary or translator.
///
/// Confirms with a brief snack bar, since the clipboard itself gives no sign
/// that anything happened.
class CopyTextButton extends StatelessWidget {
  const CopyTextButton({super.key, required this.text, this.color});

  final String text;

  /// The icon's color; null keeps the surrounding icon theme's.
  final Color? color;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Copy sentence',
    // Compact, so it fits a card's header row without making it taller.
    visualDensity: VisualDensity.compact,
    color: color,
    icon: const Icon(Icons.copy_rounded, size: 20),
    onPressed: () => _copy(context),
  );
}
