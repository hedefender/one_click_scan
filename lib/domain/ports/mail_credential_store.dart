import '../entities/mail_provider_id.dart';

/// The password of the mail account as it is stored: with the provider and
/// the account it belongs to, so a password is never used for another one.
class StoredMailSecret {
  const StoredMailSecret({
    required this.provider,
    required this.accountEmail,
    required this.secret,
  });

  final MailProviderId provider;
  final String accountEmail;
  final String secret;

  /// Same provider and account (addresses compare without case).
  bool belongsTo(MailProviderId provider, String? account) {
    return this.provider == provider &&
        account != null &&
        accountEmail.trim().toLowerCase() == account.trim().toLowerCase();
  }

  @override
  String toString() => 'StoredMailSecret(<redacted>)';
}

/// Where the password of the mail account lives: the platform's secure storage
/// (Android Keystore), never the key/value store, never a log, never a backup
/// (ADR-021). One account at a time.
abstract interface class MailCredentialStore {
  /// The stored password, or null when there is none (or it cannot be read).
  Future<StoredMailSecret?> read();

  Future<void> write(StoredMailSecret secret);

  Future<void> delete();
}
