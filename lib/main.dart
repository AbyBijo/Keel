import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding.dart';
import 'providers.dart';
import 'services.dart';
import 'shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await NotificationService.init();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const KeelApp(),
    ),
  );
}

class KeelApp extends ConsumerWidget {
  const KeelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Keel',
      debugShowCheckedModeBanner: false,
      theme: keelThemeData(
        brightness: Brightness.light,
        accent: settings.accent,
      ),
      darkTheme: keelThemeData(
        brightness: Brightness.dark,
        accent: settings.accent,
      ),
      themeMode: settings.themeModeValue,
      // Combine the system text scaler with the in-app text-size setting.
      // MediaQuery's scaler already includes the OS accessibility factor,
      // so text scaling to 200% keeps working.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final systemFactor = media.textScaler.scale(16) / 16;
        final combined = systemFactor * settings.textScale;
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(combined.clamp(0.5, 3.0)),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: settings.onboardingDone ? const Shell() : const OnboardingScreen(),
    );
  }
}
