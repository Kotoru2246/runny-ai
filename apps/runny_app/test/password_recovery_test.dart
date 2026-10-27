import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:runny_app/app.dart';
import 'package:runny_app/l10n/app_localizations.dart';
import 'package:runny_app/l10n/language_provider.dart';
import 'package:runny_app/pages/landing_page.dart';
import 'package:runny_app/pages/login_page.dart';
import 'package:runny_app/pages/reset_password_page.dart';
import 'package:runny_app/services/password_recovery_service.dart';
import 'package:runny_app/theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

late SharedPreferences _preferences;

Future<void> _pumpGate(
  WidgetTester tester,
  PasswordRecoveryStatus status,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider(_preferences)),
        ChangeNotifierProvider(create: (_) => LanguageProvider(_preferences)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('vi')],
        home: AuthGate(initialRecoveryStatus: status),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _preferences = await SharedPreferences.getInstance();
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      anonKey: 'placeholder_anon_key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
    await AppLocalizations.preload(const Locale('en'));
  });

  tearDown(() => Supabase.instance.dispose());

  testWidgets('startup recovery survives newer auth events', (tester) async {
    await _pumpGate(tester, PasswordRecoveryStatus.ready);
    expect(find.byType(ResetPasswordPage), findsOneWidget);
    expect(find.text('Set a new password'), findsOneWidget);
    expect(find.byType(LandingPage), findsNothing);

    await tester.runAsync(() => Supabase.instance.client.auth.signOut());
    await tester.pump();
    expect(find.byType(ResetPasswordPage), findsOneWidget);
  });

  testWidgets('invalid link hides password input and returns to login', (
    tester,
  ) async {
    await _pumpGate(tester, PasswordRecoveryStatus.invalidLink);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('This reset link has expired'), findsOneWidget);
    await tester.tap(find.text('Back to login'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(ResetPasswordPage), findsNothing);
  });

  testWidgets('recovery completion does not reopen reset page', (tester) async {
    await _pumpGate(tester, PasswordRecoveryStatus.ready);
    tester.widget<ResetPasswordPage>(find.byType(ResetPasswordPage)).onDone();
    await tester.pump();
    expect(find.byType(ResetPasswordPage), findsNothing);
    expect(find.byType(LandingPage), findsOneWidget);
  });
}
