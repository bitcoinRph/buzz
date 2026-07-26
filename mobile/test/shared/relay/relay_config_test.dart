import 'package:flutter_test/flutter_test.dart';
import 'package:buzz/shared/relay/relay.dart';

void main() {
  group('RelayConfig.wsUrl', () {
    test('maps http origin to ws', () {
      const config = RelayConfig(baseUrl: 'http://localhost:3000');
      expect(config.wsUrl, 'ws://localhost:3000');
    });

    test('maps https origin to wss', () {
      const config = RelayConfig(baseUrl: 'https://relay.example');
      expect(config.wsUrl, 'wss://relay.example');
    });

    test('preserves ws base url', () {
      const config = RelayConfig(baseUrl: 'ws://localhost:3000');
      expect(config.wsUrl, 'ws://localhost:3000');
    });

    // Regression: invite links are stored as wss:// (deep_link.dart), and the
    // previous getter only special-cased `https`, so a `wss` base fell through
    // to `ws` — downgrading the connection and breaking auth against a
    // TLS-terminated relay (e.g. StartOS on port 50596).
    test('preserves wss base url instead of downgrading to ws', () {
      const config = RelayConfig(baseUrl: 'wss://rusty-fingers.local:50596');
      expect(config.wsUrl, 'wss://rusty-fingers.local:50596');
    });

    test('preserves host, port and path when rewriting scheme', () {
      const config = RelayConfig(baseUrl: 'https://relay.example:8443/base');
      expect(config.wsUrl, 'wss://relay.example:8443/base');
    });
  });
}
