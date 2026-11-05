import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One judged photo: numbers and the user's yes/no, never a picture or text.
class Verdict {
  Verdict({
    required this.n,
    required this.label,
    required this.engine,
    required this.score,
    required this.used,
    required this.good,
    required this.detectMs,
    required this.warpMs,
    required this.sourceMp,
    this.wordsBefore,
    this.wordsAfter,
    this.ocrMsBefore,
    this.ocrMsAfter,
  });

  final int n;

  /// The kind of situation the user chose for the photo (see the table of
  /// docs/PHASE_6_0_VALIDATION.md).
  final String label;
  final String engine;
  final double score;
  final bool used;

  /// The user said "yes, this is a good page for the PDF".
  final bool good;
  final int detectMs;
  final int warpMs;
  final double sourceMp;
  int? wordsBefore;
  int? wordsAfter;
  int? ocrMsBefore;
  int? ocrMsAfter;

  Map<String, Object?> toJson() => {
    'n': n,
    'label': label,
    'engine': engine,
    'score': score,
    'used': used,
    'good': good,
    'detectMs': detectMs,
    'warpMs': warpMs,
    'sourceMp': sourceMp,
    if (wordsBefore != null) 'wordsBefore': wordsBefore,
    if (wordsAfter != null) 'wordsAfter': wordsAfter,
    if (ocrMsBefore != null) 'ocrMsBefore': ocrMsBefore,
    if (ocrMsAfter != null) 'ocrMsAfter': ocrMsAfter,
  };
}

/// The answers of the phone check, kept in memory and written to one JSON
/// file in the app's own documents folder (no picture, no text of a page).
class VerdictStore {
  final verdicts = <Verdict>[];

  Future<File> save() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/image_spike_answers.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert([for (final v in verdicts) v.toJson()]),
    );
    return file;
  }

  String summary() {
    final b = StringBuffer();
    for (final v in verdicts) {
      b.writeln(
        '${v.n}. ${v.label}: ${v.good ? 'ΝΑΙ' : 'ΟΧΙ'} · '
        '${v.used ? 'κόπηκε' : 'ολόκληρο καρέ'} · '
        'εμπιστοσύνη ${v.score.toStringAsFixed(2)} · ${v.engine}',
      );
    }
    return b.toString();
  }
}
