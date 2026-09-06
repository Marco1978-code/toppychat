
import 'package:flutter/material.dart';

import '../services/background_service.dart';
import '../services/chat_controller.dart';
import '../services/relay_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import 'contacts_screen.dart';

/// Prima schermata: configura il numero proprio e il server relay.
/// Va compilata una volta sola (poi si puo' riaprire dalle impostazioni).
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _urlController = TextEditingController(text: 'wss://');
  final _tokenController = TextEditingController();
  final _settings = SettingsService();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final number = await _settings.getOwnNumber();
    final url = await _settings.getRelayUrl();
    final token = await _settings.getRelayToken();
    if (!mounted) return;
    setState(() {
      if (number != null) _numberController.text = number;
      if (url != null && url.isNotEmpty) _urlController.text = url;
      if (token != null) _tokenController.text = token;
    });
  }

  @override
  void dispose() {
    _numberController.dispose();
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    await _settings.setOwnNumber(_numberController.text.trim());
    await _settings.setRelayUrl(_urlController.text.trim());
    await _settings.setRelayToken(_tokenController.text.trim());

    // Chiediamo subito il permesso per la cartella Download, cosi' lo
    // sblocchiamo prima di arrivare alla prima chat.
    await StorageService().ensurePermission();
    await BackgroundService.requestPermissions();

    RelayService.instance.connect(
      url: _urlController.text.trim(),
      token: _tokenController.text.trim(),
      ownNumber: _numberController.text.trim(),
    );
    ChatController.instance.startListening();
    await BackgroundService.start();

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ContactsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configura ToppyChat')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const Text(
                  'Inserisci il tuo numero e i dati del relay '
                  '(il piccolo server che inoltra i messaggi senza salvarli).',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _numberController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Il tuo numero (es. +391234567890)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Campo obbligatorio'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Indirizzo relay (wss://...)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Campo obbligatorio';
                    if (!v.startsWith('ws://') && !v.startsWith('wss://')) {
                      return 'Deve iniziare con ws:// o wss://';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _tokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Token del relay (RELAY_TOKEN)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salva e continua'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
