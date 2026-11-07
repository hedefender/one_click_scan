import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../../domain/entities/page_crop_outcome.dart';
import '../../domain/imaging/page_crop_config.dart';
import '../../domain/imaging/quad.dart';
import 'detection.dart';
import 'pure_dart_detector.dart';
import 'rectify.dart';

/// The work order of one crop. Plain values only, so it can be sent to the
/// background isolate.
class CropJob {
  const CropJob({
    required this.source,
    required this.target,
    required this.maxSide,
    required this.jpegQuality,
    required this.focalLength35mm,
  });

  final String source;
  final String target;
  final int maxSide;
  final int jpegQuality;
  final int? focalLength35mm;
}

/// What a [CropJob] came to. Either [reason] is set (the page keeps the whole
/// frame and no file was written) or the picture was written to the target.
class CropJobResult {
  const CropJobResult.wholeFrame(WholeFrameReason this.reason)
    : quad = null,
      confidence = 0,
      width = 0,
      height = 0;

  const CropJobResult.cropped({
    required List<Pt> this.quad,
    required this.confidence,
    required this.width,
    required this.height,
  }) : reason = null;

  final WholeFrameReason? reason;
  final List<Pt>? quad;
  final double confidence;
  final int width;
  final int height;

  PageCropOutcome toOutcome() {
    final r = reason;
    if (r != null) return PageWholeFrame(r);
    return PageCropped(
      quad: Quad(quad!),
      confidence: confidence,
      width: width,
      height: height,
    );
  }
}

/// A picture narrower than this (pixels) is not a page: the crop is refused.
const _minSidePx = 64;

/// Focal length in pixels of the working picture, from the EXIF 35 mm
/// equivalent focal length. Null when the photo had none (the warp then takes
/// the mean of opposite sides, a page tilted 20 degrees comes out about 6%
/// too narrow, ADR-029).
double focalPixels(int? focalLength35mm, int width, int height) {
  if (focalLength35mm == null || focalLength35mm <= 0) return 0;
  final diagonal = math.sqrt((width * width + height * height).toDouble());
  return focalLength35mm * diagonal / PageCropConfig.filmDiagonalMm;
}

/// The whole crop, synchronous so that a test can call it directly and the
/// isolate only has to run it: decode the working copy, find the page, and
/// when the confidence is trusted write the straightened JPEG to the target.
///
/// Never throws: every problem is a whole-frame result, and a half-written
/// target is removed again.
CropJobResult cropPageSync(CropJob job) {
  try {
    var image = img.decodeJpg(File(job.source).readAsBytesSync());
    if (image == null) {
      return const CropJobResult.wholeFrame(WholeFrameReason.failed);
    }
    if (image.numChannels != 3) image = image.convert(numChannels: 3);
    final frame = RgbFrame(
      image.width,
      image.height,
      image.getBytes(order: img.ChannelOrder.rgb),
    );
    final detection = const PureDartDetector().detect(frame);
    final quad = detection.quad;
    if (quad == null) {
      return const CropJobResult.wholeFrame(WholeFrameReason.noPageFound);
    }
    if (!trustsDetection(detection.score)) {
      return const CropJobResult.wholeFrame(WholeFrameReason.lowConfidence);
    }
    final straight = warpToQuadDart(
      frame,
      quad,
      maxSide: job.maxSide,
      focalPx: focalPixels(job.focalLength35mm, frame.width, frame.height),
    );
    if (straight.width < _minSidePx || straight.height < _minSidePx) {
      return const CropJobResult.wholeFrame(WholeFrameReason.failed);
    }
    final jpeg = img.encodeJpg(
      img.Image.fromBytes(
        width: straight.width,
        height: straight.height,
        bytes: straight.rgb.buffer,
        numChannels: 3,
      ),
      quality: job.jpegQuality,
    );
    File(job.target).writeAsBytesSync(jpeg);
    return CropJobResult.cropped(
      quad: quad.p,
      confidence: detection.score,
      width: straight.width,
      height: straight.height,
    );
  } catch (_) {
    try {
      final file = File(job.target);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // The cache is purged at the next start-up anyway.
    }
    return const CropJobResult.wholeFrame(WholeFrameReason.failed);
  }
}
