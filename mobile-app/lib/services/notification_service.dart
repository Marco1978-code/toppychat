import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Mostra una notifica quando arriva un messaggio da un numero autorizzato.
/// Non salva nulla di suo: e' solo un avviso visivo/sonoro basato su cio'
/// che ChatController ha gia' ricevuto e scritto nel file locale.
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 0;

  static const _channelId = 'toppychat_messages';
  static const _channelName = 'Messaggi ToppyChat';
  static const _channelDescription =
      'Notifiche per i nuovi messaggi ricevuti in ToppyChat';

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  Future<void> showMessageNotification({
    required String title,
    required String body,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    _nextId = (_nextId + 1) % 100000;
    await _plugin.show(_nextId, title, body, details);
  }
}
