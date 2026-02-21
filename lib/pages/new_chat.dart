import 'package:flutter/material.dart';
import 'package:flutter_application_1/db/pb.dart';
import 'package:pocketbase/pocketbase.dart';

class NewChatPage extends StatefulWidget {
  const NewChatPage({super.key});

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final _searchController = TextEditingController();
  List<RecordModel> _users = [];
  List<RecordModel> _filteredUsers = [];
  bool _loading = true;
  bool _creatingChat = false;
  final String _currentUserId = pb.authStore.record!.id;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterUsers);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final result = await pb.collection('users').getList(
        filter: 'id != "$_currentUserId"',
        sort: 'name',
        perPage: 100,
      );
      if (mounted) {
        setState(() {
          _users = result.items;
          _filteredUsers = result.items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filterUsers() {
    final q = _searchController.text.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        _filteredUsers = _users;
      } else {
        _filteredUsers = _users.where((u) {
          final name = (u.data['name'] as String? ?? '').toLowerCase();
          final username = (u.data['username'] as String? ?? '').toLowerCase();
          return name.contains(q) || username.contains(q);
        }).toList();
      }
    });
  }

  Future<void> _startConversation(RecordModel otherUser) async {
    setState(() => _creatingChat = true);
    try {
      // Check if conversation already exists between these two users
      final existing = await pb.collection('conversations').getList(
        filter:
            'participants.id ?= "$_currentUserId" && participants.id ?= "${otherUser.id}"',
        expand: 'participants',
      );

      // Find a conversation where ONLY these two are participants (P2P)
      RecordModel? existingConversation;
      for (final conv in existing.items) {
        final participants = conv.expand['participants'];
        if (participants != null && participants.length == 2) {
          existingConversation = conv;
          break;
        }
      }

      if (existingConversation != null) {
        // Conversation exists, navigate to it
        if (mounted) {
          Navigator.pop(context, existingConversation);
        }
      } else {
        // Create new conversation
        final newConv = await pb.collection('conversations').create(body: {
          'participants': [_currentUserId, otherUser.id],
        });
        if (mounted) {
          Navigator.pop(context, newConv);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creatingChat = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start chat: $e')),
        );
      }
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
        title: const Text(
          'New Chat',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0D1B2A),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFF0F0F0)),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(fontSize: 15, color: Color(0xFF0D1B2A)),
              decoration: InputDecoration(
                hintText: 'Search by name or username...',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF1565C0),
                  size: 22,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded,
                            size: 18, color: Colors.grey),
                        onPressed: () => _searchController.clear(),
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
          ),

          // User count header
          if (!_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Text(
                    _searchController.text.isEmpty
                        ? 'All Users'
                        : 'Results',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0D1B2A),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${_filteredUsers.length})',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),

          // Users list
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF1565C0)),
                  )
                : _filteredUsers.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 20),
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, index) =>
                            _buildUserTile(_filteredUsers[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(RecordModel user) {
    final name = user.data['name'] as String? ?? '';
    final username = user.data['username'] as String? ?? '';
    final status = user.data['status'] as String? ?? 'offline';
    final isOnline = status == 'online';
    final color = _colorFromName(name.isNotEmpty ? name : username);
    final displayName = name.isNotEmpty ? name : username;
    final subtitle = name.isNotEmpty && username.isNotEmpty ? '@$username' : '';

    return GestureDetector(
      onTap: _creatingChat ? null : () => _startConversation(user),
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withOpacity(0.12),
                child: Text(
                  _getInitial(displayName),
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
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C853),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            displayName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0D1B2A),
            ),
          ),
          subtitle: subtitle.isNotEmpty
              ? Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                )
              : Text(
                  isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 13,
                    color: isOnline
                        ? const Color(0xFF00C853)
                        : Colors.grey[400],
                  ),
                ),
          trailing: _creatingChat
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF1565C0),
                  ),
                )
              : Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: Color(0xFF1565C0),
                    size: 18,
                  ),
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
          Icon(Icons.person_search_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No users found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different name or username',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}
