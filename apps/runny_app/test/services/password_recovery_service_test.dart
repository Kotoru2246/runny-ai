import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runny_app/services/password_recovery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GoTrueClient auth;
  late PasswordRecoveryService service;
  late Map<String, dynamic> session;
  late List<http.Request> requests;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests = [];
    session = {
      'access_token': 'test-token',
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': 'recovery-user',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    };
    auth = GoTrueClient(
      url: 'https://example.supabase.co/auth/v1',
      autoRefreshToken: false,
      asyncStorage: SharedPreferencesGotrueAsyncStorage(),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(request.url.path.endsWith('/token') ? session : {}),
          200,
        );
      }),
    );
    service = PasswordRecoveryService(auth);
  });

  tearDown(() => auth.dispose());

  test('reset redirect retains origin/path and removes old callback data', () {
    expect(
      PasswordRecoveryService.recoveryRedirect(
        Uri.parse('https://runny-ai.onrender.com/?code=old#access_token=old'),
      ),
      Uri.parse('https://runny-ai.onrender.com/?recovery=1'),
    );
    expect(
      PasswordRecoveryService.recoveryRedirect(
        Uri.parse('http://localhost:8080/app/'),
      ),
      Uri.parse('http://localhost:8080/app/?recovery=1'),
    );
  });

  test('preserves recovery result after later startup auth events', () async {
    await service.sendResetEmail('runner@example.com');
    expect(requests.single.url.path, '/auth/v1/recover');
    expect(jsonDecode(requests.single.body)['code_challenge'], isNotEmpty);

    final result = await service.handleWebCallback(
      Uri.parse('https://runny-ai.onrender.com/?recovery=1&code=valid-code'),
    );
    expect(result, PasswordRecoveryStatus.ready);
    expect(auth.currentSession?.user.id, 'recovery-user');
    expect(jsonDecode(requests.last.body)['auth_code'], 'valid-code');
    expect(jsonDecode(requests.last.body)['code_verifier'], isNotEmpty);

    await auth.setInitialSession(jsonEncode(session));
    expect(
      (await auth.onAuthStateChange.first).event,
      AuthChangeEvent.initialSession,
    );
    expect(result, PasswordRecoveryStatus.ready);
  });

  test('accepts existing reset links without the recovery marker', () async {
    await service.sendResetEmail('runner@example.com');
    expect(
      await service.handleWebCallback(
        Uri.parse('https://runny-ai.onrender.com/?code=legacy-code'),
      ),
      PasswordRecoveryStatus.ready,
    );
  });

  test('missing PKCE verifier shows an error instead of landing', () async {
    expect(
      await service.handleWebCallback(
        Uri.parse('https://runny-ai.onrender.com/?recovery=1&code=valid-code'),
      ),
      PasswordRecoveryStatus.invalidLink,
    );
    expect(requests, isEmpty);
  });

  test('expired link cannot use an existing signed-in session', () async {
    await auth.setInitialSession(jsonEncode(session));
    expect(
      await service.handleWebCallback(
        Uri.parse(
          'https://runny-ai.onrender.com/?recovery=1'
          '#error=access_denied&error_code=otp_expired'
          '&error_description=Email+link+is+invalid+or+has+expired',
        ),
      ),
      PasswordRecoveryStatus.invalidLink,
    );
  });

  test('refreshing recovery page requires an authenticated session', () async {
    final uri = Uri.parse('https://runny-ai.onrender.com/?recovery=1');
    expect(
      await service.handleWebCallback(uri),
      PasswordRecoveryStatus.invalidLink,
    );
    await auth.setInitialSession(jsonEncode(session));
    expect(await service.handleWebCallback(uri), PasswordRecoveryStatus.ready);
  });

  test('ordinary auth callback does not become password recovery', () async {
    await auth.signInWithOtp(email: 'runner@example.com');
    expect(
      await service.handleWebCallback(
        Uri.parse('https://runny-ai.onrender.com/?code=signup-code'),
      ),
      PasswordRecoveryStatus.none,
    );
    expect(auth.currentSession, isNotNull);
  });

  test('ordinary landing URL does not make an auth request', () async {
    expect(
      await service.handleWebCallback(
        Uri.parse('https://runny-ai.onrender.com/'),
      ),
      PasswordRecoveryStatus.none,
    );
    expect(requests, isEmpty);
  });
}
