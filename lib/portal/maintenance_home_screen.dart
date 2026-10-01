// Restricted portal shell for a standalone maintenance-technician account
// (no employee_profiles row — see login_screen.dart's role check). Reads
// and writes ppm_devices/ppm_maintenance_log/assets/suppliers/
// maintenance_items directly, protected by the RLS policies added in
// hrmanager's 20260929150000/20260929160000 migrations (role='maintenance'
// in this user's own JWT — the same tables the desktop app's admin uses).
import 'package:flutter/material.dart';
import 'portal_client.dart';
import 'login_screen.dart';
import 'portal_i18n.dart';

class MaintenanceHomeScreen extends StatefulWidget {
  const MaintenanceHomeScreen({super.key});
  @override
  State<MaintenanceHomeScreen> createState() => _MaintenanceHomeScreenState();
}

class _MaintenanceHomeScreenState extends State<MaintenanceHomeScreen>
    with SingleTickerProviderStateMixin {
  final bool _isEnglish = false;
  // 'regular' technicians only log maintenance visits — everything else
  // (Assets/Suppliers/Maintenance&Warranty and the technician-accounts
  // tab) is manager-only, both here and at the RLS layer (migration
  // 20260929170000). Missing level (accounts created before this existed)
  // defaults to manager, matching the RLS policies' own coalesce default.
  late final bool _isManager =
      portalClient.auth.currentUser?.userMetadata?['level'] != 'regular';
  late final TabController _tabs = TabController(length: _isManager ? 5 : 1, vsync: this);

  void _logout() async {
    try {
      await portalClient.auth.signOut();
    } catch (_) {}
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => Directionality(
            textDirection: TextDirection.rtl,
            child: const PortalLoginScreen(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isEnglish ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          title: Text(tr(_isEnglish, 'صيانة الأجهزة'),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
              onPressed: _logout,
            ),
            const SizedBox(width: 8),
          ],
          bottom: _isManager
              ? TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  indicatorColor: _indigo,
                  labelColor: _indigo,
                  unselectedLabelColor: Colors.white54,
                  tabs: [
                    Tab(text: tr(_isEnglish, 'الصيانة الدورية PPM')),
                    Tab(text: tr(_isEnglish, 'العهد والأصول')),
                    Tab(text: tr(_isEnglish, 'الموردون')),
                    Tab(text: tr(_isEnglish, 'الصيانة والضمان')),
                    Tab(text: tr(_isEnglish, 'إدارة الفنيين')),
                  ],
                )
              : null,
        ),
        body: _isManager
            ? TabBarView(
                controller: _tabs,
                children: [
                  _PpmTab(isEnglish: _isEnglish),
                  _AssetsTab(isEnglish: _isEnglish),
                  _SuppliersTab(isEnglish: _isEnglish),
                  _MaintenanceItemsTab(isEnglish: _isEnglish),
                  _TechniciansTab(isEnglish: _isEnglish),
                ],
              )
            : _PpmTab(isEnglish: _isEnglish, restricted: true),
      ),
    );
  }
}

// ---- shared bits ----

const _bg = Color(0xFF061A22);
const _card = Color(0xFF0D2731);
const _indigo = Color(0xFF06B6D4);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFEF4444);
const _green = Color(0xFF34D399);

InputDecoration _dec(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0x99FFFFFF)),
      filled: true,
      fillColor: const Color(0x0AFFFFFF),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _indigo, width: 1.5)),
    );

Widget _cardTile({required Widget child}) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: child,
    );

// ---- PPM tab ----

class _PpmTab extends StatefulWidget {
  final bool isEnglish;
  // Regular technicians (level == 'regular') can only log a maintenance
  // visit — no adding/editing/deleting devices, matching what the RLS
  // policies from migration 20260929170000 actually allow them to do.
  final bool restricted;
  const _PpmTab({required this.isEnglish, this.restricted = false});
  @override
  State<_PpmTab> createState() => _PpmTabState();
}

class _PpmTabState extends State<_PpmTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _devices = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await portalClient.from('ppm_devices').select().order('name');
      if (mounted) setState(() { _devices = List<Map<String, dynamic>>.from(data as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _status(Map<String, dynamic> d) {
    final raw = d['next_due_date'] as String?;
    if (raw == null) return tr(widget.isEnglish, 'غير مجدول');
    final next = DateTime.tryParse(raw);
    if (next == null) return tr(widget.isEnglish, 'غير مجدول');
    final days = next.difference(DateTime.now()).inDays;
    if (days < 0) return tr(widget.isEnglish, 'متأخرة');
    if (days <= 14) return tr(widget.isEnglish, 'قريبة');
    return tr(widget.isEnglish, 'منتظمة');
  }

  Color _statusColor(String s) {
    if (s == tr(widget.isEnglish, 'منتظمة')) return _green;
    if (s == tr(widget.isEnglish, 'قريبة')) return _amber;
    if (s == tr(widget.isEnglish, 'متأخرة')) return _red;
    return Colors.white38;
  }

  String _fmt(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _fmtDateTime(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${_fmt(iso)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _addOrEditDevice({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(text: existing?['name'] as String? ?? '');
    final numberCtrl = TextEditingController(text: existing?['device_number'] as String? ?? '');
    final modelCtrl = TextEditingController(text: existing?['model_version'] as String? ?? '');
    final locationCtrl = TextEditingController(text: existing?['location'] as String? ?? '');
    int interval = existing?['interval_months'] as int? ?? 3;
    bool locationError = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: _card,
          title: Text(existing == null ? tr(widget.isEnglish, 'إضافة جهاز جديد') : tr(widget.isEnglish, 'تعديل بيانات الجهاز'),
              style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'اسم الجهاز'))),
              const SizedBox(height: 12),
              TextField(controller: numberCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'رقم الجهاز'))),
              const SizedBox(height: 12),
              TextField(controller: modelCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'الموديل/الإصدار'))),
              const SizedBox(height: 12),
              TextField(
                controller: locationCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('${tr(widget.isEnglish, 'الموقع')} *').copyWith(
                  errorText: locationError ? tr(widget.isEnglish, 'الموقع مطلوب') : null,
                  errorStyle: const TextStyle(color: _red),
                ),
                onChanged: (_) {
                  if (locationError) setSt(() => locationError = false);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: interval,
                dropdownColor: _card,
                style: const TextStyle(color: Colors.white),
                decoration: _dec(tr(widget.isEnglish, 'دورية الصيانة (أشهر)')),
                items: [1, 3, 6, 12].map((m) => DropdownMenuItem(value: m, child: Text('$m'))).toList(),
                onChanged: (v) => setSt(() => interval = v ?? 3),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(widget.isEnglish, 'إلغاء'))),
            FilledButton(
              onPressed: () {
                if (existing == null && locationCtrl.text.trim().isEmpty) {
                  setSt(() => locationError = true);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(tr(widget.isEnglish, 'حفظ')),
            ),
          ],
        ),
      ),
    );
    if (saved != true || nameCtrl.text.trim().isEmpty) return;
    try {
      if (existing == null) {
        await portalClient.from('ppm_devices').insert({
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'name': nameCtrl.text.trim(),
          'device_number': numberCtrl.text.trim().isEmpty ? null : numberCtrl.text.trim(),
          'model_version': modelCtrl.text.trim().isEmpty ? null : modelCtrl.text.trim(),
          'interval_months': interval,
          'location': locationCtrl.text.trim(),
          'added_by': _currentTechName(),
          'created_at': DateTime.now().toIso8601String(),
        });
      } else {
        await portalClient.from('ppm_devices').update({
          'name': nameCtrl.text.trim(),
          'device_number': numberCtrl.text.trim(),
          'model_version': modelCtrl.text.trim(),
          'interval_months': interval,
          'location': locationCtrl.text.trim(),
        }).eq('id', existing['id']);
      }
      _load();
    } catch (_) {}
  }

  Future<void> _logMaintenance(Map<String, dynamic> device) async {
    bool isEmergency = false;
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: _card,
          title: Text(tr(widget.isEnglish, 'تسجيل صيانة'), style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(device['name'] as String? ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: isEmergency,
                onChanged: (v) => setSt(() => isEmergency = v ?? false),
                title: Text(tr(widget.isEnglish, 'صيانة طارئة (لا تغيّر الموعد القادم)'),
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: _indigo,
              ),
              TextField(controller: notesCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'ملاحظات (اختياري)'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(widget.isEnglish, 'إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(widget.isEnglish, 'تسجيل'))),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final now = DateTime.now();
      final intervalMonths = device['interval_months'] as int? ?? 3;
      String nextDue;
      if (isEmergency) {
        nextDue = (device['next_due_date'] as String?) ?? _addMonths(now, intervalMonths).toIso8601String();
      } else {
        nextDue = _addMonths(now, intervalMonths).toIso8601String();
      }
      await portalClient.from('ppm_maintenance_log').insert({
        'id': '${now.millisecondsSinceEpoch}_${device['id']}',
        'device_id': device['id'],
        'performed_at': now.toIso8601String(),
        'next_due_date': nextDue,
        'type': isEmergency ? 'طارئة' : 'دورية',
        'technician': _currentTechName(),
        'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        'created_at': now.toIso8601String(),
      });
      await portalClient.from('ppm_devices').update({
        'last_maintenance_date': now.toIso8601String(),
        'next_due_date': nextDue,
        'last_maintenance_by': _currentTechName(),
      }).eq('id', device['id']);
      _load();
    } catch (_) {}
  }

  String? _currentTechName() {
    final meta = portalClient.auth.currentUser?.userMetadata;
    return (meta?['name'] as String?) ?? portalClient.auth.currentUser?.email;
  }

  DateTime _addMonths(DateTime d, int months) {
    final total = d.month - 1 + months;
    final year = d.year + total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, d.day > lastDay ? lastDay : d.day);
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    try {
      await portalClient.from('ppm_devices').delete().eq('id', d['id']);
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _indigo));
    return Scaffold(
      backgroundColor: _bg,
      // Both levels can add/edit devices (regular technicians are only
      // blocked from deleting one — see the button row below). RLS was
      // extended to match (migration 20261001100000): regular now has
      // INSERT alongside its existing SELECT/UPDATE on ppm_devices.
      floatingActionButton: FloatingActionButton(
        backgroundColor: _indigo,
        onPressed: () => _addOrEditDevice(),
        child: const Icon(Icons.add),
      ),
      body: _devices.isEmpty
          ? Center(child: Text(tr(widget.isEnglish, 'لا توجد أجهزة'), style: const TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _devices.length,
              itemBuilder: (context, i) {
                final d = _devices[i];
                final status = _status(d);
                return _cardTile(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(d['name'] as String? ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                          child: Text(status, style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      if ((d['location'] as String?)?.isNotEmpty ?? false)
                        Text(
                          '📍 ${d['location']}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      Text(
                        '${tr(widget.isEnglish, "آخر صيانة")}: ${_fmtDateTime(d['last_maintenance_date'] as String?)}   •   ${tr(widget.isEnglish, "القادمة")}: ${_fmt(d['next_due_date'] as String?)}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      if ((d['last_maintenance_by'] as String?)?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${tr(widget.isEnglish, "آخر صيانة بواسطة")}: ${d['last_maintenance_by']}',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ),
                      if ((d['added_by'] as String?)?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${tr(widget.isEnglish, "أضيف بواسطة")}: ${d['added_by']} — ${_fmtDateTime(d['created_at'] as String?)}',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(children: [
                        TextButton(onPressed: () => _logMaintenance(d), child: Text(tr(widget.isEnglish, 'تسجيل صيانة'))),
                        TextButton(onPressed: () => _addOrEditDevice(existing: d), child: Text(tr(widget.isEnglish, 'تعديل'))),
                        // Delete stays manager-only — RLS has no delete
                        // policy for level='regular' on ppm_devices.
                        if (!widget.restricted)
                          TextButton(
                            onPressed: () => _delete(d),
                            child: Text(tr(widget.isEnglish, 'حذف'), style: const TextStyle(color: _red)),
                          ),
                      ]),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ---- Assets tab ----

class _AssetsTab extends StatefulWidget {
  final bool isEnglish;
  const _AssetsTab({required this.isEnglish});
  @override
  State<_AssetsTab> createState() => _AssetsTabState();
}

class _AssetsTabState extends State<_AssetsTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await portalClient.from('assets').select().order('created_at', ascending: false);
      if (mounted) setState(() { _items = List<Map<String, dynamic>>.from(data as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addAsset() async {
    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final serialCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr(widget.isEnglish, 'إضافة أصل'), style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'الاسم'))),
            const SizedBox(height: 12),
            TextField(controller: typeCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'النوع'))),
            const SizedBox(height: 12),
            TextField(controller: serialCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'الرقم التسلسلي (اختياري)'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(widget.isEnglish, 'إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(widget.isEnglish, 'حفظ'))),
        ],
      ),
    );
    if (saved != true || nameCtrl.text.trim().isEmpty || typeCtrl.text.trim().isEmpty) return;
    try {
      await portalClient.from('assets').insert({
        'name': nameCtrl.text.trim(),
        'type': typeCtrl.text.trim(),
        'serial_number': serialCtrl.text.trim().isEmpty ? null : serialCtrl.text.trim(),
        'status': 'نشط',
        'created_at': DateTime.now().toIso8601String(),
      });
      _load();
    } catch (_) {}
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    try {
      await portalClient.from('assets').delete().eq('id', a['id']);
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _indigo));
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: FloatingActionButton(backgroundColor: _indigo, onPressed: _addAsset, child: const Icon(Icons.add)),
      body: _items.isEmpty
          ? Center(child: Text(tr(widget.isEnglish, 'لا توجد أصول'), style: const TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final a = _items[i];
                return _cardTile(
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a['name'] as String? ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        Text(
                          [a['type'], a['serial_number'], a['assigned_to_employee_name']]
                              .where((e) => e != null && (e as String).isNotEmpty)
                              .join(' • '),
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ]),
                    ),
                    IconButton(icon: const Icon(Icons.delete, color: _red, size: 18), onPressed: () => _delete(a)),
                  ]),
                );
              },
            ),
    );
  }
}

// ---- Suppliers tab ----

class _SuppliersTab extends StatefulWidget {
  final bool isEnglish;
  const _SuppliersTab({required this.isEnglish});
  @override
  State<_SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends State<_SuppliersTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await portalClient.from('suppliers').select().order('name');
      if (mounted) setState(() { _items = List<Map<String, dynamic>>.from(data as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addSupplier() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr(widget.isEnglish, 'إضافة مورّد'), style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'الاسم'))),
            const SizedBox(height: 12),
            TextField(controller: phoneCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'الهاتف (اختياري)'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(widget.isEnglish, 'إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(widget.isEnglish, 'حفظ'))),
        ],
      ),
    );
    if (saved != true || nameCtrl.text.trim().isEmpty) return;
    try {
      await portalClient.from('suppliers').insert({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': nameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
      });
      _load();
    } catch (_) {}
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    try {
      await portalClient.from('suppliers').delete().eq('id', s['id']);
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _indigo));
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: FloatingActionButton(backgroundColor: _indigo, onPressed: _addSupplier, child: const Icon(Icons.add)),
      body: _items.isEmpty
          ? Center(child: Text(tr(widget.isEnglish, 'لا يوجد موردون'), style: const TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final s = _items[i];
                return _cardTile(
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s['name'] as String? ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        if ((s['phone'] as String?)?.isNotEmpty ?? false)
                          Text(s['phone'] as String, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ]),
                    ),
                    IconButton(icon: const Icon(Icons.delete, color: _red, size: 18), onPressed: () => _delete(s)),
                  ]),
                );
              },
            ),
    );
  }
}

// ---- Maintenance & warranty tab ----

class _MaintenanceItemsTab extends StatefulWidget {
  final bool isEnglish;
  const _MaintenanceItemsTab({required this.isEnglish});
  @override
  State<_MaintenanceItemsTab> createState() => _MaintenanceItemsTabState();
}

class _MaintenanceItemsTabState extends State<_MaintenanceItemsTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await portalClient.from('maintenance_items').select().order('created_at', ascending: false);
      if (mounted) setState(() { _items = List<Map<String, dynamic>>.from(data as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addItem() async {
    final nameCtrl = TextEditingController();
    DateTime purchaseDate = DateTime.now();
    DateTime warrantyEnd = DateTime.now().add(const Duration(days: 365));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: _card,
          title: Text(tr(widget.isEnglish, 'إضافة جهاز جديد'), style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'اسم الجهاز'))),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr(widget.isEnglish, 'تاريخ انتهاء الضمان'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                trailing: Text('${warrantyEnd.year}-${warrantyEnd.month.toString().padLeft(2, '0')}-${warrantyEnd.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx, initialDate: warrantyEnd, firstDate: DateTime(2020), lastDate: DateTime(2040),
                  );
                  if (picked != null) setSt(() => warrantyEnd = picked);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(widget.isEnglish, 'إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(widget.isEnglish, 'حفظ'))),
          ],
        ),
      ),
    );
    if (saved != true || nameCtrl.text.trim().isEmpty) return;
    try {
      await portalClient.from('maintenance_items').insert({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'equipment_name': nameCtrl.text.trim(),
        'purchase_date': purchaseDate.toIso8601String(),
        'warranty_start_date': purchaseDate.toIso8601String(),
        'warranty_end_date': warrantyEnd.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
      _load();
    } catch (_) {}
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    try {
      await portalClient.from('maintenance_items').delete().eq('id', item['id']);
      _load();
    } catch (_) {}
  }

  String _fmt(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _indigo));
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: FloatingActionButton(backgroundColor: _indigo, onPressed: _addItem, child: const Icon(Icons.add)),
      body: _items.isEmpty
          ? Center(child: Text(tr(widget.isEnglish, 'لا توجد أجهزة'), style: const TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final it = _items[i];
                final expired = DateTime.tryParse(it['warranty_end_date'] as String? ?? '')?.isBefore(DateTime.now()) ?? false;
                return _cardTile(
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it['equipment_name'] as String? ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        Text(
                          '${tr(widget.isEnglish, "انتهاء الضمان")}: ${_fmt(it['warranty_end_date'] as String?)}',
                          style: TextStyle(color: expired ? _red : Colors.white54, fontSize: 12),
                        ),
                      ]),
                    ),
                    IconButton(icon: const Icon(Icons.delete, color: _red, size: 18), onPressed: () => _delete(it)),
                  ]),
                );
              },
            ),
    );
  }
}

// ---- Manage regular technicians (managers only) ----
//
// Calls the maintenance-team edge function directly (not swift-responder —
// the portal has no HR_ADMIN_SECRET, by design). That function is gated by
// the caller's OWN session: it checks this manager's JWT metadata before
// doing anything, and can only ever create/delete level='regular' accounts,
// never another manager — see supabase/functions/maintenance-team/index.ts.
class _TechniciansTab extends StatefulWidget {
  final bool isEnglish;
  const _TechniciansTab({required this.isEnglish});
  @override
  State<_TechniciansTab> createState() => _TechniciansTabState();
}

class _TechniciansTabState extends State<_TechniciansTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _accounts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _call(String action, Map<String, dynamic> payload) async {
    final res = await portalClient.functions.invoke(
      'maintenance-team',
      body: {'action': action, 'payload': payload},
    );
    final body = res.data;
    if (body is Map && body['error'] != null) {
      throw Exception(body['error']);
    }
    return (body as Map)['data'] as Map<String, dynamic>? ?? {};
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await portalClient.functions.invoke(
        'maintenance-team',
        body: {'action': 'listRegularAccounts', 'payload': {}},
      );
      final body = res.data;
      if (body is Map && body['error'] != null) throw Exception(body['error']);
      final rows = ((body as Map)['data'] as List? ?? []);
      if (mounted) setState(() => _accounts = rows.cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addAccount() async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr(widget.isEnglish, 'فني صيانة جديد (عادي)'), style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'الاسم'))),
            const SizedBox(height: 12),
            TextField(controller: userCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'اسم المستخدم'))),
            const SizedBox(height: 12),
            TextField(controller: passCtrl, obscureText: true, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'كلمة المرور'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(widget.isEnglish, 'إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(widget.isEnglish, 'إنشاء'))),
        ],
      ),
    );
    if (saved != true || userCtrl.text.trim().isEmpty || passCtrl.text.trim().isEmpty) return;
    try {
      await _call('createRegularAccount', {
        'username': userCtrl.text.trim(),
        'password': passCtrl.text.trim(),
        'name': nameCtrl.text.trim().isEmpty ? userCtrl.text.trim() : nameCtrl.text.trim(),
      });
      _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _deleteAccount(Map<String, dynamic> a) async {
    try {
      await _call('deleteRegularAccount', {'userId': a['userId']});
      _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _indigo));
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: FloatingActionButton(backgroundColor: _indigo, onPressed: _addAccount, child: const Icon(Icons.add)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr(widget.isEnglish, 'حسابات فنيين عاديين — يسجّلون صيانة فقط، بلا وصول للعهد أو الموردين أو الصيانة والضمان.'),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: _red, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          if (_accounts.isEmpty)
            Text(tr(widget.isEnglish, 'لا توجد حسابات بعد.'), style: const TextStyle(color: Colors.white38, fontSize: 12))
          else
            ..._accounts.map((a) => _cardTile(
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a['name'] as String? ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        Text(a['email'] as String? ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ]),
                    ),
                    IconButton(icon: const Icon(Icons.delete, color: _red, size: 18), onPressed: () => _deleteAccount(a)),
                  ]),
                )),
        ],
      ),
    );
  }
}
