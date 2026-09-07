import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/contact.dart';

/// Gestisce le impostazioni salvate localmente sul telefono:
/// numero proprio, indirizzo del relay, token e whitelist dei contatti.
///
/// Relay e token hanno un default incorporato nell'app (vedi AppConfig):
/// finche' l'utente non li cambia esplicitamente dalle impostazioni
/// avanzate, getRelayUrl()/getRelayToken() ritornano quei default, cosi'
/// il flusso normale richiede solo il numero di telefono.
///
/// Non contiene nessun messaggio: quelli vivono solo nei file di testo
/// (vedi StorageService).
class SettingsService {
  static const _kOwnNumber = 'own_number';
  static const _kRelayUrl = 'relay_url';
  static const _kRelayToken = 'relay_token';
  static const _kContacts = 'contacts';

  Future<String?> getOwnNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kOwnNumber);
  }

  Future<void> setOwnNumber(String number) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOwnNumber, number);
  }

  /// Indirizzo relay effettivo: quello scelto dall'utente nelle impostazioni
  /// avanzate, oppure il default incorporato nell'app.
  Future<String> getRelayUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kRelayUrl);
    return (saved == null || saved.isEmpty) ? AppConfig.defaultRelayUrl : saved;
  }

  /// true se l'utente ha scelto un relay diverso da quello di default.
  Future<bool> hasCustomRelayUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kRelayUrl);
    return saved != null && saved.isNotEmpty;
  }

  Future<void> setRelayUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRelayUrl, url);
  }

  /// Token relay effettivo: quello scelto dall'utente, oppure il default.
  Future<String> getRelayToken() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kRelayToken);
    return (saved == null || saved.isEmpty)
        ? AppConfig.defaultRelayToken
        : saved;
  }

  Future<void> setRelayToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRelayToken, token);
  }

  /// Ora basta il numero di telefono: relay e token hanno gia' un default.
  Future<bool> isSetupComplete() async {
    final number = await getOwnNumber();
    return number != null && number.isNotEmpty;
  }

  Future<List<Contact>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kContacts);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Contact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveContacts(List<Contact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await prefs.setString(_kContacts, raw);
  }

  Future<void> addContact(Contact contact) async {
    final contacts = await getContacts();
    if (contacts.any((c) => c.number == contact.number)) return;
    contacts.add(contact);
    await saveContacts(contacts);
  }

  Future<void> removeContact(String number) async {
    final contacts = await getContacts();
    contacts.removeWhere((c) => c.number == number);
    await saveContacts(contacts);
  }
}
