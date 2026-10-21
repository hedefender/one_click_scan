/// Mail providers the user can pick in the wizard.
///
/// Phase 0 only stores the choice. The `MailProvider` implementations
/// (SMTP/OAuth) arrive in the e-mail phase.
enum MailProviderId { gmail, outlook, yahoo }
