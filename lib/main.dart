import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'constants/api_constants.dart';
import 'screens/auth_screen.dart';
import 'screens/game_screen.dart';
import 'screens/setup_required_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ключи Supabase передаются при сборке, а не хранятся в репозитории.
  if (!isSupabaseConfigured) {
    runApp(const _BootstrapApp(home: SetupRequiredScreen()));
    return;
  }

  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  } catch (e) {
    debugPrint('Supabase init error: $e');
    runApp(_BootstrapApp(home: SetupRequiredScreen(details: '$e')));
    return;
  }

  runApp(const PraxisApp());
}

/// Каркас приложения для экранов вне игры: настройка и ошибки запуска.
class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PRAXIS',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: home,
    );
  }
}

class PraxisApp extends StatelessWidget {
  const PraxisApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'PRAXIS',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: session != null ? const GameScreen() : const AuthScreen(),
    );
  }
}
