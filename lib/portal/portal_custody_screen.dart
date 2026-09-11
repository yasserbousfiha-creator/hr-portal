import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:supabase_flutter/supabase_flutter.dart';
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
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _showCompleted = false;
  late final RealtimeChannel _channel;

  static const _indigo = Color(0xFF06B6D4);
  static const _green = Color(0xFF34D399);
  static const _amber = Color(0xFFF59E0B);
  static const _blue = Color(0xFF0EA5E9);
  static const _grey = Color(0xFF9CA3AF);

  @override
  void initState() {
    super.initState();
    _load();
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
      final data = await portalClient
          .from('portal_custody_items')
          .select()
          .eq('employee_id', widget.employeeId)
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

  Future<void> _confirmReceived(String id) async {
    try {
      await portalClient.from('portal_custody_items').update({
        'status': 'مستلم',
        'received_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      await _load();
    } catch (_) {}
  }

  Future<void> _initiateReturn(String id) async {
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D2731),
        title: Text(tr(widget.isEnglish, 'إعادة العهدة للإدارة'),
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: 340,
          child: TextField(
            controller: notesCtrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: tr(widget.isEnglish, 'تفاصيل (اختياري) — مثال: لم أعد بحاجته، أو به عطل...'),
              hintStyle: const TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
              filled: true,
              fillColor: const Color(0x0AFFFFFF),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
            ),
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
    );
    if (confirmed != true) return;
    try {
      await portalClient.from('portal_custody_items').update({
        'status': 'قيد الإعادة',
        'return_initiated_at': DateTime.now().toIso8601String(),
        'return_notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
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

  List<Widget> _detailLines(Map<String, dynamic> item) {
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
    if (item['returned_to_admin_at'] != null) {
      lines.add(line(tr(widget.isEnglish, 'تاريخ استلام الإدارة'), _fmtDate(item['returned_to_admin_at'] as String?)));
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
      default:
        return _amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _items.where((t) => t['status'] == 'بانتظار الاستلام').length;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(widget.isEnglish, 'عهدتي'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 2),
          Text(
              widget.isEnglish
                  ? '$pending item(s) awaiting confirmation'
                  : '$pending عنصر بانتظار تأكيد الاستلام',
              style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _indigo))
                : _items.isEmpty
                    ? _empty(tr(widget.isEnglish, 'لا توجد عهد'))
                    : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final active = _items.where((it) => it['status'] != 'أعيدت للإدارة').toList();
    final completed = _items.where((it) => it['status'] == 'أعيدت للإدارة').toList();
    return ListView(
      children: [
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
                  Text('${tr(widget.isEnglish, 'العهد المكتملة')} (${completed.length})',
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

  Widget _itemCard(Map<String, dynamic> it) {
    final status = it['status'] as String? ?? 'بانتظار الاستلام';
    final color = _colorForStatus(status);
    final name = it['equipment_name'] as String? ?? '';
    final notes = it['notes'] as String?;
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
                                      width: 38, height: 38,
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
                                      child: Text(tr(widget.isEnglish, status),
                                          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                                ..._detailLines(it),
                                if (status == 'بانتظار الاستلام') ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: FilledButton.icon(
                                      onPressed: () => _confirmReceived(it['id'] as String),
                                      icon: const Icon(Icons.check_circle_outline, size: 16),
                                      label: Text(tr(widget.isEnglish, 'تم الاستلام'), style: const TextStyle(fontSize: 13)),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _green,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ] else if (status == 'مستلم') ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _initiateReturn(it['id'] as String),
                                      icon: const Icon(Icons.assignment_return_outlined, size: 16),
                                      label: Text(tr(widget.isEnglish, 'إعادة العهدة للإدارة'), style: const TextStyle(fontSize: 13)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _blue,
                                        side: BorderSide(color: _blue.withValues(alpha: 0.5)),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
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
