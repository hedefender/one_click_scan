import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Phase 1.6c breadcrumb: a small text file in the app's own directory that
/// records which cell is about to run and what finished, so that a run cut by
/// the system (ANR, memory kill) can be reported and resumed. It holds only
/// ids, timings and counts: never image content or recognised text.
///
/// Line format, fields split by `|` (the last field may contain `|`):
///   P|epochMs|plan|paramsJson      a plan starts
///   B|epochMs|cellId               a cell is about to run
///   E|epochMs|cellId|resultJson    a cell finished (result has a `line`)
///   L|epochMs|text                 a line produced by a study
///   X|epochMs|plan                 the plan finished normally
class RunLog {
  RunLog._(this._file);
  final File _file;

  static Future<RunLog> open() async {
    final dir = await getApplicationSupportDirectory();
    return RunLog._(File('${dir.path}/perf_runlog.txt'));
  }

  Future<void> _add(String kind, List<String> fields) async {
    final line = [
      kind,
      DateTime.now().millisecondsSinceEpoch,
      ...fields,
    ].join('|').replaceAll('\n', ' ');
    await _file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  Future<void> plan(String plan, Map<String, Object?> params) =>
      _add('P', [plan, jsonEncode(params)]);
  Future<void> begin(String cellId) => _add('B', [cellId]);
  Future<void> end(String cellId, Map<String, Object?> result) =>
      _add('E', [cellId, jsonEncode(result)]);
  Future<void> note(String text) => _add('L', [text]);
  Future<void> finish(String plan) => _add('X', [plan]);

  Future<void> clear() async {
    if (_file.existsSync()) await _file.delete();
  }

  /// Reads the file back.
  RunLogState read() {
    final state = RunLogState();
    if (!_file.existsSync()) return state;
    for (final raw in _file.readAsLinesSync()) {
      final parts = raw.split('|');
      if (parts.length < 3) continue;
      try {
        _apply(state, parts);
      } catch (_) {
        // A line cut in the middle by a kill: ignore it.
      }
    }
    return state;
  }

  static void _apply(RunLogState state, List<String> parts) {
    {
      final kind = parts[0];
      final ts = int.tryParse(parts[1]) ?? 0;
      final rest = parts.sublist(2);
      switch (kind) {
        case 'P':
          state.planName = rest[0];
          state.planParams = rest.length > 1
              ? (jsonDecode(rest.sublist(1).join('|')) as Map)
                    .cast<String, Object?>()
              : {};
          state.finished = false;
          state.done.clear();
          state.open = null;
          state.lines.add('-- plan ${rest[0]} ${_t(ts)}');
        case 'B':
          state.open = rest[0];
          state.openTs = ts;
        case 'E':
          final id = rest[0];
          final json = jsonDecode(rest.sublist(1).join('|')) as Map;
          state.done[id] = json.cast<String, Object?>();
          state.lines.add(json['line'] as String? ?? id);
          if (state.open == id) state.open = null;
        case 'L':
          state.lines.add(rest.join('|'));
        case 'X':
          state.finished = true;
          state.open = null;
      }
    }
  }

  static String _t(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms)
          .toIso8601String()
          .substring(11, 19);
}

class RunLogState {
  String? planName;
  Map<String, Object?> planParams = {};
  bool finished = true;

  /// Cells finished in the last plan: id -> result json.
  final Map<String, Map<String, Object?>> done = {};

  /// Cell that had begun but not finished when the file ended.
  String? open;
  int openTs = 0;

  /// Every summary line saved so far, in order.
  final List<String> lines = [];

  bool get wasCut => planName != null && !finished;

  String get cutText => open != null
      ? 'The previous run was cut in cell "$open" (plan $planName, '
            '${done.length} cells saved before it).'
      : 'The previous run of plan $planName stopped between cells '
            '(${done.length} cells saved).';
}
