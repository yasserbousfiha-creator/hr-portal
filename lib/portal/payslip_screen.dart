import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'portal_client.dart';
import 'portal_i18n.dart';

class PortalPayslipScreen extends StatefulWidget {
  final String employeeId;
  final bool isEnglish;
  const PortalPayslipScreen({super.key, required this.employeeId, this.isEnglish = false});

  @override
  State<PortalPayslipScreen> createState() => _PortalPayslipScreenState();
}

class _PortalPayslipScreenState extends State<PortalPayslipScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  int? _selectedIdx;
  bool _showDetail = false;
  bool _acknowledging = false;
  late final RealtimeChannel _channel;

  static const _indigo = Color(0xFF06B6D4);
  static const _months = [
    '', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _channel = portalClient
        .channel('emp-payslip-${widget.employeeId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payroll_records',
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
      final data = await portalClient
          .from('payroll_records')
          .select()
          .eq('employee_id', widget.employeeId)
          .order('year', ascending: false)
          .order('month', ascending: false);
      if (mounted) {
        setState(() {
          _records = List<Map<String, dynamic>>.from(data as List);
          _loading = false;
          if (_selectedIdx == null || _selectedIdx! >= _records.length) {
            _selectedIdx = _records.isNotEmpty ? 0 : null;
          }
        });
      }
    } catch (_) {
      if (mounted) { setState(() => _loading = false); }
    }
  }

  Future<void> _acknowledge(String id) async {
    setState(() => _acknowledging = true);
    try {
      await portalClient.from('payroll_records').update({
        'status': 'تم الاستلام',
        'acknowledged_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      await _load();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _acknowledging = false);
    }
  }

  String _monthName(int m) => tr(widget.isEnglish, (m > 0 && m < 13) ? _months[m] : '$m');

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 650;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────
          Row(
            children: [
              if (isMobile && _showDetail) ...[
                GestureDetector(
                  onTap: () => setState(() => _showDetail = false),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white60, size: 18),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(widget.isEnglish, 'كشف الراتب'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(tr(widget.isEnglish, 'سجل مستحقاتك الشهرية'),
                        style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: _indigo)))
          else if (_records.isEmpty)
            Expanded(child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 52, color: Colors.white.withValues(alpha: 0.15)),
                  const SizedBox(height: 12),
                  Text(tr(widget.isEnglish, 'لا توجد كشوف رواتب'),
                      style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 14)),
                ],
              ),
            ))
          else if (isMobile)
            Expanded(
              child: _showDetail && _selectedIdx != null
                  ? SingleChildScrollView(
                      child: _PayslipDetail(
                        record: _records[_selectedIdx!],
                        isEnglish: widget.isEnglish,
                        acknowledging: _acknowledging,
                        onAcknowledge: () => _acknowledge(_records[_selectedIdx!]['id'] as String),
                      ))
                  : ListView.separated(
                      itemCount: _records.length,
                      separatorBuilder: (context, idx) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final r = _records[i];
                        final month = r['month'] as int? ?? 0;
                        final year = r['year'] as int? ?? 0;
                        final net = (r['net_salary'] as num?)?.toDouble() ?? 0;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _selectedIdx = i;
                            _showDetail = true;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0x0AFFFFFF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0x14FFFFFF)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: _indigo.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.receipt_long_outlined,
                                      color: _indigo, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_monthName(month),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white)),
                                      Text('$year', style: const TextStyle(
                                          fontSize: 12, color: Color(0x66FFFFFF))),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('${net.toStringAsFixed(0)} ${tr(widget.isEnglish, 'ريال')}',
                                        style: const TextStyle(
                                            color: _indigo,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15)),
                                    Text(tr(widget.isEnglish, 'صافي'),
                                        style: const TextStyle(
                                            fontSize: 11, color: Color(0x66FFFFFF))),
                                  ],
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.chevron_left,
                                    color: Color(0x44FFFFFF), size: 18),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            )
          else
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 170,
                    child: ListView.separated(
                      itemCount: _records.length,
                      separatorBuilder: (context, idx) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final r = _records[i];
                        final month = r['month'] as int? ?? 0;
                        final year = r['year'] as int? ?? 0;
                        final active = _selectedIdx == i;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedIdx = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: active
                                  ? _indigo.withValues(alpha: 0.15)
                                  : const Color(0x08FFFFFF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: active
                                      ? _indigo.withValues(alpha: 0.4)
                                      : const Color(0x14FFFFFF)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_monthName(month),
                                    style: TextStyle(
                                        fontWeight: active
                                            ? FontWeight.w700
                                            : FontWeight.normal,
                                        color: active
                                            ? Colors.white
                                            : const Color(0x99FFFFFF))),
                                Text('$year',
                                    style: const TextStyle(
                                        fontSize: 11, color: Color(0x66FFFFFF))),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _selectedIdx != null
                        ? SingleChildScrollView(
                            child: _PayslipDetail(
                              record: _records[_selectedIdx!],
                              isEnglish: widget.isEnglish,
                              acknowledging: _acknowledging,
                              onAcknowledge: () => _acknowledge(_records[_selectedIdx!]['id'] as String),
                            ))
                        : const SizedBox(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PayslipDetail extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool isEnglish;
  final bool acknowledging;
  final VoidCallback? onAcknowledge;
  const _PayslipDetail({
    required this.record,
    this.isEnglish = false,
    this.acknowledging = false,
    this.onAcknowledge,
  });

  static const _months = [
    '', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const _indigo = Color(0xFF06B6D4);
  static const _green = Color(0xFF34D399);
  static const _red = Color(0xFFF87171);

  double _d(String key) => (record[key] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final month = record['month'] as int? ?? 0;
    final year = record['year'] as int? ?? 0;
    final basic = _d('basic_salary');
    final allowances = _d('allowances');
    final commissions = _d('commissions');
    final deductions = _d('deductions');
    final advDeduct = _d('advance_deduction');
    final net = _d('net_salary');
    final deductionReason = record['deduction_reason'] as String?;
    final monthName = tr(isEnglish, month > 0 && month < 13 ? _months[month] : '$month');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _indigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_outlined, color: _indigo, size: 18),
              ),
              const SizedBox(width: 12),
              Text('$monthName $year',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ],
          ),
          const SizedBox(height: 20),

          _sectionHead(tr(isEnglish, 'الإيرادات'), _green),
          const SizedBox(height: 10),
          _Row(label: tr(isEnglish, 'الراتب الأساسي'), value: basic, color: _green, isEnglish: isEnglish),
          _Row(label: tr(isEnglish, 'البدلات'), value: allowances, color: _green, isEnglish: isEnglish),
          _Row(label: tr(isEnglish, 'العمولات'), value: commissions, color: _green, isEnglish: isEnglish),

          const SizedBox(height: 16),

          _sectionHead(tr(isEnglish, 'الاستقطاعات'), _red),
          const SizedBox(height: 10),
          _Row(label: tr(isEnglish, 'الاستقطاعات'), value: deductions, color: _red, neg: true, isEnglish: isEnglish),
          if (advDeduct > 0)
            _Row(label: tr(isEnglish, 'استقطاع السلفة'), value: advDeduct, color: _red, neg: true, isEnglish: isEnglish),
          if (deductionReason != null && deductionReason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('${tr(isEnglish, 'سبب الخصم')}: $deductionReason',
                style: TextStyle(fontSize: 11, color: _red.withValues(alpha: 0.85), height: 1.4)),
          ],

          const SizedBox(height: 20),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [_indigo, Color(0xFF0EA5E9)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(tr(isEnglish, 'صافي الراتب'),
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text('${net.toStringAsFixed(2)} ${tr(isEnglish, 'ريال')}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 28, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _acknowledgeSection(),
        ],
      ),
    );
  }

  Widget _acknowledgeSection() {
    final status = record['status'] as String? ?? 'لم يُستلم';
    final acknowledged = status == 'تم الاستلام';
    if (acknowledged) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _green.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, color: _green, size: 16),
            const SizedBox(width: 8),
            Text(tr(isEnglish, 'تم الاستلام'),
                style: const TextStyle(color: _green, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_inReminderWindow())
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_outlined, color: Color(0xFFF59E0B), size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr(isEnglish, 'يرجى تأكيد استلام الراتب في أقرب وقت'),
                      style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11.5)),
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: acknowledging ? null : onAcknowledge,
            icon: acknowledging
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline, size: 16),
            label: Text(tr(isEnglish, 'تم الاستلام'), style: const TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  // Reminder window: from the last day of the payslip's own month through
  // the 10th of the next month (e.g. a September record reminds from
  // Sept 30 through Oct 10) — purely a visual nudge, the button itself
  // stays available indefinitely either way (confirmed with the user).
  bool _inReminderWindow() {
    final month = record['month'] as int? ?? 0;
    final year = record['year'] as int? ?? 0;
    if (month < 1 || month > 12) return false;
    final lastDayOfMonth = DateTime(year, month + 1, 0);
    final windowEnd = DateTime(year, month + 1, 10, 23, 59, 59);
    final now = DateTime.now();
    return !now.isBefore(lastDayOfMonth) && !now.isAfter(windowEnd);
  }

  static Widget _sectionHead(String label, Color color) => Row(
    children: [
      Container(width: 3, height: 14,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    ],
  );
}

class _Row extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool neg;
  final bool isEnglish;
  const _Row({required this.label, required this.value, required this.color, this.neg = false, this.isEnglish = false});

  @override
  Widget build(BuildContext context) {
    if (value == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0x99FFFFFF))),
          Text('${neg ? '- ' : '+ '}${value.toStringAsFixed(2)} ${tr(isEnglish, 'ريال')}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
