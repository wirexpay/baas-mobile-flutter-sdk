/// The one-line failure every example shows for a Trade call.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';
import 'package:wirex_mobile_sdk_example/key_login.dart';
import 'package:wirex_mobile_sdk_example/trade_error_line.dart';
import 'package:wirex_mobile_sdk_example/trade_session.dart';

void main() {
  test('each of the five hints', () {
    expect(tradeErrorLine(const WirexTradeError('signer_mismatch', step: WirexTradeStep.setup)),
        'signer_mismatch · (the key does not own this account) · step setup');
    expect(tradeErrorLine(const WirexTradeError('investment_wallet_required')),
        'investment_wallet_required · (set up the account first)');
    expect(tradeErrorLine(const WirexTradeError('quote_expired')), 'quote_expired · (get a new quote)');
    expect(tradeErrorLine(const WirexTradeError('insufficient_funds')),
        'insufficient_funds · (the main account cannot cover the buy)');
    expect(tradeErrorLine(const WirexTradeError('order_not_ended', step: WirexTradeStep.awaitOrder)),
        'order_not_ended · (the order is still open: resume it from Open orders) · step awaitOrder');
    expect(tradeReasonHints, hasLength(5));
  });

  test('any other reason shows plainly, quote_required included', () {
    expect(tradeErrorLine(const WirexTradeError('quote_required')), 'quote_required');
  });

  test('every part, in order', () {
    expect(
      tradeErrorLine(const WirexTradeError(
        'api_error',
        step: WirexTradeStep.submit,
        routeReason: 'ErrorGeneral',
        detailKey: 'amount',
        httpStatus: 400,
        entryPointCode: 'AA22',
      )),
      'api_error · step submit · route ErrorGeneral / amount · HTTP 400 · AA22',
    );
  });

  test('leaves out each part that is absent', () {
    expect(tradeErrorLine(const WirexTradeError('rpc_error', entryPointCode: 'AA25')), 'rpc_error · AA25');
    expect(tradeErrorLine(const WirexTradeError('api_error', routeReason: 'ErrorNotFound', httpStatus: 404)),
        'api_error · route ErrorNotFound · HTTP 404');
    expect(tradeErrorLine(const WirexTradeError('api_error', detailKey: 'nonce')), 'api_error · route nonce');
  });

  test('a login, a config gap, a disposed trade and anything else', () {
    expect(tradeErrorLine(const KeyLoginException('baasApiUrl must be https')), 'baasApiUrl must be https');
    expect(tradeErrorLine(const TradeUnavailable('set ownerKey on the Config tab')), 'set ownerKey on the Config tab');
    expect(tradeErrorLine(StateError('WirexTrade: disposed')), contains('tap again'));
    expect(tradeErrorLine(Exception('0xsecret')), isNot(contains('0xsecret')));
  });

  test('a crypto failure takes the Crypto hints, word for word', () {
    expect(cryptoReasonHints, hasLength(12));
    expect(tradeErrorLine(const WirexCryptoError('insufficient_funds', step: WirexCryptoStep.request)),
        'insufficient_funds · (the main account cannot cover the send) · step request');
    expect(tradeErrorLine(const WirexCryptoError('quote_mismatch')), "quote_mismatch · (the quote is not this send's)");
    expect(tradeErrorLine(const WirexCryptoError('bridge_refused', httpStatus: 422)), 'bridge_refused · HTTP 422');
    expect(tradeErrorLine(const WirexCryptoError('token_unavailable')), 'token_unavailable · (sign in again)');
  });
}
