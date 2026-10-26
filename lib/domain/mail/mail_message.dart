import 'package:equatable/equatable.dart';

/// A file to attach: a local file the sender reads.
class MailAttachment extends Equatable {
  const MailAttachment({
    required this.fileName,
    required this.mimeType,
    required this.path,
  });

  final String fileName;
  final String mimeType;
  final String path;

  @override
  List<Object?> get props => [fileName, mimeType, path];
}

/// A message to send. The recipients are a list (several recipients later);
/// the screens show one.
class MailMessage extends Equatable {
  const MailMessage({
    required this.from,
    required this.to,
    required this.subject,
    required this.body,
    required this.attachments,
  });

  final String from;
  final List<String> to;
  final String subject;
  final String body;
  final List<MailAttachment> attachments;

  @override
  List<Object?> get props => [from, to, subject, body, attachments];

  /// Never prints the addresses.
  @override
  String toString() => 'MailMessage(<redacted>)';
}
