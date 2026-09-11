import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'portal_client.dart';
import 'portal_i18n.dart';

class PortalLeavesScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final bool isEnglish;
  const PortalLeavesScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.isEnglish = false,
  });

  @override
  State<PortalLeavesScreen> createState() => _PortalLeavesScreenState();
}

class _PortalLeavesScreenState extends State<PortalLeavesScreen> {
  List<Map<String, dynamic>> _requests = [];
  Map<String, dynamic>? _balance;
  bool _loading = true;
  bool _showForm = false;

  String _type = 'سنوية';
  DateTime? _start;
  DateTime? _end;
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;
  late final RealtimeChannel _channel;

  static const _indigo = Color(0xFF06B6D4);
  static const _green = Color(0xFF34D399);
  static const _amber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _load();
    _channel = portalClient
        .channel('emp-leaves-${widget.employeeId}')
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
    _reasonCtrl.dispose();
    portalClient.removeChannel(_channel);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final year = DateTime.now().year;
      final [requests, balance] = await Future.wait([
        portalClient
            .from('leave_requests')
            .select()
            .eq('employee_id', widget.employeeId)
            .order('submitted_at', ascending: false),
        portalClient
            .from('leave_balances')
            .select()
            .eq('employee_id', widget.employeeId)
            .eq('year', year)
            .maybeSingle(),
      ]);
      if (mounted) {
        setState(() {
          _requests = List<Map<String, dynamic>>.from(requests as List);
          _balance = balance as Map<String, dynamic>?;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_start == null || _end == null) {
      _snack(tr(widget.isEnglish, 'يرجى تحديد تاريخ البداية والنهاية'));
      return;
    }

    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final startDay = DateTime(_start!.year, _start!.month, _start!.day);

    if (startDay.isBefore(today)) {
      _snack(tr(widget.isEnglish, 'لا يمكن تسجيل إجازة بتاريخ في الماضي'));
      return;
    }

    if (_end!.isBefore(_start!) || _end!.isAtSameMomentAs(_start!.subtract(const Duration(days: 1)))) {
      _snack(tr(widget.isEnglish, 'تاريخ النهاية يجب أن يكون بعد البداية'));
      return;
    }

    final days = _end!.difference(_start!).inDays + 1;

    final overlapping = _requests.where((r) {
      if (r['status'] == 'مرفوضة') return false;
      final existStart = DateTime.tryParse(r['start_date'] as String? ?? '');
      final existEnd = DateTime.tryParse(r['end_date'] as String? ?? '');
      if (existStart == null || existEnd == null) return false;
      return _start!.isBefore(existEnd.add(const Duration(days: 1))) &&
             _end!.isAfter(existStart.subtract(const Duration(days: 1)));
    }).toList();

    if (overlapping.isNotEmpty) {
      final o = overlapping.first;
      _snack(widget.isEnglish
          ? 'A leave request already exists for the same period (${o['start_date']} → ${o['end_date']})'
          : 'يوجد طلب إجازة في نفس الفترة (${o['start_date']} → ${o['end_date']})');
      return;
    }

    if (_type == 'سنوية') {
      final quota = _balance?['annual_quota'] as int? ?? 21;
      final used = _balance?['used_days'] as int? ?? 0;
      final remaining = quota - used;
      if (days > remaining) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (c) => Directionality(
            textDirection: widget.isEnglish ? TextDirection.ltr : TextDirection.rtl,
            child: AlertDialog(
            backgroundColor: const Color(0xFF123540),
            title: Text(tr(widget.isEnglish, 'تجاوز الرصيد'), style: const TextStyle(color: Colors.white)),
            content: Text(
              widget.isEnglish
                  ? 'You are requesting $days day(s) but only $remaining day(s) remain.\n'
                      'Do you want to send the request anyway?'
                  : 'تطلب $days يوم والرصيد المتبقي $remaining يوم فقط.\n'
                      'هل تريد إرسال الطلب رغم ذلك؟',
              style: const TextStyle(color: Color(0x99FFFFFF)),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(widget.isEnglish, 'إلغاء'))),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(tr(widget.isEnglish, 'إرسال رغم التجاوز'), style: const TextStyle(color: Color(0xFFF59E0B))),
              ),
            ],
            ),
          ),
        );
        if (proceed != true) return;
      }
    }

    setState(() => _submitting = true);
    try {
      await portalClient.from('leave_requests').insert({
        'employee_id': widget.employeeId,
        'employee_name': widget.employeeName,
        'type': _type,
        'start_date': _start!.toIso8601String().substring(0, 10),
        'end_date': _end!.toIso8601String().substring(0, 10),
        'days_count': days,
        'reason': _reasonCtrl.text.isEmpty ? null : _reasonCtrl.text,
        'status': 'قيد المراجعة',
        'source': 'portal',
      });
      if (mounted) {
        setState(() { _showForm = false; _submitting = false; });
        _snack(tr(widget.isEnglish, 'تم إرسال طلب الإجازة بنجاح ✓'), isError: false);
        _load();
      }
    } catch (e) {
      if (mounted) { setState(() => _submitting = false); _snack(widget.isEnglish ? 'Error: $e' : 'خطأ: $e'); }
    }
  }

  void _snack(String msg, {bool isError = true}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor:
          isError ? const Color(0xFFF87171) : const Color(0xFF34D399),
    ),
  );

  Color _statusColor(String s) {
    if (s == 'موافق عليها') return _green;
    if (s == 'مرفوضة') return const Color(0xFFF87171);
    return _amber;
  }

  @override
  Widget build(BuildContext context) {
    final quota = _balance?['annual_quota'] as int? ?? 21;
    final used = _balance?['used_days'] as int? ?? 0;
    final remaining = quota - used;
    final isMobile = MediaQuery.of(context).size.width < 700;

    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────
          if (isMobile) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(widget.isEnglish, 'الإجازات'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(tr(widget.isEnglish, 'إدارة إجازاتك وطلباتك'),
                    style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => setState(() => _showForm = !_showForm),
                icon: Icon(_showForm ? Icons.close : Icons.add, size: 16),
                label: Text(_showForm ? tr(widget.isEnglish, 'إلغاء') : tr(widget.isEnglish, 'طلب جديد'),
                    style: const TextStyle(fontSize: 13)),
                style: FilledButton.styleFrom(
                  backgroundColor: _indigo,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(widget.isEnglish, 'الإجازات'),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(tr(widget.isEnglish, 'إدارة إجازاتك وطلباتك'),
                          style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => setState(() => _showForm = !_showForm),
                  icon: Icon(_showForm ? Icons.close : Icons.add, size: 16),
                  label: Text(_showForm ? tr(widget.isEnglish, 'إلغاء') : tr(widget.isEnglish, 'طلب جديد'),
                      style: const TextStyle(fontSize: 13)),
                  style: FilledButton.styleFrom(
                    backgroundColor: _indigo,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),

          if (isMobile)
            Column(
              children: [
                Row(children: [_BalCard(label: tr(widget.isEnglish, 'الرصيد'), value: quota, color: _indigo)]),
                const SizedBox(height: 10),
                Row(children: [_BalCard(label: tr(widget.isEnglish, 'مستخدم'), value: used, color: _amber)]),
                const SizedBox(height: 10),
                Row(children: [_BalCard(label: tr(widget.isEnglish, 'متبقي'), value: remaining, color: _green)]),
              ],
            )
          else
            Row(
              children: [
                _BalCard(label: tr(widget.isEnglish, 'الرصيد'), value: quota, color: _indigo),
                const SizedBox(width: 10),
                _BalCard(label: tr(widget.isEnglish, 'مستخدم'), value: used, color: _amber),
                const SizedBox(width: 10),
                _BalCard(label: tr(widget.isEnglish, 'متبقي'), value: remaining, color: _green),
              ],
            ),
          const SizedBox(height: 16),

          if (_showForm) ...[
            _LeaveForm(
              type: _type, start: _start, end: _end,
              reasonCtrl: _reasonCtrl, submitting: _submitting,
              isEnglish: widget.isEnglish,
              onTypeChanged: (v) => setState(() => _type = v),
              onStartPicked: (d) => setState(() => _start = d),
              onEndPicked: (d) => setState(() => _end = d),
              onSubmit: _submit,
            ),
            const SizedBox(height: 16),
          ],

          Text(tr(widget.isEnglish, 'سجل الطلبات'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                  color: Color(0xCCFFFFFF))),
          const SizedBox(height: 10),

          if (isMobile)
            _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator(color: _indigo)),
                  )
                : _requests.isEmpty
                    ? _empty(tr(widget.isEnglish, 'لا توجد طلبات إجازات'))
                    : Column(
                        children: [
                          for (int i = 0; i < _requests.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _buildRequestItem(_requests[i], isMobile),
                          ],
                        ],
                      )
          else
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _indigo))
                  : _requests.isEmpty
                      ? _empty(tr(widget.isEnglish, 'لا توجد طلبات إجازات'))
                      : ListView.separated(
                          itemCount: _requests.length,
                          separatorBuilder: (context, idx) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _buildRequestItem(_requests[i], isMobile),
                        ),
            ),
        ],
      );

    return isMobile
        ? SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: body,
          )
        : Padding(
            padding: const EdgeInsets.all(20),
            child: body,
          );
  }

  Widget _buildRequestItem(Map<String, dynamic> r, bool isMobile) {
    final status = r['status'] as String? ?? '';
    final sc = _statusColor(status);
    final icon = Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: _indigo.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.beach_access_outlined,
          color: _indigo, size: 18),
    );
    final title = Text(
        '${tr(widget.isEnglish, r['type'] as String? ?? '')} — ${r['days_count']} '
        '${tr(widget.isEnglish, 'أيام')}',
        style: const TextStyle(fontWeight: FontWeight.w600,
            fontSize: 14, color: Colors.white));
    final dates = Text('${r['start_date']}  →  ${r['end_date']}',
        style: const TextStyle(fontSize: 12,
            color: Color(0x99FFFFFF)));
    final reasonText = r['reason'] != null
        ? Text('${tr(widget.isEnglish, 'السبب')}: ${r['reason']}',
            style: const TextStyle(fontSize: 11,
                color: Color(0x66FFFFFF)))
        : null;
    final adminNotes = r['admin_notes'] as String?;
    final adminNoteText = (adminNotes != null && adminNotes.isNotEmpty)
        ? Text('${tr(widget.isEnglish, 'ملاحظة الإدارة')}: $adminNotes',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sc))
        : null;
    final badge = _StatusBadge(label: tr(widget.isEnglish, status), color: sc);

    return _Card(
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(child: title),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [dates, badge],
                ),
                if (reasonText != null) ...[
                  const SizedBox(height: 4),
                  reasonText,
                ],
                if (adminNoteText != null) ...[
                  const SizedBox(height: 4),
                  adminNoteText,
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 3),
                      dates,
                      if (reasonText != null) ...[
                        const SizedBox(height: 2),
                        reasonText,
                      ],
                      if (adminNoteText != null) ...[
                        const SizedBox(height: 2),
                        adminNoteText,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                badge,
              ],
            ),
    );
  }
}

// ── Balance Card ──────────────────────────────────────────
class _BalCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _BalCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Color(0x99FFFFFF))),
          ],
        ),
      ),
    );
  }
}

class _LeaveForm extends StatelessWidget {
  final String type;
  final DateTime? start;
  final DateTime? end;
  final TextEditingController reasonCtrl;
  final bool submitting;
  final bool isEnglish;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<DateTime> onStartPicked;
  final ValueChanged<DateTime> onEndPicked;
  final VoidCallback onSubmit;

  const _LeaveForm({
    required this.type, required this.start, required this.end,
    required this.reasonCtrl, required this.submitting, required this.isEnglish,
    required this.onTypeChanged, required this.onStartPicked,
    required this.onEndPicked, required this.onSubmit,
  });

  static const _types = ['سنوية', 'مرضية', 'طارئة', 'بدون راتب', 'أخرى'];
  static const _indigo = Color(0xFF06B6D4);

  String _fmt(DateTime? d) =>
      d == null ? tr(isEnglish, 'اختر') : intl.DateFormat('yyyy-MM-dd').format(d);

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _indigo.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _indigo.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(isEnglish, 'طلب إجازة جديدة'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 10),
              Builder(builder: (context) {
                final typeField = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(tr(isEnglish, 'نوع الإجازة')),
                    _inputWrap(
                      child: DropdownButton<String>(
                        value: type,
                        isExpanded: true,
                        isDense: true,
                        dropdownColor: const Color(0xFF123540),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        underline: const SizedBox(),
                        items: _types.map((t) => DropdownMenuItem(value: t, child: Text(tr(isEnglish, t)))).toList(),
                        onChanged: (v) { if (v != null) onTypeChanged(v); },
                      ),
                    ),
                  ],
                );
                final startField = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(tr(isEnglish, 'من تاريخ')),
                    _DateBtn(text: _fmt(start), onTap: () async {
                      final today = DateTime.now();
                      final d = await showDatePicker(context: context,
                          initialDate: start ?? today,
                          firstDate: today, lastDate: DateTime(today.year + 2, 12, 31));
                      if (d != null) onStartPicked(d);
                    }),
                  ],
                );
                final endField = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(tr(isEnglish, 'إلى تاريخ')),
                    _DateBtn(text: _fmt(end), onTap: () async {
                      final today = DateTime.now();
                      final d = await showDatePicker(context: context,
                          initialDate: end ?? start ?? today,
                          firstDate: start ?? today, lastDate: DateTime(today.year + 2, 12, 31));
                      if (d != null) onEndPicked(d);
                    }),
                  ],
                );

                if (isMobile) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      typeField,
                      const SizedBox(height: 8),
                      startField,
                      const SizedBox(height: 8),
                      endField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 2, child: typeField),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: startField),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: endField),
                  ],
                );
              }),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final reasonField = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(tr(isEnglish, 'السبب (اختياري)')),
                    TextField(
                      controller: reasonCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 1,
                      decoration: _decor(),
                    ),
                  ],
                );
                final submitBtn = FilledButton(
                  onPressed: submitting ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _indigo,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  ),
                  child: submitting
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(tr(isEnglish, 'إرسال'), style: const TextStyle(fontSize: 13)),
                );

                if (isMobile) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      reasonField,
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: submitBtn),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: reasonField),
                    const SizedBox(width: 8),
                    submitBtn,
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputWrap({required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0x0AFFFFFF),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x1AFFFFFF)),
    ),
    child: child,
  );

  InputDecoration _decor() => InputDecoration(
    filled: true,
    fillColor: const Color(0x0AFFFFFF),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _indigo, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Text(text,
        style: const TextStyle(fontSize: 11, color: Color(0x99FFFFFF),
            fontWeight: FontWeight.w500)),
  );
}

class _DateBtn extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _DateBtn({required this.text, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Text(text,
          style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 13)),
    ),
  );
}

// ── Shared Widgets ─────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0x0AFFFFFF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0x14FFFFFF)),
    ),
    child: child,
  );
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
  );
}

Widget _empty(String msg) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.inbox_outlined, size: 48, color: Colors.white.withValues(alpha: 0.2)),
      const SizedBox(height: 10),
      Text(msg, style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 14)),
    ],
  ),
);
