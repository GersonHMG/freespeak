import 'package:flutter/material.dart';

/// Asks for one line of text in a dialog -- a deck's name, today. Returns
/// it trimmed, or null when cancelled or left empty.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String hint,
  required String action,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      void submit() => Navigator.of(context).pop(controller.text.trim());
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(onPressed: submit, child: Text(action)),
        ],
      );
    },
  );
  // After the dialog's closing animation, so its field is gone from the
  // tree before the controller is.
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  return result == null || result.isEmpty ? null : result;
}
