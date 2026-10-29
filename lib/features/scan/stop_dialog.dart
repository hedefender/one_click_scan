import 'package:flutter/material.dart';

import '../../presentation/l10n/app_strings.dart';
import 'scan_keys.dart';

/// "Stop the processing?" with [body] saying what stays. True when the user
/// chose to stop. Shared by the camera screen (while the pictures are written)
/// and the result screen (while the text, the PDF or the mail is made).
Future<bool> confirmStop(BuildContext context, String body) async {
  final strings = AppStrings.of(context);
  final stop = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.stopTitle),
      content: Text(body),
      actions: [
        TextButton(
          key: ScanKeys.stopContinue,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(strings.stopContinue),
        ),
        TextButton(
          key: ScanKeys.stopConfirm,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(strings.stopConfirm),
        ),
      ],
    ),
  );
  return stop ?? false;
}
