import 'package:flutter/services.dart';

import '../../domain/ports/upright_image_maker.dart';

/// Talks to `ImageDecodeHandler.kt` (see `android_overlay/`): the photo is
/// decoded natively with `inSampleSize` (never at full size), rotated by its
/// EXIF orientation, scaled and written as a JPEG. Only paths and numbers
/// cross the channel, never pixels.
class NativeUprightImageMaker implements UprightImageMaker {
  NativeUprightImageMaker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Must match `CHANNEL` in ImageDecodeHandler.kt.
  static const channelName = 'com.example.one_click_scan/image_decode';

  final MethodChannel _channel;

  @override
  Future<UprightPixels> make({
    required String source,
    required String target,
    required int maxSide,
    required int jpegQuality,
  }) async {
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>(
        'makeUpright',
        <String, Object?>{
          'source': source,
          'target': target,
          'maxSide': maxSide,
          'quality': jpegQuality,
        },
      );
      final width = reply?['width'] as int?;
      final height = reply?['height'] as int?;
      if (width == null || height == null) {
        throw const UprightImageException('failed');
      }
      return UprightPixels(width: width, height: height);
    } on PlatformException catch (error) {
      throw UprightImageException(switch (error.code) {
        'unreadable' => 'unreadable',
        'out_of_memory' => 'outOfMemory',
        _ => 'failed',
      });
    } on MissingPluginException {
      throw const UprightImageException('failed');
    }
  }
}
