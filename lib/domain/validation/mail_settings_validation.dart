import '../../shared/validators/email_validator.dart';
import '../entities/destination_mode.dart';
import '../entities/mail_provider_id.dart';

enum MailSettingsError {
  providerMissing,
  senderInvalid,
  customDestinationInvalid,
}

/// Single source of truth for the e-mail settings rules. Used by the first-run
/// wizard and by the settings screen, so both always accept the same input.
/// Empty result means the settings are valid.
Set<MailSettingsError> validateMailSettings({
  required MailProviderId? provider,
  required String senderAccount,
  required DestinationMode destinationMode,
  required String customDestination,
}) {
  return <MailSettingsError>{
    if (provider == null) MailSettingsError.providerMissing,
    if (!isValidEmail(senderAccount)) MailSettingsError.senderInvalid,
    if (destinationMode == DestinationMode.custom &&
        !isValidEmail(customDestination))
      MailSettingsError.customDestinationInvalid,
  };
}
