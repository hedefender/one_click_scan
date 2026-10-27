/// Where the "open in the e-mail app" route sends the PDF. The order is the
/// decision of ADR-024: the app of the chosen provider, then an e-mail app that
/// handles `mailto:` (the only one, or a chooser limited to e-mail apps), and
/// the generic share menu only when no e-mail app exists.
sealed class DraftShareRoute {
  const DraftShareRoute();
}

/// The installed app of the selected provider: opens straight to the message.
final class ProviderAppRoute extends DraftShareRoute {
  const ProviderAppRoute(this.package);

  final String package;
}

/// The only e-mail app of the phone.
final class SingleMailAppRoute extends DraftShareRoute {
  const SingleMailAppRoute(this.package);

  final String package;
}

/// Several e-mail apps: a chooser that lists only them.
final class MailAppChooserRoute extends DraftShareRoute {
  const MailAppChooserRoute(this.packages);

  final List<String> packages;
}

/// No e-mail app was found: the generic share menu, the last resort.
final class GenericShareRoute extends DraftShareRoute {
  const GenericShareRoute();
}

/// What the phone has: whether the provider's app is installed and which apps
/// handle `mailto:`.
class MailApps {
  const MailApps({
    this.providerAppInstalled = false,
    this.mailtoPackages = const [],
  });

  final bool providerAppInstalled;
  final List<String> mailtoPackages;
}

/// Pure, so every case is a unit test.
DraftShareRoute chooseShareRoute({
  required String? providerPackage,
  required MailApps apps,
}) {
  if (providerPackage != null && apps.providerAppInstalled) {
    return ProviderAppRoute(providerPackage);
  }
  final packages = apps.mailtoPackages.toSet().toList();
  if (packages.length == 1) return SingleMailAppRoute(packages.single);
  if (packages.length > 1) return MailAppChooserRoute(packages);
  return const GenericShareRoute();
}
