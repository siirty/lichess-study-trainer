import 'package:test/test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:trainer_lichess/trainer_lichess.dart';

void main() {
  test('documented export endpoint and status failures', () async {
    final source = StudySource.url(
      'https://lichess.org/study/abcd1234/efgh5678',
    );
    final client = LichessStudyClient(
      MockClient((r) async {
        expect(r.url.path, '/api/study/abcd1234/efgh5678.pgn');
        return Response('1. e4 *', 200);
      }),
    );
    expect(await client.download(source), '1. e4 *');
    final limited = LichessStudyClient(
      MockClient(
        (r) async => Response('', 429, headers: {'retry-after': '60'}),
      ),
    );
    await expectLater(
      limited.download(source),
      throwsA(isA<StudyDownloadException>()),
    );
    await expectLater(limited.download(source), throwsStateError);
  });
  test('untrusted hosts rejected', () {
    expect(
      () => StudySource.url('https://example.com/study/abcd1234'),
      throwsFormatException,
    );
  });
  test('persisted source IDs map back to documented refresh endpoints', () {
    expect(
      StudySource.fromId('lichess:abcd1234').exportUri.path,
      '/api/study/abcd1234.pgn',
    );
    expect(
      StudySource.fromId('lichess:abcd1234/efgh5678').exportUri.path,
      '/api/study/abcd1234/efgh5678.pgn',
    );
    expect(() => StudySource.fromId('local:abcd1234'), throwsFormatException);
    expect(
      () => StudySource.fromId('lichess:abcd1234/../example.org'),
      throwsFormatException,
    );
  });
}
