import 'package:flutter/material.dart';

import '../config/chat_gradients.dart';
import '../services/settings_service.dart';

/// Permette di scegliere uno sfondo sfumato per le schermate di chat,
/// oppure tornare allo sfondo predefinito del tema.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  final _settings = SettingsService();
  int _selected = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final index = await _settings.getChatGradientIndex();
    if (!mounted) return;
    setState(() => _selected = index);
  }

  Future<void> _select(int index) async {
    await _settings.setChatGradientIndex(index);
    if (!mounted) return;
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aspetto delle chat')),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.3,
        children: [
          _OptionTile(
            name: 'Predefinito',
            selected: _selected == -1,
            onTap: () => _select(-1),
            child: Container(color: Theme.of(context).colorScheme.surface),
          ),
          for (var i = 0; i < chatGradients.length; i++)
            _OptionTile(
              name: chatGradients[i].name,
              selected: _selected == i,
              onTap: () => _select(i),
              child: Container(
                decoration: BoxDecoration(gradient: chatGradients[i].gradient),
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _OptionTile({
    required this.name,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black12,
            width: selected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: child),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                color: Colors.black.withValues(alpha: 0.35),
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            if (selected)
              Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
