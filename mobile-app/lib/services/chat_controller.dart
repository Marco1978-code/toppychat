import 'dart:async';

import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/contact.dart';
import 'notification_service.dart';
import 'relay_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// Evento emesso quando arriva (o viene inviato) un messaggio per un
/// certo contatto: le schermate in ascolto possono aggiornare la UI.
class ChatEvent {
  final String contactNumber;
  final ChatMessage message;
  ChatEvent(this.contactNumber, this.message);
}

/// Punto centrale che collega relay, whitelist e salvataggio su file.
///
/// E' l'UNICO posto che scrive messaggi ricevuti su disco, cosi' anche se
/// nessuna schermata di chat e' aperta la cronologia non si perde. Applica
/// anche il filtro "solo numeri autorizzati": i messaggi da numeri non in
/// whitelist vengono scartati e non arrivano mai al file system.
class ChatController {
  ChatController._internal();
  static final ChatController instance = ChatController._internal();

  final StorageService _storage = StorageService();
  final SettingsService _settings = SettingsService();
  final _eventsController = StreamController<ChatEvent>.broadcast();
  final _uuid = const Uuid();

  bool _listening = false;
  StreamSubscription<Map<String, dynamic>>? _sub;

  Stream<ChatEvent> get events => _eventsController.stream;
  Stream<bool> get connectionStatus => RelayService.instance.connectionStatus;

  void startListening() {
    if (_listening) return;
    _listening = true;
    _sub = RelayService.instance.incoming.listen(_handleIncoming);
  }

  void stopListening() {
    _listening = false;
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _handleIncoming(Map<String, dynamic> data) async {
    if (data['type'] != 'message') return;
    final from = data['from'] as String? ?? '';
    if (from.isEmpty) return;

    // Filtro whitelist: se il numero non e' tra i contatti autorizzati,
    // il messaggio viene ignorato del tutto (mai scritto su disco).
    final contacts = await _settings.getContacts();
    final isAllowed = contacts.any((c) => c.number == from);
    if (!isAllowed) return;

    final ownNumber = await _settings.getOwnNumber() ?? '';
    final tsRaw = data['ts'];
    final ts = tsRaw is num
        ? DateTime.fromMillisecondsSinceEpoch(tsRaw.toInt())
        : DateTime.now();

    final msg = ChatMessage(
      id: data['id'] as String? ?? '',
      from: from,
      to: ownNumber,
      text: data['text'] as String? ?? '',
      timestamp: ts,
      mine: false,
    );

    await _storage.appendMessage(from, msg);
    _eventsController.add(ChatEvent(from, msg));

    final contact = contacts.firstWhere(
      (c) => c.number == from,
      orElse: () => Contact(number: from, name: from),
    );
    await NotificationService.instance.showMessageNotification(
      title: contact.name,
      body: msg.text,
      contactNumber: from,
    );
  }

  /// Invia un messaggio testuale a [contact]: lo salva subito in locale e
  /// lo spedisce al relay per l'inoltro in tempo reale.
  Future<void> sendMessage(Contact contact, String text) async {
    if (text.trim().isEmpty) return;
    final ownNumber = await _settings.getOwnNumber() ?? '';
    final id = _uuid.v4();
    final msg = ChatMessage(
      id: id,
      from: ownNumber,
      to: contact.number,
      text: text,
      timestamp: DateTime.now(),
      mine: true,
    );

    await _storage.appendMessage(contact.number, msg);
    RelayService.instance.sendMessage(to: contact.number, text: text, id: id);
    _eventsController.add(ChatEvent(contact.number, msg));
  }

  Future<List<ChatMessage>> loadConversation(String contactNumber) async {
    final ownNumber = await _settings.getOwnNumber() ?? '';
    return _storage.readConversation(contactNumber, ownNumber: ownNumber);
  }

  Future<String?> lastLinePreview(String contactNumber) {
    return _storage.lastLinePreview(contactNumber);
  }
}
