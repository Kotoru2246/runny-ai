import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/run_reminder_model.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  void Function(String? payload)? _onRunReminderTap;

  static const _androidChannelId = 'runny_run_reminders';
  static const _androidChannelName = 'Run reminders';
  static const _androidChannelDescription =
      'Notifications for scheduled running workouts.';

  Future<void> initialize({
    void Function(String? payload)? onRunReminderTap,
  }) async {
    if (onRunReminderTap != null) {
      _onRunReminderTap = onRunReminderTap;
    }
    if (_initialized) return;
    if (!_supportsScheduledNotifications) {
      _initialized = true;
      return;
    }

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        _onRunReminderTap?.call(response.payload);
      },
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true) {
      scheduleMicrotask(() => _onRunReminderTap?.call(launchResponse?.payload));
    }

    _initialized = true;
  }

  Future<bool> requestReminderPermission() async {
    await initialize();
    if (!_supportsScheduledNotifications) return false;

    final androidGranted = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission() ??
        true;

    final iosGranted = await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        true;

    final macGranted = await _plugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        true;

    return androidGranted && iosGranted && macGranted;
  }

  Future<void> scheduleRunReminder({
    required RunReminder reminder,
    required String workoutTitle,
  }) async {
    await initialize();
    if (!_supportsScheduledNotifications) {
      throw UnsupportedError('Scheduled local notifications are not supported.');
    }
    if (!reminder.enabled) {
      await cancelRunReminder(reminder.notificationId);
      return;
    }

    final scheduledFor = reminder.scheduledFor.toUtc();
    if (!scheduledFor.isAfter(DateTime.now().toUtc())) {
      throw StateError('Reminder time is in the past.');
    }

    final body = reminder.leadMinutes == 0
        ? 'Đã đến giờ chạy rồi! Bắt đầu buổi chạy hôm nay nhé.'
        : 'Còn ${reminder.leadMinutes} phút nữa đến lịch chạy của bạn.';

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelDescription: _androidChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'runny_run_reminders',
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'runny_run_reminders',
      ),
    );

    await _plugin.cancel(id: reminder.notificationId);
    await _plugin.zonedSchedule(
      id: reminder.notificationId,
      title: workoutTitle.isEmpty ? 'Runny AI' : workoutTitle,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledFor, tz.UTC),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.workoutId,
    );
  }

  Future<void> cancelRunReminder(int notificationId) async {
    await initialize();
    if (!_supportsScheduledNotifications) return;
    try {
      await _plugin.cancel(id: notificationId);
    } on UnsupportedError catch (e) {
      debugPrint('Cancel notification unsupported on this platform: $e');
    }
  }

  bool get supportsScheduledNotifications => _supportsScheduledNotifications;

  bool get _supportsScheduledNotifications {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }
}
