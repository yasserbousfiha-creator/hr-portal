// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'portal_client.dart';
import 'home_screen.dart';
import 'portal_i18n.dart';

class PortalLoginScreen extends StatefulWidget {
  const PortalLoginScreen({super.key});
  @override
  State<PortalLoginScreen> createState() => _PortalLoginScreenState();
}

class _PortalLoginScreenState extends State<PortalLoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscure = true;
  bool _isEnglish = false;

  @override
  void initState() {
    super.initState();
    try {
      _isEnglish = html.window.localStorage['portal_lang'] == 'en';
    } catch (_) {}
  }

  void _toggleLanguage() {
    setState(() => _isEnglish = !_isEnglish);
    try {
      html.window.localStorage['portal_lang'] = _isEnglish ? 'en' : 'ar';
    } catch (_) {}
  }

  String _toEmail(String username) => '${username.trim().toLowerCase()}@ybhrportal.com';

  Future<void> _login() async {
    if (_userCtrl.text.trim().isEmpty) {
      setState(() => _error = tr(_isEnglish, 'أدخل اسم المستخدم'));
      return;
    }
    final email = _toEmail(_userCtrl.text);
    setState(() { _loading = true; _error = null; });
    try {
      await portalClient.auth.signInWithPassword(
        email: email,
        password: _passCtrl.text,
      );
      if (mounted) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const PortalHomeScreen()));
      }
    } on AuthException catch (e) {
      setState(() => _error = _arabicError(e.message));
    } catch (e) {
      setState(() => _error = _isEnglish ? 'Error: $e' : 'خطأ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _arabicError(String msg) {
    if (msg.contains('Invalid login')) {
      return tr(_isEnglish, 'اسم المستخدم أو كلمة المرور غير صحيحة');
    }
    if (msg.contains('Too many requests')) {
      return tr(_isEnglish, 'محاولات كثيرة، انتظر قليلاً');
    }
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isEnglish ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
      backgroundColor: const Color(0xFF061A22),
      appBar: AppBar(
        backgroundColor: const Color(0xFF061A22),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 18),
          onPressed: () {
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggleLanguage,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.language_rounded, size: 14, color: Color(0xFF06B6D4)),
                        const SizedBox(width: 4),
                        Text(_isEnglish ? 'AR' : 'EN',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                color: Color(0xFF06B6D4))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            width: double.infinity,
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF0D2731),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x1AFFFFFF)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 40),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF06B6D4), Color(0xFF0EA5E9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.people_alt_rounded,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(height: 20),
                Text(tr(_isEnglish, 'بوابة الموظفين'),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 6),
                Text(tr(_isEnglish, 'سجّل دخولك للاطلاع على بياناتك'),
                    style: const TextStyle(fontSize: 13, color: Color(0x99FFFFFF))),
                const SizedBox(height: 32),

                TextField(
                  controller: _userCtrl,
                  keyboardType: TextInputType.text,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(tr(_isEnglish, 'اسم المستخدم'), Icons.person_outline),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    tr(_isEnglish, 'كلمة المرور'),
                    Icons.lock_outline,
                    suffix: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                          color: Colors.white38, size: 18),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 20),

                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ),
                  const SizedBox(height: 14),
                ],

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(tr(_isEnglish, 'تسجيل الدخول'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0x99FFFFFF)),
      prefixIcon: Icon(icon, color: const Color(0x66FFFFFF), size: 18),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0x0AFFFFFF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF06B6D4), width: 1.5),
      ),
    );
  }
}
