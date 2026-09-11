import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'portal_client.dart';
import 'portal_i18n.dart';

class AdminMessagesScreen extends StatefulWidget {
  final bool isEnglish;
  const AdminMessagesScreen({super.key, this.isEnglish = false});

  @override
  State<AdminMessagesScreen> createState() => _AdminMessagesScreenState();
}

class _AdminMessagesScreenState extends State<AdminMessagesScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  late final RealtimeChannel _channel;

  static const _indigo = Color(0xFF06B6D4);
  static const _surface = Color(0xFF0D2731);

  @override
  void initState() {
    super.initState();
    _load();
    _channel = portalClient
        .channel('admin-messages-list')
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        portalClient
            .from('portal_messages')
            .select('employee_id, message, sent_at, is_read, sender')
            .order('sent_at', ascending: false),
        portalClient
            .from('employee_profiles')
            .select('id, name, department'),
      ]);

      final messages = List<Map<String, dynamic>>.from(results[0] as List);
      final emps = List<Map<String, dynamic>>.from(results[1] as List);
      final empMap = <String, Map<String, dynamic>>{
        for (final e in emps) e['id'].toString(): e,
      };

      final Map<String, Map<String, dynamic>> convMap = {};
      for (final msg in messages) {
        final empId = msg['employee_id'] as String?;
        if (empId == null) continue;
        if (!convMap.containsKey(empId)) {
          final profile = empMap[empId];
          convMap[empId] = {
            'employee_id': empId,
            'name': profile?['name'] as String? ?? empId,
            'department': profile?['department'] as String? ?? '',
            'last_message': msg['message'] as String? ?? '',
            'last_time': msg['sent_at'] as String? ?? '',
            'unread': 0,
          };
        }
        if (msg['sender'] == 'employee' && msg['is_read'] == false) {
          final cur = convMap[empId]!;
          convMap[empId] = {...cur, 'unread': (cur['unread'] as int) + 1};
        }
      }

      if (mounted) {
        setState(() {
          _conversations = convMap.values.toList()
            ..sort((a, b) {
              final ua = a['unread'] as int;
              final ub = b['unread'] as int;
              if (ua != ub) return ub.compareTo(ua);
              return (b['last_time'] as String)
                  .compareTo(a['last_time'] as String);
            });
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Scaffold(
      backgroundColor: const Color(0xFF061A22),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                isMobile ? 14 : 20, isMobile ? 14 : 20, isMobile ? 14 : 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(widget.isEnglish, 'المراسلات'),
                          style: TextStyle(
                              fontSize: isMobile ? 17 : 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(tr(widget.isEnglish, 'محادثات الموظفين مع الإدارة'),
                          style: TextStyle(
                              fontSize: isMobile ? 11 : 12,
                              color: const Color(0x99FFFFFF))),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh,
                      color: Color(0x99FFFFFF), size: 20),
                  onPressed: _load,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _indigo))
                : _conversations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chat_bubble_outline,
                                size: 52, color: Color(0x22FFFFFF)),
                            const SizedBox(height: 12),
                            Text(tr(widget.isEnglish, 'لا توجد محادثات بعد'),
                                style: const TextStyle(
                                    color: Color(0x66FFFFFF),
                                    fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        itemCount: _conversations.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 6),
                        itemBuilder: (ctx, i) {
                          final conv = _conversations[i];
                          final name = conv['name'] as String;
                          final dept = conv['department'] as String;
                          final lastMsg = conv['last_message'] as String;
                          final lastTime = _formatTime(
                              conv['last_time'] as String);
                          final unread = conv['unread'] as int;

                          return GestureDetector(
                            onTap: () async {
                              await Navigator.push(
                                ctx,
                                MaterialPageRoute(
                                  builder: (_) => AdminChatScreen(
                                    employeeId:
                                        conv['employee_id'] as String,
                                    employeeName: name,
                                    isEnglish: widget.isEnglish,
                                  ),
                                ),
                              );
                              _load();
                            },
                            child: Container(
                              padding: EdgeInsets.all(isMobile ? 10 : 14),
                              decoration: BoxDecoration(
                                color: _surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: unread > 0
                                      ? _indigo.withValues(alpha: 0.4)
                                      : const Color(0x14FFFFFF),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: isMobile ? 38 : 44,
                                    height: isMobile ? 38 : 44,
                                    decoration: BoxDecoration(
                                      color: _indigo.withValues(
                                          alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        name.isNotEmpty ? name[0] : '?',
                                        style: TextStyle(
                                            color: _indigo,
                                            fontWeight: FontWeight.w700,
                                            fontSize: isMobile ? 15 : 18),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: isMobile ? 8 : 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: unread > 0
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                fontSize: isMobile ? 13 : 14),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        if (dept.isNotEmpty)
                                          Text(dept,
                                              style: TextStyle(
                                                  color:
                                                      const Color(0x66FFFFFF),
                                                  fontSize: isMobile ? 10 : 11),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis),
                                        const SizedBox(height: 3),
                                        Text(
                                          lastMsg,
                                          style: TextStyle(
                                              color: unread > 0
                                                  ? const Color(
                                                      0xCCFFFFFF)
                                                  : const Color(
                                                      0x66FFFFFF),
                                              fontSize: isMobile ? 11 : 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: isMobile ? 6 : 8),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Text(lastTime,
                                          style: TextStyle(
                                              color: const Color(0x66FFFFFF),
                                              fontSize: isMobile ? 10 : 11)),
                                      if (unread > 0) ...[
                                        const SizedBox(height: 4),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _indigo,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text('$unread',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
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

class AdminChatScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final bool isEnglish;
  const AdminChatScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.isEnglish = false,
  });

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
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
        .channel('admin-chat-${widget.employeeId}')
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

      await portalClient
          .from('portal_messages')
          .update({'is_read': true})
          .eq('employee_id', widget.employeeId)
          .eq('sender', 'employee');

      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await portalClient.from('portal_messages').insert({
        'employee_id': widget.employeeId,
        'sender': 'admin',
        'message': text,
        'is_read': false,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        _ctrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(widget.isEnglish, 'فشل إرسال الرسالة')),
            backgroundColor: const Color(0xFFF87171),
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
    return Directionality(
      textDirection: widget.isEnglish ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF061A22),
        appBar: AppBar(
          backgroundColor: const Color(0xFF061A22),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white54, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              Container(
                width: isMobile ? 30 : 34,
                height: isMobile ? 30 : 34,
                decoration: BoxDecoration(
                  color: _indigo.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: Text(
                    widget.employeeName.isNotEmpty
                        ? widget.employeeName[0]
                        : '?',
                    style: TextStyle(
                        color: _indigo,
                        fontWeight: FontWeight.w700,
                        fontSize: isMobile ? 13 : 15),
                  ),
                ),
              ),
              SizedBox(width: isMobile ? 8 : 10),
              Flexible(
                child: Text(widget.employeeName,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 14 : 15,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh,
                  color: Color(0x99FFFFFF), size: 20),
              onPressed: _load,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: _loading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: _indigo))
                    : _messages.isEmpty
                        ? Center(
                            child: Text(tr(widget.isEnglish, 'لا توجد رسائل بعد'),
                                style: const TextStyle(
                                    color: Color(0x66FFFFFF),
                                    fontSize: 13)))
                        : ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final m = _messages[i];
                              final isEmp = m['sender'] == 'employee';
                              final text = m['message'] as String? ?? '';
                              final sentAt = m['sent_at'] as String? ?? '';
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
                                  mainAxisAlignment: isEmp
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    if (isEmp)
                                      SizedBox(width: isMobile ? 28 : 52),
                                    Flexible(
                                      child: Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 10),
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
                                                        color: Color(
                                                            0xFF22D3EE),
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight
                                                                .w600)),
                                              ),
                                            if (isEmp)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                        bottom: 4),
                                                child: Text(
                                                    widget.employeeName,
                                                    style: const TextStyle(
                                                        color: Color(
                                                            0xFF34D399),
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight
                                                                .w600)),
                                              ),
                                            Text(text,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
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
                                    if (!isEmp)
                                      SizedBox(width: isMobile ? 28 : 52),
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
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: tr(widget.isEnglish, 'اكتب ردك هنا...'),
                        hintStyle: const TextStyle(
                            color: Color(0x55FFFFFF), fontSize: 13),
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
                        width: isMobile ? 44 : 48,
                        height: isMobile ? 44 : 48,
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
        ),
      ),
    );
  }
}
