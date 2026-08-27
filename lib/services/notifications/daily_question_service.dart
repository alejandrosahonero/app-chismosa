import 'dart:math';

import 'package:aja/core/config/app_config.dart';
import 'package:aja/core/utils/app_logger.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/services/storage/key_value_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The question of the day.
///
/// **Local notifications, not push.** There is no backend and this feature does
/// not justify growing one: every notification is queued on the device with its
/// question already picked, so the whole thing works offline and costs nothing
/// to run. The price is that the queue only reaches
/// [AppConfig.dailyQuestionDaysAhead] days out and is topped up whenever the
/// app is opened — a user who does not open the app for two weeks stops being
/// reminded, which is a fair trade for having no server at all.
///
/// The permission is **never** requested at startup. It is asked for the first
/// time the user turns the switch on in Settings, which is the only moment they
/// have said they want this.
class DailyQuestionService {
  DailyQuestionService(this._store, {FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final KeyValueStore _store;
  final FlutterLocalNotificationsPlugin _plugin;

  static const String _enabledKey = 'daily_question_enabled';

  /// Ids [_notificationIdBase] .. +[AppConfig.dailyQuestionDaysAhead] belong to
  /// this feature. Fixed so a reschedule replaces the queue instead of stacking
  /// a second one on top of it.
  static const int _notificationIdBase = 4200;

  static const String _channelId = 'daily_question';

  bool _ready = false;

  /// Whether the user has turned the daily question on.
  ///
  /// Stored separately from the OS permission: revoking the permission in
  /// Android settings should not silently flip the app's own switch, and asking
  /// the plugin on every build would be a platform channel call per frame.
  bool get isEnabled => _store.getBool(_enabledKey);

  /// Wires up tap handling. Safe to call more than once.
  ///
  /// [onOpenFact] receives the id of the fact behind the notification the user
  /// tapped while the app was already running.
  Future<void> initialize({required ValueChanged<String> onOpenFact}) async {
    if (_ready) return;

    try {
      tz_data.initializeTimeZones();
      // Without this every schedule would be computed in UTC, so "20:00" would
      // land at whatever hour the user's offset happens to be.
      final TimezoneInfo zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final String? id = response.payload;
          if (id != null && id.isNotEmpty) onOpenFact(id);
        },
      );
      _ready = true;
    } on Object catch (error, stackTrace) {
      // A device without a resolvable timezone database still runs the app; it
      // just does not get reminders.
      AppLogger.error(
        'Daily question init failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Fact id behind the notification that cold-started the app, if any.
  Future<String?> launchFactId() async {
    try {
      final NotificationAppLaunchDetails? details = await _plugin
          .getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;

      final String? payload = details?.notificationResponse?.payload;
      return (payload?.isEmpty ?? true) ? null : payload;
    } on Object catch (error) {
      AppLogger.debug('Launch details unavailable: $error', name: 'notif');
      return null;
    }
  }

  /// Turns the reminder on: asks for the permission, then fills the queue.
  ///
  /// Returns false when the user denied it, so the caller can put the switch
  /// back where it was instead of lying about the state.
  Future<bool> enable({
    required List<Fact> facts,
    required String language,
    required String title,
  }) async {
    if (!_ready) return false;

    final bool granted =
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        false;

    if (!granted) return false;

    await _store.setBool(_enabledKey, value: true);
    await reschedule(facts: facts, language: language, title: title);
    return true;
  }

  Future<void> disable() async {
    await _store.setBool(_enabledKey, value: false);
    await _cancelAll();
  }

  /// Rebuilds the queue from scratch.
  ///
  /// Called on every app open as well as when the switch is turned on: the
  /// queue is finite, so topping it up is what keeps the reminders coming.
  Future<void> reschedule({
    required List<Fact> facts,
    required String language,
    required String title,
  }) async {
    if (!_ready || !isEnabled || facts.isEmpty) return;

    try {
      await _cancelAll();

      // Shuffled without a seed on purpose: two consecutive weeks should not
      // deal the same fourteen questions, and nothing here needs to be
      // reproducible.
      final List<Fact> pool = List<Fact>.of(facts)..shuffle(Random());

      for (int day = 0; day < AppConfig.dailyQuestionDaysAhead; day++) {
        final Fact fact = pool[day % pool.length];
        final tz.TZDateTime when = _slotFor(day);

        await _plugin.zonedSchedule(
          id: _notificationIdBase + day,
          scheduledDate: when,
          title: title,
          body: fact.question.resolve(language),
          payload: fact.id,
          // Inexact on purpose: exact alarms need SCHEDULE_EXACT_ALARM, which
          // Play reviews case by case and which this does not remotely need.
          // A reminder that lands a few minutes late is still a reminder.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              'Pregunta del día',
              channelDescription:
                  'Una pregunta curiosa al día, a la hora que elijas.',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
        );
      }
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Daily question scheduling failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// The slot [daysFromNow] days out, skipping today's if its hour has passed.
  static tz.TZDateTime _slotFor(int daysFromNow) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime slot = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      AppConfig.dailyQuestionHour,
      AppConfig.dailyQuestionMinute,
    );

    // Opening the app at 21:00 must not queue a notification for 20:00 today,
    // which the OS would either drop or fire immediately.
    if (!slot.isAfter(now)) slot = slot.add(const Duration(days: 1));

    return slot.add(Duration(days: daysFromNow));
  }

  Future<void> _cancelAll() async {
    for (int day = 0; day < AppConfig.dailyQuestionDaysAhead; day++) {
      await _plugin.cancel(id: _notificationIdBase + day);
    }
  }
}
