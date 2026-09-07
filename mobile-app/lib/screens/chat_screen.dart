import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/chat_gradients.dart';
import '../models/chat_message.dart';
import '../models/contact.dart';
import '../services/chat_controller.dart';
import '../services/settings_service.dart';

/// Conversazione con un singolo contatto. Legge la cronologia dal file
/// Download/ToppyChat/<numero>.txt e si aggiorna in tempo reale quando
/// arrivano nuovi messaggi, cambi di stato (spunte) o allegati.
class ChatScreen extends StatefulWidget {
  final Contact contact;
  const ChatScreen({super.key, required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  static final _timeFormat = DateFormat('HH:mm');
  bool _loading = true;
  bool _sendingFile = false;
  int _gradientIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadGradient();
    _load();
    ChatController.instance.events.listen((event) {
      if (event.contactNumber != widget.contact.number || !mounted) return;
      setState(() {
        if (event.isStatusUpdate) {
          final idx = _messages.indexWhere((m) => m.id == event.message.id);
          if (idx != -1) {
            _messages[idx] =
                _messages[idx].copyWith(status: event.message.status);
          }
        } else {
          _messages.add(event.message);
        }
      });
      if (!event.isStatusUpdate) _scrollToBottom();
    });
  }

  Future<void> _loadGradient() async {
    final index = await SettingsService().getChatGradientIndex();
    if (!mounted) return;
    setState(() => _gradientIndex = index);
  }

  Future<void> _load() async {
    final messages = await ChatController.instance.loadConversation(
      widget.contact.number,
    );
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(messages);
      _loading = false;
    });
    _scrollToBottom();
    ChatController.instance.sendReadReceipts(widget.contact, messages);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    await ChatController.instance.sendMessage(widget.contact, text.trim());
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    final path = result?.files.single.path;
    if (path == null) return;

    setState(() => _sendingFile = true);
    final error = await ChatController.instance.sendFile(widget.contact, path);
    if (!mounted) return;
    setState(() => _sendingFile = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _gradientIndex >= 0 && _gradientIndex < chatGradients.length
        ? chatGradients[_gradientIndex].gradient
        : null;

    return Scaffold(
      backgroundColor: gradient != null ? Colors.transparent : null,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.contact.name),
            Text(
              widget.contact.number,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: gradient != null ? BoxDecoration(gradient: gradient) : null,
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const Center(
                          child: Text(
                            'Nessun messaggio ancora. Scrivi il primo!',
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final m = _messages[index];
                            return _MessageBubble(
                              message: m,
                              timeLabel: _timeFormat.format(m.timestamp),
                            );
                          },
                        ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      icon: _sendingFile
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file),
                      onPressed: _sendingFile ? null : _pickAndSendFile,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Scrivi un messaggio...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(24)),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String timeLabel;
  const _MessageBubble({required this.message, required this.timeLabel});

  Widget _buildContent(BuildContext context) {
    switch (message.kind) {
      case MessageKind.text:
        return Text(message.text);
      case MessageKind.image:
        final path = message.attachmentPath;
        if (path == null || !File(path).existsSync()) {
          return const _AttachmentMissing();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            width: 220,
            height: 220,
          ),
        );
      case MessageKind.file:
        return InkWell(
          onTap: () {
            final path = message.attachmentPath ?? '';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Salvato in: $path')),
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.attachmentName ?? 'file',
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _formatSize(message.attachmentSize),
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget? _buildStatusIcon() {
    if (!message.mine) return null;
    switch (message.status) {
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 14, color: Colors.black45);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: Colors.black45);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 14, color: Colors.blue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final bg = mine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final statusIcon = _buildStatusIcon();

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildContent(context),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeLabel,
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
                if (statusIcon != null) ...[
                  const SizedBox(width: 4),
                  statusIcon,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentMissing extends StatelessWidget {
  const _AttachmentMissing();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined),
        SizedBox(width: 6),
        Text('Immagine non trovata'),
      ],
    );
  }
}
