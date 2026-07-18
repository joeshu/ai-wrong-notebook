import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';

class NotificationService {
  NotificationService({required QuestionRepository questionRepository})
      : _questionRepository = questionRepository;

  final QuestionRepository _questionRepository;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _notificationsAllowed = true;

  Future<bool> init() async {
    if (_initialized) return _notificationsAllowed;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidAllowed = await androidPlugin?.requestNotificationsPermission();
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosAllowed = await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    _notificationsAllowed = androidAllowed ?? iosAllowed ?? true;
    _initialized = true;
    return _notificationsAllowed;
  }

  /// Sends an immediate reminder only when questions are actually due.
  /// Timed background scheduling is intentionally handled separately: local
  /// notifications cannot re-check the database after iOS suspends the app.
  Future<bool> checkAndNotify() async {
    final allowed = await init();
    if (!allowed) return false;
    final all = await _questionRepository.listAll();
    const scheduler = ReviewScheduleService();
    final dueCount = all.where(scheduler.isDue).length;

    if (dueCount > 0) {
      await _plugin.show(
        0,
        '错题本复习提醒',
        '你有 $dueCount 道错题待复习，快来巩固吧！',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'review_reminder',
            '复习提醒',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      return true;
    }
    return false;
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
