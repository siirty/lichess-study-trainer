import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:trainer_lichess/connection.dart';

class SecureTokenVault implements TokenVault {
  const SecureTokenVault();
  static const storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const key = 'study_trainer.lichess.oauth';
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> delete() => storage.delete(key: key);
}

Future<AccessGrant?> authorizeLichess() async {
  try {
    final result = await const FlutterAppAuth().authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        'org.studytrainer.standalone',
        'org.studytrainer.standalone://oauth',
        scopes: const ['study:read'],
        serviceConfiguration: const AuthorizationServiceConfiguration(
          authorizationEndpoint: 'https://lichess.org/oauth',
          tokenEndpoint: 'https://lichess.org/api/token',
        ),
      ),
    );
    final token = result.accessToken;
    if (token == null)
      throw const ConnectionException('Lichess did not return a token.');
    return AccessGrant(token, expiresAt: result.accessTokenExpirationDateTime);
  } on FlutterAppAuthUserCancelledException {
    return null;
  } catch (_) {
    throw const ConnectionException(
      'Lichess sign-in failed. Please retry in your system browser.',
    );
  }
}
