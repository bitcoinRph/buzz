import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nostr/nostr.dart' as nostr;

import '../community/community_provider.dart';
import 'relay_client.dart';

/// Relay connection configuration.
///
/// In the pure-nostr world the only secrets the app cares about are:
///   - `baseUrl` — where the relay lives (used for WS + media upload)
///   - `nsec`    — the user's signing key (drives NIP-42 AUTH and event sigs)
class RelayConfig {
  final String baseUrl;

  /// Nostr secret key (bech32 nsec) for signing events and NIP-42 AUTH.
  final String? nsec;

  const RelayConfig({required this.baseUrl, this.nsec});

  /// Derive the websocket URL from the configured base URL.
  ///
  /// `baseUrl` may be an HTTP(S) origin (dev config / media base) or already a
  /// WS(S) URL — invite links are parsed and stored as `wss://…`
  /// (see `deep_link.dart` / `Community.relayUrl`). Map both secure schemes to
  /// `wss` and both insecure schemes to `ws`, so an already-`wss` base is not
  /// silently downgraded to `ws` (which then fails against a TLS-terminated
  /// relay, e.g. behind StartOS's HTTPS port).
  String get wsUrl {
    final uri = Uri.parse(baseUrl);
    final secure = uri.scheme == 'https' || uri.scheme == 'wss';
    return uri.replace(scheme: secure ? 'wss' : 'ws').toString();
  }
}

/// Compile-time environment config via --dart-define.
///
/// Run with:
///   flutter run --dart-define=BUZZ_RELAY_URL=http://localhost:3000
///
/// Or create a `.env.json` and use --dart-define-from-file=.env.json
class Env {
  static const relayUrl = String.fromEnvironment(
    'BUZZ_RELAY_URL',
    defaultValue: 'http://localhost:3000',
  );
}

class RelayConfigNotifier extends Notifier<RelayConfig> {
  @override
  RelayConfig build() {
    // Watch the active community so that when it changes (community switch),
    // the config rebuilds, triggering the full provider cascade.
    final activeAsync = ref.watch(activeCommunityProvider);
    final active = activeAsync.value;
    if (active != null) {
      return RelayConfig(baseUrl: active.relayUrl, nsec: active.nsec);
    }

    // Fallback to compile-time env config (dev mode).
    return const RelayConfig(baseUrl: Env.relayUrl);
  }

  void update({required String baseUrl, String? nsec}) {
    state = RelayConfig(baseUrl: baseUrl, nsec: nsec);
  }
}

final relayConfigProvider = NotifierProvider<RelayConfigNotifier, RelayConfig>(
  RelayConfigNotifier.new,
);

/// Derive the hex pubkey from a bech32 nsec, or null on any failure.
String? pubkeyFromNsec(String? nsec) {
  if (nsec == null || nsec.isEmpty) return null;
  try {
    final privkeyHex = nostr.Nip19.decode(payload: nsec).data;
    if (privkeyHex.isEmpty) return null;
    return nostr.Keys(privkeyHex).public;
  } catch (_) {
    return null;
  }
}

/// The current user's hex pubkey, derived from the active community nsec.
final myPubkeyProvider = Provider<String?>((ref) {
  final config = ref.watch(relayConfigProvider);
  return pubkeyFromNsec(config.nsec);
});

/// Provides a [RelayClient] that reacts to config changes.
///
/// Only used for the media upload HTTP endpoint now — all data flow goes
/// through the relay WebSocket session.
final relayClientProvider = Provider<RelayClient>((ref) {
  final config = ref.watch(relayConfigProvider);
  final client = RelayClient(baseUrl: config.baseUrl);
  ref.onDispose(client.dispose);
  return client;
});
