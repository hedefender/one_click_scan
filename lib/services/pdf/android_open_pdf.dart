import 'package:flutter/services.dart';

import '../../domain/ports/open_pdf.dart';

/// Talks to `ScanFilesHandler.kt` (see `android_overlay/`): ACTION_VIEW with
/// the document URI and a temporary read grant for the viewer.
class AndroidOpenPdf implements OpenPdf {
  AndroidOpenPdf({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// The same channel as `AndroidScanFileStore`: the handler is one class.
  static const channelName = 'com.example.one_click_scan/scan_files';

  final MethodChannel _channel;

  @override
  Future<OpenPdfResult> open(String uri) async {
    try {
      final reply = await _channel.invokeMethod<String>(
        'openDocument',
        <String, String>{'uri': uri, 'mimeType': 'application/pdf'},
      );
      return switch (reply) {
        'opened' => OpenPdfResult.opened,
        'no_viewer' => OpenPdfResult.noViewer,
        _ => OpenPdfResult.failed,
      };
    } on PlatformException {
      return OpenPdfResult.failed;
    } on MissingPluginException {
      return OpenPdfResult.failed;
    }
  }
}
