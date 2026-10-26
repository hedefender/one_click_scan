/// Proof of who sends. Sealed, so a new kind (OAuth) is one more subclass and
/// every `switch` over it must handle it.
sealed class MailAuth {
  const MailAuth();
}

/// The account and a password made for this app.
final class AppPasswordAuth extends MailAuth {
  const AppPasswordAuth({required this.accountEmail, required this.secret});

  final String accountEmail;
  final String secret;

  /// Never prints the secret or the address (a log line or an error message
  /// that includes the object must not leak them).
  @override
  String toString() => 'AppPasswordAuth(<redacted>)';
}

// Reserved: `final class OAuthAuth extends MailAuth` (access token and its
// account) arrives with MAIL_OAUTH_PLAN.md. Nothing else changes.
