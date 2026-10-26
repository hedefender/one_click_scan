// A tiny SMTP server for the tests of the mail layer. It only listens on the
// loopback of this computer (the Android emulator reaches it as 10.0.2.2) and
// keeps every message it accepts, so a test can compare the attachment of the
// received message with the file that was sent, byte for byte.
//
//   dart run tool/smtp_test_server.dart [--smtp-port 2525] [--control-port 2526]
//
// It prints `READY smtp=<port> control=<port>` when it is up. The control
// port is a small HTTP interface for a test that runs on the emulator:
//
//   GET  /mails        JSON list of what was received (from, to, subject,
//                      attachments with name, size and SHA-256)
//   POST /mode/<name>  accept | authFail | tooLarge | rejectRecipient | hang
//   POST /reset        forget the received messages, mode back to accept
//
// The `testLocal` mail provider (plain connection, no TLS) is the only client
// of this server and exists only in the tests. Never put a real password here:
// the server accepts exactly the invented user and password it is started
// with (`user@example.test` / `test-password` by default).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum SmtpMode {
  /// Takes the message.
  accept,

  /// Answers 535 to the log in.
  authFail,

  /// Answers 552 after the message (too much data).
  tooLarge,

  /// Answers 550 to the recipient.
  rejectRecipient,

  /// Accepts the connection and never says anything (a timeout test).
  hang,
}

class ReceivedAttachment {
  ReceivedAttachment(this.name, this.bytes);

  final String name;
  final Uint8List bytes;

  String get sha256Hex => sha256.convert(bytes).toString();
}

class ReceivedMail {
  ReceivedMail({required this.from, required this.to, required this.raw});

  final String from;
  final List<String> to;
  final List<int> raw;

  late final String _text = latin1.decode(raw);

  Map<String, String> get headers => _parseHeaders(_headerBlock(_text));

  String get subject => _decodeWords(headers['subject'] ?? '');

  /// The text part of the message, decoded.
  String get bodyText {
    for (final part in _parts()) {
      final type = part.headers['content-type'] ?? '';
      if (type.toLowerCase().startsWith('text/plain') ||
          !part.headers.containsKey('content-disposition')) {
        if (!(part.headers['content-disposition'] ?? '')
            .toLowerCase()
            .startsWith('attachment')) {
          return utf8.decode(part.decoded, allowMalformed: true);
        }
      }
    }
    return '';
  }

  List<ReceivedAttachment> get attachments {
    return [
      for (final part in _parts())
        if ((part.headers['content-disposition'] ?? '')
            .toLowerCase()
            .startsWith('attachment'))
          ReceivedAttachment(part.fileName, part.decoded),
    ];
  }

  Map<String, Object?> toJson() => {
    'from': from,
    'to': to,
    'subject': subject,
    'body': bodyText,
    'bytes': raw.length,
    'attachments': [
      for (final a in attachments)
        {'name': a.name, 'size': a.bytes.length, 'sha256': a.sha256Hex},
    ],
  };

  List<_Part> _parts() {
    final top = headers;
    final type = top['content-type'] ?? '';
    final boundary = RegExp(r'boundary="?([^";]+)"?')
        .firstMatch(type)
        ?.group(1);
    final body = _bodyBlock(_text);
    if (boundary == null) {
      return [_Part(top, latin1.encode(body))];
    }
    final parts = <_Part>[];
    for (final chunk in body.split('--$boundary')) {
      final piece = chunk.startsWith('\r\n') ? chunk.substring(2) : chunk;
      if (piece.trim().isEmpty || piece.trimLeft().startsWith('--')) continue;
      parts.add(
        _Part(
          _parseHeaders(_headerBlock(piece)),
          latin1.encode(_bodyBlock(piece)),
        ),
      );
    }
    return parts;
  }
}

class _Part {
  _Part(this.headers, this.rawBody);

  final Map<String, String> headers;
  final List<int> rawBody;

  String get fileName {
    final disposition = headers['content-disposition'] ?? '';
    final type = headers['content-type'] ?? '';
    final match =
        RegExp(r'filename="?([^";]+)"?').firstMatch(disposition) ??
        RegExp(r'name="?([^";]+)"?').firstMatch(type);
    return _decodeWords(match?.group(1) ?? '');
  }

  Uint8List get decoded {
    final encoding = (headers['content-transfer-encoding'] ?? '')
        .toLowerCase()
        .trim();
    final text = latin1.decode(rawBody);
    if (encoding == 'base64') {
      return base64.decode(text.replaceAll(RegExp(r'\s+'), ''));
    }
    return Uint8List.fromList(rawBody);
  }
}

String _headerBlock(String text) {
  final end = text.indexOf('\r\n\r\n');
  return end < 0 ? text : text.substring(0, end);
}

String _bodyBlock(String text) {
  final end = text.indexOf('\r\n\r\n');
  return end < 0 ? '' : text.substring(end + 4);
}

Map<String, String> _parseHeaders(String block) {
  final result = <String, String>{};
  String? current;
  for (final line in block.split('\r\n')) {
    if (line.startsWith(' ') || line.startsWith('\t')) {
      if (current != null) result[current] = '${result[current]}${line.trim()}';
      continue;
    }
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    current = line.substring(0, colon).toLowerCase();
    result[current] = line.substring(colon + 1).trim();
  }
  return result;
}

/// RFC 2047 words (`=?utf-8?B?...?=` and `=?utf-8?Q?...?=`), enough for tests.
String _decodeWords(String value) {
  return value.replaceAllMapped(RegExp(r'=\?([^?]+)\?([bBqQ])\?([^?]*)\?='), (
    m,
  ) {
    final data = m.group(3)!;
    if (m.group(2)!.toLowerCase() == 'b') {
      return utf8.decode(base64.decode(data), allowMalformed: true);
    }
    final bytes = <int>[];
    final q = data.replaceAll('_', ' ');
    for (var i = 0; i < q.length; i++) {
      if (q[i] == '=' && i + 2 < q.length) {
        bytes.add(int.parse(q.substring(i + 1, i + 3), radix: 16));
        i += 2;
      } else {
        bytes.add(q.codeUnitAt(i));
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  });
}

class TestSmtpServer {
  TestSmtpServer._(this._server, this.user, this.password);

  /// Starts on the loopback. A port of 0 picks a free one.
  static Future<TestSmtpServer> start({
    int port = 0,
    String user = 'user@example.test',
    String password = 'test-password',
    SmtpMode mode = SmtpMode.accept,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    final result = TestSmtpServer._(server, user, password)..mode = mode;
    server.listen(result._handle);
    return result;
  }

  final ServerSocket _server;
  final String user;
  final String password;
  SmtpMode mode = SmtpMode.accept;
  final List<ReceivedMail> mails = [];
  final List<Socket> _open = [];

  int get port => _server.port;

  void reset() {
    mails.clear();
    mode = SmtpMode.accept;
  }

  Future<void> close() async {
    await _server.close();
    for (final socket in _open.toList()) {
      socket.destroy();
    }
  }

  Future<void> _handle(Socket socket) async {
    _open.add(socket);
    if (mode == SmtpMode.hang) return; // never a word
    final session = _Session(this, socket);
    unawaited(session.run().whenComplete(() => _open.remove(socket)));
  }
}

class _Session {
  _Session(this.server, this.socket);

  final TestSmtpServer server;
  final Socket socket;
  String from = '';
  final to = <String>[];

  void _send(String line) => socket.write('$line\r\n');

  Future<void> run() async {
    final data = StreamController<List<int>>();
    socket.listen(
      data.add,
      onDone: () {
        data.close();
      },
      onError: (_) {},
    );
    final reader = _Reader(data.stream);
    _send('220 localhost test smtp');
    try {
      while (true) {
        final line = await reader.line();
        if (line == null) return;
        final upper = line.toUpperCase();
        if (upper.startsWith('EHLO') || upper.startsWith('HELO')) {
          socket.write(
            '250-localhost\r\n250-AUTH LOGIN PLAIN\r\n250 8BITMIME\r\n',
          );
        } else if (upper.startsWith('AUTH LOGIN')) {
          _send('334 VXNlcm5hbWU6');
          final u = utf8.decode(base64.decode((await reader.line()) ?? ''));
          _send('334 UGFzc3dvcmQ6');
          final p = utf8.decode(base64.decode((await reader.line()) ?? ''));
          _authResult(u, p);
        } else if (upper.startsWith('AUTH PLAIN')) {
          final arg = line.length > 11 ? line.substring(11).trim() : '';
          String encoded = arg;
          if (encoded.isEmpty) {
            _send('334 ');
            encoded = (await reader.line()) ?? '';
          }
          final parts = utf8.decode(base64.decode(encoded)).split('\u0000');
          _authResult(
            parts.length > 1 ? parts[1] : '',
            parts.length > 2 ? parts[2] : '',
          );
        } else if (upper.startsWith('MAIL FROM:')) {
          from = _address(line);
          _send('250 ok');
        } else if (upper.startsWith('RCPT TO:')) {
          if (server.mode == SmtpMode.rejectRecipient) {
            _send('550 no such user');
          } else {
            to.add(_address(line));
            _send('250 ok');
          }
        } else if (upper == 'DATA') {
          _send('354 go ahead');
          final raw = await reader.until('\r\n.\r\n');
          if (raw == null) return;
          if (server.mode == SmtpMode.tooLarge) {
            _send('552 message too large');
          } else {
            server.mails.add(
              ReceivedMail(from: from, to: List.of(to), raw: raw),
            );
            _send('250 queued');
          }
        } else if (upper == 'RSET') {
          from = '';
          to.clear();
          _send('250 ok');
        } else if (upper == 'NOOP') {
          _send('250 ok');
        } else if (upper == 'QUIT') {
          _send('221 bye');
          await socket.flush();
          await socket.close();
          return;
        } else {
          _send('502 not implemented');
        }
      }
    } catch (_) {
      // A client that vanished.
    }
  }

  void _authResult(String u, String p) {
    if (server.mode != SmtpMode.authFail &&
        u == server.user &&
        p == server.password) {
      _send('235 ok');
    } else {
      _send('535 5.7.8 authentication failed');
    }
  }

  static String _address(String line) {
    final m = RegExp(r'<([^>]*)>').firstMatch(line);
    return m?.group(1) ?? '';
  }
}

/// Reads lines and the body of DATA from a stream of bytes.
class _Reader {
  _Reader(Stream<List<int>> stream) {
    stream.listen(
      (chunk) {
        _bytes.addAll(chunk);
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
    );
  }

  final _bytes = <int>[];
  var _done = false;
  Completer<void>? _waiting;

  void _wake() {
    final w = _waiting;
    _waiting = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<void> _more() {
    final w = _waiting = Completer<void>();
    return w.future;
  }

  Future<String?> line() async {
    while (true) {
      final i = _find(const [13, 10]);
      if (i >= 0) {
        final text = latin1.decode(_bytes.sublist(0, i));
        _bytes.removeRange(0, i + 2);
        return text;
      }
      if (_done) return null;
      await _more();
    }
  }

  /// Everything up to the terminator, which is not part of the result
  /// (dot-stuffing is undone, the first CRLF of the terminator is kept).
  Future<List<int>?> until(String terminator) async {
    final t = latin1.encode(terminator);
    // Look only at what is new (a message of hundreds of KB arrives in many
    // small pieces on the emulator; scanning it all again for each piece was
    // slower than the client's wait for the answer).
    var from = 0;
    while (true) {
      final i = _find(t, from);
      from = _bytes.length - t.length + 1 < 0
          ? 0
          : _bytes.length - t.length + 1;
      if (i >= 0) {
        final body = _bytes.sublist(0, i + 2);
        _bytes.removeRange(0, i + t.length);
        return _unstuff(body);
      }
      if (_done) return null;
      await _more();
    }
  }

  int _find(List<int> pattern, [int from = 0]) {
    for (var i = from; i + pattern.length <= _bytes.length; i++) {
      var ok = true;
      for (var j = 0; j < pattern.length; j++) {
        if (_bytes[i + j] != pattern[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  static List<int> _unstuff(List<int> body) {
    // A line that starts with ".." had a dot added by the client.
    final out = <int>[];
    for (var i = 0; i < body.length; i++) {
      final atLineStart = i == 0 || (body[i - 1] == 10 && i >= 1);
      if (atLineStart &&
          body[i] == 46 &&
          i + 1 < body.length &&
          body[i + 1] == 46) {
        continue;
      }
      out.add(body[i]);
    }
    return out;
  }
}

/// The HTTP side, for a test that runs on the emulator.
class ControlServer {
  ControlServer._(this._http, this._smtp);

  static Future<ControlServer> start(
    TestSmtpServer smtp, {
    int port = 0,
  }) async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final control = ControlServer._(http, smtp);
    http.listen(control._handle);
    return control;
  }

  final HttpServer _http;
  final TestSmtpServer _smtp;

  int get port => _http.port;

  Future<void> close() => _http.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/mails') {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode([for (final m in _smtp.mails) m.toJson()]));
    } else if (request.method == 'POST' && path.startsWith('/mode/')) {
      final name = path.substring('/mode/'.length);
      final mode = SmtpMode.values.where((m) => m.name == name);
      if (mode.isEmpty) {
        request.response.statusCode = 400;
      } else {
        _smtp.mode = mode.first;
        request.response.write('ok');
      }
    } else if (request.method == 'POST' && path == '/reset') {
      _smtp.reset();
      request.response.write('ok');
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  }
}

Future<void> main(List<String> args) async {
  int option(String name, int fallback) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? int.parse(args[i + 1]) : fallback;
  }

  final smtp = await TestSmtpServer.start(port: option('--smtp-port', 0));
  final control = await ControlServer.start(
    smtp,
    port: option('--control-port', 0),
  );
  stdout.writeln('READY smtp=${smtp.port} control=${control.port}');
  await ProcessSignal.sigint.watch().first;
  await control.close();
  await smtp.close();
}
