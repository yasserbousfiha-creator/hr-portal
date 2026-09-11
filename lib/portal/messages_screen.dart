import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'portal_client.dart';
import 'portal_i18n.dart';

class PortalMessagesScreen extends StatefulWidget {
  final String employeeId;
  final bool isEnglish;
  const PortalMessagesScreen(
      {super.key, required this.employeeId, this.isEnglish = false});

  @override
  State<PortalMessagesScreen> createState() =>
      _PortalMessagesScreenState();
}

class _PortalMessagesScreenState extends State<PortalMessagesScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  late final RealtimeChannel _channel;

  static const _indigo = Color(0xFF06B6D4);
  static const _border = Color(0x14FFFFFF);

  @override
  void initState() {
    super.initState();
    _load();
    _channel = portalClient
        .channel('emp-messages-${widget.employeeId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'portal_messages',
          callback: (_) { if (mounted) _load(); },
        )
        .subscribe();
  }

  @override
  void dispose() {
    portalClient.removeChannel(_channel);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await portalClient
          .from('portal_messages')
          .select()
          .eq('employee_id', widget.employeeId)
          .order('sent_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
      _markRead();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead() async {
    try {
      await portalClient
          .from('portal_messages')
          .update({'is_read': true})
          .eq('employee_id', widget.employeeId)
          .inFilter('sender', ['admin', 'hr'])
          .eq('is_read', false);
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await portalClient.from('portal_messages').insert({
        'employee_id': widget.employeeId,
        'sender': 'employee',
        'message': text,
        'is_read': false,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        _ctrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(widget.isEnglish, 'فشل إرسال الرسالة — يرجى التواصل مع المسؤول لإعداد النظام')),
            backgroundColor: const Color(0xFFF87171),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(widget.isEnglish, 'المراسلات'),
              style: TextStyle(
                  fontSize: isMobile ? 17 : 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 4),
          Text(tr(widget.isEnglish, 'تواصل مع إدارة الموارد البشرية'),
              style: TextStyle(
                  fontSize: isMobile ? 11 : 12,
                  color: const Color(0x99FFFFFF))),
          const SizedBox(height: 16),

          Expanded(
            child: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: _indigo))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                size: 52,
                                color: Colors.white
                                    .withValues(alpha: 0.1)),
                            const SizedBox(height: 14),
                            Text(
                              tr(widget.isEnglish, 'ابدأ محادثة مع الإدارة'),
                              style: const TextStyle(
                                  color: Color(0x66FFFFFF),
                                  fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr(widget.isEnglish, 'يمكنك إرسال أي استفسار أو طلب'),
                              style: const TextStyle(
                                  color: Color(0x44FFFFFF),
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final m = _messages[i];
                          final isEmp = m['sender'] == 'employee';
                          final text =
                              m['message'] as String? ?? '';
                          final sentAt =
                              m['sent_at'] as String? ?? '';
                          // sentAt is like "2025-01-01T14:30:00+03:00"
                          String time = '';
                          try {
                            final dt =
                                DateTime.parse(sentAt).toLocal();
                            time =
                                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                          } catch (_) {}

                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: 10),
                            child: Row(
                              // RTL: start=right, end=left
                              mainAxisAlignment: isEmp
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.end,
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              children: [
                                if (!isEmp)
                                  SizedBox(width: isMobile ? 20 : 52),
                                Flexible(
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 10 : 14,
                                        vertical: isMobile ? 8 : 10),
                                    decoration: BoxDecoration(
                                      color: isEmp
                                          ? const Color(0x0AFFFFFF)
                                          : _indigo.withValues(
                                              alpha: 0.18),
                                      borderRadius:
                                          BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isEmp
                                            ? _border
                                            : _indigo.withValues(
                                                alpha: 0.35),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: isEmp
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        if (!isEmp)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 4),
                                            child: Text(tr(widget.isEnglish, 'الإدارة'),
                                                style: const TextStyle(
                                                    color:
                                                        Color(0xFF22D3EE),
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ),
                                        Text(text,
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize:
                                                    isMobile ? 12 : 13,
                                                height: 1.4)),
                                        const SizedBox(height: 4),
                                        Text(time,
                                            style: const TextStyle(
                                                color:
                                                    Color(0x66FFFFFF),
                                                fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                ),
                                if (isEmp)
                                  SizedBox(width: isMobile ? 20 : 52),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 13 : 14,
                      fontFamily: 'Tajawal'),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: tr(widget.isEnglish, 'اكتب رسالتك هنا...'),
                    hintStyle: TextStyle(
                        color: const Color(0x55FFFFFF),
                        fontSize: isMobile ? 12 : 13,
                        fontFamily: 'Tajawal'),
                    filled: true,
                    fillColor: const Color(0x0AFFFFFF),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _indigo)),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 16,
                        vertical: isMobile ? 10 : 12),
                  ),
                ),
              ),
              SizedBox(width: isMobile ? 8 : 10),
              Material(
                color: _indigo,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _sending ? null : _send,
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: isMobile ? 42 : 48,
                    height: isMobile ? 42 : 48,
                    child: Center(
                      child: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2))
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
