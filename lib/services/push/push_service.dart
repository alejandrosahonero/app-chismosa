import 'dart:async';

import 'package:chismosa/core/utils/app_logger.dart';
import 'package:chismosa/services/storage/key_value_store.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A push that arrived while the app was on screen, reduced to what the UI
/// needs to decide whether to say anything.
@immutable
class ThreadPush {
  const ThreadPush({required this.storyId, this.title, this.body});

  final String storyId;
  final String? title;
  final String? body;
}

/// Push notifications for new messages in the threads the reader joined.
///
/// **FCM, and only for delivery.** The server decides who hears about what —
/// the Edge Function `thread-push`, called by a trigger on every message (see
/// `0006_push.sql`) — so muting a thread, blocking someone or leaving a group
/// takes effect without the phone having to be awake. The app only does three
/// things: hand its token to the server, ask for the permission at the right
/// moment, and open the thread when a notification is tapped.
///
/// Nothing here touches Firebase until [initialize] has succeeded, so tests and
/// builds without a `google-services.json` see a service that quietly does
/// nothing.
class PushService {
  PushService(this._store);

  final KeyValueStore _store;

  static const String _askedKey = 'push_permission_asked';

  /// Must match `android_channel_id` in the Edge Function and the default
  /// channel declared in `AndroidManifest.xml`.
  static const String channelId = 'thread_messages';

  bool _ready = false;
  SupabaseClient? _client;
  String? _token;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  /// Starts FCM and wires taps and foreground messages.
  ///
  /// [onOpenThread] receives the story id behind a tapped notification — the
  /// one that launched the app included. [onForeground] receives pushes that
  /// arrive with the app open, which Android does not show by itself.
  Future<void> initialize({
    required String channelName,
    required ValueChanged<String> onOpenThread,
    required VoidCallback onOpenMyStories,
    required ValueChanged<ThreadPush> onForeground,
  }) async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();

      // The channel has to exist before the first push, or Android files it
      // under "Miscellaneous", where the reader cannot turn it off on its own.
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            AndroidNotificationChannel(
              channelId,
              channelName,
              importance: Importance.high,
            ),
          );

      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      _subscriptions
        ..add(
          FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
            _open(message, onOpenThread, onOpenMyStories);
          }),
        )
        ..add(
          FirebaseMessaging.onMessage.listen((RemoteMessage message) {
            final String? id = _storyIdOf(message);
            if (id == null || _isReview(message)) return;
            onForeground(
              ThreadPush(
                storyId: id,
                title: message.notification?.title,
                body: message.notification?.body,
              ),
            );
          }),
        )
        ..add(messaging.onTokenRefresh.listen(_register));
      _ready = true;

      final RemoteMessage? launch = await messaging.getInitialMessage();
      if (launch != null) _open(launch, onOpenThread, onOpenMyStories);
    } on Object catch (error, stackTrace) {
      AppLogger.error('Push init failed', error: error, stackTrace: stackTrace);
    }
  }

  /// Hands this device's token to the account now signed in.
  ///
  /// Called after sign-in and again after an account is restored: the token
  /// belongs to the phone, and the server moves it to whoever is using it now,
  /// so the previous account stops getting this phone's notifications.
  Future<void> attach(SupabaseClient client) async {
    _client = client;
    if (!_ready) return;
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
    } on Object catch (error) {
      AppLogger.debug('FCM token unavailable: $error', name: 'push');
    }
  }

  Future<void> _register(String token) async {
    final SupabaseClient? client = _client;
    if (client == null || client.auth.currentUser == null) return;
    _token = token;
    try {
      await client.rpc<void>(
        'register_device',
        params: <String, dynamic>{'p_token': token},
      );
    } on Object catch (error) {
      AppLogger.debug('Device registration failed: $error', name: 'push');
    }
  }

  /// Asks for the notification permission once in the app's life.
  ///
  /// Called right after the reader's first message in a thread: that is the
  /// moment "tell me when someone answers" means something. Android shows the
  /// dialog a single time and remembers a no forever, so spending it on the
  /// first launch would kill the feature before anyone knew what it did.
  Future<void> askPermissionOnce() async {
    if (!_ready || _store.getBool(_askedKey)) return;
    await _store.setBool(_askedKey, value: true);
    try {
      await FirebaseMessaging.instance.requestPermission();
    } on Object catch (error) {
      AppLogger.debug('Permission request failed: $error', name: 'push');
    }
  }

  /// Asks for the permission now, from the row in Settings.
  Future<void> requestPermission() async {
    if (!_ready) return;
    await _store.setBool(_askedKey, value: true);
    try {
      await FirebaseMessaging.instance.requestPermission();
    } on Object catch (error) {
      AppLogger.debug('Permission request failed: $error', name: 'push');
    }
  }

  /// The token this device registered, for tests and diagnostics.
  String? get token => _token;

  /// A notice about the reader's own story being hidden for review or
  /// restored lands on "Mis historias", where its state is shown — not in a
  /// thread they may no longer be able to open.
  static bool _isReview(RemoteMessage message) =>
      message.data['kind'] == 'hidden' || message.data['kind'] == 'restored';

  static void _open(
    RemoteMessage message,
    ValueChanged<String> onOpenThread,
    VoidCallback onOpenMyStories,
  ) {
    if (_isReview(message)) {
      onOpenMyStories();
      return;
    }
    final String? id = _storyIdOf(message);
    if (id != null) onOpenThread(id);
  }

  static String? _storyIdOf(RemoteMessage message) {
    final Object? id = message.data['story_id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  Future<void> dispose() async {
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}
