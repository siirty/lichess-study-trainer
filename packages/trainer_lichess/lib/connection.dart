import 'dart:convert';
import 'package:http/http.dart' as http;
import 'response_limits.dart';

abstract interface class TokenVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class AccessGrant {
  AccessGrant(this.token, {this.expiresAt});
  final String token;
  final DateTime? expiresAt;
  @override
  String toString() => 'AccessGrant(redacted)';
}

class ConnectionException implements Exception {
  const ConnectionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Host-only account adapter. Core/SQLite never receive credentials. The inner
/// client must be unauthenticated; credentials are attached only to lichess.org.
class LichessConnection extends http.BaseClient {
  LichessConnection({
    required this.inner,
    required this.vault,
    required this.authorize,
  });
  final http.Client inner;
  final TokenVault vault;
  final Future<AccessGrant?> Function() authorize;
  String? _token, _username;
  DateTime? _expiresAt;
  String? get username => _username;
  bool get connected => _token != null;
  Future<void> restore() async {
    try {
      final saved = await vault.read();
      if (saved == null) return;
      final j = jsonDecode(saved) as Map<String, dynamic>;
      final token = j['token'] as String, username = j['username'] as String;
      final expires = j['expiresAt'] == null
          ? null
          : DateTime.parse(j['expiresAt'] as String);
      if (token.isEmpty || username.isEmpty) throw const FormatException();
      if (expires != null && !expires.isAfter(DateTime.now())) {
        await vault.delete();
        return;
      }
      _token = token;
      _username = username;
      _expiresAt = expires;
    } catch (_) {
      throw const ConnectionException(
        'Could not read the secure Lichess connection. Local training is still available.',
      );
    }
  }

  Future<void> connect() async {
    final grant = await authorize();
    if (grant == null) return;
    if (grant.token.isEmpty)
      throw const ConnectionException(
        'Lichess did not return an access token.',
      );
    try {
      final request = http.Request(
        'GET',
        Uri.https('lichess.org', '/api/account'),
      )..followRedirects = false;
      request.headers['Authorization'] = 'Bearer ${grant.token}';
      final response = await inner
          .send(request)
          .timeout(const Duration(seconds: 30));
      final body = await readResponseBytes(response.stream, 65536);
      if (response.statusCode != 200)
        throw const ConnectionException(
          'Could not verify the Lichess account. Please reconnect.',
        );
      final j = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      final username = j['username'] as String;
      await vault.write(
        jsonEncode({
          'token': grant.token,
          'username': username,
          'expiresAt': grant.expiresAt?.toUtc().toIso8601String(),
        }),
      );
      _token = grant.token;
      _username = username;
      _expiresAt = grant.expiresAt;
    } catch (_) {
      // A minted token must not be abandoned if account validation or secure
      // storage fails. Best effort; remote failures remain revocable on Lichess.
      try {
        final request = http.Request(
          'DELETE',
          Uri.https('lichess.org', '/api/token'),
        )..followRedirects = false;
        request.headers['Authorization'] = 'Bearer ${grant.token}';
        final response = await inner
            .send(request)
            .timeout(const Duration(seconds: 10));
        await response.stream.drain<void>().timeout(const Duration(seconds: 5));
      } catch (_) {}
      throw const ConnectionException(
        'Could not connect securely. Try again; any remaining authorization can be revoked on Lichess.',
      );
    }
  }

  Future<void> disconnect({bool revoke = true}) async {
    if (revoke && _token != null) {
      try {
        final request = http.Request(
          'DELETE',
          Uri.https('lichess.org', '/api/token'),
        )..followRedirects = false;
        request.headers['Authorization'] = 'Bearer $_token';
        final response = await inner
            .send(request)
            .timeout(const Duration(seconds: 30));
        await response.stream.drain<void>().timeout(const Duration(seconds: 5));
        if (response.statusCode != 200 &&
            response.statusCode != 204 &&
            response.statusCode != 401)
          throw const ConnectionException('Revocation failed');
      } catch (_) {
        throw const ConnectionException(
          'Could not revoke the token. Retry online or disconnect this device and revoke access on Lichess.',
        );
      }
    }
    try {
      await vault.delete();
    } catch (_) {
      throw const ConnectionException(
        'Could not clear secure storage. Please retry disconnecting.',
      );
    }
    _token = null;
    _username = null;
    _expiresAt = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url;
    // Refuse destinations outside the explicit API host before injecting auth.
    if (url.scheme != 'https' ||
        url.host != 'lichess.org' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty)
      throw const ConnectionException(
        'Refusing an untrusted Lichess API destination.',
      );
    if (_expiresAt != null && !_expiresAt!.isAfter(DateTime.now()))
      throw const ConnectionException(
        'Lichess connection expired. Reconnect in Settings.',
      );
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
      request.followRedirects = false;
    }
    final response = await inner.send(request);
    if (response.statusCode == 401 && _token != null) {
      await response.stream.drain<void>().timeout(const Duration(seconds: 5));
      throw const ConnectionException(
        'Lichess authorization expired or was revoked. Reconnect in Settings.',
      );
    }
    return response;
  }

  @override
  void close() => inner.close();
}
