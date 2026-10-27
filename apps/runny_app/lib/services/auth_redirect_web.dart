import 'package:web/web.dart' as web;

void clearAuthRedirect({bool keepRecovery = false}) {
  final uri = Uri.base;
  final query = Map<String, String>.of(uri.queryParameters)
    ..remove('code')
    ..remove('error')
    ..remove('error_code')
    ..remove('error_description')
    ..remove('recovery');
  if (keepRecovery) query['recovery'] = '1';
  final cleaned = uri.replace(queryParameters: query).removeFragment();
  web.window.history.replaceState(null, '', cleaned.toString());
}
