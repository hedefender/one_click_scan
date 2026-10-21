import '../../domain/entities/mail_provider_id.dart';

extension MailProviderLabel on MailProviderId {
  /// Brand names are not translated.
  String get label {
    return switch (this) {
      MailProviderId.gmail => 'Gmail',
      MailProviderId.outlook => 'Outlook',
      MailProviderId.yahoo => 'Yahoo',
    };
  }
}
