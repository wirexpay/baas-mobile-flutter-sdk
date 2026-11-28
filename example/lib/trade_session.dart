/// The Trade tab's one `WirexTrade`, built from the config and rebuilt, the old one disposed, when
/// the environment, the chain or the key's address changes.
library;

import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

import 'diag_log.dart';
import 'key_login.dart';
import 'live_config.dart';
import 'test_signer.dart';

/// Why there is no `WirexTrade`: a config field is missing or wrong. Names fields, never values.
class TradeUnavailable implements Exception {
  const TradeUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The SDK's signer, over the example's test key. FOR TESTING ONLY, as `test_signer.dart` says.
class ExampleTradeSigner implements WirexTradeSigner {
  ExampleTradeSigner(this._signer);

  final TestSigner _signer;

  @override
  String get address => _signer.address;

  @override
  Future<String> signPersonal(String hash) async => hexOf(_signer.signPersonalHash(hexToBytes(hash)));
}

typedef TradeFactory = Future<WirexTrade> Function({
  required bool testMode,
  required String chainId,
  required WirexTradeTokenProvider tokenProvider,
  required WirexTradeSigner signer,
});

Future<WirexTrade> _createTrade({
  required bool testMode,
  required String chainId,
  required WirexTradeTokenProvider tokenProvider,
  required WirexTradeSigner signer,
}) =>
    WirexTrade.create(testMode: testMode, chainId: chainId, tokenProvider: tokenProvider, signer: signer);

class TradeSession {
  TradeSession({KeyLogin? login, TradeFactory? create})
      : login = login ?? exampleLogin,
        _create = create ?? _createTrade;

  final KeyLogin login;
  final TradeFactory _create;
  WirexTrade? _trade;
  String _key = '';

  /// The key a `WirexTrade` is built for: test mode, chain and the signer's address.
  static String keyFor({required bool testMode, required String chainId, required String address}) =>
      '$testMode|$chainId|$address';

  /// The trade for the config as it stands, rebuilt when its key changed. Call it only between calls.
  Future<WirexTrade> current() async {
    final LiveConfig config = LiveConfig.instance;
    final String ownerKey = config.credential('ownerKey');
    final String chainId = config.credential('chainId');
    final List<String> missing = <String>[if (ownerKey.isEmpty) 'ownerKey', if (chainId.isEmpty) 'chainId'];
    if (missing.isNotEmpty) throw TradeUnavailable('set ${missing.join(', ')} on the Config tab');
    final TestSigner signer;
    try {
      signer = TestSigner.fromHex(ownerKey);
    } on FormatException catch (error) {
      throw TradeUnavailable(error.message);
    }
    final String key = keyFor(testMode: config.isTestMode, chainId: chainId, address: signer.address);
    final WirexTrade? existing = _trade;
    if (existing != null && key == _key) return existing;
    _trade = null;
    _key = '';
    if (existing != null) await existing.dispose();
    final WirexTrade trade = await _create(
      testMode: config.isTestMode,
      chainId: chainId,
      tokenProvider: login,
      signer: ExampleTradeSigner(signer),
    );
    _trade = trade;
    _key = key;
    DiagLog.instance.sdk('trade created (testMode=${config.isTestMode}, chainId ${chainId.length} chars)');
    return trade;
  }

  Future<void> dispose() async {
    final WirexTrade? trade = _trade;
    _trade = null;
    _key = '';
    await trade?.dispose();
  }
}
