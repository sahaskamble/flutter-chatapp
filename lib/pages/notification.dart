import 'package:flutter/material.dart';
import 'package:flutter_application_1/db/pb.dart';
import 'package:pocketbase/pocketbase.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<RecordModel> _unreadMessages = [];
  bool _loading = true;
  UnsubscribeFunc? _unsubscribe;
  final String _currentUserId = pb.authStore.record!.id;

  @override
  void initState() {
    super.initState();
    _loadUnreadMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  Future<void> _loadUnreadMessages() async {
    try {
      final result = await pb.collection('messages').getList(
        sort: '-created',
        filter:
            'read = false && sender.id != "$_currentUserId" && conversation.participants.id ?= "$_currentUserId"',
        expand: 'sender,conversation',
        perPage: 50,
      );
      if (mounted) {
        setState(() {
          _unreadMessages = result.items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _subscribeToMessages() async {
    _unsubscribe = await pb
        .collection('messages')
        .subscribe('*', (e) => _loadUnreadMessages());
  }

  Future<void> _markAsRead(RecordModel message) async {
    try {
      await pb.collection('messages').update(message.id, body: {'read': true});
      if (mounted) {
        setState(() => _unreadMessages.removeWhere((m) => m.id == message.id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      for (final msg in List<RecordModel>.from(_unreadMessages)) {
        await pb.collection('messages').update(msg.id, body: {'read': true});
      }
      if (mounted) setState(() => _unreadMessages.clear());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  RecordModel? _getSender(RecordModel message) {
    final raw = message.expand['sender'];
    if (raw == null || raw.isEmpty) return null;
    final item = raw.first;
    if (item is RecordModel) return item;
    try {
      return RecordModel.fromJson(Map<String, dynamic>.from(item as Map));
    } catch (_) {
      return null;
    }
  }

  RecordModel? _getConversation(RecordModel message) {
    final raw = message.expand['conversation'];
    if (raw == null || raw.isEmpty) return null;
    final item = raw.first;
    if (item is RecordModel) return item;
    try {
      return RecordModel.fromJson(Map<String, dynamic>.from(item as Map));
    } catch (_) {
      return null;
    }
  }

  String _formatTime(String dateStr) {
    try {
      final date = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays == 1) return 'Yesterday';
      return '${date.day}/${date.month}';
    } catch (_) {
      return '';
    }
  }

  String _getInitial(String name) =>
      name.isNotEmpty ? name[0].toUpperCase() : '?';

  Color _colorFromName(String name) {
    const colors = [
      Color(0xFF1565C0),
      Color(0xFF6A1B9A),
      Color(0xFF00695C),
      Color(0xFFAD1457),
      Color(0xFFE65100),
      Color(0xFF37474F),
    ];
    return colors[name.isNotEmpty ? name.codeUnitAt(0) % colors.length : 0];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notifications',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0D1B2A),
              ),
            ),
            if (_unreadMessages.isNotEmpty)
              Text(
                '${_unreadMessages.length} unread',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF1565C0),
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          if (_unreadMessages.isNotEmpty)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: Color(0xFF1565C0),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFF0F0F0)),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1565C0)),
            )
          : _unreadMessages.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadUnreadMessages,
                  color: const Color(0xFF1565C0),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _unreadMessages.length,
                    itemBuilder: (context, index) =>
                        _buildNotificationTile(_unreadMessages[index]),
                  ),
                ),
    );
  }

  Widget _buildNotificationTile(RecordModel message) {
    final sender = _getSender(message);
    final senderName = sender?.data['name'] ?? sender?.data['username'] ?? 'Someone';
    final content = message.data['content'] as String? ?? '';
    final time = _formatTime(message.data['created'] as String? ?? '');
    final color = _colorFromName(senderName);

    return Dismissible(
      key: Key(message.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _markAsRead(message),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1565C0).withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.done_all_rounded, color: Color(0xFF1565C0)),
      ),
      child: GestureDetector(
        onTap: () => _markAsRead(message),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF1565C0).withOpacity(0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withOpacity(0.12),
                child: Text(
                  _getInitial(senderName),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            senderName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Color(0xFF0D1B2A),
                            ),
                          ),
                        ),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      content,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF1565C0),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'All caught up!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No unread messages',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}
