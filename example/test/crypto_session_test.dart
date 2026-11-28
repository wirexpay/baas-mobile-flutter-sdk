/// The Crypto tab's one `WirexCrypto`, rebuilt like the Trade tab's, and the login both tabs share.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';
import 'package:wirex_mobile_sdk_example/crypto_session.dart';
import 'package:wirex_mobile_sdk_example/key_login.dart';
import 'package:wirex_mobile_sdk_example/live_config.dart';
import 'package:wirex_mobile_sdk_example/trade_session.dart';

// The contract's synthetic test keys; both hold nothing.
const String _key1 = '0x0101010101010101010101010101010101010101010101010101010101010101';
const String _key2 = '0x0202020202020202020202020202020202020202020202020202020202020202';

class _FakeCrypto implements WirexCrypto {
  _FakeCrypto(this.testMode, this.chainId, this.address, this.tokenProvider);
  final bool testMode;
  final String chainId;
  final String address;
  final WirexCryptoTokenProvider tokenProvider;
  bool disposed = false;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final LiveConfig config = LiveConfig.instance;
  final List<_FakeCrypto> made = <_FakeCrypto>[];

  CryptoSession session() => CryptoSession(create: ({
        required bool testMode,
        required String chainId,
        required WirexCryptoTokenProvider tokenProvider,
        required WirexCryptoSigner signer,
      }) async {
        final _FakeCrypto crypto = _FakeCrypto(testMode, chainId, signer.address, tokenProvider);
        made.add(crypto);
        return crypto;
      });

  setUp(() {
    made.clear();
    config.resetCredentials();
    config.clearFileValues();
    config.applyCredentials(jsonEncode(<String, String>{'ownerKey': _key1, 'chainId': '8453', 'environment': 'production'}));
  });

  test('keeps one instance while the config holds, and rebuilds on a new environment, chain or key', () async {
    final CryptoSession cryptos = session();
    final WirexCrypto first = await cryptos.current();
    expect(await cryptos.current(), same(first));
    config.setCredential('environment', 'test');
    await cryptos.current();
    config.setCredential('chainId', '5042');
    await cryptos.current();
    config.setCredential('ownerKey', _key2);
    await cryptos.current();
    expect(made, hasLength(4));
    expect(made.take(3).every((_FakeCrypto crypto) => crypto.disposed), isTrue);
    expect(made.first.testMode, isFalse);
    expect(made[1].testMode, isTrue);
    expect(made[2].chainId, '5042');
    expect(made.last.address, '0x5050A4F4b3f9338C3472dcC01A87C76A144b3c9c');
  });

  test('names a missing field instead of building', () async {
    config.setCredential('chainId', '');
    await expectLater(session().current(), throwsA(isA<TradeUnavailable>()));
    expect(made, isEmpty);
  });

  test('the Trade and Crypto tabs share one login', () async {
    await session().current();
    expect(made.single.tokenProvider, same(exampleLogin));
    expect(TradeSession().login, same(exampleLogin));
  });
}
