/// Valori di default del relay, incorporati nell'app cosi' chi la installa
/// deve inserire solo il proprio numero di telefono: relay e token sono
/// gia' pronti all'uso e restano nascosti nel flusso normale.
///
/// Un utente esperto puo' comunque cambiarli dalle "Impostazioni avanzate"
/// (vedi SetupScreen); in quel caso il valore scelto da lui sovrascrive
/// questi default e viene salvato in locale.
class AppConfig {
  static const String defaultRelayUrl = 'wss://toppychat-relay.onrender.com';
  static const String defaultRelayToken = 'toppy2026segreta';
}
