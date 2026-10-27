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

  group('the step and the reply code of a failure (the diagnostic line)', () {
    test('a refused sign-in: the step authentication, and the code', () {
      final outcome = outcomeForSmtpError(
        SmtpClientAuthenticationException(
          'Authentication Failed\nResponse from server: < 535 5.7.8 bad',
        ),
      );
      expect(outcome.stage, MailStage.authentication);
      expect(outcome.replyCode, 535);
    });

    test('a refused sign-in with no reply text still names the step', () {
      final outcome = outcomeForSmtpError(
        SmtpClientAuthenticationException('Authentication Failed'),
      );
      expect(outcome.stage, MailStage.authentication);
      expect(outcome.replyCode, isNull);
    });

    test('the sign-in reply codes keep their code', () {
      for (final code in [530, 534, 535, 454]) {
        expect(outcomeForReplyCode(code).replyCode, code);
        expect(outcomeForReplyCode(code).stage, MailStage.authentication);
      }
    });

    test('552 is the step sending with its code', () {
      expect(outcomeForReplyCode(552).stage, MailStage.sending);
      expect(outcomeForReplyCode(552).replyCode, 552);
    });

    test('another reply: sending, and its code', () {
      final outcome = outcomeForReplyCode(550);
      expect(outcome.stage, MailStage.sending);
      expect(outcome.replyCode, 550);
    });

    test('a socket error or a timeout: the step connection, no code', () {
      for (final error in <Object>[
        const SocketException('x'),
        TimeoutException('t'),
      ]) {
        final outcome = outcomeForSmtpError(error);
        expect(outcome.stage, MailStage.connection);
        expect(outcome.replyCode, isNull);
      }
    });

    test('a failed encryption: the step TLS', () {
      for (final error in <Object>[
        const HandshakeException('h'),
        const TlsException('t'),
      ]) {
        expect(outcomeForSmtpError(error).stage, MailStage.tls);
      }
    });

    test('the step and the code hold nothing of the text of the error', () {
      final outcome = outcomeForSmtpError(
        SmtpClientAuthenticationException(
          'Response from server: < 535 user@example.test smtp.example.test '
          'secret-xyz',
        ),
      );
      final line = '${outcome.stage} ${outcome.replyCode}';
      for (final secret in ['example', 'smtp', 'secret-xyz', '@']) {
        expect(line, isNot(contains(secret)));
      }
    });
  });
}
