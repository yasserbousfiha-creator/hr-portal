import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'portal_client.dart';
import 'portal_i18n.dart';

const _dialogBg = Color(0xFF0D2731);
const _accent = Color(0xFF06B6D4);
const _muted = Color(0x99FFFFFF);
const _faint = Color(0x66FFFFFF);

/// What the employee entered in a custody step dialog.
class CustodyStepResult {
  final List<String> accessories;
  final String? notes;
  final String? toEmployeeId;
  const CustodyStepResult({
    required this.accessories,
    this.notes,
    this.toEmployeeId,
  });
}

/// One dialog for every custody step: confirm receipt, hand over to a
/// colleague, accept / reject a handover, return to management.
///
/// [colleagues] non-null means the employee MUST pick one of those real
/// employees (there is no free-text name) — the server re-validates the pick.
Future<CustodyStepResult?> showCustodyStepDialog(
  BuildContext context, {
  required bool isEnglish,
  required String title,
  required String confirmLabel,
  List<String> accessories = const [],
  bool showAccessories = true,
  bool allowAddAccessory = false,
  List<Map<String, dynamic>>? colleagues,
  String? notesHint,
}) {
  return showDialog<CustodyStepResult>(
    context: context,
    builder: (_) => _StepDialog(
      isEnglish: isEnglish,
      title: title,
      confirmLabel: confirmLabel,
      accessories: accessories,
      showAccessories: showAccessories,
      allowAddAccessory: allowAddAccessory,
      colleagues: colleagues,
      notesHint: notesHint,
    ),
  );
}

class _StepDialog extends StatefulWidget {
  final bool isEnglish;
  final String title;
  final String confirmLabel;
  final List<String> accessories;
  final bool showAccessories;
  final bool allowAddAccessory;
  final List<Map<String, dynamic>>? colleagues;
  final String? notesHint;
  const _StepDialog({
    required this.isEnglish,
    required this.title,
    required this.confirmLabel,
    required this.accessories,
    required this.showAccessories,
    required this.allowAddAccessory,
    required this.colleagues,
    required this.notesHint,
  });

  @override
  State<_StepDialog> createState() => _StepDialogState();
}

class _StepDialogState extends State<_StepDialog> {
  late final List<String> _all = List<String>.from(widget.accessories);
  late final Set<String> _checked = Set<String>.from(widget.accessories);
  final _addCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String? _selectedId;

  @override
  void dispose() {
    _addCtrl.dispose();
    _notesCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _isEn => widget.isEnglish;

  void _addAccessory() {
    final v = _addCtrl.text.trim();
    if (v.isEmpty || _all.contains(v)) return;
    setState(() {
      _all.add(v);
      _checked.add(v);
      _addCtrl.clear();
    });
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _faint, fontSize: 12),
        filled: true,
        fillColor: const Color(0x0AFFFFFF),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
        ),
      );

  Widget _label(String ar) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(tr(_isEn, ar),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _muted)),
      );

  @override
  Widget build(BuildContext context) {
    final colleagues = widget.colleagues;
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = colleagues == null
        ? const <Map<String, dynamic>>[]
        : colleagues
            .where((c) => q.isEmpty || (c['name'] as String? ?? '').toLowerCase().contains(q))
            .toList();
    final canConfirm = colleagues == null || _selectedId != null;

    return AlertDialog(
      backgroundColor: _dialogBg,
      title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (colleagues != null) ...[
                _label('اختر الزميل (موظف موجود فعليًا)'),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _dec(tr(_isEn, 'ابحث بالاسم...')),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 170,
                  decoration: BoxDecoration(
                    color: const Color(0x08FFFFFF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x14FFFFFF)),
                  ),
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(tr(_isEn, 'لا يوجد زميل بهذا الاسم'),
                              style: const TextStyle(color: _faint, fontSize: 12)))
                      : ListView(
                          children: filtered.map((c) {
                            final id = c['id'].toString();
                            final sel = id == _selectedId;
                            return InkWell(
                              onTap: () => setState(() => _selectedId = id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                color: sel ? _accent.withValues(alpha: 0.15) : null,
                                child: Row(
                                  children: [
                                    Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
                                        size: 16, color: sel ? _accent : _faint),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(c['name'] as String? ?? id,
                                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
              if (widget.showAccessories) ...[
                _label('الملحقات'),
                if (_all.isEmpty)
                  Text(tr(_isEn, 'لا توجد ملحقات مسجّلة'),
                      style: const TextStyle(color: _faint, fontSize: 12))
                else
                  ..._all.map((a) => InkWell(
                        onTap: () => setState(() {
                          if (!_checked.remove(a)) _checked.add(a);
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Icon(_checked.contains(a) ? Icons.check_box : Icons.check_box_outline_blank,
                                  size: 18, color: _checked.contains(a) ? _accent : _faint),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(a,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _checked.contains(a) ? Colors.white : _faint,
                                      decoration: _checked.contains(a) ? null : TextDecoration.lineThrough,
                                    )),
                              ),
                            ],
                          ),
                        ),
                      )),
                if (widget.allowAddAccessory) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addCtrl,
                          onSubmitted: (_) => _addAccessory(),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: _dec(tr(_isEn, 'إضافة ملحق (مثال: شاحن، حقيبة)')),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: _addAccessory,
                        icon: const Icon(Icons.add_circle_outline, color: _accent),
                        tooltip: tr(_isEn, 'إضافة'),
                      ),
                    ],
                  ),
                ],
              ],
              _label('ملاحظات'),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _dec(tr(_isEn, widget.notesHint ?? 'ملاحظات (اختياري)')),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(_isEn, 'إلغاء'), style: const TextStyle(color: _muted)),
        ),
        FilledButton(
          onPressed: canConfirm
              ? () => Navigator.pop(
                    context,
                    CustodyStepResult(
                      accessories: _all.where(_checked.contains).toList(),
                      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
                      toEmployeeId: _selectedId,
                    ),
                  )
              : null,
          style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Read-only chips for a custody item's accessory list.
class AccessoryChips extends StatelessWidget {
  final List<dynamic> accessories;
  const AccessoryChips({super.key, required this.accessories});

  @override
  Widget build(BuildContext context) {
    if (accessories.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: accessories
          .map((a) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _accent.withValues(alpha: 0.25)),
                ),
                child: Text(a.toString(),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF67E8F9))),
              ))
          .toList(),
    );
  }
}

/// Vertical history of one custody item, read from portal_custody_events
/// (RLS: an employee sees items they hold/held or were handed; admin sees all).
class CustodyTimeline extends StatefulWidget {
  final String itemId;
  final bool isEnglish;
  final Map<String, String> names;
  const CustodyTimeline({
    super.key,
    required this.itemId,
    required this.isEnglish,
    required this.names,
  });

  @override
  State<CustodyTimeline> createState() => _CustodyTimelineState();
}

class _CustodyTimelineState extends State<CustodyTimeline> {
  List<Map<String, dynamic>>? _events;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await portalClient
          .from('portal_custody_events')
          .select()
          .eq('item_id', widget.itemId)
          .order('created_at', ascending: true);
      if (mounted) setState(() => _events = List<Map<String, dynamic>>.from(data as List));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _name(dynamic id) {
    if (id == null) return widget.isEnglish ? 'management' : 'الإدارة';
    final s = id.toString();
    return widget.names[s] ?? (widget.isEnglish ? 'a colleague' : 'زميل');
  }

  (IconData, Color, String) _describe(Map<String, dynamic> e) {
    final from = _name(e['from_employee_id']);
    final to = _name(e['to_employee_id']);
    final en = widget.isEnglish;
    switch (e['event_type']) {
      case 'assigned':
        return (Icons.outbox_outlined, const Color(0xFFF59E0B),
            en ? 'Assigned by management to $to' : 'سُلّمت من الإدارة إلى $to');
      case 'received':
        return (Icons.check_circle_outline, const Color(0xFF34D399),
            en ? '$to confirmed receipt' : 'أكّد $to الاستلام');
      case 'handover_initiated':
        return (Icons.swap_horiz, const Color(0xFF8B5CF6),
            en ? '$from handed it to $to (awaiting receipt)' : 'سلّمها $from إلى $to (بانتظار الاستلام)');
      case 'handover_accepted':
        return (Icons.how_to_reg_outlined, const Color(0xFF34D399),
            en ? '$to received it from $from' : 'استلمها $to من $from');
      case 'handover_rejected':
        return (Icons.block, const Color(0xFFF87171),
            en ? '$from declined the handover from $to' : 'رفض $from الاستلام من $to');
      case 'handover_cancelled':
        return (Icons.undo, const Color(0xFF9CA3AF),
            en ? '$from cancelled the handover to $to' : 'ألغى $from التسليم إلى $to');
      case 'return_initiated':
        return (Icons.assignment_return_outlined, const Color(0xFF0EA5E9),
            en ? '$from started returning it to management' : 'بدأ $from إعادتها للإدارة');
      case 'returned_to_admin':
        return (Icons.inventory_2_outlined, const Color(0xFF9CA3AF),
            en ? 'Management received it from $from' : 'استلمتها الإدارة من $from');
      default:
        return (Icons.circle_outlined, const Color(0xFF9CA3AF), e['event_type']?.toString() ?? '');
    }
  }

  String _fmt(String? iso) {
    if (iso == null) return '';
    try {
      return intl.DateFormat('dd/MM/yyyy — HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(tr(widget.isEnglish, 'تعذّر تحميل السجل'),
            style: const TextStyle(fontSize: 11, color: _faint)),
      );
    }
    final events = _events;
    if (events == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
      );
    }
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(tr(widget.isEnglish, 'لا يوجد سجل'),
            style: const TextStyle(fontSize: 11, color: _faint)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: events.map((e) {
          final (icon, color, text) = _describe(e);
          final acc = (e['accessories'] as List?) ?? const [];
          final notes = e['notes'] as String?;
          final warehouse = e['warehouse'] as String?;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text, style: const TextStyle(fontSize: 12, color: Colors.white)),
                      Text(_fmt(e['created_at'] as String?),
                          style: const TextStyle(fontSize: 10.5, color: _faint)),
                      if (acc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        AccessoryChips(accessories: acc),
                      ],
                      if (warehouse != null && warehouse.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text('${tr(widget.isEnglish, 'المستودع')}: $warehouse',
                              style: const TextStyle(fontSize: 11, color: _muted)),
                        ),
                      if (notes != null && notes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(notes, style: const TextStyle(fontSize: 11, color: _muted)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
