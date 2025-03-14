import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'utils/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '牛马',
      theme: AppTheme.theme,
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(),
        '/settings': (context) => const SettingsPage(),
      },
    );
  }
} 