part of 'trainer_storage.dart';

const _backupColumns = {
  'decisions': {'id', 'source', 'data'},
  'states': {'id', 'data'},
  'events': {
    'id',
    'decision',
    'data',
    'at',
    'day',
    'is_new',
    'source',
    'chapter',
  },
  'sources': {'id', 'pgn', 'imported_at'},
  'settings': {'key', 'value'},
};

(int, Map<String, List<Map<String, Object?>>>) _validatedBackup(String text) {
  checkJsonInput(text);
  try {
    final json = jsonDecode(text) as Map<String, dynamic>;
    final version = json['version'];
    if (version is! int ||
        version < 1 ||
        version > 4 ||
        json.keys.any(
          (k) => k != 'version' && !_backupColumns.containsKey(k),
        )) {
      throw const FormatException('Unsupported backup');
    }
    final tables = <String, List<Map<String, Object?>>>{};
    var count = 0;
    for (final entry in _backupColumns.entries) {
      final table = entry.key;
      final rows = (json[table] ?? (table == 'settings' ? [] : null)) as List;
      count += rows.length;
      if (count > maxBackupRows) {
        throw const InputLimitException('Backup exceeds 100,000 total rows.');
      }
      final seen = <String>{};
      tables[table] = [
        for (final raw in rows) Map<String, Object?>.from(raw as Map),
      ];
      for (final row in tables[table]!) {
        if (row.keys.any((k) => !entry.value.contains(k))) {
          throw const FormatException('Unknown backup column');
        }
        for (final cell in row.entries) {
          if (table == 'events' && cell.key == 'is_new') {
            if (cell.value != 0 && cell.value != 1) {
              throw const FormatException('Invalid review flag');
            }
          } else if (cell.value is! String) {
            throw const FormatException('Invalid backup cell');
          }
        }
        final id = row[table == 'settings' ? 'key' : 'id'] as String;
        if (id.isEmpty || id.length > 512 || !seen.add(id)) {
          throw const FormatException('Invalid or duplicate backup identity');
        }
        if (table == 'decisions') {
          final d = Decision.fromJson(_rowJson(row['data']));
          if (d.id != id || d.source != row['source']) {
            throw const FormatException('Decision identity mismatch');
          }
        } else if (table == 'states') {
          ReviewState.fromJson(_rowJson(row['data']));
        } else if (table == 'events') {
          if ((row['decision'] as String).isEmpty) {
            throw const FormatException('Missing review decision');
          }
          final log = _rowJson(row['data']);
          validateReviewLog(log);
          final at = row['at'] as String?;
          if (at != null &&
              at.isNotEmpty &&
              !DateTime.parse(at).isAtSameMomentAs(
                DateTime.parse(log['reviewDateTime'] as String),
              )) {
            throw const FormatException('Review timestamp mismatch');
          }
          final day = row['day'] as String?;
          if (day != null &&
              day.isNotEmpty &&
              !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
            throw const FormatException('Invalid review day');
          }
        } else if (table == 'sources') {
          checkTextBytes(row['pgn'] as String, maxPgnBytes);
          final at = row['imported_at'] as String?;
          if (at != null && at.isNotEmpty) DateTime.parse(at);
        } else if (table == 'settings') {
          _validateSetting(id, row['value'] as String);
        }
      }
    }
    return (version, tables);
  } on InputLimitException {
    rethrow;
  } catch (_) {
    // Decoder/type errors may contain the user's data; do not propagate them.
    throw const FormatException(
      'Invalid backup. Existing saved data was retained.',
    );
  }
}

Map<String, dynamic> _rowJson(Object? data) {
  final text = data as String;
  checkJsonInput(text);
  return jsonDecode(text) as Map<String, dynamic>;
}

void _validateSetting(String key, String value) {
  switch (key) {
    case 'session':
      checkJsonInput(value);
      final session = TrainingSession.decode(value);
      if (session.remaining.length > maxPgnPositions ||
          session.attempts.length > maxPgnPositions ||
          session.remaining.any((id) => id.isEmpty || id.length > 512)) {
        throw const FormatException('Invalid session size');
      }
    case 'newLimit':
    case 'reviewLimit':
      final n = int.tryParse(value);
      if (n == null || n < 0 || n > 100000)
        throw const FormatException('Invalid daily limit');
    case 'retention':
      final n = double.tryParse(value);
      if (n == null || !n.isFinite || n <= 0 || n >= 1)
        throw const FormatException('Invalid retention');
    case 'side':
      if (value != 'white' && value != 'black')
        throw const FormatException('Invalid side');
    case 'dark':
    case 'autoReply':
      if (value != 'true' && value != 'false')
        throw const FormatException('Invalid preference');
    default:
      throw const FormatException('Unknown backup setting');
  }
}

/// Stop JSON escaping/encoding before it can expand a snapshot past the limit.
class _BackupByteSink implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> chunk) {
    if (chunk.length > maxBackupBytes - bytes.length) {
      throw const InputLimitException('Backup exceeds 25 MB.');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
