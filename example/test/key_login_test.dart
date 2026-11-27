/// The Trade tab's bearer, against a fake `api-business`: nothing here reaches a network.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wirex_mobile_sdk_example/key_login.dart';
import 'package:wirex_mobile_sdk_example/live_config.dart';

// Contract test key 1: synthetic, holds nothing.
const String _key = '0x0101010101010101010101010101010101010101010101010101010101010101';
const String _owner = '0x1a642f0E3c3aF545E7AcBD38b07251B3990914F1';
const String _company = '11111111-1111-1111-1111-111111111111';
const String _base = 'https://api.example.invalid';
// viem's `signMessage` of the login message for _owner, _company, chain 8453 and nonce 1700000000.
const String _signature =
    '0x896151005f262445a45c3de1326dd86e081f545b720bb1b7ac2d5cec2694539a6e9eb858438dcd27505a85302e1af9b4bd0536c4f25643a81f0a76b477bb3c7e1b';

void main() {
  final LiveConfig config = LiveConfig.instance;
  final List<http.Request> requests = <http.Request>[];
  DateTime now = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);

  MockClient answering(int status, Map<String, Object?> body) => MockClient((http.Request request) async {
        requests.add(request);
        return http.Response(jsonEncode(body), status);
      });

  setUp(() {
    requests.clear();
    now = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
    config.resetCredentials();
    config.clearFileValues();
    config.applyCredentials(jsonEncode(<String, String>{
      'ownerKey': _key, 'companyId': _company, 'chainId': '8453', 'baasApiUrl': '$_base/',
    }));
  });

  test('the message is the template, character for character', () {
    expect(
      loginMessage(owner: _owner, companyId: _company, chainId: '8453', nonce: 1700000000),
      'I, owner of account $_owner confirm that I request access token for company $_company on chain 8453 at 1700000000',
    );
  });

  test('logs in with the signed message, the headers and the nonce in Unix seconds', () async {
    final KeyLogin login = KeyLogin(
        client: answering(200, <String, Object?>{'access_token': 'fake-token', 'expires_at': 1700003600}),
        clock: () => now);

    expect(await login.accessToken(), 'fake-token');
    expect(requests, hasLength(1));
    final http.Request request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), '$_base/api/v1/user/authorize');
    expect(request.headers['X-Company-Id'], _company);
    expect(request.headers['X-Chain-Id'], '8453');
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(jsonDecode(request.body), <String, Object?>{
      'owner_address': _owner,
      'message_signature': _signature,
      'nonce': 1700000000,
    });
  });

  test('keeps the token until 30 seconds before it expires', () async {
    final KeyLogin login = KeyLogin(
        client: answering(200, <String, Object?>{'access_token': 'fake-token', 'expires_at': 1700000100}),
        clock: () => now);
    await login.accessToken();
    now = now.add(const Duration(seconds: 60));
    await login.accessToken();
    expect(requests, hasLength(1));
    now = now.add(const Duration(seconds: 20));
    await login.accessToken();
    expect(requests, hasLength(2));
  });

  test('a pasted bearer wins, and nothing is sent', () async {
    config.setCredential('bearer', 'pasted-bearer');
    final KeyLogin login = KeyLogin(client: answering(500, <String, Object?>{}), clock: () => now);
    expect(await login.accessToken(), 'pasted-bearer');
    expect(requests, isEmpty);
  });

  test('refuses a base that is not https, before signing or sending', () async {
    config.setCredential('baasApiUrl', 'http://api.example.invalid');
    final KeyLogin login = KeyLogin(client: answering(200, <String, Object?>{}), clock: () => now);
    await expectLater(login.accessToken(), throwsA(isA<KeyLoginException>()));
    expect(requests, isEmpty);
  });

  test('names the missing fields', () async {
    config.setCredential('companyId', '');
    config.setCredential('ownerKey', '');
    final KeyLogin login = KeyLogin(client: answering(200, <String, Object?>{}), clock: () => now);
    await expectLater(
      login.accessToken(),
      throwsA(isA<KeyLoginException>().having((KeyLoginException e) => e.message, 'message', contains('ownerKey, companyId'))),
    );
  });

  test('a refused login names the route reason and the field, never the key', () async {
    final KeyLogin login = KeyLogin(
        client: answering(401, <String, Object?>{
          'error_reason': 'ErrorExpired',
          'error_details': <Object?>[
            <String, Object?>{'key': 'nonce', 'details': 'Signed message has expired'},
          ],
        }),
        clock: () => now);
    await expectLater(
      login.accessToken(),
      throwsA(isA<KeyLoginException>()
          .having((KeyLoginException e) => e.message, 'message', 'login refused: HTTP 401 ErrorExpired nonce')),
    );
  });
}
