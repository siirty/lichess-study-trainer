import 'dart:convert';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:trainer_lichess/connection.dart';

class MemoryVault implements TokenVault {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String text) async {
    if (failWrite) throw StateError('fixture vault failure');
    value = text;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

void main() {
  test(
    'connection restores offline, scopes headers to Lichess and revokes before deleting vault',
    () async {
      final vault = MemoryVault();
      final calls = <String>[];
      final transport = MockClient((r) async {
        calls.add(r.url.path);
        expect(r.headers['Authorization'], 'Bearer fixture-token');
        expect(r.followRedirects, false);
        return r.url.path == '/api/account'
            ? Response('{"username":"FixtureUser"}', 200)
            : Response('', 204);
      });
      final connection = LichessConnection(
        inner: transport,
        vault: vault,
        authorize: () async => AccessGrant('fixture-token'),
      );
      await connection.connect();
      expect(connection.username, 'FixtureUser');
      final restored = LichessConnection(
        inner: transport,
        vault: vault,
        authorize: () async => null,
      );
      await restored.restore();
      expect(restored.connected, true);
      expect(calls, ['/api/account']);
      await restored.get(Uri.https('lichess.org', '/api/study/abcd1234.pgn'));
      await expectLater(
        restored.get(Uri.https('example.org', '/leak')),
        throwsA(isA<ConnectionException>()),
      );
      expect(calls.length, 2);
      await restored.disconnect();
      expect(vault.value, isNull);
      expect(restored.connected, false);
      expect(calls.last, '/api/token');
    },
  );
  test(
    'cancel leaves vault unchanged; expired token removed without network',
    () async {
      final vault = MemoryVault();
      var networkCalled = false;
      final c = LichessConnection(
        inner: MockClient((r) async {
          networkCalled = true;
          return Response('', 500);
        }),
        vault: vault,
        authorize: () async => null,
      );
      await c.connect();
      expect(c.connected, false);
      expect(vault.value, isNull);
      vault.value = jsonEncode({
        'token': 'fixture-token',
        'username': 'FixtureUser',
        'expiresAt': '2000-01-01T00:00:00Z',
      });
      await c.restore();
      expect(vault.value, isNull);
      expect(networkCalled, false);
    },
  );
  test(
    'revocation failure retains retryable connection; local-only logout clears it',
    () async {
      final vault = MemoryVault()
        ..value = jsonEncode({
          'token': 'fixture-token',
          'username': 'FixtureUser',
          'expiresAt': null,
        });
      final c = LichessConnection(
        inner: MockClient(
          (r) async => Response('fixture-token must not appear in error', 503),
        ),
        vault: vault,
        authorize: () async => null,
      );
      await c.restore();
      await expectLater(
        c.disconnect(),
        throwsA(
          isA<ConnectionException>().having(
            (e) => e.toString(),
            'redacted',
            isNot(contains('fixture-token')),
          ),
        ),
      );
      expect(c.connected, true);
      expect(vault.value, isNotNull);
      await c.disconnect(revoke: false);
      expect(c.connected, false);
      expect(vault.value, isNull);
    },
  );
  test(
    'vault write failure attempts revocation; no token appears in errors',
    () async {
      final vault = MemoryVault()..failWrite = true;
      var revoked = false;
      final c = LichessConnection(
        inner: MockClient((r) async {
          if (r.method == 'DELETE') {
            revoked = true;
            return Response('', 204);
          }
          return Response('{"username":"FixtureUser"}', 200);
        }),
        vault: vault,
        authorize: () async => AccessGrant('fixture-token'),
      );
      await expectLater(
        c.connect(),
        throwsA(
          isA<ConnectionException>().having(
            (e) => e.toString(),
            'redacted',
            isNot(contains('fixture-token')),
          ),
        ),
      );
      expect(revoked, true);
      expect(c.connected, false);
      expect(vault.value, isNull);
    },
  );
  test('revoked tokens produce actionable, redacted errors', () async {
    final vault = MemoryVault()
      ..value = jsonEncode({
        'token': 'fixture-token',
        'username': 'FixtureUser',
        'expiresAt': null,
      });
    final c = LichessConnection(
      inner: MockClient((r) async => Response('fixture-token', 401)),
      vault: vault,
      authorize: () async => null,
    );
    await c.restore();
    await expectLater(
      c.get(Uri.https('lichess.org', '/api/study/abcd1234.pgn')),
      throwsA(
        isA<ConnectionException>().having(
          (e) => e.toString(),
          'redacted',
          isNot(contains('fixture-token')),
        ),
      ),
    );
    expect(
      AccessGrant('fixture-token').toString(),
      isNot(contains('fixture-token')),
    );
  });
}
