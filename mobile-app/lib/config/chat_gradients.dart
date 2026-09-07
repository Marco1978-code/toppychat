import 'package:flutter/material.dart';

/// Sfondi sfumati selezionabili per le schermate di chat (vedi
/// AppearanceScreen). L'indice di questa lista e' quello salvato da
/// SettingsService.setChatGradientIndex.
class ChatGradientOption {
  final String name;
  final List<Color> colors;
  const ChatGradientOption(this.name, this.colors);

  LinearGradient get gradient => LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

const List<ChatGradientOption> chatGradients = [
  ChatGradientOption('Tramonto', [Color(0xFFFF9A8B), Color(0xFFFF6A88), Color(0xFFFF99AC)]),
  ChatGradientOption('Oceano', [Color(0xFF2E3192), Color(0xFF1BFFFF)]),
  ChatGradientOption('Foresta', [Color(0xFF134E5E), Color(0xFF71B280)]),
  ChatGradientOption('Lavanda', [Color(0xFF7F7FD5), Color(0xFF86A8E7), Color(0xFF91EAE4)]),
  ChatGradientOption('Pesca', [Color(0xFFFFE29F), Color(0xFFFFA99F), Color(0xFFFF719A)]),
  ChatGradientOption('Notte', [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)]),
];
