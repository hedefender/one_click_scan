import 'package:equatable/equatable.dart';

import '../entities/mail_provider_id.dart';

/// How the connection to the SMTP server is secured.
enum SmtpSecurity {
  /// TLS from the first byte (port 465).
  implicitTls,

  /// Plain connection upgraded with STARTTLS (port 587); the connection is
  /// refused when the server does not offer it.
  startTls,

  /// No encryption. Only for the local test server of the integration tests,
  /// never in [MailProviderRegistry.standard].
  plain,
}

/// The ways an account can prove who it is.
enum MailAuthKind {
  /// A password made for this app (needs 2-step verification at the provider).
  appPassword,

  /// OAuth 2.0 (not built yet: `MAIL_OAUTH_PLAN.md`).
  oauth,
}

/// What `MAIL_PROVIDERS.md` could confirm about app passwords with SMTP.
enum AppPasswordSupport {
  /// The provider's own pages describe app passwords for third-party mail apps.
  supported,

  /// Not confirmed, and the pages read point the other way (Outlook.com). The
  /// user may try it; the app warns and suggests the share route.
  unconfirmed,
}

class SmtpEndpoint extends Equatable {
  const SmtpEndpoint({
    required this.host,
    required this.port,
    required this.security,
  });

  final String host;
  final int port;
  final SmtpSecurity security;

  @override
  List<Object?> get props => [host, port, security];
}

/// One mail provider: where its SMTP server is, how it can be signed in to and
/// how big a message it takes. A plain value, so a provider that is added
/// later (or an OAuth route) changes this file and a sender, nothing else.
class MailProvider extends Equatable {
  const MailProvider({
    required this.id,
    required this.smtp,
    required this.authKinds,
    required this.appPasswordSupport,
    required this.maxMessageBytes,
    this.sizeLimitConfirmed = true,
    this.appPackage,
    this.appPasswordGuideUrl,
  });

  /// Stable name (`gmail`, `outlook`, `yahoo`; `testLocal` only in tests).
  final String id;
  final SmtpEndpoint smtp;
  final Set<MailAuthKind> authKinds;
  final AppPasswordSupport appPasswordSupport;

  /// Largest MESSAGE the provider takes, as the provider states it, before any
  /// safety margin (see `MailSizePolicy`).
  final int maxMessageBytes;

  /// False when no official page states the size and the number is an
  /// assumption (Yahoo).
  final bool sizeLimitConfirmed;

  /// Android package of the provider's own mail app, which the share route
  /// opens first (`MAIL_PROVIDERS.md` has the sources and what is confirmed).
  final String? appPackage;

  /// The official page where the user makes an app password, opened in the
  /// browser when the user taps the button. `https` only; null when the
  /// provider has no such page for SMTP (Outlook.com).
  final String? appPasswordGuideUrl;

  bool supports(MailAuthKind kind) => authKinds.contains(kind);

  @override
  List<Object?> get props => [
    id,
    smtp,
    authKinds,
    appPasswordSupport,
    maxMessageBytes,
    sizeLimitConfirmed,
    appPackage,
    appPasswordGuideUrl,
  ];
}

/// Maps the provider the user picked (`MailProviderId`) to the facts the
/// senders need. The numbers come from `docs/MAIL_PROVIDERS.md`.
class MailProviderRegistry {
  /// A registry with other providers, for tests only (the integration tests
  /// map `gmail` to a server on the PC).
  const MailProviderRegistry(this._providers);

  final Map<MailProviderId, MailProvider> _providers;

  static const MailProviderRegistry standard = MailProviderRegistry({
    MailProviderId.gmail: MailProvider(
      id: 'gmail',
      smtp: SmtpEndpoint(
        host: 'smtp.gmail.com',
        port: 465,
        security: SmtpSecurity.implicitTls,
      ),
      authKinds: {MailAuthKind.appPassword},
      appPasswordSupport: AppPasswordSupport.supported,
      maxMessageBytes: 25000000,
      appPackage: 'com.google.android.gm',
      appPasswordGuideUrl: 'https://myaccount.google.com/apppasswords',
    ),
    MailProviderId.outlook: MailProvider(
      id: 'outlook',
      smtp: SmtpEndpoint(
        host: 'smtp-mail.outlook.com',
        port: 587,
        security: SmtpSecurity.startTls,
      ),
      authKinds: {MailAuthKind.appPassword},
      appPasswordSupport: AppPasswordSupport.unconfirmed,
      // Two official pages say 20 MB and 25 MB: the smaller one.
      maxMessageBytes: 20000000,
      appPackage: 'com.microsoft.office.outlook',
    ),
    MailProviderId.yahoo: MailProvider(
      id: 'yahoo',
      smtp: SmtpEndpoint(
        host: 'smtp.mail.yahoo.com',
        port: 465,
        security: SmtpSecurity.implicitTls,
      ),
      authKinds: {MailAuthKind.appPassword},
      appPasswordSupport: AppPasswordSupport.supported,
      // No official page states it: the smallest confirmed number.
      maxMessageBytes: 20000000,
      sizeLimitConfirmed: false,
      appPackage: 'com.yahoo.mobile.client.android.mail',
      appPasswordGuideUrl: 'https://login.yahoo.com/account/security',
    ),
  });

  /// The provider behind [id].
  MailProvider resolve(MailProviderId id) => _providers[id]!;

  Iterable<MailProvider> get all => _providers.values;

  /// The guide page of [id], or null.
  String? guideUrlFor(MailProviderId id) => _providers[id]?.appPasswordGuideUrl;

  /// Whether [url] may be opened in the browser: `https`, no user info, no
  /// query, no fragment, and exactly a guide page of a provider of this
  /// registry. Nothing of the user is ever added to the link.
  bool isAllowedGuideLink(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      return false;
    }
    if (uri.hasPort && uri.port != 443) return false;
    return all.any((provider) {
      final guide = provider.appPasswordGuideUrl;
      if (guide == null) return false;
      final known = Uri.parse(guide);
      return known.host == uri.host && known.path == uri.path;
    });
  }
}
