import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  Future<void> init() async {
    if (kIsWeb) return;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload == 'medication_screen') {
          navigatorKey.currentState?.pushNamed('/medication');
        }
      },
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
        await androidImplementation.requestExactAlarmsPermission();
      }
    }
  }

  /// 📍 1. ตั้งเวลาแจ้งเตือนยาพร้อม Snooze ล่วงหน้า 3 วัน (Rolling Window)
  Future<void> scheduleMedicationWithSnooze({
    required int baseId,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    if (kIsWeb) return;

    await cancelAllAlarmsForMeal(baseId);

    final now = tz.TZDateTime.now(tz.local);

    for (int dayOffset = 0; dayOffset < 3; dayOffset++) {
      for (int snooze = 0; snooze < 4; snooze++) {
        tz.TZDateTime targetTime = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          scheduledTime.hour,
          scheduledTime.minute,
        ).add(Duration(days: dayOffset, minutes: snooze * 15));

        if (targetTime.isBefore(now)) {
          continue;
        }

        int id = baseId + (dayOffset * 4) + snooze;

        await _scheduleSingleAlarm(
          id: id,
          title: snooze == 0 ? title : '⏳ แจ้งเตือนซ้ำ: $title',
          body: body,
          targetTime: targetTime,
          matchTime: null,
        );
      }
    }
  }

  /// 📍 2. ฟังก์ชันยิง Schedule เข้า OS
  Future<void> _scheduleSingleAlarm({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime targetTime,
    DateTimeComponents? matchTime,
  }) async {
    if (kIsWeb) return;

    AndroidScheduleMode scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      final hasExactAlarm =
          await androidImplementation?.canScheduleExactNotifications() ?? false;

      if (!hasExactAlarm) {
        scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
        debugPrint('⚠️ ขาดสิทธิ์ Exact Alarm -> สลับไปใช้ Inexact Mode อัตโนมัติ');
      }
    }

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        targetTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'medication_channel',
            'Medication Reminders',
            channelDescription: 'แจ้งเตือนการรับประทานยา',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            visibility: NotificationVisibility.public,
            autoCancel: false,
            enableVibration: true,
            playSound: true,
          ),
        ),
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchTime,
        payload: 'medication_screen',
      );
    } catch (e) {
      debugPrint('❌ Notification Error: $e');
      rethrow;
    }
  }

  /// 📍 3. ฟังก์ชันหยุด Snooze วันนี้เมื่อผู้ใช้กดยืนยันกินยา และต่ออายุคิวไปอีก 3 วัน
  Future<void> stopSnoozeForToday({
    required int baseId,
    required DateTime scheduledTime,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;

    await cancelAllAlarmsForMeal(baseId);

    try {
      final now = tz.TZDateTime.now(tz.local);

      for (int dayOffset = 1; dayOffset <= 3; dayOffset++) {
        for (int snooze = 0; snooze < 4; snooze++) {
          tz.TZDateTime targetTime = tz.TZDateTime(
            tz.local,
            now.year,
            now.month,
            now.day,
            scheduledTime.hour,
            scheduledTime.minute,
          ).add(Duration(days: dayOffset, minutes: snooze * 15));

          int id = baseId + (dayOffset * 4) + snooze;

          try {
            await _scheduleSingleAlarm(
              id: id,
              title: snooze == 0 ? title : '⏳ แจ้งเตือนซ้ำ: $title',
              body: body,
              targetTime: targetTime,
              matchTime: null,
            );
          } catch (scheduleError) {
            debugPrint('⚠️ Non-fatal schedule error for ID $id: $scheduleError');
          }
        }
      }
    } catch (e, stack) {
      debugPrint('❌ Error in stopSnoozeForToday execution: $e\n$stack');
    }
  }

  /// 📍 4. ยกเลิกการแจ้งเตือนทั้งหมดของมื้อยานั้นๆ
  Future<void> cancelAllAlarmsForMeal(int baseId) async {
    if (kIsWeb) return;

    for (int i = 0; i <= 15; i++) {
      try {
        await flutterLocalNotificationsPlugin.cancel(baseId + i);
      } catch (cancelError) {
        debugPrint(
            '⚠️ Non-fatal cancel error for meal ID ${baseId + i}: $cancelError');
      }
    }
  }
}