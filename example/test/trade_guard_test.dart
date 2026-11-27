/// The Trade tab's 10 USD cap on `production`, and its amount maths.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';
import 'package:wirex_mobile_sdk_example/trade_guard.dart';

BigInt? _worth(WirexTradeSide side, String amountIn, String out, {String? fee, int inDecimals = 6, int outDecimals = 6}) =>
    worthCents(
      side: side,
      amountIn: amountIn,
      tokenInDecimals: inDecimals,
      estimatedAmountOut: out,
      tokenOutDecimals: outDecimals,
      transferFee: fee,
    );

WirexTradeOrder _order(WirexTradeSide side, String amountIn, String out) => WirexTradeOrder(
      orderId: 'order-1',
      market: WirexTradeMarket.stock,
      side: side,
      token: '0x0000000000000000000000000000000000000001',
      wallet: '0x0000000000000000000000000000000000000002',
      status: 'AwaitingFunds',
      tokenIn: '0x0000000000000000000000000000000000000003',
      amountIn: amountIn,
      tokenInDecimals: side == WirexTradeSide.buy ? 6 : 18,
      tokenOut: '0x0000000000000000000000000000000000000004',
      estimatedAmountOut: out,
      minimumAmountOut: '0',
      amountOut: '0',
      tokenOutDecimals: side == WirexTradeSide.buy ? 18 : 6,
      refundedAmount: '0',
      feeAmount: '0',
      recipient: '0x0000000000000000000000000000000000000005',
      returnTo: '0x0000000000000000000000000000000000000006',
      validUntil: '2026-01-01T00:00:00Z',
    );

void main() {
  group('refuseBuyAmount', () {
    test('lets a buy of up to 10 USD through on production', () {
      expect(refuseBuyAmount(environment: 'production', side: 'buy', amount: '10'), isNull);
      expect(refuseBuyAmount(environment: 'production', side: 'buy', amount: '9.999999'), isNull);
    });

    test('refuses more than 10 USD on production', () {
      expect(refuseBuyAmount(environment: 'production', side: 'buy', amount: '10.000001'), contains('at most 10 USD'));
      expect(refuseBuyAmount(environment: 'production', side: 'buy', amount: '250'), contains('at most 10 USD'));
    });

    test('refuses an amount it cannot read', () {
      expect(refuseBuyAmount(environment: 'production', side: 'buy', amount: '1e3'), isNotNull);
      expect(refuseBuyAmount(environment: 'production', side: 'buy', amount: '1.0000001'), isNotNull);
      expect(refuseBuyAmount(environment: 'production', side: 'buy', amount: ''), isNotNull);
    });

    test('caps nothing on test, and leaves a sale to the quote', () {
      expect(refuseBuyAmount(environment: 'test', side: 'buy', amount: '250'), isNull);
      expect(refuseBuyAmount(environment: 'production', side: 'sell', amount: '250'), isNull);
    });
  });

  group('worthCents', () {
    test('rounds up to the cent', () {
      expect(_worth(WirexTradeSide.buy, '10000000', '0'), BigInt.from(1000));
      expect(_worth(WirexTradeSide.buy, '10000001', '0'), BigInt.from(1001));
      expect(_worth(WirexTradeSide.buy, '1', '0'), BigInt.one);
      expect(_worth(WirexTradeSide.buy, '0', '0'), BigInt.zero);
    });

    test('a buy adds the Arc transfer fee; a sale is the USDC it pays', () {
      expect(_worth(WirexTradeSide.buy, '9990000', '0', fee: '10000'), BigInt.from(1000));
      expect(_worth(WirexTradeSide.sell, '5000000000000000000', '10000000', inDecimals: 18), BigInt.from(1000));
    });

    test('is null for amounts that are not base-unit integers', () {
      expect(_worth(WirexTradeSide.buy, '1.5', '0'), isNull);
      expect(_worth(WirexTradeSide.buy, '1', '0', fee: 'x'), isNull);
      expect(_worth(WirexTradeSide.sell, '1', ''), isNull);
    });
  });

  group('refuseWorth', () {
    test('lets 10.00 USD through and refuses 10.01 on production', () {
      expect(refuseWorth(environment: 'production', cents: BigInt.from(1000)), isNull);
      expect(refuseWorth(environment: 'production', cents: BigInt.from(1001)), contains('at most 10 USD'));
    });

    test('a buy of 10.000001 USD rounds up to 10.01 and is refused', () {
      expect(refuseWorth(environment: 'production', cents: _worth(WirexTradeSide.buy, '10000001', '0')), isNotNull);
    });

    test('refuses an unreadable worth on production, and caps nothing on test', () {
      expect(refuseWorth(environment: 'production', cents: null), isNotNull);
      expect(refuseWorth(environment: 'test', cents: null), isNull);
      expect(refuseWorth(environment: 'test', cents: BigInt.from(99999)), isNull);
    });
  });

  group('orderWorthCents', () {
    test('an open buy counts amountIn alone', () {
      expect(orderWorthCents(_order(WirexTradeSide.buy, '10000000', '1')), BigInt.from(1000));
      expect(orderWorthCents(_order(WirexTradeSide.buy, '10000001', '1')), BigInt.from(1001));
    });

    test('an open sale counts estimatedAmountOut', () {
      expect(orderWorthCents(_order(WirexTradeSide.sell, '1', '12345678')), BigInt.from(1235));
    });
  });

  group('amounts', () {
    test('parseUnits reads decimal text at the given decimals', () {
      expect(parseUnits('10', 6), BigInt.from(10000000));
      expect(parseUnits('0.5', 18), BigInt.parse('500000000000000000'));
      expect(parseUnits('3', 0), BigInt.from(3));
      expect(parseUnits('1.5', 0), isNull);
      expect(parseUnits('-1', 6), isNull);
    });

    test('formatUnits and formatCents show what the tab shows', () {
      expect(formatUnits('12345678', 6), '12.345678');
      expect(formatUnits('10000000', 6), '10');
      expect(formatUnits('5', 6), '0.000005');
      expect(formatUnits('x', 6), 'x');
      expect(formatCents(BigInt.from(1235)), r'$12.35');
      expect(formatCents(BigInt.from(5)), r'$0.05');
      expect(formatCents(null), '—');
    });
  });
}
