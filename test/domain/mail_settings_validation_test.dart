import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/destination_mode.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/validation/mail_settings_validation.dart';

void main() {
  Set<MailSettingsError> validate({
    MailProviderId? provider = MailProviderId.gmail,
    String sender = 'sender@example.com',
    DestinationMode mode = DestinationMode.own,
    String custom = '',
  }) {
    return validateMailSettings(
      provider: provider,
      senderAccount: sender,
      destinationMode: mode,
      customDestination: custom,
    );
  }

  test('valid settings have no errors', () {
    expect(validate(), isEmpty);
  });

  test('provider is required', () {
    expect(validate(provider: null), {MailSettingsError.providerMissing});
  });

  test('sender must be a valid address', () {
    expect(validate(sender: ''), {MailSettingsError.senderInvalid});
    expect(validate(sender: 'not-an-email'), {MailSettingsError.senderInvalid});
    expect(validate(sender: '  sender@example.com  '), isEmpty);
  });

  test('custom destination is only checked in custom mode', () {
    expect(validate(custom: 'garbage'), isEmpty);
    expect(validate(mode: DestinationMode.custom, custom: 'garbage'), {
      MailSettingsError.customDestinationInvalid,
    });
    expect(
      validate(mode: DestinationMode.custom, custom: 'to@example.com'),
      isEmpty,
    );
  });

  test('all problems are reported together', () {
    expect(
      validate(
        provider: null,
        sender: '',
        mode: DestinationMode.custom,
        custom: '',
      ),
      {
        MailSettingsError.providerMissing,
        MailSettingsError.senderInvalid,
        MailSettingsError.customDestinationInvalid,
      },
    );
  });
}
