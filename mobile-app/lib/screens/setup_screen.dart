import 'package:flutter/material.dart';

import '../services/background_service.dart';
import '../services/chat_controller.dart';
import '../services/notification_service.dart';
import '../services/relay_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import 'contacts_screen.dart';

/// Prima schermata: nel flusso normale chiede solo il numero di telefono,
/// perche' relay e token hanno gia' un valore di default incorporato
/// nell'app (vedi AppConfig/SettingsService). Chi vuole usare un relay
/// proprio puo' aprire "Impostazioni avanzate" ed inserirlo li'.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _settings = SettingsService();
  bool _saving = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final number = await _settings.getOwnNumber();
    final url = await _settings.getRelayUrl();
    final token = await _settings.getRelayToken();
    final hasCustomRelay = await _settings.hasCustomRelayUrl();
    if (!mounted) return;
    setState(() {
      if (number != null) _numberController.text = number;
      _urlController.text = url;
      _tokenController.text = token;
      // Se l'utente aveva gia' scelto un relay diverso dal default,
      // mostriamo subito la sezione avanzata cosi' la vede.
      _showAdvanced = hasCustomRelay;
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

    // Chiediamo subito il permesso per la cartella Download e per le
    // notifiche, cosi' li sblocchiamo prima di arrivare alla prima chat.
    await StorageService().ensurePermission();
    await NotificationService.instance.requestPermission();
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
                  'Inserisci il tuo numero di telefono per iniziare a '
                  'chattare. Il resto e\' gia\' configurato.',
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
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _showAdvanced = !_showAdvanced),
                    icon: Icon(
                      _showAdvanced
                          ? Icons.expand_less
                          : Icons.expand_more,
                    ),
                    label: const Text('Impostazioni avanzate'),
                  ),
                ),
                if (_showAdvanced) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Solo per utenti esperti: qui puoi usare un relay '
                    'diverso da quello incorporato nell\'app.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Indirizzo relay (wss://...)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Campo obbligatorio';
                      }
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
                ],
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
