/// Thrown when the user-visible storage folder cannot be chosen or used.
class StorageFolderException implements Exception {
  const StorageFolderException(this.message);

  final String message;

  @override
  String toString() => 'StorageFolderException: $message';
}
