import '../mail/share_route.dart';

/// Asks the phone which e-mail apps are there. Never throws; "nothing found"
/// is the answer on any failure.
abstract interface class MailAppFinder {
  /// [providerPackage] is the package of the provider's own app, or null.
  Future<MailApps> find({String? providerPackage});
}
