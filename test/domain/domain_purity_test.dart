import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The domain layer is pure Dart (ARCHITECTURE.md section 3): no file under
/// `lib/domain/` imports Flutter, directly or through a file of `core/` or
/// `shared/` that does (A1-016). A source test, like `no_network_test.dart`.
void main() {
  final importLine = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

  List<File> dartFiles(String root) =>
      Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

  List<String> importsOf(File file) => [
    for (final line in file.readAsLinesSync())
      if (importLine.firstMatch(line) case final match?) match.group(1)!,
  ];

  bool isFlutter(String uri) =>
      uri.startsWith('package:flutter/') ||
      uri.startsWith('package:flutter_') ||
      uri == 'dart:ui';

  test('no file of lib/domain imports Flutter', () {
    final files = dartFiles('lib/domain');
    expect(files, isNotEmpty);
    final offenders = <String>[
      for (final file in files)
        for (final uri in importsOf(file))
          if (isFlutter(uri)) '${file.path} imports $uri',
    ];
    expect(offenders, isEmpty);
  });

  test('the files of core/ and shared/ that the domain imports have no '
      'Flutter either', () {
    final reached = <String>{};
    for (final file in dartFiles('lib/domain')) {
      for (final uri in importsOf(file)) {
        if (uri.startsWith('package:') || uri.startsWith('dart:')) continue;
        final target = File.fromUri(file.uri.resolve(uri)).absolute.path;
        if (target.contains(
              '${Platform.pathSeparator}core${Platform.pathSeparator}',
            ) ||
            target.contains(
              '${Platform.pathSeparator}shared${Platform.pathSeparator}',
            )) {
          reached.add(target);
        }
      }
    }
    expect(reached, isNotEmpty);
    final offenders = <String>[
      for (final path in reached)
        for (final uri in importsOf(File(path)))
          if (isFlutter(uri)) '$path imports $uri',
    ];
    expect(offenders, isEmpty);
  });
}
