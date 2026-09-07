/// Stato di consegna di un messaggio inviato da questo dispositivo (le
/// "spunte" stile chat: singola grigia = inviato, doppia grigia =
/// consegnato, doppia blu = letto). Non ha senso per i messaggi ricevuti.
enum MessageStatus { sent, delivered, read }

/// Tipo di contenuto del messaggio.
enum MessageKind { text, image, file }

/// Un singolo messaggio di una conversazione.
class ChatMessage {
  final String id;
  final String from; // numero mittente
  final String to; // numero destinatario
  final String text;
  final DateTime timestamp;
  final bool mine; // true se inviato da questo dispositivo
  final MessageStatus status;
  final MessageKind kind;

  /// Percorso locale del file allegato (immagine o documento), se
  /// [kind] non e' [MessageKind.text].
  final String? attachmentPath;
  final String? attachmentName;
  final int? attachmentSize;

  const ChatMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.text,
    required this.timestamp,
    required this.mine,
    this.status = MessageStatus.sent,
    this.kind = MessageKind.text,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentSize,
  });

  ChatMessage copyWith({MessageStatus? status}) => ChatMessage(
        id: id,
        from: from,
        to: to,
        text: text,
        timestamp: timestamp,
        mine: mine,
        status: status ?? this.status,
        kind: kind,
        attachmentPath: attachmentPath,
        attachmentName: attachmentName,
        attachmentSize: attachmentSize,
      );
}
