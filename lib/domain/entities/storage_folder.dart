import 'package:equatable/equatable.dart';

/// A user-chosen, user-visible folder (Android: a persisted SAF tree URI).
class StorageFolder extends Equatable {
  const StorageFolder({required this.uri, required this.name});

  /// Opaque identifier. On Android this is a `content://` tree URI.
  final String uri;

  /// Human readable folder name for display only.
  final String name;

  @override
  List<Object?> get props => [uri, name];
}
