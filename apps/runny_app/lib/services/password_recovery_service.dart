import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum PasswordRecoveryStatus { none, ready, invalidLink }

class PasswordRecoveryService {
  final GoTrueClient _auth;

  PasswordRecoveryService(this._auth);

  Future<void> sendResetEmail(String email) => _auth.resetPasswordForEmail(
    email,
    redirectTo: kIsWeb ? recoveryRedirect(Uri.base).toString() : null,
  );

  static Uri recoveryRedirect(Uri uri) =>
      uri.replace(queryParameters: {'recovery': '1'}).removeFragment();

  /// Await the web callback before rendering: session restoration can replace
  /// the recovery event before AuthGate subscribes to the auth stream.
  Future<PasswordRecoveryStatus> handleWebCallback(Uri uri) async {
    final isRecovery = uri.queryParameters['recovery'] == '1';
    final hasCallback =
        uri.queryParameters.containsKey('code') ||
        uri.fragment.contains('access_token=') ||
        uri.fragment.contains('error_description=') ||
        uri.queryParameters.containsKey('error_description');
    if (!hasCallback) {
      return isRecovery
          ? (_auth.currentSession != null
                ? PasswordRecoveryStatus.ready
                : PasswordRecoveryStatus.invalidLink)
          : PasswordRecoveryStatus.none;
    }
    try {
      final response = await _auth.getSessionFromUrl(uri);
      return isRecovery ||
              response.redirectType == AuthChangeEvent.passwordRecovery.name ||
              response.redirectType == 'recovery'
          ? PasswordRecoveryStatus.ready
          : PasswordRecoveryStatus.none;
    } catch (_) {
      return PasswordRecoveryStatus.invalidLink;
    }
  }
}
