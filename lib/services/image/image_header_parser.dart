import 'dart:io';
import 'dart:typed_data';

import '../../domain/ports/image_header_reader.dart';

/// Random access to the bytes of a file, so the header can be read without
/// loading (let alone decoding) the image.
abstract interface class ByteSource {
  int get length;

  /// Up to [count] bytes at [offset] (fewer at the end of the data).
  Uint8List read(int offset, int count);
}

class BytesSource implements ByteSource {
  BytesSource(this._bytes);

  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Uint8List read(int offset, int count) {
    if (offset >= _bytes.length) return Uint8List(0);
    final end = offset + count > _bytes.length ? _bytes.length : offset + count;
    return Uint8List.sublistView(_bytes, offset, end);
  }
}

class FileByteSource implements ByteSource {
  FileByteSource(this._file) : length = _file.lengthSync();

  final RandomAccessFile _file;

  @override
  final int length;

  @override
  Uint8List read(int offset, int count) {
    _file.setPositionSync(offset);
    return _file.readSync(count);
  }
}

/// Normalises an EXIF orientation value: 1..8 stay, anything else (the
/// invalid 0, 9 and above, a missing tag) means "no rotation".
int normalizeOrientation(int? raw) =>
    raw != null && raw >= 1 && raw <= 8 ? raw : 1;

/// Reads orientation from the payload of an APP1 segment (the bytes after the
/// length field, starting with `Exif\0\0`). Returns the raw tag value, or null
/// when there is none. Never throws on malformed data.
int? readExifOrientation(Uint8List payload) {
  const header = [0x45, 0x78, 0x69, 0x66, 0, 0]; // "Exif\0\0"
  if (payload.length < 14) return null;
  for (var i = 0; i < header.length; i++) {
    if (payload[i] != header[i]) return null;
  }
  const tiff = 6;
  final little = payload[tiff] == 0x49 && payload[tiff + 1] == 0x49;
  final big = payload[tiff] == 0x4D && payload[tiff + 1] == 0x4D;
  if (!little && !big) return null;
  final data = ByteData.sublistView(payload);
  final endian = little ? Endian.little : Endian.big;
  int u16(int at) => data.getUint16(at, endian);
  int u32(int at) => data.getUint32(at, endian);
  if (u16(tiff + 2) != 42) return null;
  final ifd = tiff + u32(tiff + 4);
  if (ifd < tiff || ifd + 2 > payload.length) return null;
  final count = u16(ifd);
  for (var i = 0; i < count; i++) {
    final entry = ifd + 2 + i * 12;
    if (entry + 12 > payload.length) return null;
    if (u16(entry) == 0x0112) {
      // type 3 (SHORT), the value sits in the first two bytes of the field.
      return u16(entry + 8);
    }
  }
  return null;
}

/// Width, height and EXIF orientation of a JPEG or PNG from its header.
/// Null when the data is neither, or the header is damaged.
ImageHeader? parseImageHeader(ByteSource source) {
  try {
    final head = source.read(0, 24);
    if (head.length >= 24 &&
        head[0] == 0x89 &&
        head[1] == 0x50 &&
        head[2] == 0x4E &&
        head[3] == 0x47) {
      final b = ByteData.sublistView(head);
      final w = b.getUint32(16), h = b.getUint32(20);
      if (w == 0 || h == 0) return null;
      return ImageHeader(width: w, height: h, orientation: 1);
    }
    if (head.length < 4 || head[0] != 0xFF || head[1] != 0xD8) return null;

    int? orientation;
    var pos = 2;
    while (pos + 4 <= source.length) {
      final seg = source.read(pos, 4);
      if (seg.length < 4) return null;
      if (seg[0] != 0xFF) return null;
      final marker = seg[1];
      if (marker == 0xFF) {
        pos += 1; // fill byte
        continue;
      }
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        pos += 2; // standalone markers have no length
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) return null; // end / scan: no SOF
      final size = (seg[2] << 8) | seg[3];
      if (size < 2) return null;
      final isSof =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        final d = source.read(pos + 4, 5);
        if (d.length < 5) return null;
        final h = (d[1] << 8) | d[2], w = (d[3] << 8) | d[4];
        if (w == 0 || h == 0) return null;
        return ImageHeader(
          width: w,
          height: h,
          orientation: normalizeOrientation(orientation),
        );
      }
      if (marker == 0xE1 && orientation == null) {
        orientation = readExifOrientation(source.read(pos + 4, size - 2));
      }
      pos += 2 + size;
    }
    return null;
  } on RangeError {
    return null;
  } on FileSystemException {
    return null;
  }
}
