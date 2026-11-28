/// The Crypto tab's spending cap: on `production` it refuses a send worth more than 10 USD. The
/// example's rule, not the SDK's; every example applies the same one.
library;

import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

const int _capCents = 1000;

/// USD per unit of each token a production send may move, as a fraction. EUR is overstated on purpose.
const Map<String, (int, int)> _capRates = <String, (int, int)>{
  'USDC': (1, 1),
  'USDT': (1, 1),
  'WUSD': (1, 1),
  'EURC': (5, 4),
  'WEUR': (5, 4),
};

/// The typed amount in cents of its token, rounded up; null unless it is a positive decimal.
BigInt? sendTextCents(String text) {
  final RegExpMatch? match = RegExp(r'^([0-9]+)(?:\.([0-9]+))?$').firstMatch(text.trim());
  if (match == null) return null;
  final String fraction = match.group(2) ?? '';
  final BigInt cents = BigInt.parse(match.group(1)!) * BigInt.from(100) + BigInt.parse('${fraction}00'.substring(0, 2));
  final BigInt rest = fraction.length > 2 && RegExp('[1-9]').hasMatch(fraction.substring(2)) ? BigInt.one : BigInt.zero;
  final BigInt total = cents + rest;
  return total > BigInt.zero ? total : null;
}

/// Base units at [decimals] in cents of the token, rounded up; null when unreadable.
BigInt? unitsCents(String units, int decimals) {
  if (!RegExp(r'^[0-9]+$').hasMatch(units) || decimals < 0) return null;
  final BigInt scale = BigInt.from(10).pow(decimals);
  return (BigInt.parse(units) * BigInt.from(100) + scale - BigInt.one) ~/ scale;
}

/// A send of [cents] of [symbol] over the cap on `production`; null when it may run.
String? refuseSend({required String environment, required String symbol, required BigInt? cents}) {
  if (environment != 'production') return null;
  final (int, int)? rate = _capRates[symbol.trim().toUpperCase()];
  // SECURITY: on production only the listed stablecoins count toward the cap; any other token is refused.
  if (rate == null) return 'refused: on production only USDC, USDT, WUSD, EURC and WEUR can be sent';
  if (cents == null) return 'refused: the send worth cannot be read';
  final BigInt worth = (cents * BigInt.from(rate.$1) + BigInt.from(rate.$2 - 1)) ~/ BigInt.from(rate.$2);
  return worth > BigInt.from(_capCents) ? 'refused: a production send above 10 USD' : null;
}

/// What leaves the main account: the unwrapped synthetic when the quote unwraps, otherwise the pay token.
({String token, String units}) sendLeaves(WirexSendQuote quote) {
  final WirexSendUnwrap? unwrap = quote.unwrap;
  return unwrap == null ? (token: quote.payToken, units: quote.payUnits) : (token: unwrap.token, units: unwrap.units);
}

/// The cap on a quote at Send and Resume, with the paying token's symbol and decimals from fresh [balances].
String? refuseQuotedSend({
  required String environment,
  required WirexSendQuote quote,
  required List<WirexCryptoBalance> balances,
}) {
  if (environment != 'production') return null;
  final ({String token, String units}) leaves = sendLeaves(quote);
  WirexCryptoBalance? row;
  for (final WirexCryptoBalance balance in balances) {
    if (balance.token.toLowerCase() == leaves.token.toLowerCase()) row = balance;
  }
  // SECURITY: what leaves is read in its own token; a token the balances do not list is never let through.
  if (row == null) return 'refused: the paying token is not among the balances';
  return refuseSend(environment: environment, symbol: row.symbol, cents: unitsCents(leaves.units, row.decimals));
}
