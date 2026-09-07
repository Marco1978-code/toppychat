import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/chat_controller.dart';
import '../services/settings_service.dart';
import 'appearance_screen.dart';
import 'chat_screen.dart';
import 'setup_screen.dart';

/// Elenco dei numeri autorizzati a chattare con te (whitelist). I messaggi
/// da qualsiasi altro numero vengono ignorati dall'app.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _settings = SettingsService();
  List<Contact> _contacts = [];
  final Map<String, String> _previews = {};
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _load();
    ChatController.instance.connectionStatus.listen((status) {
      if (mounted) setState(() => _connected = status);
    });
    ChatController.instance.events.listen((_) => _load());
  }

  Future<void> _load() async {
    final contacts = await _settings.getContacts();
    final previews = <String, String>{};
    for (final c in contacts) {
      final preview = await ChatController.instance.lastLinePreview(c.number);
      if (preview != null) previews[c.number] = preview;
    }
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _previews
        ..clear()
        ..addAll(previews);
    });
  }

  Future<void> _addContactDialog() async {
    final numberController = TextEditingController();
    final nameController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aggiungi numero autorizzato'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nome (a piacere)'),
            ),
            TextField(
              controller: numberController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Numero (es. +391234567890)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    );

    if (added == true && numberController.text.trim().isNotEmpty) {
      final name = nameController.text.trim().isEmpty
          ? numberController.text.trim()
          : nameController.text.trim();
      await _settings.addContact(
        Contact(number: numberController.text.trim(), name: name),
      );
      _load();
    }
  }

  Future<void> _removeContact(Contact contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovere questo numero?'),
        content: Text(
          '${contact.name} non potra\' piu\' scriverti. '
          'La conversazione gia\' salvata in Download/ToppyChat resta comunque sul telefono.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _settings.removeContact(contact.number);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ToppyChat'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Row(
                children: [
                  Icon(
                    _connected ? Icons.cloud_done : Icons.cloud_off,
                    size: 18,
                    color: _connected ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _connected ? 'Connesso' : 'Offline',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Aspetto delle chat',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AppearanceScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SetupScreen()),
            ),
          ),
        ],
      ),
      body: _contacts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nessun numero autorizzato ancora.\n'
                  'Tocca + per aggiungere il primo contatto con cui chattare.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          : ListView.separated(
              itemCount: _contacts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                final preview = _previews[contact.number];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      contact.name.isNotEmpty
                          ? contact.name[0].toUpperCase()
                          : '?',
                    ),
                  ),
                  title: Text(contact.name),
                  subtitle: Text(
                    preview ?? contact.number,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onLongPress: () => _removeContact(contact),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(contact: contact),
                    ),
                  ).then((_) => _load()),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addContactDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
