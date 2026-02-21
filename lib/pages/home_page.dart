import 'package:flutter/material.dart';
import 'package:flutter_application_1/components/BadgeIcon.dart';
import 'package:flutter_application_1/db/pb.dart';
import 'package:flutter_application_1/pages/chat_page.dart';
import 'package:flutter_application_1/pages/new_chat_page.dart';
import 'package:flutter_application_1/pages/notifications_page.dart';
import 'package:flutter_application_1/pages/profile_page.dart';
import 'package:flutter_application_1/services/presence_service.dart';
import 'package:pocketbase/pocketbase.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  bool _isSearching = false;

  List<RecordModel> _conversations = [];
  List<RecordModel> _onlineUsers = [];
  bool _loadingConversations = true;
  bool _loadingOnlineUsers = true;

  late AnimationController _fabAnimController;
  late Animation<double> _fabScaleAnim;

  UnsubscribeFunc? _unsubscribeConversations;
  UnsubscribeFunc? _unsubscribeUsers;
  UnsubscribeFunc? _unsubscribeMessages;
  late PresenceService _presenceService;
  int _unreadCount = 0;

  final String _currentUserId = pb.authStore.record!.id;

  @override
  void initState() {
    super.initState();
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fabScaleAnim = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.elasticOut,
    );
    _fabAnimController.forward();

    // Start presence heartbeat — marks user online and keeps it fresh every 30s
    _presenceService = PresenceService(_currentUserId);
    _presenceService.init();

    _loadConversations();
    _loadOnlineUsers();
    _loadUnreadCount();
    _subscribeToConversations();
    _subscribeToUsers();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _presenceService.dispose(); // marks offline + cancels heartbeat
    _fabAnimController.dispose();
    _searchController.dispose();
    _unsubscribeConversations?.call();
    _unsubscribeUsers?.call();
    _unsubscribeMessages?.call();
    super.dispose();
  }

  // ── Data Fetching ──────────────────────────────────────────────

  Future<void> _loadConversations() async {
    try {
      final result = await pb
          .collection('conversations')
          .getList(
            sort: '-last_message_at',
            filter: 'participants.id ?= "$_currentUserId"',
            expand: 'participants,last_message',
          );
      if (mounted) {
        setState(() {
          _conversations = result.items;
          _loadingConversations = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingConversations = false);
    }
  }

  Future<void> _loadOnlineUsers() async {
    try {
      // Fetch users marked online whose last_seen was within the last 90s
      // (gives a buffer over the 60s UI threshold). Post-filter with
      // PresenceService.isOnline() for the precise check.
      final threshold = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 90))
          .toIso8601String();
      final result = await pb
          .collection('users')
          .getList(
            filter:
                'status = "online" && id != "$_currentUserId" && last_seen >= "$threshold"',
            sort: '-last_seen',
            perPage: 20,
          );
      if (mounted) {
        setState(() {
          // Final guard: discard any that don't pass the strict 60s check
          _onlineUsers = result.items
              .where((u) => PresenceService.isOnline(u.data))
              .toList();
          _loadingOnlineUsers = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingOnlineUsers = false);
    }
  }

  // ── Real-time Subscriptions ────────────────────────────────────

  Future<void> _subscribeToConversations() async {
    _unsubscribeConversations = await pb
        .collection('conversations')
        .subscribe('*', (e) => _loadConversations());
  }

  Future<void> _subscribeToUsers() async {
    _unsubscribeUsers = await pb
        .collection('users')
        .subscribe('*', (e) => _loadOnlineUsers());
  }

  Future<void> _loadUnreadCount() async {
    try {
      final result = await pb
          .collection('messages')
          .getList(
            filter:
                'read = false && sender.id != "$_currentUserId" && conversation.participants.id ?= "$_currentUserId"',
            perPage: 1, // we only need the totalItems count
          );
      if (mounted) setState(() => _unreadCount = result.totalItems);
    } catch (_) {}
  }

  Future<void> _subscribeToMessages() async {
    _unsubscribeMessages = await pb
        .collection('messages')
        .subscribe('*', (_) => _loadUnreadCount());
  }

  // ── Helpers ────────────────────────────────────────────────────

  RecordModel? _getOtherParticipant(RecordModel conversation) {
    final participants = conversation.expand['participants'];
    if (participants == null || participants.isEmpty) return null;
    try {
      return participants.firstWhere((p) => p.id != _currentUserId);
    } catch (_) {
      return participants.isNotEmpty ? participants.first : null;
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
      Color(0xFF0277BD),
      Color(0xFF558B2F),
    ];
    final index = name.isNotEmpty ? name.codeUnitAt(0) % colors.length : 0;
    return colors[index];
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) {
        final h = date.hour.toString().padLeft(2, '0');
        final m = date.minute.toString().padLeft(2, '0');
        return '$h:$m';
      }
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) {
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return days[date.weekday - 1];
      }
      return '${date.day}/${date.month}';
    } catch (_) {
      return '';
    }
  }

  List<RecordModel> get _filteredConversations {
    if (!_isSearching || _searchController.text.isEmpty) return _conversations;
    final q = _searchController.text.toLowerCase();
    return _conversations.where((c) {
      final other = _getOtherParticipant(c);
      final name = (other?.data['name'] ?? other?.data['username'] ?? '')
          .toLowerCase();
      final lastMsg =
          (c.expand['last_message']?.firstOrNull?.data['content'] ?? '')
              .toLowerCase();
      return name.contains(q) || lastMsg.contains(q);
    }).toList();
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadConversations();
                await _loadOnlineUsers();
              },
              color: const Color(0xFF1565C0),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  if (!_loadingOnlineUsers && _onlineUsers.isNotEmpty)
                    SliverToBoxAdapter(child: _buildOnlineUsersSection()),
                  SliverToBoxAdapter(child: _buildConversationsHeader()),
                  if (_loadingConversations)
                    const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    )
                  else if (_filteredConversations.isEmpty)
                    SliverFillRemaining(child: _buildEmptyState())
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildConversationTile(
                          _filteredConversations[index],
                        ),
                        childCount: _filteredConversations.length,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScaleAnim,
        child: FloatingActionButton(
          onPressed: () async {
            final conv = await Navigator.push<RecordModel>(
              context,
              MaterialPageRoute(builder: (_) => const NewChatPage()),
            );
            // NewChatPage returns the conversation (new or existing).
            // Reload so it bubbles to the top of the list.
            if (conv != null && mounted) await _loadConversations();
          },
          backgroundColor: const Color(0xFF1565C0),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.edit_rounded, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Messages',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0D1B2A),
          letterSpacing: -0.5,
        ),
      ),
      actions: [
        IconButton(
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFE8F0FE),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            );
            // Refresh unread count when returning from notifications
            if (mounted) _loadUnreadCount();
          },
          icon: BadgeIcon(
            icon: const Icon(
              Icons.notifications_outlined,
              color: Color(0xFF1565C0),
              size: 22,
            ),
            count: _unreadCount,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfilePage()),
          ),
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF1565C0),
              child: Text(
                _getInitial(pb.authStore.record?.data['name'] ?? 'U'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFF0F0F0)),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _isSearching = val.isNotEmpty),
        style: const TextStyle(fontSize: 15, color: Color(0xFF0D1B2A)),
        decoration: InputDecoration(
          hintText: 'Search conversations or people...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF1565C0),
            size: 22,
          ),
          suffixIcon: _isSearching
              ? IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.grey,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _isSearching = false);
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF0F4FF),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineUsersSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00C853),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Active Now',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[600],
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${_onlineUsers.length})',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[400],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 82,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              physics: const BouncingScrollPhysics(),
              itemCount: _onlineUsers.length,
              itemBuilder: (context, index) {
                final user = _onlineUsers[index];
                final name = user.data['name'] ?? user.data['username'] ?? '?';
                final color = _colorFromName(name);
                return GestureDetector(
                  onTap: () async {
                    // Pass the tapped user directly — NewChatPage will find
                    // or create the conversation and pop back with it.
                    final conv = await Navigator.push<RecordModel>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NewChatPage(preselectedUser: user),
                      ),
                    );
                    if (conv != null && mounted) await _loadConversations();
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: color.withOpacity(0.15),
                              child: Text(
                                _getInitial(name),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 13,
                                height: 13,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00C853),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          name.split(' ').first,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0D1B2A),
                          ),
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

  Widget _buildConversationsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Recent Chats',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0D1B2A),
              letterSpacing: -0.3,
            ),
          ),
          Text(
            '${_filteredConversations.length} chats',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationTile(RecordModel conversation) {
    final other = _getOtherParticipant(conversation);
    final name = other?.data['name'] ?? other?.data['username'] ?? 'Unknown';
    final isOnline = other != null && PresenceService.isOnline(other.data);
    final color = _colorFromName(name);

    final lastMessageRecord = conversation.expand['last_message'];
    final lastMessage =
        (lastMessageRecord != null && lastMessageRecord.isNotEmpty)
        ? (lastMessageRecord.first.data['content'] ?? '')
        : 'No messages yet';

    final time = _formatTime(conversation.data['last_message_at'] as String?);

    return GestureDetector(
      onTap: () async {
        final other = _getOtherParticipant(conversation);
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChatPage(conversation: conversation, otherUser: other),
          ),
        );
        // Reload on return — messages may have been read, last_message updated
        if (mounted) {
          _loadConversations();
          _loadUnreadCount();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 6,
          ),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withOpacity(0.12),
                child: Text(
                  _getInitial(name),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              if (isOnline)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C853),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0D1B2A),
                  ),
                ),
              ),
              if (time.isNotEmpty)
                Text(
                  time,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
            ],
          ),
          subtitle: Text(
            lastMessage,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
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
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the pencil icon to start a chat',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}
