import 'dart:io';

import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Phase 1.6c: what the system can tell the spike about itself. Numbers and
/// system reason names only; nothing here touches a user image.
const _channel = MethodChannel('spike/device');

/// Battery temperature in °C from the system (BatteryManager), null when it
/// is not available.
Future<double?> batteryTempC() async {
  try {
    final v = await _channel.invokeMethod<double>('batteryTemp');
    if (v != null) return v;
  } catch (_) {}
  for (final path in const [
    '/sys/class/power_supply/battery/temp',
    '/sys/class/power_supply/Battery/temp',
  ]) {
    try {
      final tenths = int.tryParse(File(path).readAsStringSync().trim());
      if (tenths != null) return tenths / 10;
    } catch (_) {}
  }
  return null;
}

String tempText(double? c) => c == null ? 'n/a' : c.toStringAsFixed(1);

/// One entry of Android's record of why a previous process of this app ended.
class ExitInfo {
  ExitInfo(this.name, this.ts, this.importance, this.description, this.rssKb);
  final String name;
  final DateTime ts;
  final int importance;
  final String? description;
  final int rssKb;

  String get line =>
      '${ts.toIso8601String().substring(0, 19)} $name'
      '${rssKb > 0 ? ', rss ${(rssKb / 1024).round()} MB' : ''}'
      '${description == null ? '' : ', "${description!.length > 140 ? description!.substring(0, 140) : description}"'}';
}

/// The last process exits recorded by Android (API 30+), newest first.
Future<List<ExitInfo>> exitReasons() async {
  try {
    final raw = await _channel.invokeMethod<List<Object?>>('exitReasons');
    return [
      for (final m in raw ?? const <Object?>[])
        ExitInfo(
          (m! as Map)['name'] as String,
          DateTime.fromMillisecondsSinceEpoch((m as Map)['ts'] as int),
          m['importance'] as int,
          m['description'] as String?,
          (m['rssKb'] as num).toInt(),
        ),
    ];
  } catch (_) {
    return const [];
  }
}

/// Resident and peak resident memory of this process in MB (`/proc`), null
/// when it cannot be read.
({int rssMb, int hwmMb})? memoryMb() {
  try {
    int kb(String text, String key) {
      final m = RegExp('$key:\\s+(\\d+) kB').firstMatch(text);
      return m == null ? 0 : int.parse(m.group(1)!);
    }

    final s = File('/proc/self/status').readAsStringSync();
    return (
      rssMb: (kb(s, 'VmRSS') / 1024).round(),
      hwmMb: (kb(s, 'VmHWM') / 1024).round(),
    );
  } catch (_) {
    return null;
  }
}

/// Lets VmHWM start again from the current size (allowed for the process
/// itself on most devices; ignored when not).
void resetPeakMemory() {
  try {
    File('/proc/self/clear_refs').writeAsStringSync('5');
  } catch (_) {}
}

/// Keeps the screen on while a study runs, so that the frame count is not
/// confused by the screen turning off.
Future<void> keepAwake(bool on) async {
  try {
    await (on ? WakelockPlus.enable() : WakelockPlus.disable());
  } catch (_) {}
}
