import 'dart:async';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:trainer_lichess/response_limits.dart';
import 'package:trainer_lichess/trainer_lichess.dart';
import 'package:trainer_lichess/connection.dart';

class ProbeVault implements TokenVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

void main() {
  test(
    'oversized response cancels subscription without consuming remainder',
    () async {
      var cancelled = false;
      final input = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final result = readResponseBytes(input.stream, 4);
      final expectation = expectLater(result, throwsFormatException);
      input.add([1, 2, 3, 4, 5]);
      await expectation;
      expect(cancelled, true);
      await input.close();
    },
  );
  test('public study imports do not follow redirects', () async {
    final client = LichessStudyClient(
      MockClient((request) async {
        expect(request.followRedirects, false);
        return Response('', 302, headers: {'location': 'https://example.org'});
      }),
    );
    await expectLater(
      client.download(StudySource('abcd1234')),
      throwsA(isA<StudyDownloadException>()),
    );
    expect(
      () => StudySource.url('https://user:pass@lichess.org/study/abcd1234'),
      throwsFormatException,
    );
    expect(
      () => StudySource.url('https://lichess.org:444/study/abcd1234'),
      throwsFormatException,
    );
  });
  test(
    'oversized account response is rejected and minted token revoked',
    () async {
      final vault = ProbeVault();
      var revoked = false;
      final client = LichessConnection(
        inner: MockClient((request) async {
          if (request.url.path == '/api/token') {
            revoked = true;
            return Response('', 204);
          }
          return Response('x' * 65537, 200);
        }),
        vault: vault,
        authorize: () async => AccessGrant('probe'),
      );
      await expectLater(client.connect(), throwsA(isA<ConnectionException>()));
      expect(revoked, true);
      expect(vault.value, isNull);
      expect(client.connected, false);
    },
  );
}
