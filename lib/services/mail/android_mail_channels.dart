import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/entities/pdf_page_input.dart';
import '../../domain/mail/mail_message.dart';
import '../../domain/mail/share_route.dart';
import '../../domain/ports/attachment_source.dart';
import '../../domain/ports/draft_sharer.dart';
import '../../domain/ports/link_opener.dart';
import '../../domain/ports/mail_app_finder.dart';

/// The same channel as the file store, the PDF opener and the handler in
/// `ScanFilesHandler.kt`: it is one Kotlin class.
const mailChannelName = 'com.example.one_click_scan/scan_files';

/// Copies the stored PDF (behind a document URI) into the app cache, natively:
/// the bytes never cross the channel. The copy is deleted after the send.
class AndroidAttachmentSource implements AttachmentSource {
  AndroidAttachmentSource({required this.directory, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(mailChannelName);

  /// `cache/mail_work`, purged at start-up.
  final Directory directory;
  final MethodChannel _channel;

  @override
  Future<MailAttachment> prepare(StoredPdf pdf) async {
    await directory.create(recursive: true);
    final target =
        '${directory.path}${Platform.pathSeparator}'
        '${DateTime.now().microsecondsSinceEpoch}.pdf';
    try {
      await _channel.invokeMethod<void>('copyUriToFile', <String, String>{
        'uri': pdf.uri,
        'targetPath': target,
      });
    } on PlatformException {
      throw const AttachmentUnavailable();
    } on MissingPluginException {
      throw const AttachmentUnavailable();
    }
    if (!await File(target).exists()) throw const AttachmentUnavailable();
    return MailAttachment(
      fileName: pdf.fileName,
      mimeType: 'application/pdf',
      path: target,
    );
  }

  @override
  Future<void> release(MailAttachment attachment) async {
    try {
      final file = File(attachment.path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Purged at the next start.
    }
  }

  @override
  Future<void> purgeAll() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // A file in use; the next start tries again.
    }
  }
}

/// `ACTION_SEND` with the recipient, subject, text and the PDF as a
/// `content://` URI with a temporary read-only grant (`ScanFilesHandler.kt`),
/// sent to the app or the chooser of the [DraftShareRoute]. The user presses
/// send in the e-mail app.
class AndroidDraftSharer implements DraftSharer {
  AndroidDraftSharer({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(mailChannelName);

  final MethodChannel _channel;

  @override
  Future<DraftShareResult> share({
    required DraftShareRoute route,
    required List<String> to,
    required String subject,
    required String body,
    required String documentUri,
    required String mimeType,
  }) async {
    try {
      final reply = await _channel.invokeMethod<String>(
        'shareDocument',
        _arguments(route, to, subject, body, documentUri, mimeType),
      );
      return switch (reply) {
        'opened' =>
          route is GenericShareRoute
              ? DraftShareResult.openedGeneric
              : DraftShareResult.opened,
        'no_app' => DraftShareResult.noApp,
        _ => DraftShareResult.failed,
      };
    } on PlatformException {
      return DraftShareResult.failed;
    } on MissingPluginException {
      return DraftShareResult.failed;
    }
  }

  /// What the intent WOULD carry, without starting anything (the tests of the
  /// intent use it: the same function of the handler builds both).
  Future<Map<String, Object?>> describe({
    required DraftShareRoute route,
    required List<String> to,
    required String subject,
    required String body,
    required String documentUri,
    required String mimeType,
  }) async {
    final reply = await _channel.invokeMapMethod<String, Object?>(
      'describeShare',
      _arguments(route, to, subject, body, documentUri, mimeType),
    );
    return reply ?? const {};
  }

  static Map<String, Object> _arguments(
    DraftShareRoute route,
    List<String> to,
    String subject,
    String body,
    String documentUri,
    String mimeType,
  ) {
    final (name, packages) = switch (route) {
      ProviderAppRoute(:final package) => ('provider', [package]),
      SingleMailAppRoute(:final package) => ('mail', [package]),
      MailAppChooserRoute(:final packages) => ('chooser', packages),
      GenericShareRoute() => ('generic', const <String>[]),
    };
    return <String, Object>{
      'route': name,
      'packages': packages,
      'to': to,
      'subject': subject,
      'body': body,
      'uri': documentUri,
      'mimeType': mimeType,
    };
  }
}

/// Which e-mail apps are on the phone (`findMailApps` in `ScanFilesHandler.kt`):
/// whether the provider's app is installed, and the apps that handle `mailto:`.
class AndroidMailAppFinder implements MailAppFinder {
  AndroidMailAppFinder({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(mailChannelName);

  final MethodChannel _channel;

  @override
  Future<MailApps> find({String? providerPackage}) async {
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>(
        'findMailApps',
        <String, Object?>{'providerPackage': providerPackage},
      );
      if (reply == null) return const MailApps();
      final packages = reply['mailtoPackages'];
      return MailApps(
        providerAppInstalled: reply['providerAppInstalled'] == true,
        mailtoPackages: packages is List
            ? [for (final p in packages) p.toString()]
            : const [],
      );
    } on PlatformException {
      return const MailApps();
    } on MissingPluginException {
      return const MailApps();
    }
  }
}

/// Opens a page in the browser (`ACTION_VIEW`, `https` only on the native side
/// too). It starts the browser app; the app itself opens no connection.
class AndroidLinkOpener implements LinkOpener {
  AndroidLinkOpener({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(mailChannelName);

  final MethodChannel _channel;

  @override
  Future<bool> open(String url) async {
    try {
      final reply = await _channel.invokeMethod<String>(
        'openLink',
        <String, String>{'url': url},
      );
      return reply == 'opened';
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
