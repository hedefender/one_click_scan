/// What happens after a scan is taken (ADR-025).
enum ScanFlowMode {
  /// The scan is processed and sent at once; there is no preview.
  oneClick,

  /// The pages are shown first; the user sends or discards the scan.
  preview,
}
