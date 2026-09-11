import 'package:flutter/material.dart';
import 'portal_client.dart';
import 'portal_i18n.dart';

class PortalAdvancesScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final bool isEnglish;
  const PortalAdvancesScreen({super.key, required this.employeeId, required this.employeeName, this.isEnglish = false});

  @override
  State<PortalAdvancesScreen> createState() => _PortalAdvancesScreenState();
}

class _PortalAdvancesScreenState extends State<PortalAdvancesScreen> {
  List<Map<String, dynamic>> _advances = [];
  bool _loading = true;
  bool _showForm = false;

  final _amountCtrl = TextEditingController();
  final _deductCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;

  static const _indigo = Color(0xFF06B6D4);
  static const _green = Color(0xFF34D399);
  static const _amber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await portalClient
          .from('advance_requests')
          .select()
          .eq('employee_id', widget.employeeId)
          .order('submitted_at', ascending: false);
      if (mounted) {
        setState(() {
          _advances = List<Map<String, dynamic>>.from(data as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) { setState(() => _loading = false); }
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text);
    final deduct = double.tryParse(_deductCtrl.text);
    if (amount == null || amount <= 0) { _snack(tr(widget.isEnglish, 'أدخل مبلغاً صحيحاً')); return; }
    if (deduct == null || deduct <= 0) { _snack(tr(widget.isEnglish, 'أدخل مبلغ الاستقطاع الشهري')); return; }
    if (deduct > amount) { _snack(tr(widget.isEnglish, 'الاستقطاع الشهري لا يمكن أن يكون أكثر من إجمالي السلفة')); return; }

    final months = (amount / deduct).ceil();
    if (months > 24) {
      _snack(tr(widget.isEnglish, 'مدة السداد تتجاوز 24 شهراً — يرجى رفع مبلغ الاستقطاع الشهري'));
      return;
    }

    final blocked = _advances.where((a) {
      final s = a['status'] as String? ?? '';
      return s == 'قيد المراجعة' || s == 'موافق عليها';
    }).toList();
    if (blocked.isNotEmpty) {
      final s = blocked.first['status'] as String;
      _snack(widget.isEnglish
          ? 'You already have an advance ${tr(widget.isEnglish, s)} — it must be repaid before requesting a new one'
          : 'لديك سلفة $s بالفعل — يجب تسديدها قبل طلب سلفة جديدة');
      return;
    }

    setState(() => _submitting = true);
    try {
      await portalClient.from('advance_requests').insert({
        'employee_id': widget.employeeId,
        'employee_name': widget.employeeName,
        'amount': amount,
        'remaining_amount': amount,
        'monthly_deduction': deduct,
        'reason': _reasonCtrl.text.isEmpty ? null : _reasonCtrl.text,
        'status': 'قيد المراجعة',
        'is_local_sync': false,
      });
      if (mounted) {
        setState(() { _showForm = false; _submitting = false; });
        _amountCtrl.clear(); _deductCtrl.clear(); _reasonCtrl.clear();
        _snack(tr(widget.isEnglish, 'تم إرسال طلب السلفة ✓'));
        _load();
      }
    } catch (e) {
      if (mounted) { setState(() => _submitting = false); _snack(widget.isEnglish ? 'Error: $e' : 'خطأ: $e'); }
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: const Color(0xFF123540)),
  );

  Color _statusColor(String s) {
    if (s == 'موافق عليها') return _green;
    if (s == 'مرفوضة') return const Color(0xFFF87171);
    return _amber;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final totalActive = _advances
        .where((a) => a['status'] == 'موافق عليها')
        .fold<double>(0, (s, a) => s + ((a['remaining_amount'] as num?)?.toDouble() ?? 0));

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr(widget.isEnglish, 'السلف'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                color: Colors.white)),
        const SizedBox(height: 2),
        Text(tr(widget.isEnglish, 'إدارة سلفك وطلباتك'),
            style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
      ],
    );
    final requestButton = FilledButton.icon(
      onPressed: () => setState(() => _showForm = !_showForm),
      icon: Icon(_showForm ? Icons.close : Icons.add, size: 16),
      label: Text(_showForm ? tr(widget.isEnglish, 'إلغاء') : tr(widget.isEnglish, 'طلب جديد'),
          style: const TextStyle(fontSize: 13)),
      style: FilledButton.styleFrom(
        backgroundColor: _green,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: requestButton),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: titleBlock),
                    requestButton,
                  ],
                ),
          const SizedBox(height: 16),

          if (totalActive > 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _amber.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined,
                        color: _amber, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(widget.isEnglish, 'إجمالي السلف المتبقية'),
                            style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
                        Text('${totalActive.toStringAsFixed(2)} ${tr(widget.isEnglish, 'ريال')}',
                            style: TextStyle(fontSize: isMobile ? 17 : 20,
                                fontWeight: FontWeight.w700, color: _amber)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_showForm) ...[
            _AdvanceForm(
              amountCtrl: _amountCtrl,
              deductCtrl: _deductCtrl,
              reasonCtrl: _reasonCtrl,
              submitting: _submitting,
              isEnglish: widget.isEnglish,
              onSubmit: _submit,
            ),
            const SizedBox(height: 16),
          ],

          Text(tr(widget.isEnglish, 'سجل السلف'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                  color: Color(0xCCFFFFFF))),
          const SizedBox(height: 10),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _indigo))
                : _advances.isEmpty
                    ? _empty(tr(widget.isEnglish, 'لا توجد سلف'))
                    : ListView.separated(
                        itemCount: _advances.length,
                        separatorBuilder: (context, idx) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final a = _advances[i];
                          final status = a['status'] as String? ?? '';
                          final sc = _statusColor(status);
                          final amount = (a['amount'] as num?)?.toDouble() ?? 0;
                          final remaining = (a['remaining_amount'] as num?)?.toDouble() ?? 0;
                          final monthly = (a['monthly_deduction'] as num?)?.toDouble() ?? 0;
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0x0AFFFFFF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0x14FFFFFF)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: _green.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.account_balance_wallet_outlined,
                                      color: _green, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${amount.toStringAsFixed(0)} ${tr(widget.isEnglish, 'ريال')}',
                                          style: const TextStyle(fontSize: 15,
                                              fontWeight: FontWeight.w700, color: Colors.white)),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${tr(widget.isEnglish, 'المتبقي')}: ${remaining.toStringAsFixed(0)} ${tr(widget.isEnglish, 'ريال')}'
                                        '  •  ${tr(widget.isEnglish, 'شهري')}: ${monthly.toStringAsFixed(0)} ${tr(widget.isEnglish, 'ريال')}',
                                        style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF)),
                                      ),
                                      if (a['reason'] != null) ...[
                                        const SizedBox(height: 2),
                                        Text('${tr(widget.isEnglish, 'السبب')}: ${a['reason']}',
                                            style: const TextStyle(fontSize: 11,
                                                color: Color(0x66FFFFFF))),
                                      ],
                                      if (a['admin_notes'] != null &&
                                          (a['admin_notes'] as String).isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                            '${tr(widget.isEnglish, 'ملاحظة الإدارة')}: ${a['admin_notes']}',
                                            style: TextStyle(fontSize: 11,
                                                fontWeight: FontWeight.w600, color: sc)),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _StatusBadge(label: tr(widget.isEnglish, status), color: sc),
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

class _AdvanceForm extends StatelessWidget {
  final TextEditingController amountCtrl;
  final TextEditingController deductCtrl;
  final TextEditingController reasonCtrl;
  final bool submitting;
  final bool isEnglish;
  final VoidCallback onSubmit;

  const _AdvanceForm({
    required this.amountCtrl, required this.deductCtrl,
    required this.reasonCtrl, required this.submitting, required this.isEnglish,
    required this.onSubmit,
  });

  static const _green = Color(0xFF34D399);

  InputDecoration _d(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0x99FFFFFF), fontSize: 13),
    filled: true,
    fillColor: const Color(0x0AFFFFFF),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _green, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final amountField = TextField(controller: amountCtrl, keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: _d(tr(isEnglish, 'المبلغ المطلوب (ريال)')));
    final deductField = TextField(controller: deductCtrl, keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: _d(tr(isEnglish, 'الاستقطاع الشهري (ريال)')));

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(isEnglish, 'طلب سلفة جديدة'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 12),
          isMobile
              ? Column(
                  children: [
                    amountField,
                    const SizedBox(height: 10),
                    deductField,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: amountField),
                    const SizedBox(width: 10),
                    Expanded(child: deductField),
                  ],
                ),
          const SizedBox(height: 10),
          TextField(controller: reasonCtrl, maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _d(tr(isEnglish, 'السبب (اختياري)'))),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: submitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: submitting
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : Text(tr(isEnglish, 'إرسال الطلب'),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
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
    child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
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
