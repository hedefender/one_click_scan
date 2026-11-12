import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/ports/app_info_source.dart';
import '../../domain/ports/feedback_composer.dart';

/// Same channel as the camera service's system helpers (`SystemHandler.kt`).
const aboutChannelName = 'io.github.hedefender.simpledocscan/system';

/// The platform adapters of About, created together like `MailServices`.
class AboutServices {
  const AboutServices({required this.info, required this.feedback});

  /// Nothing: the default of the container, so a test never calls a channel.
  const AboutServices.unsupported()
    : info = const UnsupportedAppInfoSource(),
      feedback = const UnsupportedFeedbackComposer();

  final AppInfoSource info;
  final FeedbackComposer feedback;
}

AboutServices createPlatformAboutServices() {
  if (!Platform.isAndroid) return const AboutServices.unsupported();
  return AboutServices(
    info: AndroidAppInfoSource(),
    feedback: AndroidFeedbackComposer(),
  );
}

class AndroidAppInfoSource implements AppInfoSource {
  AndroidAppInfoSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(aboutChannelName);

  final MethodChannel _channel;

  @override
  Future<AppInfo?> read() async {
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>('appInfo');
      if (reply == null) return null;
      return AppInfo(
        versionName: '${reply['versionName'] ?? ''}',
        buildNumber: '${reply['buildNumber'] ?? ''}',
        androidRelease: '${reply['androidRelease'] ?? ''}',
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// `ACTION_SENDTO` with `mailto:` (`composeMail` in `SystemHandler.kt`).
class AndroidFeedbackComposer implements FeedbackComposer {
  AndroidFeedbackComposer({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(aboutChannelName);

  final MethodChannel _channel;

  @override
  Future<bool> compose({
    required String to,
    required String subject,
    required String body,
  }) async {
    try {
      final reply = await _channel.invokeMethod<String>(
        'composeMail',
        <String, String>{'to': to, 'subject': subject, 'body': body},
      );
      return reply == 'opened';
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

class UnsupportedAppInfoSource implements AppInfoSource {
  const UnsupportedAppInfoSource();

  @override
  Future<AppInfo?> read() async => null;
}

class UnsupportedFeedbackComposer implements FeedbackComposer {
  const UnsupportedFeedbackComposer();

  @override
  Future<bool> compose({
    required String to,
    required String subject,
    required String body,
  }) async => false;
}
