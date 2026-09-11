import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'portal_client.dart';

/// Session gate for direct-URL access to the employee portal
/// (mirrors _openPortal in main.dart, as a standalone page).
class PortalGateScreen extends StatefulWidget {
  const PortalGateScreen({super.key});

  @override
  State<PortalGateScreen> createState() => _PortalGateScreenState();
}

class _PortalGateScreenState extends State<PortalGateScreen> {
  bool _checking = true;
  bool _isEmployee = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    await portalReady;
    try {
      final session = portalClient.auth.currentSession;
      if (session != null) {
        final data = await portalClient
            .from('employee_profiles')
            .select('id')
            .eq('user_id', session.user.id)
            .maybeSingle();
        _isEmployee = data != null;
        if (!_isEmployee) {
          await portalClient.auth.signOut();
        }
      }
    } catch (_) {
      _isEmployee = false;
    }
    if (!mounted) return;
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _isEmployee ? const PortalHomeScreen() : const PortalLoginScreen(),
    );
  }
}
