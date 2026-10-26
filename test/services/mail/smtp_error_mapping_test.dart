import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/services/mail/smtp_error_mapping.dart';

void main() {
  group('the reply code is read from the text of mailer', () {
    test('after a command', () {
      const text =
          'After sending DATA, response did not start with any of: [2, 3].\n'
          'Response from server: < 552 5.3.4 message too large';
      expect(smtpReplyCode(text), 552);
    });

    test('a multi line reply uses the first code', () {
      expect(
        smtpReplyCode('Response from server: < 550-first\n< 550 last'),
        550,
      );
    });

    test('no reply, no code', () {
      expect(
        smtpReplyCode('Socket was closed even though a response was expected.'),
        isNull,
      );
      expect(smtpReplyCode('plain text 552 without the marker'), isNull);
    });
  });

  group('every error of mailer is an outcome', () {
    test('535 and the others of the account are authFailed', () {
      expect(
        outcomeForSmtpError(
          SmtpClientAuthenticationException(
            'Authentication Failed (code: 535)',
          ),
        ),
        isA<MailAuthFailed>(),
      );
      for (final code in [530, 534, 535, 454]) {
        expect(
          outcomeForReplyCode(code),
          isA<MailAuthFailed>(),
          reason: '$code',
        );
      }
    });

    test('552 is tooLarge, even inside a communication exception', () {
      expect(outcomeForReplyCode(552), isA<MailTooLarge>());
      expect(
        outcomeForSmtpError(
          SmtpClientCommunicationException(
            'After sending ., response did not start with any of: [2, 3].\n'
            'Response from server: < 552 too much data',
          ),
        ),
        isA<MailTooLarge>(),
      );
    });

    test('another reply is a rejection with its code', () {
      final outcome = outcomeForSmtpError(
        SmtpClientCommunicationException(
          'After sending RCPT TO:<x>, response did not start with any of: [2].\n'
          'Response from server: < 550 no such user',
        ),
      );
      expect(outcome, isA<MailRejected>());
      expect((outcome as MailRejected).code, 550);
      expect((outcomeForReplyCode(421) as MailRejected).code, 421);
    });

    test('no connection, a timeout, a failed handshake, no greeting and no '
        'secure connection are network', () {
      for (final error in <Object>[
        const SocketException('Connection refused'),
        TimeoutException('too slow'),
        const HandshakeException('bad certificate'),
        SmtpNoGreetingException('no greeting'),
        SmtpUnsecureException('not secure'),
        SmtpClientCommunicationException(
          'Socket was closed even though a response was expected.',
        ),
      ]) {
        expect(
          outcomeForSmtpError(error),
          isA<MailNetworkError>(),
          reason: '${error.runtimeType}',
        );
      }
    });

    test('a message that does not validate, or anything else, is unknown', () {
      expect(
        outcomeForSmtpError(
          SmtpMessageValidationException('Invalid', const []),
        ),
        isA<MailUnknown>(),
      );
      expect(outcomeForSmtpError(StateError('x')), isA<MailUnknown>());
      expect(outcomeForSmtpError(ArgumentError('y')), isA<MailUnknown>());
    });

    test('the outcome carries nothing of the text of the error', () {
      final outcome = outcomeForSmtpError(
        SmtpClientCommunicationException(
          'Response from server: < 550 user@example.test unknown',
        ),
      );
      expect(
        '${outcome.runtimeType}${(outcome as MailRejected).code}',
        isNot(contains('example')),
      );
    });
  });
}
