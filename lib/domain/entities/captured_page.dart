import 'package:equatable/equatable.dart';

/// One camera shot, held in the app cache until the scan is stored.
class CapturedPage extends Equatable {
  const CapturedPage({required this.path, required this.order});

  /// Temporary file in the app cache (never the user's folder).
  final String path;

  /// Position in the scan, starting at 1.
  final int order;

  @override
  List<Object?> get props => [path, order];
}
