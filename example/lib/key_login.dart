/// The Trade tab's bearer: a pasted `bearer` wins; otherwise the test key logs in through
/// `POST /api/v1/user/authorize` in wallet-signature mode, and the token is kept in memory until it expires.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart' show WirexTradeTokenProvider;

import 'diag_log.dart';
import 'live_config.dart';
import 'test_signer.dart';

/// Why there is no bearer. Its message names fields and statuses, never a value.
class KeyLoginException implements Exception {
  const KeyLoginException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The login message `api-business` checks, character for character.
String loginMessage({required String owner, required String companyId, required String chainId, required int nonce}) =>
    'I, owner of account $owner confirm that I request access token for company $companyId on chain $chainId at $nonce';

/// The one login the Trade and Crypto tabs share, so the key signs in once for both.
final KeyLogin exampleLogin = KeyLogin();

/// Answers the bearer the Trade and Crypto tabs send, from [LiveConfig].
class KeyLogin implements WirexTradeTokenProvider {
  KeyLogin({http.Client? client, DateTime Function()? clock})
      : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _clock;

  String? _token;
  int _expiresAt = 0;
  String _tokenScope = '';

  /// Drops the cached login, so the next call logs in again.
  void reset() {
    _token = null;
    _expiresAt = 0;
  }

  @override
  Future<String> accessToken() async {
    final LiveConfig config = LiveConfig.instance;
    final String pasted = config.credential('bearer');
    if (pasted.isNotEmpty) return pasted;

    final String key = config.credential('ownerKey');
    final String companyId = config.credential('companyId');
    final String chainId = config.credential('chainId');
    final String base = config.credential('baasApiUrl').trim().replaceAll(RegExp(r'/+$'), '');
    final List<String> missing = <String>[
      if (key.isEmpty) 'ownerKey',
      if (companyId.isEmpty) 'companyId',
      if (chainId.isEmpty) 'chainId',
      if (base.isEmpty) 'baasApiUrl',
    ];
    if (missing.isNotEmpty) throw KeyLoginException('no bearer: paste one, or set ${missing.join(', ')}');
    // SECURITY: the signed login and the token go to this host, so it must be https.
    if (!base.startsWith('https://')) throw const KeyLoginException('baasApiUrl must be https');

    final TestSigner signer;
    try {
      signer = TestSigner.fromHex(key);
    } on FormatException catch (error) {
      throw KeyLoginException(error.message);
    }

    final int nowSeconds = _clock().millisecondsSinceEpoch ~/ 1000;
    final String scope = '${signer.address}|$companyId|$chainId|$base';
    final String? cached = _token;
    if (cached != null && scope == _tokenScope && nowSeconds < _expiresAt - 30) return cached;

    final String signature = hexOf(signer.signPersonalMessage(
        loginMessage(owner: signer.address, companyId: companyId, chainId: chainId, nonce: nowSeconds)));
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$base/api/v1/user/authorize'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'X-Company-Id': companyId,
          'X-Chain-Id': chainId,
        },
        body: jsonEncode(<String, Object>{
          'owner_address': signer.address,
          'message_signature': signature,
          'nonce': nowSeconds,
        }),
      );
    } on Exception catch (error) {
      DiagLog.instance.err('key login: ${error.runtimeType}');
      throw KeyLoginException('login failed: ${error.runtimeType}');
    }
    if (response.statusCode != 200) {
      final String reason = _errorReason(response.body);
      DiagLog.instance.err('key login: HTTP ${response.statusCode} $reason');
      throw KeyLoginException('login refused: HTTP ${response.statusCode} $reason'.trim());
    }
    final Object? body = _decode(response.body);
    final Object? token = body is Map<String, Object?> ? body['access_token'] : null;
    final Object? expiresAt = body is Map<String, Object?> ? body['expires_at'] : null;
    if (token is! String || token.isEmpty) throw const KeyLoginException('login answered no access_token');
    _token = token;
    _expiresAt = expiresAt is int ? expiresAt : nowSeconds;
    _tokenScope = scope;
    DiagLog.instance.app('key login ok: token ${token.length} chars, ${_expiresAt - nowSeconds}s');
    return token;
  }

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// The route's `error_reason` and its first `error_details` key: names, never values.
  static String _errorReason(String text) {
    final Object? body = _decode(text);
    if (body is! Map<String, Object?>) return '';
    final Object? reason = body['error_reason'];
    final Object? details = body['error_details'];
    final Object? first = details is List && details.isNotEmpty ? details.first : null;
    final Object? key = first is Map ? first['key'] : null;
    return <String>[if (reason is String) reason, if (key is String) key].join(' ');
  }
}
