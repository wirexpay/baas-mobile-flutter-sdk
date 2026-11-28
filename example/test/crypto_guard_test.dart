/// The Crypto tab's 10 USD cap on `production`: the typed amount, then what leaves at Send and Resume.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';
import 'package:wirex_mobile_sdk_example/crypto_guard.dart';

const String _usdc = '0x00000000000000000000000000000000000000c1';
const String _wusd = '0x00000000000000000000000000000000000000c2';
const String _eurc = '0x00000000000000000000000000000000000000c3';

WirexSendQuote _quote({String payToken = _usdc, String payUnits = '5060000', WirexSendUnwrap? unwrap}) => WirexSendQuote(
      sendId: '00000000-0000-4000-8000-000000000001',
      chainId: 8453,
      network: 'ETHEREUM',
      rail: WirexSendRail.cctp,
      token: 'USDC',
      to: '0x0000000000000000000000000000000000000009',
      amount: '5000000',
      fee: '60000',
      arrives: '5000000',
      payToken: payToken,
      payUnits: payUnits,
      validUntil: '1700000600',
      requestHash: '0x${'ab' * 32}',
      unwrap: unwrap,
    );

const List<WirexCryptoBalance> _balances = <WirexCryptoBalance>[
  WirexCryptoBalance(token: _usdc, symbol: 'USDC', units: '100000000', decimals: 6),
  WirexCryptoBalance(token: _wusd, symbol: 'WUSD', units: '100000000000000000000', decimals: 18),
  WirexCryptoBalance(token: _eurc, symbol: 'EURC', units: '100000000', decimals: 6),
];

void main() {
  group('refuseSend', () {
    test('counts USDC, USDT and WUSD at face value, up to 10.00', () {
      for (final String symbol in <String>['USDC', 'usdt', 'WUSD']) {
        expect(refuseSend(environment: 'production', symbol: symbol, cents: BigInt.from(1000)), isNull);
        expect(refuseSend(environment: 'production', symbol: symbol, cents: BigInt.from(1001)), contains('above 10 USD'));
      }
    });

    test('counts EURC and WEUR at 1.25, so 8.00 passes and 8.01 does not', () {
      expect(refuseSend(environment: 'production', symbol: 'EURC', cents: BigInt.from(800)), isNull);
      expect(refuseSend(environment: 'production', symbol: 'WEUR', cents: BigInt.from(801)), isNotNull);
    });

    test('refuses any other symbol and an unreadable worth, and caps nothing on test', () {
      expect(refuseSend(environment: 'production', symbol: 'ETH', cents: BigInt.one), contains('only USDC, USDT, WUSD'));
      expect(refuseSend(environment: 'production', symbol: 'USDC', cents: null), contains('cannot be read'));
      expect(refuseSend(environment: 'test', symbol: 'ETH', cents: null), isNull);
    });
  });

  test('sendTextCents rounds a typed amount up to the cent', () {
    expect(sendTextCents('10'), BigInt.from(1000));
    expect(sendTextCents(' 10.001 '), BigInt.from(1001));
    expect(sendTextCents('10.0010'), BigInt.from(1001));
    expect(sendTextCents('10.000'), BigInt.from(1000));
    expect(sendTextCents('0'), isNull);
    expect(sendTextCents('1e3'), isNull);
  });

  test('unitsCents rounds base units up to the cent', () {
    expect(unitsCents('10000000', 6), BigInt.from(1000));
    expect(unitsCents('10000001', 6), BigInt.from(1001));
    expect(unitsCents('x', 6), isNull);
  });

  group('refuseQuotedSend', () {
    test('what leaves is payUnits of payToken, the fee included', () {
      expect(refuseQuotedSend(environment: 'production', quote: _quote(), balances: _balances), isNull);
      expect(refuseQuotedSend(environment: 'production', quote: _quote(payUnits: '10000001'), balances: _balances),
          contains('above 10 USD'));
    });

    test('an unwrap leaves unwrap.units of unwrap.token, at its own decimals', () {
      final WirexSendQuote unwrapping = _quote(unwrap: const WirexSendUnwrap(token: _wusd, units: '5060000000000000000'));
      expect(sendLeaves(unwrapping).token, _wusd);
      expect(refuseQuotedSend(environment: 'production', quote: unwrapping, balances: _balances), isNull);
      final WirexSendQuote over = _quote(unwrap: const WirexSendUnwrap(token: _wusd, units: '10000000000000000001'));
      expect(refuseQuotedSend(environment: 'production', quote: over, balances: _balances), isNotNull);
    });

    test('a EURC send counts at 1.25', () {
      expect(refuseQuotedSend(environment: 'production', quote: _quote(payToken: _eurc, payUnits: '8000000'), balances: _balances),
          isNull);
      expect(refuseQuotedSend(environment: 'production', quote: _quote(payToken: _eurc, payUnits: '8000001'), balances: _balances),
          isNotNull);
    });

    test('refuses a paying token the balances do not list, and caps nothing on test', () {
      final WirexSendQuote stranger = _quote(payToken: '0x00000000000000000000000000000000000000ff');
      expect(refuseQuotedSend(environment: 'production', quote: stranger, balances: _balances), contains('not among the balances'));
      expect(refuseQuotedSend(environment: 'test', quote: stranger, balances: const <WirexCryptoBalance>[]), isNull);
    });
  });
}
