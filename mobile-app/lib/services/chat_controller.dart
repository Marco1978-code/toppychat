import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/contact.dart';
import 'notification_service.dart';
import 'relay_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';

const int maxAttachmentBytes = 5 * 1024 * 1024;

const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
const _mimeTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'pdf': 'application/pdf',
};

String _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

MessageKind kindForFileName(String fileName) {
  return _imageExtensions.contains(_extensionOf(fileName))
      ? MessageKind.image
      : MessageKind.file;
}

String _mimeTypeForFileName(String fileName) {
  return _mimeTypes[_extensionOf(fileName)] ?? 'application/octet-stream';
}

/// Evento emesso quando arriva (o viene inviato) un messaggio per un
/// certo contatto: le schermate in ascolto possono aggiornare la UI.
///
/// Se [isStatusUpdate] e' true, [message] non e' un messaggio nuovo ma solo
/// il veicolo per comunicare che lo stato di consegna (spunte) del
/// messaggio con quell'id e' cambiato: chi ascolta deve aggiornare il
/// messaggio gia' mostrato con quell'id, non aggiungerne uno nuovo.
class ChatEvent {
  final String contactNumber;
  final ChatMessage message;
  final bool isStatusUpdate;
  ChatEvent(this.contactNumber, this.message, {this.isStatusUpdate = false});
}

/// Punto centrale che collega relay, whitelist e salvataggio su file.
///
/// E' l'UNICO posto che scrive messaggi ricevuti su disco, cosi' anche se
/// nessuna schermata di chat e' aperta la cronologia non si perde. Applica
/// anche il filtro "solo numeri autorizzati": i messaggi da numeri non in
/// whitelist vengono scartati e non arrivano mai al file system.
///
/// Gestisce anche le ricevute di consegna/lettura (le "spunte") e il
/// trasferimento di allegati (immagini e file), oltre a un piccolo suono
/// quando si invia o si riceve qualcosa.
class ChatController {
  ChatController._internal();
  static final ChatController instance = ChatController._internal();

  final StorageService _storage = StorageService();
  final SettingsService _settings = SettingsService();
  final _eventsController = StreamController<ChatEvent>.broadcast();
  final _uuid = const Uuid();
  final AudioPlayer _sentPlayer = AudioPlayer();
  final AudioPlayer _recvPlayer = AudioPlayer();

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

  Future<void> _playSentSound() async {
    try {
      await _sentPlayer.play(AssetSource('sounds/message_sent.wav'));
    } catch (_) {
      // Il suono e' solo un dettaglio estetico: se il dispositivo non
      // riesce a riprodurlo (es. modalita' silenziosa bloccata da
      // qualche OEM) non deve interrompere l'invio del messaggio.
    }
  }

  Future<void> _playReceivedSound() async {
    try {
      await _recvPlayer.play(AssetSource('sounds/message_pop.wav'));
    } catch (_) {
      // Come sopra: mai bloccare la ricezione per un suono che non parte.
    }
  }

  Future<void> _handleIncoming(Map<String, dynamic> data) async {
    final type = data['type'];

    if (type == 'receipt') {
      await _handleReceipt(data);
      return;
    }

    if (type != 'message' && type != 'file') return;

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
    final id = data['id'] as String? ?? '';

    late final ChatMessage msg;
    late final String notificationBody;

    if (type == 'file') {
      final fileName = data['fileName'] as String? ?? 'file';
      final dataBase64 = data['data'] as String? ?? '';
      if (dataBase64.isEmpty) return;
      List<int> bytes;
      try {
        bytes = base64Decode(dataBase64);
      } catch (_) {
        return;
      }
      final kind = kindForFileName(fileName);
      String path;
      try {
        path = await _storage.saveAttachmentBytes(
          contactNumber: from,
          id: id.isEmpty ? _uuid.v4() : id,
          fileName: fileName,
          bytes: bytes,
        );
      } catch (_) {
        return;
      }
      msg = ChatMessage(
        id: id,
        from: from,
        to: ownNumber,
        text: '',
        timestamp: ts,
        mine: false,
        kind: kind,
        attachmentPath: path,
        attachmentName: fileName,
        attachmentSize: bytes.length,
      );
      notificationBody = kind == MessageKind.image ? '📷 Immagine' : '📎 $fileName';
    } else {
      msg = ChatMessage(
        id: id,
        from: from,
        to: ownNumber,
        text: data['text'] as String? ?? '',
        timestamp: ts,
        mine: false,
      );
      notificationBody = msg.text;
    }

    await _storage.appendMessage(from, msg);
    _eventsController.add(ChatEvent(from, msg));
    unawaited(_playReceivedSound());

    final contact = contacts.firstWhere(
      (c) => c.number == from,
      orElse: () => Contact(number: from, name: from),
    );
    await NotificationService.instance.showMessageNotification(
      title: contact.name,
      body: notificationBody,
      contactNumber: from,
    );

    if (id.isNotEmpty) {
      RelayService.instance.sendReceipt(to: from, id: id, status: 'consegnato');
    }
  }

  Future<void> _handleReceipt(Map<String, dynamic> data) async {
    final from = data['from'] as String? ?? '';
    final id = data['id'] as String? ?? '';
    final statusLabel = data['status'] as String? ?? '';
    if (from.isEmpty || id.isEmpty) return;

    final contacts = await _settings.getContacts();
    final isAllowed = contacts.any((c) => c.number == from);
    if (!isAllowed) return;

    final status = statusLabel == 'letto'
        ? MessageStatus.read
        : MessageStatus.delivered;
    await _storage.updateMessageStatus(from, id, status);

    final placeholder = ChatMessage(
      id: id,
      from: from,
      to: '',
      text: '',
      timestamp: DateTime.now(),
      mine: true,
      status: status,
    );
    _eventsController.add(ChatEvent(from, placeholder, isStatusUpdate: true));
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
    unawaited(_playSentSound());
  }

  /// Invia il file al percorso [filePath] a [contact] (immagine o
  /// documento qualsiasi). Ritorna un messaggio di errore leggibile se il
  /// file e' troppo grande o non e' stato possibile leggerlo, altrimenti
  /// null.
  Future<String?> sendFile(Contact contact, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return 'File non trovato.';
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxAttachmentBytes) {
      return 'File troppo grande: il limite e\' di 5 MB.';
    }

    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'file';
    final ownNumber = await _settings.getOwnNumber() ?? '';
    final id = _uuid.v4();
    final kind = kindForFileName(fileName);

    final savedPath = await _storage.saveAttachmentBytes(
      contactNumber: contact.number,
      id: id,
      fileName: fileName,
      bytes: bytes,
    );

    final msg = ChatMessage(
      id: id,
      from: ownNumber,
      to: contact.number,
      text: '',
      timestamp: DateTime.now(),
      mine: true,
      kind: kind,
      attachmentPath: savedPath,
      attachmentName: fileName,
      attachmentSize: bytes.length,
    );
    await _storage.appendMessage(contact.number, msg);

    RelayService.instance.sendFile(
      to: contact.number,
      id: id,
      fileName: fileName,
      mimeType: _mimeTypeForFileName(fileName),
      dataBase64: base64Encode(bytes),
    );
    _eventsController.add(ChatEvent(contact.number, msg));
    unawaited(_playSentSound());
    return null;
  }

  /// Segna come "letti" tutti i messaggi ricevuti in [messages] mandando
  /// una ricevuta al mittente. Va chiamato quando l'utente apre la chat.
  void sendReadReceipts(Contact contact, List<ChatMessage> messages) {
    for (final m in messages) {
      if (m.mine || m.id.isEmpty) continue;
      RelayService.instance.sendReceipt(
        to: contact.number,
        id: m.id,
        status: 'letto',
      );
    }
  }

  Future<List<ChatMessage>> loadConversation(String contactNumber) async {
    final ownNumber = await _settings.getOwnNumber() ?? '';
    return _storage.readConversation(contactNumber, ownNumber: ownNumber);
  }

  Future<String?> lastLinePreview(String contactNumber) {
    return _storage.lastLinePreview(contactNumber);
  }
}
