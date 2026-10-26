import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/ports/mail_credential_store.dart';
import 'package:one_click_scan/services/mail/secure_mail_credential_store.dart';

import '../../support/mail_fakes.dart';

void main() {
  late InMemorySecureStringStore secure;
  late CapturingLogger logger;
  late SecureMailCredentialStore store;

  setUp(() {
    secure = InMemorySecureStringStore();
    logger = CapturingLogger();
    store = SecureMailCredentialStore(store: secure, logger: logger);
  });

  const secret = StoredMailSecret(
    provider: MailProviderId.gmail,
    accountEmail: testAccount,
    secret: canarySecret,
  );

  test('nothing stored reads as null', () async {
    expect(await store.read(), isNull);
  });

  test('a password is written, read back and deleted', () async {
    await store.write(secret);

    final read = await store.read();
    expect(read, isNotNull);
    expect(read!.provider, MailProviderId.gmail);
    expect(read.accountEmail, testAccount);
    expect(read.secret, canarySecret);

    await store.delete();
    expect(await store.read(), isNull);
    expect(secure.values, isEmpty);
  });

  test('a new password replaces the old one: one account at a time', () async {
    await store.write(secret);
    await store.write(
      const StoredMailSecret(
        provider: MailProviderId.yahoo,
        accountEmail: 'other@example.test',
        secret: 'second-secret',
      ),
    );

    final read = await store.read();
    expect(read!.provider, MailProviderId.yahoo);
    expect(read.secret, 'second-secret');
    expect(secure.values, hasLength(1));
  });

  test(
    'one value under a fixed key: the account is not in a key name',
    () async {
      await store.write(secret);

      expect(secure.values.keys, [SecureMailCredentialStore.key]);
      expect(secure.values.keys.single, isNot(contains('example')));
      final json =
          jsonDecode(secure.values.values.single) as Map<String, dynamic>;
      expect(json['secret'], canarySecret);
    },
  );

  test('a value that cannot be read, or is damaged, is no password', () async {
    secure.values[SecureMailCredentialStore.key] = 'not json';
    expect(await store.read(), isNull);

    secure.values[SecureMailCredentialStore.key] = '{"provider":"nope"}';
    expect(await store.read(), isNull);

    secure.values[SecureMailCredentialStore.key] =
        '{"provider":"gmail","account":"a@example.test","secret":""}';
    expect(await store.read(), isNull);

    secure.failRead = StateError('keystore lost $canarySecret');
    expect(await store.read(), isNull);
  });

  test('the password is never in a log, even when reading fails', () async {
    await store.write(secret);
    secure.failRead = StateError('keystore lost $canarySecret $testAccount');
    await store.read();

    // The kind of the error may be logged; its text may not.
    expect(logger.lines, isNotEmpty);
    expect(logger.all.contains('StateError'), isTrue);
    expect(logger.all, isNot(contains(canarySecret)));
  });
}
