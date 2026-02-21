import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/db/pb.dart';

class PresenceService with WidgetsBindingObserver {
  Timer? _heartbeatTimer;
  final String userId;

  // Heartbeat every 30s. If no heartbeat for 60s → user is considered offline
  // by the UI even if status field still says "online" (handles force-kill).
  static const _heartbeatInterval = Duration(seconds: 30);
  static const _onlineThreshold = 60; // seconds

  PresenceService(this.userId);

  void init() {
    WidgetsBinding.instance.addObserver(this);
    _setOnline();
    _startHeartbeat();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _setOffline();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _setOnline());
  }

  Future<void> _setOnline() async {
    try {
      await pb
          .collection('users')
          .update(
            userId,
            body: {
              'status': 'online',
              'last_seen': DateTime.now().toUtc().toIso8601String(),
            },
          );
    } catch (_) {
      // Silently fail — network may be temporarily unavailable
    }
  }

  Future<void> _setOffline() async {
    try {
      await pb
          .collection('users')
          .update(
            userId,
            body: {
              'status': 'offline',
              'last_seen': DateTime.now().toUtc().toIso8601String(),
            },
          );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // App came back to foreground — mark online and restart heartbeat
        _setOnline();
        _startHeartbeat();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // App backgrounded or killed — stop heartbeat and mark offline
        // Note: detached is NOT guaranteed on all Android devices when force-killed.
        // The 60s threshold in isOnline() handles that case on the UI side.
        _heartbeatTimer?.cancel();
        _setOffline();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Transient states (e.g. phone call overlay) — do nothing
        break;
    }
  }

  /// Use this helper anywhere in the UI instead of checking status == 'online' alone.
  /// Guards against stale status when the app was force-killed and _setOffline()
  /// never fired — if last_seen is older than 60s the user is treated as offline.
  static bool isOnline(Map<String, dynamic> userData) {
    final status = userData['status'] as String? ?? 'offline';
    if (status != 'online') return false;

    final lastSeenStr = userData['last_seen'] as String?;
    if (lastSeenStr == null || lastSeenStr.isEmpty) return false;

    try {
      final lastSeen = DateTime.parse(lastSeenStr).toLocal();
      final diff = DateTime.now().difference(lastSeen);
      return diff.inSeconds < _onlineThreshold;
    } catch (_) {
      return false;
    }
  }
}
