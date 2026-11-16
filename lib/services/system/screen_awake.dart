import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/ports/screen_awake.dart';

/// Same channel as the other system helpers (`SystemHandler.kt`).
const screenAwakeChannelName = 'io.github.hedefender.simpledocscan/system';

/// `FLAG_KEEP_SCREEN_ON` on the window of the activity (`keepScreenOn` in
/// `SystemHandler.kt`). It needs no permission, and it is a flag of the window,
/// so it ends with the window.
class AndroidScreenAwake implements ScreenAwake {
  AndroidScreenAwake({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(screenAwakeChannelName);

  final MethodChannel _channel;

  @override
  Future<void> keepOn(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', <String, bool>{
        'on': on,
      });
    } on PlatformException {
      // A convenience: the work goes on with the normal screen timeout.
    } on MissingPluginException {
      // The same.
    }
  }
}

/// Does nothing: the default of the container and of other platforms.
class UnsupportedScreenAwake implements ScreenAwake {
  const UnsupportedScreenAwake();

  @override
  Future<void> keepOn(bool on) async {}
}

ScreenAwake createPlatformScreenAwake() =>
    Platform.isAndroid ? AndroidScreenAwake() : const UnsupportedScreenAwake();
