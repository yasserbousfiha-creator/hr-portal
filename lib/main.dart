import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_strategy/url_strategy.dart';

import 'portal/portal_client.dart';
import 'portal/portal_gate_screen.dart';
import 'portal/supabase_config.dart';
import 'theme/app_colors.dart';

void main() async {
  setPathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HrPortalApp());
  try {
    await Supabase.initialize(
      url: PortalConfig.url,
      publishableKey: PortalConfig.anonKey,
    );
  } catch (_) {
    // PortalGateScreen falls back to its login form if the auth check
    // below fails, so no user-facing handling needed here.
  } finally {
    markPortalReady();
  }
}

const Color _kBg = AppColors.bgDark;

class HrPortalApp extends StatelessWidget {
  const HrPortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'بوابة الموظفين',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: _kBg,
        colorScheme: ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
          error: AppColors.danger,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        textTheme: ThemeData.dark().textTheme
            .apply(fontFamily: 'Tajawal', bodyColor: Colors.white),
      ),
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
      home: const PortalGateScreen(),
    );
  }
}
