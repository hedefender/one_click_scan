import 'dart:io';

import '../../domain/ports/image_header_reader.dart';
import 'image_header_parser.dart';

/// Reads the header of a file in a few small reads; nothing is decoded.
class FileImageHeaderReader implements ImageHeaderReader {
  const FileImageHeaderReader();

  @override
  Future<ImageHeader?> read(String path) async {
    RandomAccessFile? file;
    try {
      file = File(path).openSync();
      return parseImageHeader(FileByteSource(file));
    } on FileSystemException {
      return null;
    } finally {
      file?.closeSync();
    }
  }
}
