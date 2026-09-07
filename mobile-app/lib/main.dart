import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'models/contact.dart';
import 'screens/chat_screen.dart';
import 'services/background_service.dart';
import 'services/chat_controller.dart';
import 'services/notification_service.dart';
import 'services/relay_service.dart';
import 'services/settings_service.dart';
import 'screens/contacts_screen.dart';
import 'screens/setup_screen.dart';

/// Chiave globale del Navigator: serve a NotificationService per aprire la
/// chat giusta quando l'utente tocca una notifica, anche se in quel momento
/// non abbiamo un BuildContext a portata di mano (es. app riaperta a
/// freddo).
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  FlutterForegroundTask.initCommunicationPort();
  NotificationService.instance.onOpenContact = _openChatForNumber;
  runApp(const ToppyChatApp());
}

/// Apre la ChatScreen del contatto con questo numero. Se il numero non e'
/// (piu') tra i contatti salvati, apre comunque una chat "al volo" cosi'
/// l'utente vede il messaggio che ha toccato.
Future<void> _openChatForNumber(String number) async {
  final contacts = await SettingsService().getContacts();
  final contact = contacts.firstWhere(
    (c) => c.number == number,
    orElse: () => Contact(number: number, name: number),
  );
  navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => ChatScreen(contact: contact)),
  );
}

class ToppyChatApp extends StatelessWidget {
  const ToppyChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'ToppyChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const _StartupGate(),
      builder: (context, child) =>
          WithForegroundTask(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Decide se mostrare il setup iniziale o andare direttamente alla lista
/// contatti, in base a cosa e' gia' salvato sul telefono.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  final _settings = SettingsService();
  bool _checked = false;
  bool _setupComplete = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    BackgroundService.configure();
    await NotificationService.instance.initialize();

    final complete = await _settings.isSetupComplete();
    if (complete) {
      final url = await _settings.getRelayUrl();
      final token = await _settings.getRelayToken();
      final number = await _settings.getOwnNumber() ?? '';
      RelayService.instance.connect(url: url, token: token, ownNumber: number);
      ChatController.instance.startListening();
      await NotificationService.instance.requestPermission();
      await BackgroundService.requestPermissions();
      await BackgroundService.start();
    }
    if (!mounted) return;
    setState(() {
      _setupComplete = complete;
      _checked = true;
    });

    // Se l'app era chiusa del tutto ed e' stata aperta toccando una
    // notifica, apriamo subito la chat giusta.
    final launchNumber =
        await NotificationService.instance.consumeLaunchContactNumber();
    if (launchNumber != null && launchNumber.isNotEmpty) {
      await _openChatForNumber(launchNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _setupComplete ? const ContactsScreen() : const SetupScreen();
  }
}
