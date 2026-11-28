/// The Crypto tab on a fake engine: the typed amount, Check delivery off `transfer`, Resume by
/// `requestHash`, and the cap at Send. Nothing crosses a channel.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';
import 'package:wirex_mobile_sdk_example/crypto_screen.dart';
import 'package:wirex_mobile_sdk_example/crypto_session.dart';
import 'package:wirex_mobile_sdk_example/live_config.dart';

// The contract's synthetic test key 1; it holds nothing.
const String _key1 = '0x0101010101010101010101010101010101010101010101010101010101010101';
const String _usdc = '0x00000000000000000000000000000000000000c1';
const String _hash = '0xabababababababababababababababababababababababababababababababab';

class _FakeCrypto implements WirexCrypto {
  _FakeCrypto({this.rail = WirexSendRail.cctp, this.payUnits = '5060000', this.pending = const <WirexPendingSend>[]});
  final WirexSendRail rail;
  final String payUnits;
  final List<WirexPendingSend> pending;
  final List<String> amounts = <String>[];
  final List<WirexSendQuote> sent = <WirexSendQuote>[];
  final List<String> resumed = <String>[];

  @override
  Future<List<WirexCryptoBalance>> balances() async =>
      const <WirexCryptoBalance>[WirexCryptoBalance(token: _usdc, symbol: 'USDC', units: '100000000', decimals: 6)];

  @override
  Future<WirexSendQuote> quoteSend({
    required String to,
    required String network,
    required String token,
    required String amount,
    String? provider,
  }) async {
    amounts.add(amount);
    return WirexSendQuote(
      sendId: '00000000-0000-4000-8000-000000000001',
      chainId: 8453,
      network: network,
      rail: rail,
      token: token,
      to: to,
      amount: '5000000',
      fee: '60000',
      arrives: '5000000',
      payToken: _usdc,
      payUnits: payUnits,
      validUntil: '1700000600',
      requestHash: _hash,
    );
  }

  @override
  Future<WirexSendResult> send(WirexSendQuote quote, {WirexCryptoStepListener? onStep}) async {
    sent.add(quote);
    return WirexSendResult(sendId: quote.sendId, rail: quote.rail, transactionHash: '0x${'cd' * 32}');
  }

  @override
  Future<WirexSendResult> resumeSend(String sendId, WirexSendQuote quote, {WirexCryptoStepListener? onStep}) async {
    resumed.add(sendId);
    return WirexSendResult(sendId: sendId, rail: quote.rail);
  }

  @override
  Future<List<WirexPendingSend>> pendingSends() async => pending;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WirexPendingSend _row(String hash) => WirexPendingSend(
      hash: hash,
      token: _usdc,
      destination: '0x0000000000000000000000000000000000000009',
      units: '5060000',
      decimals: 6,
      validAfter: '2026-01-01T00:00:00Z',
      validBefore: '2026-01-01T00:10:00Z',
    );

Future<void> _open(WidgetTester tester, _FakeCrypto crypto) async {
  tester.view.physicalSize = const Size(1400, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  LiveConfig.instance
    ..resetCredentials()
    ..clearFileValues()
    ..applyCredentials(jsonEncode(<String, String>{
      'ownerKey': _key1, 'chainId': '8453', 'environment': 'production', 'bearer': 'fake-bearer',
    }));
  final CryptoSession session = CryptoSession(create: ({
    required bool testMode,
    required String chainId,
    required WirexCryptoTokenProvider tokenProvider,
    required WirexCryptoSigner signer,
  }) async =>
      crypto);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: CryptoScreen(session: session))));
}

Future<void> _quote(WidgetTester tester, String amount) async {
  await tester.enterText(find.widgetWithText(TextField, 'Recipient, an address on that network'),
      '0x0000000000000000000000000000000000000009');
  await tester.enterText(find.widgetWithText(TextField, 'Amount, what arrives'), amount);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Get quote'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a typed amount reaches quoteSend trimmed, and Check delivery shows off transfer', (WidgetTester tester) async {
    final _FakeCrypto crypto = _FakeCrypto();
    await _open(tester, crypto);
    await _quote(tester, ' 5 ');
    expect(crypto.amounts, <String>['5']);
    await _tap(tester, 'Send');
    expect(crypto.sent, hasLength(1));
    expect(find.widgetWithText(FilledButton, 'Check delivery'), findsOneWidget);
  });

  testWidgets('no Check delivery after a transfer', (WidgetTester tester) async {
    final _FakeCrypto crypto = _FakeCrypto(rail: WirexSendRail.transfer);
    await _open(tester, crypto);
    await _quote(tester, '5');
    await _tap(tester, 'Send');
    expect(crypto.sent, hasLength(1));
    expect(find.widgetWithText(FilledButton, 'Check delivery'), findsNothing);
  });

  testWidgets('Resume finds the held quote by requestHash in any case; a stranger row stays off', (WidgetTester tester) async {
    final _FakeCrypto crypto = _FakeCrypto(pending: <WirexPendingSend>[_row(_hash.toUpperCase().replaceFirst('0X', '0x')), _row('0x${'ef' * 32}')]);
    await _open(tester, crypto);
    await _quote(tester, '5');
    await _tap(tester, 'Load pending');
    expect(find.textContaining('no quote held for this send'), findsOneWidget);
    final Finder resumes = find.widgetWithText(FilledButton, 'Resume');
    expect(resumes, findsNWidgets(2));
    expect(tester.widget<FilledButton>(resumes.at(1)).onPressed, isNull);
    await tester.tap(resumes.first);
    await tester.pumpAndSettle();
    expect(crypto.resumed, <String>['00000000-0000-4000-8000-000000000001']);
  });

  testWidgets('a typed amount over the cap leaves Get quote off', (WidgetTester tester) async {
    final _FakeCrypto crypto = _FakeCrypto();
    await _open(tester, crypto);
    await _quote(tester, '10.01');
    expect(crypto.amounts, isEmpty);
    expect(find.textContaining('above 10 USD'), findsOneWidget);
  });

  testWidgets('Send refuses a quote whose fee takes it over the cap', (WidgetTester tester) async {
    final _FakeCrypto crypto = _FakeCrypto(payUnits: '10060000');
    await _open(tester, crypto);
    await _quote(tester, '10');
    await _tap(tester, 'Send');
    expect(crypto.sent, isEmpty);
    expect(find.textContaining('above 10 USD'), findsOneWidget);
  });
}
