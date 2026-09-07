import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Client WebSocket verso il relay ToppyChat. Si occupa solo del trasporto
/// in tempo reale: non salva nulla, non conosce la whitelist. Chi lo usa
/// riceve un flusso di eventi grezzi (Map decodificate dal JSON del server)
/// e decide cosa farne.
class RelayService {
  RelayService._internal();
  static final RelayService instance = RelayService._internal();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _incomingController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<bool>.broadcast();

  String? _url;
  String? _token;
  String? _ownNumber;
  bool _shouldReconnect = false;
  Timer? _reconnectTimer;

  /// Eventi ricevuti dal server (message, registered, ack, error, ...).
  Stream<Map<String, dynamic>> get incoming => _incomingController.stream;

  /// true quando la connessione e' attiva, false quando e' caduta.
  Stream<bool> get connectionStatus => _statusController.stream;

  bool get isConnected => _channel != null;

  void connect({
    required String url,
    required String token,
    required String ownNumber,
  }) {
    _url = url;
    _token = token;
    _ownNumber = ownNumber;
    _shouldReconnect = true;
    _openConnection();
  }

  void _openConnection() {
    try {
      final channel = WebSocketChannel.connect(Uri.parse(_url!));
      _channel = channel;
      _subscription = channel.stream.listen(
        (raw) {
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            _incomingController.add(data);
          } catch (_) {
            // riga non valida, la ignoriamo
          }
        },
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
        cancelOnError: true,
      );
      _send({'type': 'register', 'phone': _ownNumber, 'token': _token});
      _statusController.add(true);
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _subscription?.cancel();
    _channel = null;
    _statusController.add(false);
    if (_shouldReconnect) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 3), _openConnection);
    }
  }

  void sendMessage({
    required String to,
    required String text,
    required String id,
  }) {
    _send({
      'type': 'message',
      'to': to,
      'text': text,
      'id': id,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Invia un file (immagine o documento) come base64 al contatto [to].
  /// Il relay non lo salva mai su disco: lo inoltra e basta (o lo tiene
  /// brevemente in coda in RAM se il destinatario e' offline).
  void sendFile({
    required String to,
    required String id,
    required String fileName,
    required String mimeType,
    required String dataBase64,
  }) {
    _send({
      'type': 'file',
      'to': to,
      'id': id,
      'fileName': fileName,
      'mimeType': mimeType,
      'data': dataBase64,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Invia una ricevuta di consegna/lettura per il messaggio [id] al
  /// mittente originale [to] (le "spunte" stile chat).
  void sendReceipt({
    required String to,
    required String id,
    required String status,
  }) {
    _send({'type': 'receipt', 'to': to, 'id': id, 'status': status});
  }

  void _send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
