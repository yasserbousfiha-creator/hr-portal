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
import 'package:url_launcher/url_launcher.dart';
import 'ppm_pdf_export.dart';
import 'ppm_report.dart';

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
  bool _recentOnly = false;
  List<Map<String, dynamic>> _recentLogs = [];

  // The periodic/emergency split tried as two tabs (2026-10-01) was undone
  // the same day: "نلغي التبويبين، بس نخليها بشكل مرتب كي نفرق بين الدورية
  // وغير الدورية" — back to one screen, differentiated by the طارئة badge
  // already shown on log entries (see _showHistory/_showAllLogs) instead of
  // a separate tab. The quick "log an emergency visit by searching any
  // device" entry point (_showLogEmergencyDialog) was kept as its own
  // button rather than removed outright — still useful on its own.

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Logs an emergency visit without going through the periodic device
  /// list — a simple name-search picker over the already-loaded `_devices`.
  Future<void> _showLogEmergencyDialog() async {
    Map<String, dynamic>? selectedDevice;
    DateTime performedAt = DateTime.now();
    final notesCtrl = TextEditingController();
    final technicianName = _currentTechName() ?? '';
    PickedPpmReport? report;
    String deviceQuery = '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final matches = deviceQuery.trim().isEmpty
              ? _devices
              : _devices.where((d) {
                  final q = deviceQuery.trim().toLowerCase();
                  return (d['name'] as String? ?? '').toLowerCase().contains(q) ||
                      (d['serial_number'] as String? ?? '').toLowerCase().contains(q);
                }).toList();
          return AlertDialog(
            backgroundColor: _card,
            title: Text(tr(widget.isEnglish, 'تسجيل صيانة طارئة'), style: const TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 340,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: _dec(tr(widget.isEnglish, 'ابحث باسم الجهاز')),
                  onChanged: (v) => setSt(() { deviceQuery = v; selectedDevice = null; }),
                ),
                const SizedBox(height: 8),
                if (selectedDevice != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: _indigo.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          [
                            selectedDevice!['name'] as String? ?? '',
                            if ((selectedDevice!['serial_number'] as String?)?.isNotEmpty ?? false) 'S/N: ${selectedDevice!['serial_number']}',
                          ].join('  •  '),
                          style: const TextStyle(color: _indigo, fontWeight: FontWeight.w600),
                        ),
                      ),
                      InkWell(onTap: () => setSt(() => selectedDevice = null), child: const Icon(Icons.close, size: 14, color: _indigo)),
                    ]),
                  )
                else if (deviceQuery.trim().isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: ListView(
                      shrinkWrap: true,
                      children: matches.map((d) => InkWell(
                            onTap: () => setSt(() { selectedDevice = d; deviceQuery = d['name'] as String? ?? ''; }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d['name'] as String? ?? '', style: const TextStyle(color: Colors.white)),
                                  if ([d['serial_number'], d['location']].any((v) => (v as String?)?.isNotEmpty ?? false))
                                    Text(
                                      [
                                        if ((d['serial_number'] as String?)?.isNotEmpty ?? false) 'S/N: ${d['serial_number']}',
                                        if ((d['location'] as String?)?.isNotEmpty ?? false) d['location'],
                                      ].join('  •  '),
                                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                ],
                              ),
                            ),
                          )).toList(),
                    ),
                  ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: _dec(tr(widget.isEnglish, 'الفني/المسؤول')),
                  child: Text(technicianName, style: const TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 12),
                _reportPicker(report, (r) => setSt(() => report = r)),
                TextField(controller: notesCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'ملاحظات (اختياري)'))),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(widget.isEnglish, 'إلغاء'))),
              FilledButton(
                onPressed: selectedDevice == null ? null : () => Navigator.pop(ctx, true),
                child: Text(tr(widget.isEnglish, 'تسجيل')),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true || selectedDevice == null) return;
    try {
      final now = performedAt;
      final logId = '${now.millisecondsSinceEpoch}_${selectedDevice!['id']}';
      final reportKey = report == null ? null : await uploadPpmReport(logId: logId, report: report!);
      await portalClient.from('ppm_maintenance_log').insert({
        'id': logId,
        'report_key': reportKey,
        'report_keys': reportKey == null ? <String>[] : [reportKey],
        'device_id': selectedDevice!['id'],
        'performed_at': now.toIso8601String(),
        'next_due_date': selectedDevice!['next_due_date'],
        'type': 'طارئة',
        'technician': technicianName.isEmpty ? null : technicianName,
        'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        'created_at': now.toIso8601String(),
      });
      await portalClient.from('ppm_devices').update({
        'last_maintenance_date': now.toIso8601String(),
        'last_maintenance_by': technicianName.isEmpty ? null : technicianName,
      }).eq('id', selectedDevice!['id']);
      _load();
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await portalClient.from('ppm_devices').select().order('name');
      if (mounted) setState(() { _devices = List<Map<String, dynamic>>.from(data as List); _loading = false; });
      if (_recentOnly) _loadRecent();
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

  Widget _reportPicker(PickedPpmReport? report, void Function(PickedPpmReport?) onChanged) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(tr(widget.isEnglish, 'صورة تقرير الصيانة (اختياري)'),
          style: const TextStyle(color: Colors.white70, fontSize: 13)),
      subtitle: Text(report?.name ?? tr(widget.isEnglish, 'لم يُرفق تقرير'),
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.upload_file, color: _indigo, size: 18),
            onPressed: () async {
              final picked = await pickPpmReport();
              if (picked != null) onChanged(picked);
            },
          ),
          if (report != null)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54, size: 18),
              onPressed: () => onChanged(null),
            ),
        ],
      ),
    );
  }

  Future<void> _logMaintenance(Map<String, dynamic> device) async {
    bool isEmergency = false;
    final notesCtrl = TextEditingController();
    PickedPpmReport? report;
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
              _reportPicker(report, (r) => setSt(() => report = r)),
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
      final logId = '${now.millisecondsSinceEpoch}_${device['id']}';
      final reportKey = report == null ? null : await uploadPpmReport(logId: logId, report: report!);
      await portalClient.from('ppm_maintenance_log').insert({
        'id': logId,
        'report_key': reportKey,
        'report_keys': reportKey == null ? <String>[] : [reportKey],
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

  // Read-only on the portal, for both levels — matches what the RLS
  // policies actually allow a regular technician (SELECT only, no
  // UPDATE/DELETE on ppm_maintenance_log); editing a logged visit stays a
  // desktop-admin-only feature (see hrmanager's ppm_screen.dart).
  // Editable by both levels (requested 2026-10-01) — regular technicians
  // got UPDATE on ppm_maintenance_log in migration 20261001120000
  // alongside the SELECT+INSERT they already had; managers already had it
  // via their existing ALL policy, this was previously just not exposed in
  // the portal UI.
  Future<void> _editLogEntry(Map<String, dynamic> entry, Future<void> Function() onUpdated) async {
    DateTime performedAt = DateTime.tryParse(entry['performed_at'] as String? ?? '') ?? DateTime.now();
    bool isEmergency = entry['type'] == 'طارئة';
    final notesCtrl = TextEditingController(text: entry['notes'] as String? ?? '');
    final technicianCtrl = TextEditingController(text: entry['technician'] as String? ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: _card,
          title: Text(tr(widget.isEnglish, 'تعديل بيانات الصيانة'), style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr(widget.isEnglish, 'تاريخ الصيانة'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                trailing: Text(_fmt(performedAt.toIso8601String()), style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx, initialDate: performedAt, firstDate: DateTime(2020), lastDate: DateTime(2040),
                  );
                  if (picked != null) {
                    setSt(() => performedAt = DateTime(picked.year, picked.month, picked.day, performedAt.hour, performedAt.minute));
                  }
                },
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                value: isEmergency,
                onChanged: (v) => setSt(() => isEmergency = v ?? false),
                title: Text(tr(widget.isEnglish, 'صيانة طارئة'), style: const TextStyle(color: Colors.white, fontSize: 13)),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: _indigo,
              ),
              const SizedBox(height: 6),
              TextField(controller: technicianCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'الفني/المسؤول'))),
              const SizedBox(height: 12),
              TextField(controller: notesCtrl, style: const TextStyle(color: Colors.white), decoration: _dec(tr(widget.isEnglish, 'ملاحظات'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(widget.isEnglish, 'إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(widget.isEnglish, 'حفظ'))),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await portalClient.from('ppm_maintenance_log').update({
        'performed_at': performedAt.toIso8601String(),
        'type': isEmergency ? 'طارئة' : 'دورية',
        'technician': technicianCtrl.text.trim().isEmpty ? null : technicianCtrl.text.trim(),
        'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      }).eq('id', entry['id']);
      await onUpdated();
    } catch (_) {}
  }

  List<String> _reportKeysOfVisit(Map<String, dynamic> h) {
    final keys = <String>{
      ...((h['report_keys'] as List?) ?? const []).map((k) => k.toString()),
      if (((h['report_key'] as String?) ?? '').isNotEmpty) h['report_key'] as String,
    };
    return keys.where((k) => k.isNotEmpty).toList();
  }

  Widget _visitReportImage(String key) {
    return FutureBuilder<String>(
      future: ppmReportViewUrl(key),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: _indigo)));
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(snap.data!, fit: BoxFit.contain),
        );
      },
    );
  }

  List<Widget> _deviceInfoWidgets(Map<String, dynamic> device) {
    final rows = <(String, String?)>[
      (tr(widget.isEnglish, 'الشركة المصنعة'), device['manufacturer'] as String?),
      (tr(widget.isEnglish, 'الموديل/الإصدار'), device['model_version'] as String?),
      (tr(widget.isEnglish, 'الرقم التسلسلي'), device['serial_number'] as String?),
      (tr(widget.isEnglish, 'القسم'), device['location'] as String?),
      (tr(widget.isEnglish, 'دورية الصيانة'), device['interval_months'] == null ? null : '${device['interval_months']} ${tr(widget.isEnglish, 'أشهر')}'),
      (tr(widget.isEnglish, 'آخر صيانة'), _fmtDateTime(device['last_maintenance_date'] as String?)),
      (tr(widget.isEnglish, 'آخر فني'), device['last_maintenance_by'] as String?),
      (tr(widget.isEnglish, 'الصيانة القادمة'), _fmt(device['next_due_date'] as String?)),
      (tr(widget.isEnglish, 'أضيف بواسطة'), device['added_by'] as String?),
    ];
    return [
      for (final r in rows)
        if ((r.$2 ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${r.$1}: ${r.$2}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ),
      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: Colors.white12)),
    ];
  }

  Future<void> _showHistory(Map<String, dynamic> device) async {
    List<Map<String, dynamic>> history = [];
    try {
      final data = await portalClient
          .from('ppm_maintenance_log')
          .select()
          .eq('device_id', device['id'])
          .order('performed_at', ascending: false);
      history = List<Map<String, dynamic>>.from(data as List);
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setOuter) => AlertDialog(
        backgroundColor: _card,
        title: Text('${tr(widget.isEnglish, "سجل الصيانة")} — ${device['name']}',
            style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 360,
          child: history.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(tr(widget.isEnglish, 'لا يوجد سجل صيانة بعد'), style: const TextStyle(color: Colors.white54)),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      ..._deviceInfoWidgets(device),
                      ...history.map((h) {
                      final next = DateTime.tryParse(h['next_due_date'] as String? ?? '');
                      final isEmergency = h['type'] == 'طارئة';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(children: [
                                    Text(_fmtDateTime(h['performed_at'] as String?),
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
                                    if (isEmergency) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(color: _amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                                        child: Text(tr(widget.isEnglish, 'طارئة'), style: const TextStyle(color: _amber, fontSize: 9.5, fontWeight: FontWeight.w700)),
                                      ),
                                    ],
                                  ]),
                                ),
                                if ((h['technician'] as String?)?.isNotEmpty ?? false)
                                  Text(h['technician'] as String, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                const SizedBox(width: 6),
                                if (((h['report_key'] as String?) ?? '').isNotEmpty) ...[
                                  InkWell(
                                    onTap: () async {
                                      final url = await ppmReportViewUrl(h['report_key'] as String);
                                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                    },
                                    child: Tooltip(
                                      message: tr(widget.isEnglish, 'عرض تقرير الصيانة'),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.attach_file, size: 14, color: _indigo),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                InkWell(
                                  onTap: () => _editLogEntry(h, () async {
                                    final fresh = await portalClient
                                        .from('ppm_maintenance_log')
                                        .select()
                                        .eq('device_id', device['id'])
                                        .order('performed_at', ascending: false);
                                    history
                                      ..clear()
                                      ..addAll(List<Map<String, dynamic>>.from(fresh as List));
                                    setOuter(() {});
                                  }),
                                  child: const Icon(Icons.edit, size: 14, color: Colors.white54),
                                ),
                              ],
                            ),
                            if (next != null && !isEmergency)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('${tr(widget.isEnglish, "الصيانة القادمة")}: ${_fmt(h['next_due_date'] as String?)}',
                                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              ),
                            if ((h['notes'] as String?)?.isNotEmpty ?? false)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(h['notes'] as String, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ),
                            for (final key in _reportKeysOfVisit(h))
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _visitReportImage(key),
                              ),
                            for (final key in _reportKeysOfVisit(h))
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton.icon(
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: ctx,
                                      builder: (c) => AlertDialog(
                                        backgroundColor: _card,
                                        title: Text(tr(widget.isEnglish, 'حذف الصورة'), style: const TextStyle(color: Colors.white)),
                                        content: Text(tr(widget.isEnglish, 'هل تريد حذف صورة التقرير نهائياً؟'),
                                            style: const TextStyle(color: Colors.white70)),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(widget.isEnglish, 'إلغاء'))),
                                          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr(widget.isEnglish, 'حذف'), style: const TextStyle(color: _red))),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;
                                    await removePpmReportImage(logId: h['id'] as String, key: key);
                                    if (!ctx.mounted) return;
                                    Navigator.pop(ctx);
                                    await _showHistory(device);
                                  },
                                  icon: const Icon(Icons.delete_outline, size: 16, color: _red),
                                  label: Text(tr(widget.isEnglish, 'حذف الصورة'), style: const TextStyle(color: _red)),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(widget.isEnglish, 'إغلاق'))),
        ],
        ),
      ),
    );
  }

  // Same idea as the desktop's "طباعة تقرير الصيانة" (generateAndPrintPpmReport
  // in pdf_helper.dart) — a combined view of every logged visit across every
  // device, not just one device's own history. No PDF export here (printing
  // isn't available the same way in a browser) — just the same "see
  // everything at once" view, with the device name attached to each row
  // since ppm_maintenance_log itself has no device name of its own.
  Future<void> _showAllLogs() async {
    List<Map<String, dynamic>> logs = [];
    Map<String, Map<String, dynamic>> devicesById = {};
    try {
      final devicesData = await portalClient.from('ppm_devices').select('id, name, device_number, model_version');
      devicesById = {
        for (final d in List<Map<String, dynamic>>.from(devicesData as List)) d['id'] as String: d,
      };
      final logsData = await portalClient.from('ppm_maintenance_log').select().order('performed_at', ascending: false);
      logs = List<Map<String, dynamic>>.from(logsData as List);
    } catch (_) {}
    if (!mounted) return;
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final h in logs) {
      grouped.putIfAbsent(h['device_id'] as String, () => []).add(h);
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr(widget.isEnglish, 'كل سجلات الصيانة'), style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 420,
          child: logs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(tr(widget.isEnglish, 'لا يوجد سجل صيانة بعد'), style: const TextStyle(color: Colors.white54)),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: grouped.entries.map((e) {
                      final device = devicesById[e.key];
                      final visits = e.value;
                      final last = visits.first;
                      final lastTech = (last['technician'] as String?) ?? '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: device == null ? null : () => _showHistory(device),
                                    child: Text(
                                      device?['name'] as String? ?? tr(widget.isEnglish, 'جهاز محذوف'),
                                      style: TextStyle(
                                        color: device == null ? Colors.white : _indigo,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        decoration: device == null ? null : TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: _indigo.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                                  child: Text(
                                    '${tr(widget.isEnglish, 'عدد الصيانات')}: ${visits.length}',
                                    style: const TextStyle(color: _indigo, fontSize: 10.5, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${tr(widget.isEnglish, 'آخر صيانة')}: ${_fmtDateTime(last['performed_at'] as String?)}'
                              '${lastTech.isEmpty ? '' : '   •   $lastTech'}',
                              style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
        ),
        actions: [
          if (logs.isNotEmpty) ...[
            TextButton(
              onPressed: () => exportPpmReportPdf(
                title: 'تقرير الصيانة', logs: logs, devicesById: devicesById, attachments: PpmPdfAttachments.all),
              child: Text(tr(widget.isEnglish, 'PDF الكل'), style: const TextStyle(color: _indigo)),
            ),
            TextButton(
              onPressed: () => exportPpmReportPdf(
                title: 'تقرير الصيانة بمرفقات', logs: logs, devicesById: devicesById, attachments: PpmPdfAttachments.withAttachments),
              child: Text(tr(widget.isEnglish, 'PDF بمرفقات'), style: const TextStyle(color: _indigo)),
            ),
            TextButton(
              onPressed: () => exportPpmReportPdf(
                title: 'تقرير الصيانة بدون مرفقات', logs: logs, devicesById: devicesById, attachments: PpmPdfAttachments.withoutAttachments),
              child: Text(tr(widget.isEnglish, 'PDF بدون مرفقات'), style: const TextStyle(color: _indigo)),
            ),
          ],
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(widget.isEnglish, 'إغلاق'))),
        ],
      ),
    );
  }

  Future<void> _loadRecent() async {
    final since = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    try {
      final data = await portalClient
          .from('ppm_maintenance_log')
          .select()
          .gte('performed_at', since)
          .order('performed_at', ascending: false);
      if (mounted) setState(() => _recentLogs = List<Map<String, dynamic>>.from(data as List));
    } catch (_) {}
  }

  Widget _buildRecentList() {
    if (_recentLogs.isEmpty) {
      return Center(
        child: Text(tr(widget.isEnglish, 'لا توجد صيانات خلال آخر شهر'), style: const TextStyle(color: Colors.white54)),
      );
    }
    final byId = {for (final d in _devices) d['id'] as String: d};
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _recentLogs.length,
      itemBuilder: (context, i) {
        final h = _recentLogs[i];
        final device = byId[h['device_id'] as String];
        final isEmergency = h['type'] == 'طارئة';
        final tech = (h['technician'] as String?) ?? '';
        return _cardTile(
          child: InkWell(
            onTap: () => device != null ? _showHistory(device) : _showVisitDetails(h, device),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device?['name'] as String? ?? tr(widget.isEnglish, 'جهاز محذوف'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_fmtDateTime(h['performed_at'] as String?)}${tech.isEmpty ? '' : '   •   $tech'}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (isEmergency)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: _amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                    child: Text(tr(widget.isEnglish, 'طارئة'), style: const TextStyle(color: _amber, fontSize: 9.5, fontWeight: FontWeight.w700)),
                  ),
                const Icon(Icons.chevron_left, color: Colors.white38),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showVisitDetails(Map<String, dynamic> h, Map<String, dynamic>? device) async {
    final keys = <String>{
      ...((h['report_keys'] as List?) ?? const []).map((k) => k.toString()),
      if (((h['report_key'] as String?) ?? '').isNotEmpty) h['report_key'] as String,
    }.toList();
    final detailRows = <(String, String?)>[
      (tr(widget.isEnglish, 'الشركة المصنعة'), device?['manufacturer'] as String?),
      (tr(widget.isEnglish, 'الموديل/الإصدار'), device?['model_version'] as String?),
      (tr(widget.isEnglish, 'الرقم التسلسلي'), device?['serial_number'] as String?),
      (tr(widget.isEnglish, 'القسم'), device?['location'] as String?),
      (tr(widget.isEnglish, 'تاريخ الصيانة'), _fmtDateTime(h['performed_at'] as String?)),
      (tr(widget.isEnglish, 'النوع'), h['type'] as String?),
      (tr(widget.isEnglish, 'الفني/المسؤول'), h['technician'] as String?),
      (tr(widget.isEnglish, 'ملاحظات'), h['notes'] as String?),
    ];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(device?['name'] as String? ?? tr(widget.isEnglish, 'جهاز محذوف'),
            style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in detailRows)
                  if ((r.$2 ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('${r.$1}: ${r.$2}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                if (device != null) ...[
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _logMaintenance(device);
                    },
                    child: Text(tr(widget.isEnglish, 'تسجيل صيانة وإرفاق صورة')),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await pickPpmReport();
                    if (picked == null) return;
                    final logId = h['id'] as String;
                    final key = await uploadPpmReport(logId: logId, report: picked, index: keys.length + 1);
                    final newKeys = [...keys, key];
                    await portalClient
                        .from('ppm_maintenance_log')
                        .update({'report_keys': newKeys, 'report_key': newKeys.first})
                        .eq('id', logId);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    await _showVisitDetails({...h, 'report_keys': newKeys, 'report_key': newKeys.first}, device);
                  },
                  icon: const Icon(Icons.attach_file, size: 16, color: _indigo),
                  label: Text(tr(widget.isEnglish, 'إرفاق صورة تقرير'), style: const TextStyle(color: _indigo)),
                ),
                for (final k in keys) ...[
                  const SizedBox(height: 10),
                  FutureBuilder<String>(
                    future: ppmReportViewUrl(k),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: _indigo)));
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(snap.data!, fit: BoxFit.contain),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(widget.isEnglish, 'إغلاق'))),
        ],
      ),
    );
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _showLogEmergencyDialog,
                  icon: const Icon(Icons.warning_amber_rounded, size: 16, color: _red),
                  label: Text(tr(widget.isEnglish, 'تسجيل صيانة طارئة'), style: const TextStyle(color: _red)),
                ),
                FilterChip(
                  label: Text(tr(widget.isEnglish, 'آخر الصيانات (30 يوماً)'), style: const TextStyle(fontSize: 12)),
                  selected: _recentOnly,
                  onSelected: (v) {
                    setState(() => _recentOnly = v);
                    if (v) _loadRecent();
                  },
                ),
                TextButton.icon(
                  onPressed: _showAllLogs,
                  icon: const Icon(Icons.fact_check_outlined, size: 16, color: _indigo),
                  label: Text(tr(widget.isEnglish, 'كل السجلات'), style: const TextStyle(color: _indigo)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _recentOnly
                ? _buildRecentList()
                : _devices.isEmpty
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
                        TextButton(onPressed: () => _showHistory(d), child: Text(tr(widget.isEnglish, 'السجل'))),
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
          ),
        ],
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
