import 'dart:io';
import 'dart:typed_data';

import '../engines/paddle/paddle_config.dart';

/// Phase 1.6c: the spike must never freeze or kill itself on a huge photo.
/// A Dart decode of a 200 MP JPEG took about 8 s on the UI isolate and needs
/// well over 1 GB (see `OCR_SPIKE_RESULTS.md` section 11), so the size of the
/// file is read from its header first and the run is adapted or skipped.

/// `--dart-define=UNSAFE=true` switches the guard off. Only used to reproduce
/// the crash on the emulator.
const unsafeHarness = bool.fromEnvironment('UNSAFE');

/// Width and height from the file header without decoding (JPEG or PNG),
/// null when the format is not recognised.
({int w, int h})? imageSize(File file) {
  RandomAccessFile? f;
  try {
    f = file.openSync();
    final head = f.readSync(24);
    if (head.length >= 24 &&
        head[0] == 0x89 &&
        head[1] == 0x50 &&
        head[2] == 0x4E &&
        head[3] == 0x47) {
      final b = ByteData.sublistView(Uint8List.fromList(head));
      return (w: b.getUint32(16), h: b.getUint32(20));
    }
    if (head.length < 4 || head[0] != 0xFF || head[1] != 0xD8) return null;
    var pos = 2;
    final length = f.lengthSync();
    while (pos + 4 < length) {
      f.setPositionSync(pos);
      final seg = f.readSync(4);
      if (seg.length < 4 || seg[0] != 0xFF) return null;
      final marker = seg[1];
      final size = (seg[2] << 8) | seg[3];
      final isSof =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        final d = f.readSync(5);
        if (d.length < 5) return null;
        return (w: (d[3] << 8) | d[4], h: (d[1] << 8) | d[2]);
      }
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7)) {
        pos += 2;
      } else {
        pos += 2 + size;
      }
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    f?.closeSync();
  }
}

/// Above this many megapixels a full-size decode is not attempted.
const skipAboveMp = 50.0;

/// Above this a Dart decode may not run on the UI isolate (it stalls it for
/// more than about a second).
const isolateAboveMp = 20.0;

class GuardVerdict {
  const GuardVerdict(this.config, {this.skipReason, this.note});

  /// The config to run (possibly moved into the background isolate).
  final PaddleConfig config;
  final String? skipReason;
  final String? note;
  bool get skipped => skipReason != null;
}

/// What a run of [config] on an image of [mp] megapixels is allowed to do.
GuardVerdict guardRun(PaddleConfig config, double? mp) {
  if (unsafeHarness || mp == null) return GuardVerdict(config);
  final fullSizeDecode =
      config.decode == DecodeMode.dart || config.maxSide == 0;
  if (fullSizeDecode && mp > skipAboveMp) {
    return GuardVerdict(
      config,
      skipReason:
          'skipped (would exceed memory budget: ${mp.toStringAsFixed(0)} MP, '
          'limit ${skipAboveMp.toStringAsFixed(0)} MP for a full-size decode)',
    );
  }
  if (config.decode == DecodeMode.dart &&
      !config.isolate &&
      mp > isolateAboveMp) {
    return GuardVerdict(
      config.copyWith(isolate: true),
      note:
          'decode moved to the background isolate (${mp.toStringAsFixed(0)} MP)',
    );
  }
  return GuardVerdict(config);
}
