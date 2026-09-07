import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Mostra una notifica quando arriva un messaggio da un numero autorizzato.
/// Non salva nulla di suo: e' solo un avviso visivo/sonoro basato su cio'
/// che ChatController ha gia' ricevuto e scritto nel file locale.
///
/// Il payload della notifica e' il numero del mittente: serve a
/// [onOpenContact] per aprire la chat giusta quando l'utente tocca la
/// notifica (sia con app in background, sia a freddo da app chiusa).
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 0;

  /// Chiamato con il numero del contatto quando l'utente tocca una notifica.
  Future<void> Function(String contactNumber)? onOpenContact;

  // "_v2": un cambio di canale con nome diverso da quello originale serve
  // a far ripartire Android con le nuove impostazioni (in particolare il
  // suono personalizzato), dato che un canale gia' creato su un telefono
  // non aggiorna piu' il suono anche se il codice cambia.
  static const _channelId = 'toppychat_messages_v2';
  static const _channelName = 'Messaggi ToppyChat';
  static const _channelDescription =
      'Notifiche per i nuovi messaggi ricevuti in ToppyChat';
  static const _notificationSound = RawResourceAndroidNotificationSound('message_pop');

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleTap,
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      sound: _notificationSound,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  void _handleTap(NotificationResponse response) {
    final number = response.payload;
    if (number != null && number.isNotEmpty) {
      onOpenContact?.call(number);
    }
  }

  /// Se l'app e' stata avviata proprio toccando una notifica (era chiusa
  /// del tutto), ritorna il numero del contatto da aprire subito.
  Future<String?> consumeLaunchContactNumber() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  /// Chiede il permesso di mostrare notifiche (necessario su Android 13+).
  Future<void> requestPermission() async {
    if (await Permission.notification.isGranted) return;
    await Permission.notification.request();
  }

  Future<void> showMessageNotification({
    required String title,
    required String body,
    required String contactNumber,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      sound: _notificationSound,
    );
    const details = NotificationDetails(android: androidDetails);

    _nextId = (_nextId + 1) % 100000;
    await _plugin.show(
      _nextId,
      title,
      body,
      details,
      payload: contactNumber,
    );
  }
}
