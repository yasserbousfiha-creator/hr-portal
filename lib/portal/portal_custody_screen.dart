import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'custody_widgets.dart';
import 'portal_client.dart';
import 'portal_i18n.dart';

class PortalCustodyScreen extends StatefulWidget {
  final String employeeId;
  final bool isEnglish;
  const PortalCustodyScreen({super.key, required this.employeeId, this.isEnglish = false});

  @override
  State<PortalCustodyScreen> createState() => _PortalCustodyScreenState();
}

class _PortalCustodyScreenState extends State<PortalCustodyScreen> {
  static const _handoverPending = 'بانتظار استلام زميل';

  List<Map<String, dynamic>> _items = [];
  // Real, active colleagues with a portal login (server-provided). Also used to
  // turn ids in the history into names.
  List<Map<String, dynamic>> _colleagues = [];
  Map<String, String> _names = {};
  bool _loading = true;
  bool _showCompleted = false;
  final Set<String> _openHistory = {};
  late final RealtimeChannel _channel;

  static const _indigo = Color(0xFF06B6D4);
  static const _green = Color(0xFF34D399);
  static const _amber = Color(0xFFF59E0B);
  static const _blue = Color(0xFF0EA5E9);
  static const _purple = Color(0xFF8B5CF6);
  static const _grey = Color(0xFF9CA3AF);

  bool get _en => widget.isEnglish;
  String get _me => widget.employeeId;

  @override
  void initState() {
    super.initState();
    _load();
    _loadColleagues();
    _channel = portalClient
        .channel('emp-custody-${widget.employeeId}')
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
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Items I hold + items a colleague is handing over to me.
      final data = await portalClient
          .from('portal_custody_items')
          .select()
          .or('employee_id.eq.$_me,pending_transfer_to.eq.$_me')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(data as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadColleagues() async {
    try {
      final rows = await portalClient.rpc('custody_list_colleagues');
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (mounted) {
        setState(() {
          _colleagues = list;
          _names = {for (final c in list) c['id'].toString(): (c['name'] as String? ?? '')};
        });
      }
    } catch (_) {}
  }

  String _nameOf(dynamic id) =>
      _names[id?.toString()] ?? (_en ? 'a colleague' : 'زميل');

  String _utcNow() => DateTime.now().toUtc().toIso8601String();

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFF87171) : _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _rpc(String fn, Map<String, dynamic> params, String okMsg) async {
    try {
      await portalClient.rpc(fn, params: params);
      _snack(tr(_en, okMsg));
      await _load();
    } catch (_) {
      _snack(tr(_en, 'تعذّر تنفيذ العملية'), error: true);
      await _load();
    }
  }

  List<String> _accessoriesOf(Map<String, dynamic> it) =>
      ((it['accessories'] as List?) ?? const []).map((e) => e.toString()).toList();

  Future<void> _confirmReceived(Map<String, dynamic> it) async {
    final res = await showCustodyStepDialog(
      context,
      isEnglish: _en,
      title: tr(_en, 'تأكيد الاستلام'),
      confirmLabel: tr(_en, 'تم الاستلام'),
      accessories: _accessoriesOf(it),
      allowAddAccessory: true,
      notesHint: 'ملاحظات الاستلام (مثلاً: ملحق ناقص)',
    );
    if (res == null) return;
    try {
      await portalClient.from('portal_custody_items').update({
        'status': 'مستلم',
        'received_at': _utcNow(),
        'accessories': res.accessories,
        'last_accessories': res.accessories,
        'last_notes': res.notes,
      }).eq('id', it['id']);
      _snack(tr(_en, 'تم استلام العهدة'));
      await _load();
    } catch (_) {
      _snack(tr(_en, 'تعذّر تنفيذ العملية'), error: true);
    }
  }

  Future<void> _initiateHandover(Map<String, dynamic> it) async {
    if (_colleagues.isEmpty) {
      await _loadColleagues();
      if (_colleagues.isEmpty) {
        _snack(tr(_en, 'لا يوجد زملاء متاحون للتسليم'), error: true);
        return;
      }
    }
    if (!mounted) return;
    final res = await showCustodyStepDialog(
      context,
      isEnglish: _en,
      title: tr(_en, 'تسليم العهدة لزميل'),
      confirmLabel: tr(_en, 'تسليم'),
      accessories: _accessoriesOf(it),
      allowAddAccessory: true,
      colleagues: _colleagues,
    );
    if (res == null || res.toEmployeeId == null) return;
    await _rpc(
      'custody_start_handover',
      {
        'p_item': it['id'],
        'p_to': res.toEmployeeId,
        'p_accessories': res.accessories,
        'p_notes': res.notes ?? '',
      },
      'تم تسليم العهدة لزميلك بانتظار موافقته',
    );
  }

  Future<void> _acceptHandover(Map<String, dynamic> it) async {
    final res = await showCustodyStepDialog(
      context,
      isEnglish: _en,
      title: tr(_en, 'استلام العهدة من زميل'),
      confirmLabel: tr(_en, 'استلام'),
      accessories: _accessoriesOf(it),
      notesHint: 'ملاحظات الاستلام (مثلاً: ملحق ناقص)',
    );
    if (res == null) return;
    await _rpc(
      'custody_accept_handover',
      {'p_item': it['id'], 'p_accessories': res.accessories, 'p_notes': res.notes ?? ''},
      'تم استلام العهدة',
    );
  }

  Future<void> _rejectHandover(Map<String, dynamic> it) async {
    final res = await showCustodyStepDialog(
      context,
      isEnglish: _en,
      title: tr(_en, 'رفض الاستلام'),
      confirmLabel: tr(_en, 'رفض'),
      showAccessories: false,
      notesHint: 'سبب الرفض (اختياري)',
    );
    if (res == null) return;
    await _rpc(
      'custody_reject_handover',
      {'p_item': it['id'], 'p_notes': res.notes ?? ''},
      'تم رفض التسليم',
    );
  }

  Future<void> _cancelHandover(Map<String, dynamic> it) async {
    await _rpc('custody_cancel_handover', {'p_item': it['id']}, 'تم إلغاء التسليم');
  }

  Future<void> _initiateReturn(Map<String, dynamic> it) async {
    final res = await showCustodyStepDialog(
      context,
      isEnglish: _en,
      title: tr(_en, 'إعادة العهدة للإدارة'),
      confirmLabel: tr(_en, 'تأكيد'),
      accessories: _accessoriesOf(it),
      allowAddAccessory: true,
      notesHint: 'تفاصيل (اختياري) — مثال: لم أعد بحاجته، أو به عطل...',
    );
    if (res == null) return;
    try {
      await portalClient.from('portal_custody_items').update({
        'status': 'قيد الإعادة',
        'return_initiated_at': _utcNow(),
        'return_notes': res.notes,
        'accessories': res.accessories,
        'last_accessories': res.accessories,
        'last_notes': res.notes,
      }).eq('id', it['id']);
      await _load();
    } catch (_) {
      _snack(tr(_en, 'تعذّر تنفيذ العملية'), error: true);
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      return intl.DateFormat('dd/MM/yyyy — HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }

  List<Widget> _detailLines(Map<String, dynamic> item) {
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('$label: $value',
              style: const TextStyle(fontSize: 11, color: Color(0x77FFFFFF))),
        );
    final lines = <Widget>[
      line(tr(_en, 'تاريخ التسليم'), _fmtDate(item['created_at'] as String?)),
    ];
    if (item['received_at'] != null) {
      lines.add(line(tr(_en, 'تاريخ الاستلام'), _fmtDate(item['received_at'] as String?)));
    }
    if (item['return_initiated_at'] != null) {
      lines.add(line(tr(_en, 'تاريخ بدء الإعادة'), _fmtDate(item['return_initiated_at'] as String?)));
    }
    if (item['returned_to_admin_at'] != null) {
      lines.add(line(tr(_en, 'تاريخ استلام الإدارة'), _fmtDate(item['returned_to_admin_at'] as String?)));
    }
    return lines;
  }

  Color _colorForStatus(String status) {
    switch (status) {
      case 'مستلم':
        return _green;
      case 'قيد الإعادة':
        return _blue;
      case 'أعيدت للإدارة':
        return _grey;
      case _handoverPending:
        return _purple;
      default:
        return _amber;
    }
  }

  bool _isIncoming(Map<String, dynamic> it) =>
      it['status'] == _handoverPending && it['pending_transfer_to']?.toString() == _me;

  @override
  Widget build(BuildContext context) {
    final pending = _items
        .where((t) =>
            (t['status'] == 'بانتظار الاستلام' && t['employee_id']?.toString() == _me) ||
            _isIncoming(t))
        .length;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(_en, 'عهدتي'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 2),
          Text(
              _en
                  ? '$pending item(s) awaiting confirmation'
                  : '$pending عنصر بانتظار تأكيد الاستلام',
              style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _indigo))
                : _items.isEmpty
                    ? _empty(tr(_en, 'لا توجد عهد'))
                    : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final incoming = _items.where(_isIncoming).toList();
    final mine = _items.where((it) => it['employee_id']?.toString() == _me).toList();
    final active = mine.where((it) => it['status'] != 'أعيدت للإدارة').toList();
    final completed = mine.where((it) => it['status'] == 'أعيدت للإدارة').toList();
    return ListView(
      children: [
        ...incoming.map((it) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _itemCard(it))),
        ...active.map((it) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _itemCard(it))),
        if (completed.isNotEmpty) ...[
          GestureDetector(
            onTap: () => setState(() => _showCompleted = !_showCompleted),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8, top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x0AFFFFFF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: Row(
                children: [
                  Icon(_showCompleted ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: const Color(0x99FFFFFF)),
                  const SizedBox(width: 8),
                  Text('${tr(_en, 'العهد المكتملة')} (${completed.length})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0x99FFFFFF))),
                ],
              ),
            ),
          ),
          if (_showCompleted)
            ...completed.map((it) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _itemCard(it))),
        ],
      ],
    );
  }

  ButtonStyle _outlined(Color c) => OutlinedButton.styleFrom(
        foregroundColor: c,
        side: BorderSide(color: c.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _actions(Map<String, dynamic> it, String status) {
    if (_isIncoming(it)) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: () => _rejectHandover(it),
            icon: const Icon(Icons.close, size: 16),
            label: Text(tr(_en, 'رفض'), style: const TextStyle(fontSize: 13)),
            style: _outlined(const Color(0xFFF87171)),
          ),
          FilledButton.icon(
            onPressed: () => _acceptHandover(it),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: Text(tr(_en, 'استلام'), style: const TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      );
    }
    if (status == 'بانتظار الاستلام') {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton.icon(
          onPressed: () => _confirmReceived(it),
          icon: const Icon(Icons.check_circle_outline, size: 16),
          label: Text(tr(_en, 'تم الاستلام'), style: const TextStyle(fontSize: 13)),
          style: FilledButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }
    if (status == 'مستلم') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: () => _initiateHandover(it),
            icon: const Icon(Icons.swap_horiz, size: 16),
            label: Text(tr(_en, 'تسليم لزميل'), style: const TextStyle(fontSize: 13)),
            style: _outlined(_purple),
          ),
          OutlinedButton.icon(
            onPressed: () => _initiateReturn(it),
            icon: const Icon(Icons.assignment_return_outlined, size: 16),
            label: Text(tr(_en, 'إعادة العهدة للإدارة'), style: const TextStyle(fontSize: 13)),
            style: _outlined(_blue),
          ),
        ],
      );
    }
    if (status == _handoverPending) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: OutlinedButton.icon(
          onPressed: () => _cancelHandover(it),
          icon: const Icon(Icons.undo, size: 16),
          label: Text(tr(_en, 'إلغاء التسليم'), style: const TextStyle(fontSize: 13)),
          style: _outlined(_grey),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _itemCard(Map<String, dynamic> it) {
    final status = it['status'] as String? ?? 'بانتظار الاستلام';
    final color = _colorForStatus(status);
    final name = it['equipment_name'] as String? ?? '';
    final notes = it['notes'] as String?;
    final id = it['id'].toString();
    final incoming = _isIncoming(it);
    final outgoing = status == _handoverPending && !incoming;
    final accessories = (it['accessories'] as List?) ?? const [];
    final historyOpen = _openHistory.contains(id);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
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
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _indigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.inventory_2_outlined, color: _indigo, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                    if (notes != null && notes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(notes, style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(tr(_en, status),
                    style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (accessories.isNotEmpty) ...[
            const SizedBox(height: 10),
            AccessoryChips(accessories: accessories),
          ],
          if (incoming)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_nameOf(it['employee_id'])} ${tr(_en, 'يريد تسليمك هذه العهدة')}',
                style: TextStyle(fontSize: 12, color: _purple.withValues(alpha: 0.95), fontWeight: FontWeight.w600),
              ),
            ),
          if (outgoing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${tr(_en, 'بانتظار استلام')} ${_nameOf(it['pending_transfer_to'])}',
                style: TextStyle(fontSize: 12, color: _purple.withValues(alpha: 0.95), fontWeight: FontWeight.w600),
              ),
            ),
          ..._detailLines(it),
          const SizedBox(height: 10),
          _actions(it, status),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() {
                if (!_openHistory.remove(id)) _openHistory.add(id);
              }),
              icon: Icon(historyOpen ? Icons.expand_less : Icons.history, size: 15),
              label: Text(tr(_en, historyOpen ? 'إخفاء السجل' : 'سجل العهدة'),
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0x99FFFFFF),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              ),
            ),
          ),
          if (historyOpen)
            CustodyTimeline(
              key: ValueKey('tl-$id-$status-${it['pending_transfer_to']}'),
              itemId: id,
              isEnglish: _en,
              names: {..._names, _me: _en ? 'You' : 'أنت'},
            ),
        ],
      ),
    );
  }
}

Widget _empty(String msg) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.inventory_2_outlined, size: 48, color: Colors.white.withValues(alpha: 0.2)),
      const SizedBox(height: 10),
      Text(msg, style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 14)),
    ],
  ),
);
