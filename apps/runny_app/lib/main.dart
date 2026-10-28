import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'theme/theme_provider.dart';
import 'l10n/language_provider.dart';
import 'services/nutrition_service.dart';
import 'services/strava_redirect.dart';
import 'services/entitlement_service.dart';
import 'services/notification_navigation_service.dart';
import 'services/notification_service.dart';
import 'services/ai_coach_hub_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('vi', null);
  await initializeDateFormatting('en', null);
  await dotenv.load(fileName: '.env');

  // Bắt mã callback của Strava (và dọn URL) TRƯỚC khi Supabase khởi tạo để
  // Supabase không nhầm `?code=` của Strava là callback đăng nhập PKCE.
  captureStravaRedirect();

  final prefs = await SharedPreferences.getInstance();

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseAnonKey == null) {
    throw Exception('Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env');
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  try {
    await NotificationService.instance.initialize(
      onRunReminderTap: handleRunReminderPayload,
    );
  } catch (e, st) {
    debugPrint('Failed to initialize NotificationService: $e\n$st');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider(prefs)),
        ChangeNotifierProvider(create: (_) => LanguageProvider(prefs)),
        ChangeNotifierProvider(create: (_) => NutritionService()),
        ChangeNotifierProvider(create: (_) => EntitlementProvider()),
        ChangeNotifierProvider(create: (_) => AICoachHubController()),
      ],
      child: const RunnyApp(),
    ),
  );
}
