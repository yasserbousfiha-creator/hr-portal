import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'portal_client.dart';
import 'portal_i18n.dart';

class AdminScreen extends StatefulWidget {
  final bool isEnglish;
  final int initialTabIndex;
  const AdminScreen({super.key, this.isEnglish = false, this.initialTabIndex = 0});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  static const _bg = Color(0xFF061A22);
  static const _indigo = Color(0xFF06B6D4);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 6,
      initialIndex: widget.initialTabIndex.clamp(0, 5),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF061A22),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_indigo, Color(0xFF0EA5E9)]),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.admin_panel_settings_rounded,
                  color: Colors.white, size: 17),
            ),
            const SizedBox(width: 10),
            Text(tr(widget.isEnglish, 'لوحة الإدارة'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: _indigo,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0x66FFFFFF),
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: [
            Tab(icon: const Icon(Icons.beach_access_outlined, size: 18),
                text: tr(widget.isEnglish, 'الإجازات')),
            Tab(icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                text: tr(widget.isEnglish, 'السلف')),
            Tab(icon: const Icon(Icons.people_outline, size: 18),
                text: tr(widget.isEnglish, 'الموظفون')),
            Tab(icon: const Icon(Icons.access_time_outlined, size: 18),
                text: tr(widget.isEnglish, 'الدوامات')),
            Tab(icon: const Icon(Icons.door_front_door_outlined, size: 18),
                text: tr(widget.isEnglish, 'العيادات')),
            Tab(icon: const Icon(Icons.task_alt_outlined, size: 18),
                text: tr(widget.isEnglish, 'المهام والعهد')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _LeavesTab(isEnglish: widget.isEnglish),
          _AdvancesTab(isEnglish: widget.isEnglish),
          _EmployeesTab(isEnglish: widget.isEnglish),
          _ShiftsTab(isEnglish: widget.isEnglish),
          _ClinicsTab(isEnglish: widget.isEnglish),
          _TasksCustodyTab(isEnglish: widget.isEnglish),
        ],
      ),
    );
  }
}

// ── Leaves Tab ─────────────────────────────────────────────────
class _LeavesTab extends StatefulWidget {
  final bool isEnglish;
  const _LeavesTab({this.isEnglish = false});
  @override
  State<_LeavesTab> createState() => _LeavesTabState();
}

class _LeavesTabState extends State<_LeavesTab> {
  List<Map<String, dynamic>> _requests = [];
  Map<String, Map<String, dynamic>> _empMap = {};
  bool _loading = true;
  String _filter = 'قيد المراجعة';
  String? _error;
  late final RealtimeChannel _channel;

  static const _indigo = Color(0xFF06B6D4);
  static const _green = Color(0xFF34D399);
  static const _amber = Color(0xFFF59E0B);
  static const _red = Color(0xFFF87171);
  static const _surface = Color(0xFF0D2731);

  @override
  void initState() {
    super.initState();
    _load();
    _channel = portalClient
        .channel('admin-leaves-tab')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'leave_requests',
          callback: (_) { if (mounted) _load(); },
        )
        .subscribe();
  }

  @override
  void dispose() {
    portalClient.removeChannel(_channel);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        portalClient.from('leave_requests').select().order('submitted_at', ascending: false),
        portalClient.from('employee_profiles').select('id, name, department'),
      ]);
      final requests = List<Map<String, dynamic>>.from(results[0] as List);
      final emps = List<Map<String, dynamic>>.from(results[1] as List);
      final empMap = <String, Map<String, dynamic>>{
        for (final e in emps) e['id'].toString(): e,
      };
      if (mounted) {
        setState(() {
          _requests = requests;
          _empMap = empMap;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await portalClient
          .from('leave_requests')
          .update({'status': status})
          .eq('id', id);
      await _load();
      if (mounted) {
        _snack(status == 'موافق عليها' ? tr(widget.isEnglish, 'تمت الموافقة') : tr(widget.isEnglish, 'تم الرفض'),
            status == 'موافق عليها' ? _green : _red);
      }
    } catch (e) {
      if (mounted) _snack(widget.isEnglish ? 'Error: $e' : 'خطأ: $e', _red);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Color _statusColor(String status) {
    if (status == 'موافق عليها') return _green;
    if (status == 'مرفوضة') return _red;
    return _amber;
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'الكل') return _requests;
    return _requests.where((r) => r['status'] == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _indigo));
    }

    final isMobile = MediaQuery.of(context).size.width < 700;

    final filterChips = [
      for (final f in ['قيد المراجعة', 'موافق عليها', 'مرفوضة', 'الكل'])
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: GestureDetector(
            onTap: () => setState(() => _filter = f),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _filter == f
                    ? _indigo
                    : const Color(0x0AFFFFFF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _filter == f
                      ? _indigo
                      : const Color(0x1AFFFFFF),
                ),
              ),
              child: Text(tr(widget.isEnglish, f),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: _filter == f
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: _filter == f
                          ? Colors.white
                          : const Color(0x99FFFFFF))),
            ),
          ),
        ),
    ];
    final refreshButton = IconButton(
      icon: const Icon(Icons.refresh, color: Color(0x99FFFFFF), size: 18),
      onPressed: _load,
      tooltip: tr(widget.isEnglish, 'تحديث'),
    );

    return Column(
      children: [
        // Filter chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: isMobile
              ? Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [...filterChips, refreshButton],
                )
              : Row(
                  children: [
                    ...filterChips,
                    const Spacer(),
                    refreshButton,
                  ],
                ),
        ),

        // List
        Expanded(
          child: _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(widget.isEnglish ? 'Error: $_error' : 'خطأ: $_error',
                      style: const TextStyle(color: Color(0xFFF87171), fontSize: 12)),
                ))
              : _filtered.isEmpty
              ? Center(
                  child: Text(tr(widget.isEnglish, 'لا توجد طلبات'),
                      style: const TextStyle(color: Color(0x66FFFFFF))))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final req = _filtered[i];
                    final empId = req['employee_id']?.toString() ?? '';
                    final empData = _empMap[empId];
                    final empName = empData?['name'] as String? ?? empId.substring(0, empId.length.clamp(0, 8));
                    final dept = empData?['department'] as String? ?? '';
                    final type = req['type'] as String? ?? '';
                    final status = req['status'] as String? ?? 'قيد الانتظار';
                    final start = req['start_date'] as String? ?? '';
                    final end = req['end_date'] as String? ?? '';
                    final reason = req['reason'] as String? ?? '';
                    final submittedAt = req['submitted_at'] as String?;

                    String fmtDate(String d) {
                      try {
                        return intl.DateFormat('dd/MM/yyyy')
                            .format(DateTime.parse(d));
                      } catch (_) {
                        return d;
                      }
                    }

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _statusColor(status).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(empName,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14)),
                                    if (dept.isNotEmpty)
                                      Text(tr(widget.isEnglish, dept),
                                          style: const TextStyle(
                                              color: Color(0x66FFFFFF),
                                              fontSize: 11)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(status)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: _statusColor(status)
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Text(tr(widget.isEnglish, status),
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _statusColor(status))),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              _infoChip(Icons.category_outlined, tr(widget.isEnglish, type)),
                              _infoChip(Icons.calendar_today_outlined,
                                  '${fmtDate(start)} → ${fmtDate(end)}'),
                              if (submittedAt != null)
                                _infoChip(Icons.schedule_outlined,
                                    fmtDate(submittedAt)),
                            ],
                          ),
                          if (reason.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(reason,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0x99FFFFFF),
                                    height: 1.5)),
                          ],
                          if (status == 'قيد المراجعة') ...[
                            const SizedBox(height: 12),
                            isMobile
                                ? Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _actionBtn(
                                        label: tr(widget.isEnglish, 'رفض'),
                                        color: _red,
                                        icon: Icons.close_rounded,
                                        onTap: () => _updateStatus(
                                            req['id'].toString(), 'مرفوضة'),
                                      ),
                                      _actionBtn(
                                        label: tr(widget.isEnglish, 'موافقة'),
                                        color: _green,
                                        icon: Icons.check_rounded,
                                        onTap: () => _updateStatus(
                                            req['id'].toString(),
                                            'موافق عليها'),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      _actionBtn(
                                        label: tr(widget.isEnglish, 'رفض'),
                                        color: _red,
                                        icon: Icons.close_rounded,
                                        onTap: () => _updateStatus(
                                            req['id'].toString(), 'مرفوضة'),
                                      ),
                                      const SizedBox(width: 8),
                                      _actionBtn(
                                        label: tr(widget.isEnglish, 'موافقة'),
                                        color: _green,
                                        icon: Icons.check_rounded,
                                        onTap: () => _updateStatus(
                                            req['id'].toString(),
                                            'موافق عليها'),
                                      ),
                                    ],
                                  ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: const Color(0x66FFFFFF)),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(
                fontSize: 12, color: Color(0x99FFFFFF))),
      ],
    );
  }

  Widget _actionBtn({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Advances Tab ───────────────────────────────────────────────
class _AdvancesTab extends StatefulWidget {
  final bool isEnglish;
  const _AdvancesTab({this.isEnglish = false});
  @override
  State<_AdvancesTab> createState() => _AdvancesTabState();
}

class _AdvancesTabState extends State<_AdvancesTab> {
  List<Map<String, dynamic>> _requests = [];
  Map<String, Map<String, dynamic>> _empMap = {};
  bool _loading = true;
  String _filter = 'قيد المراجعة';
  String? _error;
  late final RealtimeChannel _channel;

  static const _indigo = Color(0xFF06B6D4);
  static const _green = Color(0xFF34D399);
  static const _amber = Color(0xFFF59E0B);
  static const _red = Color(0xFFF87171);
  static const _surface = Color(0xFF0D2731);

  @override
  void initState() {
    super.initState();
    _load();
    _channel = portalClient
        .channel('admin-advances-tab')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'advance_requests',
          callback: (_) { if (mounted) _load(); },
        )
        .subscribe();
  }

  @override
  void dispose() {
    portalClient.removeChannel(_channel);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        portalClient.from('advance_requests').select().order('submitted_at', ascending: false),
        portalClient.from('employee_profiles').select('id, name, department'),
      ]);
      final requests = List<Map<String, dynamic>>.from(results[0] as List);
      final emps = List<Map<String, dynamic>>.from(results[1] as List);
      final empMap = <String, Map<String, dynamic>>{
        for (final e in emps) e['id'].toString(): e,
      };
      if (mounted) {
        setState(() {
          _requests = requests;
          _empMap = empMap;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await portalClient
          .from('advance_requests')
          .update({'status': status})
          .eq('id', id);
      await _load();
      if (mounted) {
        _snack(status == 'موافق عليها' ? tr(widget.isEnglish, 'تمت الموافقة') : tr(widget.isEnglish, 'تم الرفض'),
            status == 'موافق عليها' ? _green : _red);
      }
    } catch (e) {
      if (mounted) _snack(widget.isEnglish ? 'Error: $e' : 'خطأ: $e', _red);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Color _statusColor(String status) {
    if (status == 'موافق عليها') return _green;
    if (status == 'مرفوضة') return _red;
    return _amber;
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'الكل') return _requests;
    return _requests.where((r) => r['status'] == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _indigo));
    }

    final isMobile = MediaQuery.of(context).size.width < 700;

    final filterChips = [
      for (final f in ['قيد المراجعة', 'موافق عليها', 'مرفوضة', 'الكل'])
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: GestureDetector(
            onTap: () => setState(() => _filter = f),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _filter == f
                    ? _indigo
                    : const Color(0x0AFFFFFF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _filter == f
                      ? _indigo
                      : const Color(0x1AFFFFFF),
                ),
              ),
              child: Text(tr(widget.isEnglish, f),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: _filter == f
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: _filter == f
                          ? Colors.white
                          : const Color(0x99FFFFFF))),
            ),
          ),
        ),
    ];
    final refreshButton = IconButton(
      icon: const Icon(Icons.refresh, color: Color(0x99FFFFFF), size: 18),
      onPressed: _load,
      tooltip: tr(widget.isEnglish, 'تحديث'),
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: isMobile
              ? Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [...filterChips, refreshButton],
                )
              : Row(
                  children: [
                    ...filterChips,
                    const Spacer(),
                    refreshButton,
                  ],
                ),
        ),
        Expanded(
          child: _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(widget.isEnglish ? 'Error: $_error' : 'خطأ: $_error',
                      style: const TextStyle(color: Color(0xFFF87171), fontSize: 12)),
                ))
              : _filtered.isEmpty
              ? Center(
                  child: Text(tr(widget.isEnglish, 'لا توجد طلبات'),
                      style: const TextStyle(color: Color(0x66FFFFFF))))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final req = _filtered[i];
                    final empId = req['employee_id']?.toString() ?? '';
                    final empData = _empMap[empId];
                    final empName = empData?['name'] as String? ??
                        (req['employee_name'] as String? ??
                            empId.substring(0, empId.length.clamp(0, 8)));
                    final dept = empData?['department'] as String? ?? '';
                    final status = req['status'] as String? ?? 'قيد الانتظار';
                    final amount = (req['amount'] as num?)?.toDouble() ?? 0;
                    final remaining = (req['remaining_amount'] as num?)?.toDouble() ?? amount;
                    final monthly = (req['monthly_deduction'] as num?)?.toDouble() ?? 0;
                    final reason = req['reason'] as String? ?? '';
                    final submittedAt = req['submitted_at'] as String?;

                    String fmtDate(String d) {
                      try {
                        return intl.DateFormat('dd/MM/yyyy')
                            .format(DateTime.parse(d));
                      } catch (_) {
                        return d;
                      }
                    }

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _statusColor(status).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(empName,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14)),
                                    if (dept.isNotEmpty)
                                      Text(tr(widget.isEnglish, dept),
                                          style: const TextStyle(
                                              color: Color(0x66FFFFFF),
                                              fontSize: 11)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(status)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: _statusColor(status)
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Text(tr(widget.isEnglish, status),
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _statusColor(status))),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              _infoChip(Icons.payments_outlined,
                                  '${amount.toStringAsFixed(0)} ${tr(widget.isEnglish, 'ريال')}'),
                              _infoChip(Icons.account_balance_wallet_outlined,
                                  '${tr(widget.isEnglish, 'المتبقي')}: ${remaining.toStringAsFixed(0)}'),
                              _infoChip(Icons.calendar_month_outlined,
                                  '${tr(widget.isEnglish, 'شهري')}: ${monthly.toStringAsFixed(0)}'),
                              if (submittedAt != null)
                                _infoChip(Icons.schedule_outlined,
                                    fmtDate(submittedAt)),
                            ],
                          ),
                          if (reason.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(reason,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0x99FFFFFF),
                                    height: 1.5)),
                          ],
                          if (status == 'قيد المراجعة') ...[
                            const SizedBox(height: 12),
                            isMobile
                                ? Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _actionBtn(
                                        label: tr(widget.isEnglish, 'رفض'),
                                        color: _red,
                                        icon: Icons.close_rounded,
                                        onTap: () => _updateStatus(
                                            req['id'].toString(), 'مرفوضة'),
                                      ),
                                      _actionBtn(
                                        label: tr(widget.isEnglish, 'موافقة'),
                                        color: _green,
                                        icon: Icons.check_rounded,
                                        onTap: () => _updateStatus(
                                            req['id'].toString(),
                                            'موافق عليها'),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      _actionBtn(
                                        label: tr(widget.isEnglish, 'رفض'),
                                        color: _red,
                                        icon: Icons.close_rounded,
                                        onTap: () => _updateStatus(
                                            req['id'].toString(), 'مرفوضة'),
                                      ),
                                      const SizedBox(width: 8),
                                      _actionBtn(
                                        label: tr(widget.isEnglish, 'موافقة'),
                                        color: _green,
                                        icon: Icons.check_rounded,
                                        onTap: () => _updateStatus(
                                            req['id'].toString(),
                                            'موافق عليها'),
                                      ),
                                    ],
                                  ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: const Color(0x66FFFFFF)),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(
                fontSize: 12, color: Color(0x99FFFFFF))),
      ],
    );
  }

  Widget _actionBtn({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Employees Tab ───────────────────────────────────────────────
class _EmployeesTab extends StatefulWidget {
  final bool isEnglish;
  const _EmployeesTab({this.isEnglish = false});
  @override
  State<_EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<_EmployeesTab> {
  List<Map<String, dynamic>> _employees = [];
  bool _loading = true;
  String _search = '';
  bool _showArchive = false;

  static const _indigo = Color(0xFF06B6D4);
  static const _surface = Color(0xFF0D2731);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await portalClient
          .from('employee_profiles')
          .select()
          .order('name');
      if (mounted) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(data)
              .where((e) => e['is_admin'] != true)
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.trim().isEmpty) return _employees;
    final q = _search.trim().toLowerCase();
    return _employees.where((e) {
      final name = (e['name'] as String? ?? '').toLowerCase();
      final dept = (e['department'] as String? ?? '').toLowerCase();
      return name.contains(q) || dept.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _indigo));
    }

    final isMobile = MediaQuery.of(context).size.width < 700;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: tr(widget.isEnglish, 'بحث باسم الموظف أو القسم...'),
                    hintStyle:
                        const TextStyle(color: Color(0x55FFFFFF), fontSize: 13),
                    prefixIcon: const Icon(Icons.search,
                        color: Color(0x55FFFFFF), size: 18),
                    filled: true,
                    fillColor: const Color(0x0AFFFFFF),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0x1AFFFFFF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0x1AFFFFFF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: _indigo, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh,
                    color: Color(0x99FFFFFF), size: 18),
                onPressed: _load,
                tooltip: tr(widget.isEnglish, 'تحديث'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            widget.isEnglish ? '${_filtered.length} employee(s)' : '${_filtered.length} موظف',
            style: const TextStyle(
                fontSize: 12, color: Color(0x55FFFFFF)),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Text(tr(widget.isEnglish, 'لا توجد نتائج'),
                      style: const TextStyle(color: Color(0x66FFFFFF))))
              : Builder(builder: (context) {
                  final active = _filtered
                      .where((e) => (e['status'] as String? ?? '') == 'نشط')
                      .toList();
                  final inactive = _filtered
                      .where((e) => (e['status'] as String? ?? '') != 'نشط')
                      .toList();
                  final items = <Map<String, dynamic>?>[
                    ...active,
                    if (inactive.isNotEmpty) null, // archive toggle marker
                    if (_showArchive) ...inactive,
                  ];
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final emp = items[i];
                      if (emp == null) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () =>
                              setState(() => _showArchive = !_showArchive),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0x0AFFFFFF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: const Color(0x14FFFFFF)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                    _showArchive
                                        ? Icons.expand_less
                                        : Icons.archive_outlined,
                                    size: 16,
                                    color: const Color(0x99FFFFFF)),
                                const SizedBox(width: 8),
                                Text(
                                    '${tr(widget.isEnglish, 'الأرشيف')} (${inactive.length})',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0x99FFFFFF))),
                              ],
                            ),
                          ),
                        );
                      }
                      final name = emp['name'] as String? ?? '—';
                    final nameEn = emp['name_en'] as String?;
                    final displayName = (widget.isEnglish && nameEn != null && nameEn.isNotEmpty) ? nameEn : name;
                    final dept = emp['department'] as String? ?? '—';
                    final shift = emp['shift'] as String? ?? '—';
                    final status = emp['status'] as String? ?? '—';
                    final phone = emp['phone'] as String? ?? '';
                    final clinicNum = emp['clinic_number'];
                    final nationality = emp['nationality'] as String? ?? '';
                    final employeeNumber = emp['employee_number'] as String? ?? '';
                    final contractEndRaw = emp['contract_end_date'] as String?;
                    String contractEndFmt = '';
                    if (contractEndRaw != null && contractEndRaw.isNotEmpty) {
                      try {
                        contractEndFmt = intl.DateFormat('dd/MM/yyyy').format(DateTime.parse(contractEndRaw));
                      } catch (_) {}
                    }

                    final avatar = Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _indigo.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Center(
                        child: Text(
                          displayName.isNotEmpty ? displayName[0] : '?',
                          style: const TextStyle(
                              color: _indigo,
                              fontWeight: FontWeight.w700,
                              fontSize: 17),
                        ),
                      ),
                    );
                    final nameColumn = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        const SizedBox(height: 2),
                        Text('${tr(widget.isEnglish, dept)}  •  ${tr(widget.isEnglish, shift)}',
                            style: const TextStyle(
                                color: Color(0x99FFFFFF),
                                fontSize: 11)),
                        if (phone.isNotEmpty)
                          Text(phone,
                              style: const TextStyle(
                                  color: Color(0x66FFFFFF),
                                  fontSize: 11)),
                        if (nationality.isNotEmpty || employeeNumber.isNotEmpty || contractEndFmt.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 2,
                            children: [
                              if (employeeNumber.isNotEmpty)
                                Text('#$employeeNumber',
                                    style: const TextStyle(color: Color(0x55FFFFFF), fontSize: 10)),
                              if (nationality.isNotEmpty)
                                Text(tr(widget.isEnglish, nationality),
                                    style: const TextStyle(color: Color(0x55FFFFFF), fontSize: 10)),
                              if (contractEndFmt.isNotEmpty)
                                Text('${tr(widget.isEnglish, 'نهاية العقد')}: $contractEndFmt',
                                    style: const TextStyle(color: Color(0x55FFFFFF), fontSize: 10)),
                            ],
                          ),
                        ],
                      ],
                    );
                    final statusBadge = Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: status == 'نشط'
                            ? const Color(0xFF34D399)
                                .withValues(alpha: 0.12)
                            : Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(tr(widget.isEnglish, status),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: status == 'نشط'
                                  ? const Color(0xFF34D399)
                                  : Colors.redAccent)),
                    );
                    final clinicText = clinicNum != null
                        ? Text('${widget.isEnglish ? 'Clinic' : 'عيادة'} $clinicNum',
                            style: const TextStyle(
                                fontSize: 10, color: Color(0x66FFFFFF)))
                        : null;

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0x14FFFFFF)),
                      ),
                      child: isMobile
                          ? Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    avatar,
                                    const SizedBox(width: 12),
                                    Expanded(child: nameColumn),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  children: [
                                    statusBadge,
                                    ?clinicText,
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                avatar,
                                const SizedBox(width: 12),
                                Expanded(child: nameColumn),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    statusBadge,
                                    if (clinicText != null) ...[
                                      const SizedBox(height: 4),
                                      clinicText,
                                    ],
                                  ],
                                ),
                              ],
                            ),
                      );
                    },
                  );
                }),
        ),
      ],
    );
  }
}

// ── Shifts Tab ──────────────────────────────────────────────────
class _ShiftsTab extends StatefulWidget {
  final bool isEnglish;
  const _ShiftsTab({this.isEnglish = false});
  @override
  State<_ShiftsTab> createState() => _ShiftsTabState();
}

class _ShiftsTabState extends State<_ShiftsTab> {
  List<Map<String, dynamic>> _employees = [];
  bool _loading = true;
  String _search = '';

  static const _indigo = Color(0xFF06B6D4);
  static const _surface = Color(0xFF0D2731);
  static const _green = Color(0xFF34D399);
  static const _red = Color(0xFFF87171);

  static const _shiftOptions = [
    'صباحي',
    'مسائي',
    'صباحي + مسائي',
    'متناوب',
    'إداري',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await portalClient
          .from('employee_profiles')
          .select('id, name, department, shift, status, is_admin')
          .order('name');
      if (mounted) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(data)
              .where((e) => e['is_admin'] != true)
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateShift(String empId, String newShift) async {
    try {
      await portalClient
          .from('employee_profiles')
          .update({'shift': newShift})
          .eq('id', empId);
      setState(() {
        final idx = _employees.indexWhere((e) => e['id'] == empId);
        if (idx != -1) _employees[idx] = {..._employees[idx], 'shift': newShift};
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(widget.isEnglish, 'تم تحديث الدوام')),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.isEnglish ? 'Error: $e' : 'خطأ: $e'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  void _showEditSheet(Map<String, dynamic> emp) {
    final name = emp['name'] as String? ?? '—';
    String selected = emp['shift'] as String? ?? _shiftOptions[0];

    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Directionality(
        textDirection: widget.isEnglish ? TextDirection.ltr : TextDirection.rtl,
        child: StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  widget.isEnglish ? 'Change Shift: $name' : 'تغيير دوام: $name',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              ...List.generate(_shiftOptions.length, (i) {
                final opt = _shiftOptions[i];
                final isSelected = opt == selected;
                return GestureDetector(
                  onTap: () => setLocal(() => selected = opt),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _indigo.withValues(alpha: 0.15)
                          : const Color(0x0AFFFFFF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isSelected
                              ? _indigo.withValues(alpha: 0.5)
                              : const Color(0x1AFFFFFF)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isSelected
                              ? _indigo
                              : const Color(0x55FFFFFF),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(tr(widget.isEnglish, opt),
                            style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0x99FFFFFF),
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0x66FFFFFF),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(tr(widget.isEnglish, 'إلغاء')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _updateShift(emp['id'].toString(), selected);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _indigo,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(tr(widget.isEnglish, 'حفظ'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.trim().isEmpty) return _employees;
    final q = _search.trim().toLowerCase();
    return _employees.where((e) {
      final name = (e['name'] as String? ?? '').toLowerCase();
      final dept = (e['department'] as String? ?? '').toLowerCase();
      return name.contains(q) || dept.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _indigo));
    }

    final isMobile = MediaQuery.of(context).size.width < 700;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style:
                      const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: tr(widget.isEnglish, 'بحث...'),
                    hintStyle: const TextStyle(
                        color: Color(0x55FFFFFF), fontSize: 13),
                    prefixIcon: const Icon(Icons.search,
                        color: Color(0x55FFFFFF), size: 18),
                    filled: true,
                    fillColor: const Color(0x0AFFFFFF),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0x1AFFFFFF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0x1AFFFFFF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: _indigo, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh,
                    color: Color(0x99FFFFFF), size: 18),
                onPressed: _load,
                tooltip: tr(widget.isEnglish, 'تحديث'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Text(tr(widget.isEnglish, 'لا توجد نتائج'),
                      style: const TextStyle(color: Color(0x66FFFFFF))))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final emp = _filtered[i];
                    final name = emp['name'] as String? ?? '—';
                    final nameEn = emp['name_en'] as String?;
                    final displayName = (widget.isEnglish && nameEn != null && nameEn.isNotEmpty) ? nameEn : name;
                    final dept = emp['department'] as String? ?? '—';
                    final shift = emp['shift'] as String? ?? '—';

                    final avatar = Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _indigo.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          displayName.isNotEmpty ? displayName[0] : '?',
                          style: const TextStyle(
                              color: _indigo,
                              fontWeight: FontWeight.w700,
                              fontSize: 16),
                        ),
                      ),
                    );
                    final nameColumn = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(tr(widget.isEnglish, dept),
                            style: const TextStyle(
                                color: Color(0x66FFFFFF),
                                fontSize: 11)),
                      ],
                    );
                    final shiftButton = GestureDetector(
                      onTap: () => _showEditSheet(emp),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _indigo.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _indigo.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(tr(widget.isEnglish, shift),
                                style: const TextStyle(
                                    color: _indigo,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 5),
                            const Icon(Icons.edit_outlined,
                                size: 13, color: _indigo),
                          ],
                        ),
                      ),
                    );

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0x14FFFFFF)),
                      ),
                      child: isMobile
                          ? Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    avatar,
                                    const SizedBox(width: 12),
                                    Expanded(child: nameColumn),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: shiftButton,
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                avatar,
                                const SizedBox(width: 12),
                                Expanded(child: nameColumn),
                                shiftButton,
                              ],
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Clinics Tab ─────────────────────────────────────────────────
class _ClinicsTab extends StatefulWidget {
  final bool isEnglish;
  const _ClinicsTab({this.isEnglish = false});
  @override
  State<_ClinicsTab> createState() => _ClinicsTabState();
}

class _ClinicsTabState extends State<_ClinicsTab> {
  List<Map<String, dynamic>> _rows = [];
  Map<String, String> _empNames = {};
  bool _loading = true;
  late final RealtimeChannel _channel;

  static const _indigo = Color(0xFF06B6D4);
  static const _surface = Color(0xFF0D2731);

  static const _dayNames = {
    7: 'الأحد',
    1: 'الاثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
    6: 'السبت',
  };
  static const _weekOrder = [6, 7, 1, 2, 3, 4, 5];

  @override
  void initState() {
    super.initState();
    _load();
    _channel = portalClient
        .channel('admin-clinics-tab')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'clinic_schedules',
          callback: (_) { if (mounted) _load(); },
        )
        .subscribe();
  }

  @override
  void dispose() {
    portalClient.removeChannel(_channel);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        portalClient.from('clinic_schedules').select(),
        portalClient.from('employee_profiles').select('id, name'),
      ]);
      final rows = List<Map<String, dynamic>>.from(results[0] as List);
      final emps = List<Map<String, dynamic>>.from(results[1] as List);
      final empNames = <String, String>{
        for (final e in emps) e['id'].toString(): e['name'] as String? ?? '',
      };
      if (mounted) {
        setState(() {
          _rows = rows;
          _empNames = empNames;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // clinic → weekday → [employee labels]
  Map<int, Map<int, List<String>>> _buildBoard() {
    final board = <int, Map<int, List<String>>>{};
    for (final row in _rows) {
      final clinic = (row['clinic_number'] as num?)?.toInt();
      if (clinic == null) continue;
      final shift = row['shift'] as String? ?? '';
      final empId = row['employee_id']?.toString() ?? '';
      final empName = _empNames[empId] ?? empId;
      final label = shift.isNotEmpty ? '$empName ($shift)' : empName;
      final daysStr = row['days'] as String? ?? '';
      for (final part in daysStr.split(',')) {
        final d = int.tryParse(part.trim());
        if (d == null) continue;
        board.putIfAbsent(clinic, () => {});
        board[clinic]!.putIfAbsent(d, () => []);
        board[clinic]![d]!.add(label);
      }
    }
    return board;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _indigo));
    }

    final board = _buildBoard();
    final clinics = board.keys.toList()..sort();
    final todayFw = DateTime.now().weekday == 7 ? 7 : DateTime.now().weekday;

    if (clinics.isEmpty) {
      return Center(
        child: Text(tr(widget.isEnglish, 'لا توجد جداول عيادات بعد'),
            style: const TextStyle(color: Color(0x66FFFFFF))),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: clinics.length,
      itemBuilder: (_, i) {
        final clinic = clinics[i];
        final days = board[clinic]!;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x14FFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.door_front_door_outlined, color: _indigo, size: 18),
                  const SizedBox(width: 8),
                  Text('${tr(widget.isEnglish, 'عيادة')} $clinic',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                ],
              ),
              const SizedBox(height: 12),
              ..._weekOrder.map((fw) {
                final names = days[fw];
                final isOff = names == null || names.isEmpty;
                final isToday = fw == todayFw;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          tr(widget.isEnglish, _dayNames[fw] ?? ''),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                            color: isToday ? _indigo : (isOff ? const Color(0x44FFFFFF) : Colors.white),
                          ),
                        ),
                      ),
                      Expanded(
                        child: isOff
                            ? Text(tr(widget.isEnglish, 'إجازة'),
                                style: const TextStyle(fontSize: 12, color: Color(0x44FFFFFF)))
                            : Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: names.map((n) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _indigo.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _indigo.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(n, style: const TextStyle(fontSize: 11, color: _indigo, fontWeight: FontWeight.w600)),
                                )).toList(),
                              ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// ── Tasks & Custody Tab ──────────────────────────────────────────
// Lets the admin send a task or a custody item to an employee directly
// from the portal, and lists everything sent from either the portal or
// the desktop app (they share the same portal_tasks/portal_custody_items
// tables, so both sides always show the same data).
class _TasksCustodyTab extends StatefulWidget {
  final bool isEnglish;
  const _TasksCustodyTab({this.isEnglish = false});
  @override
  State<_TasksCustodyTab> createState() => _TasksCustodyTabState();
}

class _TasksCustodyTabState extends State<_TasksCustodyTab> {
  int _mode = 0; // 0 = tasks, 1 = custody
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _custodyItems = [];
  Map<String, String> _empNames = {};
  bool _loading = true;
  bool _sending = false;
  String? _selectedEmpId;
  String? _filterEmpId;
  bool _showCompleted = false;
  final _titleCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  final _equipmentCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _taskDueAt;
  late final RealtimeChannel _channel;

  static const _indigo = Color(0xFF06B6D4);
  static const _green = Color(0xFF34D399);
  static const _amber = Color(0xFFF59E0B);
  static const _blue = Color(0xFF0EA5E9);
  static const _grey = Color(0xFF9CA3AF);
  static const _purple = Color(0xFF8B5CF6);
  static const _surface = Color(0xFF0D2731);

  Color _custodyColor(String status) {
    switch (status) {
      case 'مستلم':
        return _green;
      case 'قيد الإعادة':
        return _blue;
      case 'أعيدت للإدارة':
        return _grey;
      default:
        return _amber;
    }
  }

  Future<void> _confirmReturnedToAdmin(String id) async {
    final warehouseCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final knownWarehouses = _custodyItems
        .map((it) => it['warehouse'] as String?)
        .where((w) => w != null && w.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: _surface,
          title: Text(tr(widget.isEnglish, 'تم استلامها من الإدارة'),
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field(warehouseCtrl, tr(widget.isEnglish, 'المستودع')),
                if (knownWarehouses.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: knownWarehouses.map((w) {
                      return GestureDetector(
                        onTap: () => setInner(() => warehouseCtrl.text = w),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _indigo.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(w, style: const TextStyle(fontSize: 11, color: _indigo)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 12),
                _field(notesCtrl, tr(widget.isEnglish, 'ملاحظات حالة الجهاز (اختياري)'), maxLines: 3),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(widget.isEnglish, 'إلغاء'), style: const TextStyle(color: Color(0x99FFFFFF))),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _blue),
              child: Text(tr(widget.isEnglish, 'تأكيد')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await portalClient.from('portal_custody_items').update({
        'status': 'أعيدت للإدارة',
        'returned_to_admin_at': DateTime.now().toIso8601String(),
        'warehouse': warehouseCtrl.text.trim().isEmpty ? null : warehouseCtrl.text.trim(),
        'admin_return_notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      }).eq('id', id);
      await _load();
    } catch (_) {}
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      return intl.DateFormat('dd/MM/yyyy — HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }

  List<Widget> _custodyDetailLines(Map<String, dynamic> item) {
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('$label: $value',
              style: const TextStyle(fontSize: 11, color: Color(0x77FFFFFF))),
        );
    final lines = <Widget>[
      line(tr(widget.isEnglish, 'تاريخ التسليم'), _fmtDate(item['created_at'] as String?)),
    ];
    if (item['received_at'] != null) {
      lines.add(line(tr(widget.isEnglish, 'تاريخ الاستلام'), _fmtDate(item['received_at'] as String?)));
    }
    if (item['return_initiated_at'] != null) {
      lines.add(line(tr(widget.isEnglish, 'تاريخ بدء الإعادة'), _fmtDate(item['return_initiated_at'] as String?)));
    }
    if (item['return_notes'] != null && (item['return_notes'] as String).isNotEmpty) {
      lines.add(line(tr(widget.isEnglish, 'ملاحظة الموظف'), item['return_notes'] as String));
    }
    if (item['returned_to_admin_at'] != null) {
      lines.add(line(tr(widget.isEnglish, 'تاريخ استلام الإدارة'), _fmtDate(item['returned_to_admin_at'] as String?)));
    }
    if (item['warehouse'] != null && (item['warehouse'] as String).isNotEmpty) {
      lines.add(line(tr(widget.isEnglish, 'المستودع'), item['warehouse'] as String));
    }
    if (item['admin_return_notes'] != null && (item['admin_return_notes'] as String).isNotEmpty) {
      lines.add(line(tr(widget.isEnglish, 'ملاحظة الإدارة'), item['admin_return_notes'] as String));
    }
    return lines;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _channel = portalClient
        .channel('admin-tasks-custody-tab')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'portal_tasks',
          callback: (_) { if (mounted) _load(); },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'portal_custody_items',
          callback: (_) { if (mounted) _load(); },
        )
        .subscribe();
  }

  @override
  void dispose() {
    portalClient.removeChannel(_channel);
    _titleCtrl.dispose();
    _detailsCtrl.dispose();
    _equipmentCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        portalClient.from('employee_profiles').select('id, name, is_admin').order('name'),
        portalClient.from('portal_tasks').select().order('created_at', ascending: false),
        portalClient.from('portal_custody_items').select().order('created_at', ascending: false),
      ]);
      final emps = List<Map<String, dynamic>>.from(results[0] as List)
          .where((e) => e['is_admin'] != true)
          .toList();
      if (mounted) {
        setState(() {
          _employees = emps;
          _empNames = {for (final e in emps) e['id'].toString(): e['name'] as String? ?? ''};
          _tasks = List<Map<String, dynamic>>.from(results[1] as List);
          _custodyItems = List<Map<String, dynamic>>.from(results[2] as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _pickTaskDueAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _taskDueAt ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _taskDueAt != null
          ? TimeOfDay.fromDateTime(_taskDueAt!)
          : TimeOfDay.now(),
    );
    if (time == null) return;
    setState(() => _taskDueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _send() async {
    if (_selectedEmpId == null) return;
    if (_mode == 0 && _titleCtrl.text.trim().isEmpty) return;
    if (_mode == 1 && _equipmentCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      if (_mode == 0) {
        await portalClient.from('portal_tasks').insert({
          'employee_id': _selectedEmpId,
          'title': _titleCtrl.text.trim(),
          'details': _detailsCtrl.text.trim().isEmpty ? null : _detailsCtrl.text.trim(),
          'status': 'قيد الانتظار',
          'created_by': 'admin',
          'due_at': _taskDueAt?.toIso8601String(),
        });
        _titleCtrl.clear();
        _detailsCtrl.clear();
        _taskDueAt = null;
      } else {
        await portalClient.from('portal_custody_items').insert({
          'employee_id': _selectedEmpId,
          'equipment_name': _equipmentCtrl.text.trim(),
          'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          'status': 'بانتظار الاستلام',
          'created_by': 'admin',
        });
        _equipmentCtrl.clear();
        _notesCtrl.clear();
      }
      if (mounted) {
        setState(() => _selectedEmpId = null);
        _snack(tr(widget.isEnglish, 'تم الإرسال'), _green);
      }
      await _load();
    } catch (e) {
      if (mounted) _snack(widget.isEnglish ? 'Error: $e' : 'خطأ: $e', const Color(0xFFF87171));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _indigo));
    }

    final isMobile = MediaQuery.of(context).size.width < 700;
    final allItems = _mode == 0 ? _tasks : _custodyItems;
    final items = _filterEmpId == null
        ? allItems
        : allItems.where((it) => it['employee_id']?.toString() == _filterEmpId).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode toggle
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0x0AFFFFFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                for (final (label, val) in [(tr(widget.isEnglish, 'المهام'), 0), (tr(widget.isEnglish, 'العهد'), 1)])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _mode = val),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: _mode == val ? _purple.withValues(alpha: 0.18) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _mode == val ? _purple.withValues(alpha: 0.4) : Colors.transparent),
                        ),
                        child: Text(label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: _mode == val ? FontWeight.w700 : FontWeight.normal,
                                color: _mode == val ? Colors.white : const Color(0x99FFFFFF))),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Compose form
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x14FFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _mode == 0
                        ? tr(widget.isEnglish, 'إرسال مهمة جديدة')
                        : tr(widget.isEnglish, 'تسليم عهدة لموظف'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedEmpId,
                  dropdownColor: _surface,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: tr(widget.isEnglish, 'الموظف'),
                    labelStyle: const TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
                    filled: true,
                    fillColor: const Color(0x0AFFFFFF),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
                  ),
                  items: _employees
                      .map((e) => DropdownMenuItem(
                            value: e['id'].toString(),
                            child: Text(e['name'] as String? ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedEmpId = v),
                ),
                const SizedBox(height: 10),
                if (_mode == 0) ...[
                  _field(_titleCtrl, tr(widget.isEnglish, 'عنوان المهمة')),
                  const SizedBox(height: 10),
                  _field(_detailsCtrl, tr(widget.isEnglish, 'تفاصيل (اختياري)'), maxLines: 3),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _pickTaskDueAt,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0x0AFFFFFF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x1AFFFFFF)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event_outlined, size: 16, color: Color(0x99FFFFFF)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _taskDueAt == null
                                  ? tr(widget.isEnglish, 'موعد الإنجاز (اختياري)')
                                  : intl.DateFormat('dd/MM/yyyy — HH:mm').format(_taskDueAt!),
                              style: TextStyle(
                                fontSize: 13,
                                color: _taskDueAt == null ? const Color(0x66FFFFFF) : Colors.white,
                              ),
                            ),
                          ),
                          if (_taskDueAt != null)
                            GestureDetector(
                              onTap: () => setState(() => _taskDueAt = null),
                              child: const Icon(Icons.close, size: 15, color: Color(0x66FFFFFF)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  _field(_equipmentCtrl, tr(widget.isEnglish, 'اسم الجهاز/العهدة')),
                  const SizedBox(height: 10),
                  _field(_notesCtrl, tr(widget.isEnglish, 'ملاحظات (اختياري)'), maxLines: 3),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: isMobile ? double.infinity : 180,
                  child: ElevatedButton.icon(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 16),
                    label: Text(tr(widget.isEnglish, 'إرسال')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: Text(
                    _mode == 0 ? tr(widget.isEnglish, 'المهام المُرسلة') : tr(widget.isEnglish, 'العهد المُرسلة'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xCCFFFFFF))),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  initialValue: _filterEmpId,
                  isDense: true,
                  dropdownColor: _surface,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: tr(widget.isEnglish, 'كل الموظفين'),
                    hintStyle: const TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0x0AFFFFFF),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(tr(widget.isEnglish, 'كل الموظفين'),
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                    ..._employees.map((e) => DropdownMenuItem<String?>(
                          value: e['id'].toString(),
                          child: Text(e['name'] as String? ?? '',
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                        )),
                  ],
                  onChanged: (v) => setState(() => _filterEmpId = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                    _mode == 0 ? tr(widget.isEnglish, 'لا توجد مهام') : tr(widget.isEnglish, 'لا توجد عهد'),
                    style: const TextStyle(color: Color(0x66FFFFFF))),
              ),
            )
          else
            ..._buildItemGroups(items),
        ],
      ),
    );
  }

  List<Widget> _buildItemGroups(List<Map<String, dynamic>> items) {
    final terminalStatus = _mode == 0 ? 'مكتملة' : 'أعيدت للإدارة';
    final active = items.where((it) => it['status'] != terminalStatus).toList();
    final completed = items.where((it) => it['status'] == terminalStatus).toList();
    return [
      ...active.map(_itemCard),
      if (completed.isNotEmpty) ...[
        GestureDetector(
          onTap: () => setState(() => _showCompleted = !_showCompleted),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8, top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x14FFFFFF)),
            ),
            child: Row(
              children: [
                Icon(_showCompleted ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: const Color(0x99FFFFFF)),
                const SizedBox(width: 8),
                Text(
                    '${_mode == 0 ? tr(widget.isEnglish, 'المهام المكتملة') : tr(widget.isEnglish, 'العهد المكتملة')} (${completed.length})',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0x99FFFFFF))),
              ],
            ),
          ),
        ),
        if (_showCompleted) ...completed.map(_itemCard),
      ],
    ];
  }

  String get _pendingStatus => _mode == 0 ? 'قيد الانتظار' : 'بانتظار الاستلام';

  Widget _itemCard(Map<String, dynamic> it) {
              final empId = it['employee_id']?.toString() ?? '';
              final empName = _empNames[empId] ?? empId;
              final status = it['status'] as String? ?? _pendingStatus;
              final color = _mode == 0
                  ? (status != _pendingStatus ? _green : _amber)
                  : _custodyColor(status);
              final title = _mode == 0
                  ? (it['title'] as String? ?? '')
                  : (it['equipment_name'] as String? ?? '');
              final sub = _mode == 0 ? it['details'] as String? : it['notes'] as String?;
              final canConfirmReturn = _mode == 1 && status == 'قيد الإعادة';
              DateTime? dueAt;
              if (_mode == 0 && it['due_at'] != null) {
                try { dueAt = DateTime.parse(it['due_at'] as String).toLocal(); } catch (_) {}
              }
              final taskOverdue = dueAt != null && status == 'قيد الانتظار' && dueAt.isBefore(DateTime.now());
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: _indigo.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                              _mode == 0 ? Icons.task_alt_outlined : Icons.inventory_2_outlined,
                              color: _indigo, size: 17),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                              const SizedBox(height: 2),
                              Text(empName,
                                  style: const TextStyle(fontSize: 11, color: Color(0x99FFFFFF))),
                              if (sub != null && sub.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(sub, style: const TextStyle(fontSize: 11, color: Color(0x66FFFFFF))),
                              ],
                              if (dueAt != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.schedule,
                                        size: 11,
                                        color: taskOverdue ? const Color(0xFFF87171) : const Color(0x66FFFFFF)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${tr(widget.isEnglish, 'موعد الإنجاز')}: ${intl.DateFormat('dd/MM/yyyy — HH:mm').format(dueAt)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: taskOverdue ? FontWeight.w600 : FontWeight.normal,
                                        color: taskOverdue ? const Color(0xFFF87171) : const Color(0x66FFFFFF),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(tr(widget.isEnglish, status),
                              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    if (_mode == 1) ..._custodyDetailLines(it),
                    if (canConfirmReturn) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton.icon(
                          onPressed: () => _confirmReturnedToAdmin(it['id'] as String),
                          icon: const Icon(Icons.check_circle_outline, size: 15),
                          label: Text(tr(widget.isEnglish, 'تم استلامها من الإدارة'),
                              style: const TextStyle(fontSize: 12)),
                          style: FilledButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
  }

  Widget _field(TextEditingController ctrl, String label, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
        filled: true,
        fillColor: const Color(0x0AFFFFFF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _indigo, width: 1.5)),
      ),
    );
  }
}
