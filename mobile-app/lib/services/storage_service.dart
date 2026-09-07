import 'dart:io';

import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/chat_message.dart';

/// Salva e legge le conversazioni come file di testo semplice in
/// Download/ToppyChat/<numero>.txt sul telefono. Ogni riga e' un messaggio,
/// nel formato:
///
///   [2026-09-04 10:15:32] Io: ciao come va {{id:ab12cd|stato:letto}}
///   [2026-09-04 10:16:01] +391234567890: bene grazie {{id:ff2233|stato:inviato}}
///
/// Il blocco finale tra {{ }} e' metadato (id del messaggio, stato di
/// consegna e, per gli allegati, tipo/percorso/dimensione): e' facoltativo,
/// cosi' le righe salvate da versioni precedenti dell'app restano
/// leggibili. Gli allegati veri e propri (immagini, file) vengono salvati
/// come file separati in Download/ToppyChat/_allegati/<numero>/, questo
/// file di testo ne tiene solo il riferimento.
///
/// Nessun database, nessun server: e' tutto leggibile con un qualsiasi
/// editor di testo o file manager, direttamente nella cartella Download
/// del telefono.
class StorageService {
  static final DateFormat _tsFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final RegExp _lineRegex = RegExp(r'^\[(.+?)\] (.+?): (.*)$');
  static final RegExp _metaRegex = RegExp(r'^(.*?)\s*\{\{(.*)\}\}$');
  static final RegExp _idInMetaRegex = RegExp(r'\{\{[^}]*\bid:([^|}]+)');
  static final RegExp _attachmentLabelRegex =
      RegExp(r'^\[(?:file|immagine)\]\s*(.*)$');

  /// Chiede i permessi necessari per scrivere nella cartella Download
  /// pubblica. Su Android 11+ serve il permesso "Gestione di tutti i file",
  /// che l'utente concede una volta dalle impostazioni di sistema.
  Future<bool> ensurePermission() async {
    if (await Permission.manageExternalStorage.isGranted) return true;

    final manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) return true;

    // Fallback per versioni di Android piu' vecchie (<= 10) dove basta
    // il permesso classico di scrittura.
    final legacyStatus = await Permission.storage.request();
    return legacyStatus.isGranted;
  }

  Directory _appDownloadDir() {
    return Directory('/storage/emulated/0/Download/ToppyChat');
  }

  String _fileNameFor(String number) {
    final safe = number.replaceAll(RegExp(r'[^0-9+]'), '_');
    return '$safe.txt';
  }

  File _fileFor(String number) {
    final dir = _appDownloadDir();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File('${dir.path}/${_fileNameFor(number)}');
  }

  Directory _attachmentsDirFor(String contactNumber) {
    final safe = contactNumber.replaceAll(RegExp(r'[^0-9+]'), '_');
    final dir = Directory('${_appDownloadDir().path}/_allegati/$safe');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  String _sanitizeFileName(String name) {
    final base = name.split('/').last.split('\\').last;
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '_');
    return safe.isEmpty ? 'file' : safe;
  }

  String _statusLabel(MessageStatus status) {
    switch (status) {
      case MessageStatus.sent:
        return 'inviato';
      case MessageStatus.delivered:
        return 'consegnato';
      case MessageStatus.read:
        return 'letto';
    }
  }

  MessageStatus _statusFromLabel(String? label) {
    switch (label) {
      case 'consegnato':
        return MessageStatus.delivered;
      case 'letto':
        return MessageStatus.read;
      default:
        return MessageStatus.sent;
    }
  }

  String _encodeLine(ChatMessage message) {
    final ts = _tsFormat.format(message.timestamp);
    final label = message.mine ? 'Io' : message.from;

    final String textPortion;
    switch (message.kind) {
      case MessageKind.text:
        textPortion = message.text.replaceAll('\n', ' ');
        break;
      case MessageKind.image:
        textPortion = '[immagine] ${message.attachmentName ?? ''}';
        break;
      case MessageKind.file:
        textPortion = '[file] ${message.attachmentName ?? ''}';
        break;
    }

    final meta = <String, String>{};
    if (message.id.isNotEmpty) meta['id'] = message.id;
    meta['stato'] = _statusLabel(message.status);
    if (message.kind != MessageKind.text) {
      meta['tipo'] = message.kind == MessageKind.image ? 'immagine' : 'file';
      if (message.attachmentPath != null) {
        meta['percorso'] = message.attachmentPath!;
      }
      if (message.attachmentSize != null) {
        meta['dimensione'] = message.attachmentSize.toString();
      }
    }
    final metaStr = meta.entries.map((e) => '${e.key}:${e.value}').join('|');
    return '[$ts] $label: $textPortion {{$metaStr}}';
  }

  ChatMessage? _decodeLine(
    String line, {
    required String contactNumber,
    required String ownNumber,
  }) {
    final match = _lineRegex.firstMatch(line);
    if (match == null) return null;
    final tsStr = match.group(1)!;
    final label = match.group(2)!;
    final rest = match.group(3)!;

    var text = rest;
    final meta = <String, String>{};
    final metaMatch = _metaRegex.firstMatch(rest);
    if (metaMatch != null) {
      text = metaMatch.group(1)!.trimRight();
      final metaStr = metaMatch.group(2)!;
      for (final part in metaStr.split('|')) {
        final idx = part.indexOf(':');
        if (idx <= 0) continue;
        meta[part.substring(0, idx)] = part.substring(idx + 1);
      }
    }

    final mine = label == 'Io';
    DateTime ts;
    try {
      ts = _tsFormat.parse(tsStr);
    } catch (_) {
      ts = DateTime.now();
    }

    var kind = MessageKind.text;
    String? attachmentPath;
    String? attachmentName;
    int? attachmentSize;
    final tipo = meta['tipo'];
    if (tipo == 'immagine' || tipo == 'file') {
      kind = tipo == 'immagine' ? MessageKind.image : MessageKind.file;
      attachmentPath = meta['percorso'];
      final sizeStr = meta['dimensione'];
      attachmentSize = sizeStr != null ? int.tryParse(sizeStr) : null;
      final nameMatch = _attachmentLabelRegex.firstMatch(text);
      attachmentName = nameMatch?.group(1) ?? text;
    }

    return ChatMessage(
      id: meta['id'] ?? '',
      from: mine ? ownNumber : contactNumber,
      to: mine ? contactNumber : ownNumber,
      text: kind == MessageKind.text ? text : '',
      timestamp: ts,
      mine: mine,
      status: _statusFromLabel(meta['stato']),
      kind: kind,
      attachmentPath: attachmentPath,
      attachmentName: attachmentName,
      attachmentSize: attachmentSize,
    );
  }

  /// Aggiunge un messaggio in fondo al file della conversazione con
  /// [contactNumber].
  Future<void> appendMessage(String contactNumber, ChatMessage message) async {
    final granted = await ensurePermission();
    if (!granted) {
      throw StateError(
        'Permesso di scrittura su Download non concesso. '
        'Vai nelle impostazioni del telefono e abilita "Tutti i file" per ToppyChat.',
      );
    }
    final file = _fileFor(contactNumber);
    await file.writeAsString(
      '${_encodeLine(message)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Aggiorna lo stato di consegna (inviato/consegnato/letto) del messaggio
  /// con questo [id] nella conversazione con [contactNumber]. Riscrive la
  /// singola riga interessata: e' l'unico caso in cui il file, normalmente
  /// solo in append, viene modificato in un punto precedente.
  Future<void> updateMessageStatus(
    String contactNumber,
    String id,
    MessageStatus status,
  ) async {
    if (id.isEmpty) return;
    final file = _fileFor(contactNumber);
    if (!file.existsSync()) return;

    final content = await file.readAsString();
    final lines = content.split('\n');
    var changed = false;
    final newLines = lines.map((line) {
      if (line.trim().isEmpty) return line;
      final match = _idInMetaRegex.firstMatch(line);
      if (match == null || match.group(1) != id) return line;
      changed = true;
      final label = _statusLabel(status);
      if (line.contains('stato:')) {
        return line.replaceFirst(RegExp(r'stato:[^|}]*'), 'stato:$label');
      }
      return line.replaceFirst('}}', '|stato:$label}}');
    }).toList();

    if (changed) {
      await file.writeAsString(newLines.join('\n'), flush: true);
    }
  }

  /// Salva i byte di un allegato in Download/ToppyChat/_allegati/<numero>/ e
  /// ritorna il percorso completo del file salvato sul telefono.
  Future<String> saveAttachmentBytes({
    required String contactNumber,
    required String id,
    required String fileName,
    required List<int> bytes,
  }) async {
    final granted = await ensurePermission();
    if (!granted) {
      throw StateError(
        'Permesso di scrittura su Download non concesso. '
        'Vai nelle impostazioni del telefono e abilita "Tutti i file" per ToppyChat.',
      );
    }
    final dir = _attachmentsDirFor(contactNumber);
    final safeName = _sanitizeFileName(fileName);
    final file = File('${dir.path}/${id}_$safeName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Legge tutta la conversazione salvata con [contactNumber].
  Future<List<ChatMessage>> readConversation(
    String contactNumber, {
    required String ownNumber,
  }) async {
    final granted = await ensurePermission();
    if (!granted) return [];
    final file = _fileFor(contactNumber);
    if (!file.existsSync()) return [];
    final content = await file.readAsString();
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty);
    final messages = <ChatMessage>[];
    for (final line in lines) {
      final msg = _decodeLine(
        line,
        contactNumber: contactNumber,
        ownNumber: ownNumber,
      );
      if (msg != null) messages.add(msg);
    }
    return messages;
  }

  /// Ultima riga della conversazione, utile per l'anteprima nella lista
  /// contatti. Ritorna null se non c'e' ancora nessuna conversazione.
  Future<String?> lastLinePreview(String contactNumber) async {
    final file = _fileFor(contactNumber);
    if (!file.existsSync()) return null;
    final content = await file.readAsString();
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return null;
    return _previewFromLine(lines.last);
  }

  /// Toglie il blocco metadato {{...}} dalla riga grezza e rende piu'
  /// leggibile l'anteprima di un allegato (mostra 📎 nome invece di
  /// "[file] nome").
  String _previewFromLine(String line) {
    final metaMatch = _metaRegex.firstMatch(line);
    var preview = metaMatch != null ? metaMatch.group(1)! : line;
    final attachMatch =
        RegExp(r'^(.*: )\[(?:file|immagine)\]\s*(.*)$').firstMatch(preview);
    if (attachMatch != null) {
      preview = '${attachMatch.group(1)}📎 ${attachMatch.group(2)}';
    }
    return preview;
  }
}
