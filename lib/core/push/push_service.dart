import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../network/api_client.dart';

/// FCM doesn't auto-display a notification while the app is in the
/// foreground (unlike background/killed, which the OS handles natively) —
/// this top-level handler runs in its own isolate for that case and must
/// stay a plain top-level/static function per the firebase_messaging
/// background-handler contract.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Owns Firebase Cloud Messaging setup for the whole app: requesting
/// notification permission, keeping the backend's copy of this device's FCM
/// token current, and showing a local notification for messages that
/// arrive while the app is in the foreground (FCM only auto-displays
/// background/killed-state notifications).
class PushService {
  PushService(this._apiClient);

  final ApiClient _apiClient;
  static bool _firebaseReady = false;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _listenersAttached = false;

  Future<void> _ensureFirebaseReady() async {
    if (_firebaseReady) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
      _firebaseReady = true;
    } catch (error) {
      // A misconfigured/missing Firebase project must never take the rest
      // of the app down with it.
      debugPrint('[push] Firebase init failed: $error');
    }
  }

  /// Safe to call unconditionally on every app start — sets up
  /// Firebase/local-notifications once, and registers the current token if
  /// permission was already granted in a previous session. Does NOT
  /// request permission; call [requestPermissionAndRegister] for that,
  /// once there's a logged-in user to associate the token with.
  Future<void> initialize() async {
    await _ensureFirebaseReady();
    if (!_firebaseReady) return;

    if (!_listenersAttached) {
      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) => _registerToken(),
      );
      _listenersAttached = true;
    }

    if (await Permission.notification.isGranted) {
      await _registerToken();
    }
  }

  /// Call once there's an authenticated user to attach the token to (e.g.
  /// right after login/signup, and on session restore) — prompts for
  /// notification permission if it hasn't been decided yet, then registers
  /// the token if granted.
  Future<void> requestPermissionAndRegister() async {
    await _ensureFirebaseReady();
    if (!_firebaseReady) return;

    final status = await Permission.notification.status;
    if (status.isGranted) {
      await _registerToken();
      return;
    }
    if (status.isDenied) {
      final result = await Permission.notification.request();
      if (result.isGranted) await _registerToken();
    }
    // Permanently denied: nothing to do here short of sending the user to
    // system settings, which isn't worth interrupting the flow for.
  }

  Future<void> _registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _apiClient.dio.post(
        '/device-tokens',
        data: {'token': token, 'platform': Platform.isIOS ? 'ios' : 'android'},
      );
    } catch (error) {
      debugPrint('[push] Token registration failed: $error');
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'default',
          'Notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
