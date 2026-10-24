import 'package:equatable/equatable.dart';

import 'ocr_line.dart';

/// What the engine read from one page.
class OcrResult extends Equatable {
  const OcrResult({
    required this.lines,
    required this.packId,
    required this.duration,
    required this.imageWidth,
    required this.imageHeight,
  });

  /// Every segment found, filtered ones included (the raw result).
  final List<OcrLine> lines;
  final String packId;

  /// Time the engine needed for this page (detection and recognition).
  final Duration duration;

  /// Pixels of the working image the quads refer to.
  final int imageWidth;
  final int imageHeight;

  /// Number of boxes the detector found.
  int get boxCount => lines.length;

  int get filteredCount => lines.where((l) => l.filtered).length;

  List<OcrLine> get visibleLines => [
    for (final line in lines)
      if (!line.filtered) line,
  ];

  /// The text of the visible lines: segments of one row joined with a space,
  /// rows with a new line.
  String get text => joinRows(visibleLines);

  /// Raw text, filtered lines included.
  String get rawText => joinRows(lines);

  static String joinRows(List<OcrLine> lines) {
    final rows = <int, List<String>>{};
    for (final line in lines) {
      rows.putIfAbsent(line.row, () => []).add(line.text);
    }
    final keys = rows.keys.toList()..sort();
    return keys.map((k) => rows[k]!.join(' ')).join('\n');
  }

  OcrResult copyWith({List<OcrLine>? lines}) => OcrResult(
    lines: lines ?? this.lines,
    packId: packId,
    duration: duration,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
  );

  @override
  List<Object?> get props => [lines, packId, duration, imageWidth, imageHeight];
}
