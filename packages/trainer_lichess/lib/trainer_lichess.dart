import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'response_limits.dart';

class StudySource {
  StudySource(this.studyId, [this.chapterId]);
  final String studyId;
  final String? chapterId;
  factory StudySource.url(String input) {
    final uri = Uri.parse(input);
    final p = uri.pathSegments;
    if (uri.scheme != 'https' ||
        uri.host != 'lichess.org' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        p.length < 2 ||
        p.length > 3 ||
        p.first != 'study' ||
        p.skip(1).any((s) => !RegExp(r'^[a-zA-Z0-9]{8}$').hasMatch(s)))
      throw const FormatException('Expected a Lichess study or chapter URL');
    return StudySource(p[1], p.length == 3 ? p[2] : null);
  }
  factory StudySource.fromId(String id) {
    if (!id.startsWith('lichess:'))
      throw const FormatException('Not a remote study source');
    return StudySource.url('https://lichess.org/study/${id.substring(8)}');
  }
  String get id => 'lichess:$studyId${chapterId == null ? '' : '/$chapterId'}';
  Uri get exportUri => Uri.https(
    'lichess.org',
    '/api/study/$studyId${chapterId == null ? '' : '/$chapterId'}.pgn',
  );
}

class StudyDownloadException implements Exception {
  StudyDownloadException(this.status, this.retryAfter);
  final int status;
  final String? retryAfter;
  @override
  String toString() =>
      'Study download failed ($status)${retryAfter == null ? '' : '; retry after $retryAfter'}. Existing offline data was retained.';
}

/// Inject Lichess's authenticated client upstream. Never owns or logs credentials.
class LichessStudyClient {
  LichessStudyClient(this.client);
  final http.Client client;
  bool _inFlight = false;
  DateTime? _blockedUntil;
  Future<String> download(StudySource source) async {
    if (_inFlight) throw StateError('A download is already running');
    if (_blockedUntil?.isAfter(DateTime.now()) ?? false)
      throw StateError('Rate limited; retry later');
    _inFlight = true;
    try {
      final response = await client
          .send(http.Request('GET', source.exportUri)..followRedirects = false)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        if (response.statusCode == 429)
          _blockedUntil = DateTime.now().add(
            Duration(
              seconds:
                  int.tryParse(response.headers['retry-after'] ?? '') ?? 60,
            ),
          );
        await response.stream.drain<void>().timeout(const Duration(seconds: 5));
        throw StudyDownloadException(
          response.statusCode,
          response.headers['retry-after'],
        );
      }
      final bytes = await readResponseBytes(response.stream, 5000000);
      return utf8.decode(bytes);
    } finally {
      _inFlight = false;
    }
  }
}
