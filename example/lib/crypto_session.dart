/// The Crypto tab's one `WirexCrypto`, built from the config and rebuilt, the old one disposed, when
/// the environment, the chain or the key's address changes.
library;

import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

import 'diag_log.dart';
import 'key_login.dart';
import 'live_config.dart';
import 'test_signer.dart';
import 'trade_session.dart';

typedef CryptoFactory = Future<WirexCrypto> Function({
  required bool testMode,
  required String chainId,
  required WirexCryptoTokenProvider tokenProvider,
  required WirexCryptoSigner signer,
});

Future<WirexCrypto> _createCrypto({
  required bool testMode,
  required String chainId,
  required WirexCryptoTokenProvider tokenProvider,
  required WirexCryptoSigner signer,
}) =>
    WirexCrypto.create(testMode: testMode, chainId: chainId, tokenProvider: tokenProvider, signer: signer);

class CryptoSession {
  CryptoSession({KeyLogin? login, CryptoFactory? create})
      : login = login ?? exampleLogin,
        _create = create ?? _createCrypto;

  final KeyLogin login;
  final CryptoFactory _create;
  WirexCrypto? _crypto;
  String _key = '';

  /// The instance for the config as it stands, rebuilt when its key changed. Call it only between calls.
  Future<WirexCrypto> current() async {
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
    final String key = TradeSession.keyFor(testMode: config.isTestMode, chainId: chainId, address: signer.address);
    final WirexCrypto? existing = _crypto;
    if (existing != null && key == _key) return existing;
    _crypto = null;
    _key = '';
    if (existing != null) await existing.dispose();
    final WirexCrypto crypto = await _create(
      testMode: config.isTestMode,
      chainId: chainId,
      tokenProvider: login,
      signer: ExampleTradeSigner(signer),
    );
    _crypto = crypto;
    _key = key;
    DiagLog.instance.sdk('crypto created (testMode=${config.isTestMode}, chainId ${chainId.length} chars)');
    return crypto;
  }

  Future<void> dispose() async {
    final WirexCrypto? crypto = _crypto;
    _crypto = null;
    _key = '';
    await crypto?.dispose();
  }
}
