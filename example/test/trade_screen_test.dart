/// The Trade tab hands `quote` the amount as typed: the engine converts it, not the example.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';
import 'package:wirex_mobile_sdk_example/live_config.dart';
import 'package:wirex_mobile_sdk_example/trade_screen.dart';
import 'package:wirex_mobile_sdk_example/trade_session.dart';

// The contract's synthetic test key 1; it holds nothing.
const String _key1 = '0x0101010101010101010101010101010101010101010101010101010101010101';

class _QuotingTrade implements WirexTrade {
  final List<String> amounts = <String>[];

  @override
  Future<WirexTradeQuote> quote({
    required WirexTradeMarket market,
    required WirexTradeSide side,
    required String symbol,
    required String amount,
  }) async {
    amounts.add(amount);
    return WirexTradeQuote(
      orderId: 'order-1',
      market: market,
      side: side,
      symbol: symbol,
      token: '0x0000000000000000000000000000000000000001',
      wallet: '0x0000000000000000000000000000000000000002',
      executionMethod: 'System',
      tokenIn: '0x0000000000000000000000000000000000000003',
      amountIn: '5000000',
      tokenInDecimals: 6,
      tokenOut: '0x0000000000000000000000000000000000000004',
      estimatedAmountOut: '1',
      minimumAmountOut: '1',
      tokenOutDecimals: 18,
      recipient: '0x0000000000000000000000000000000000000005',
      returnTo: '0x0000000000000000000000000000000000000006',
      validUntil: '2026-01-01T00:00:00Z',
      storeTo: '0x0000000000000000000000000000000000000007',
      storeData: '0x',
      feeAmount: '0',
      signBy: '2025-12-31T23:59:00Z',
    );
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('a typed "5" goes to quote as "5"', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    LiveConfig.instance
      ..resetCredentials()
      ..clearFileValues()
      ..applyCredentials(jsonEncode(<String, String>{
        'ownerKey': _key1, 'chainId': '8453', 'environment': 'production', 'bearer': 'fake-bearer',
      }));
    final _QuotingTrade trade = _QuotingTrade();
    final TradeSession session = TradeSession(create: ({
      required bool testMode,
      required String chainId,
      required WirexTradeTokenProvider tokenProvider,
      required WirexTradeSigner signer,
    }) async =>
        trade);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TradeScreen(session: session))));
    await tester.enterText(find.widgetWithText(TextField, 'Symbol'), 'AAPL');
    await tester.enterText(find.widgetWithText(TextField, 'Amount, USD'), ' 5 ');
    await tester.tap(find.widgetWithText(FilledButton, 'Get quote'));
    await tester.pumpAndSettle();

    expect(trade.amounts, <String>['5']);
  });
}
