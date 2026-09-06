import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Gestisce il servizio in primo piano che mantiene ToppyChat attivo anche
/// quando l'app viene messa in secondo piano (non chiusa del tutto), cosi'
/// la connessione al relay resta aperta e i messaggi continuano ad arrivare
/// (con relativa notifica) anche se non stai guardando l'app in quel
/// momento. Android mostra una piccola notifica fissa ("ToppyChat attivo")
/// finche' il servizio e' in esecuzione: e' il prezzo da pagare per non far
/// congelare l'app in background.
///
/// Il task handler qui sotto non fa nulla di suo: serve solo a soddisfare
/// l'API del plugin. Il vero lavoro (connessione WebSocket, ricezione
/// messaggi, notifiche) lo fanno RelayService, ChatController e
/// NotificationService, che continuano a girare normalmente nell'app
/// finche' il processo resta vivo.
class ChatBackgroundTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, TaskStarter starter) {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onDestroy(DateTime timestamp) {}
}

@pragma('vm:entry-point')
void chatBackgroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(ChatBackgroundTaskHandler());
}

class BackgroundService {
  static bool _configured = false;

  /// Da chiamare una volta all'avvio dell'app, prima di avviare il
  /// servizio vero e proprio.
  static void configure() {
    if (_configured) return;
    _configured = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'toppychat_foreground',
        channelName: 'ToppyChat attivo',
        channelDescription:
            'Mantiene ToppyChat connesso per ricevere i messaggi anche in background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start() async {
    configure();
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      notificationTitle: 'ToppyChat attivo',
      notificationText: 'In ascolto per nuovi messaggi',
      callback: chatBackgroundStartCallback,
    );
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  /// Chiede il permesso di mostrare notifiche (necessario su Android 13+).
  static Future<void> requestPermissions() async {
    final notifPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notifPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }
}
