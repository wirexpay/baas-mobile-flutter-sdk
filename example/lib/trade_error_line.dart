/// One line for a failed Trade or Crypto call, the same on every example:
/// `reason · (hint) · step <step> · route <routeReason> / <detailKey> · HTTP <status> · <entryPointCode>`.
library;

import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

import 'key_login.dart';
import 'trade_session.dart';

/// The hints the tab adds to a reason. Any other reason shows plainly.
const Map<String, String> tradeReasonHints = <String, String>{
  'signer_mismatch': 'the key does not own this account',
  'investment_wallet_required': 'set up the account first',
  'quote_expired': 'get a new quote',
  'insufficient_funds': 'the main account cannot cover the buy',
  'order_not_ended': 'the order is still open: resume it from Open orders',
};

/// The Crypto tab's hints, word for word as the other examples show them.
const Map<String, String> cryptoReasonHints = <String, String>{
  'invalid_address': 'the recipient is not an address of that network',
  'recipient_is_account': 'the recipient is the main account itself',
  'insufficient_funds': 'the main account cannot cover the send',
  'quote_expired': 'get a new quote',
  'quote_mismatch': "the quote is not this send's",
  'over_limit': 'try a smaller amount',
  'amount_too_small': 'try a larger amount',
  'bridge_unavailable': 'the bridge is unavailable: try again later',
  'rhino_key_missing': 'the company has no rhino.fi key',
  'deposit_unavailable': 'no deposit network is left: ask again later',
  'signer_mismatch': 'the key does not own this account',
  'token_unavailable': 'sign in again',
};

/// The parts that are present, joined with ` · `. [hints] defaults to the Trade tab's.
String tradeErrorParts({
  required String reason,
  Map<String, String> hints = tradeReasonHints,
  String? step,
  String? routeReason,
  String? detailKey,
  int? httpStatus,
  String? entryPointCode,
}) {
  final String route = <String>[?routeReason, ?detailKey].join(' / ');
  final String? hint = hints[reason];
  return <String>[
    reason,
    if (hint != null) '($hint)',
    if (step != null) 'step $step',
    if (route.isNotEmpty) 'route $route',
    if (httpStatus != null) 'HTTP $httpStatus',
    ?entryPointCode,
  ].join(' · ');
}

/// [error] as one line. Never the text of an unknown error, which may quote a value.
String tradeErrorLine(Object error) => switch (error) {
      WirexTradeError() => tradeErrorParts(
          reason: error.reason,
          step: error.step?.wire,
          routeReason: error.routeReason,
          detailKey: error.detailKey,
          httpStatus: error.httpStatus,
          entryPointCode: error.entryPointCode,
        ),
      WirexCryptoError() => tradeErrorParts(
          reason: error.reason,
          hints: cryptoReasonHints,
          step: error.step?.wire,
          routeReason: error.routeReason,
          detailKey: error.detailKey,
          httpStatus: error.httpStatus,
          entryPointCode: error.entryPointCode,
        ),
      KeyLoginException() => error.message,
      TradeUnavailable() => error.message,
      StateError() => 'the trade was rebuilt for a new config: tap again',
      _ => 'failed: ${error.runtimeType}',
    };
