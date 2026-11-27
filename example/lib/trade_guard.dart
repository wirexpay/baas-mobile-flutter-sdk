/// The Trade tab's spending cap: on `production` it refuses a trade worth more than 10 USD. The
/// example's rule, not the SDK's; the iOS, Android and React Native examples apply the same one.
library;

import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

/// The cap, in whole USD.
const int productionCapUsd = 10;

const String _overCap = 'refused: on production the example trades at most $productionCapUsd USD';
const String _unreadable = 'refused: on production the example trades only a worth it can read';

/// A buy's typed USD amount over the cap on `production`; null when it may be quoted.
String? refuseBuyAmount({required String environment, required String side, required String amount}) {
  if (environment != 'production' || side != 'buy') return null;
  final BigInt? micros = parseUnits(amount.trim(), 6);
  if (micros == null) return 'amount is not a USD amount with at most 6 decimals';
  // SECURITY: the first cap point, before any quote is asked for.
  return micros > BigInt.from(productionCapUsd * 1000000) ? _overCap : null;
}

/// A trade's worth in US cents, rounded up: a buy's USDC in (plus [transferFee]), a sale's USDC out.
/// Null when an amount is not a base-unit integer.
BigInt? worthCents({
  required WirexTradeSide side,
  required String amountIn,
  required int tokenInDecimals,
  required String estimatedAmountOut,
  required int tokenOutDecimals,
  String? transferFee,
}) {
  final bool buy = side == WirexTradeSide.buy;
  final BigInt? units = buy
      ? _sum(BigInt.tryParse(amountIn), transferFee == null ? BigInt.zero : BigInt.tryParse(transferFee))
      : BigInt.tryParse(estimatedAmountOut);
  final int decimals = buy ? tokenInDecimals : tokenOutDecimals;
  if (units == null || units.isNegative || decimals < 0) return null;
  final BigInt unit = BigInt.from(10).pow(decimals);
  return (units * BigInt.from(100) + unit - BigInt.one) ~/ unit;
}

/// A worth over the cap, or unreadable, on `production`; null when the trade may run.
String? refuseWorth({required String environment, required BigInt? cents}) {
  if (environment != 'production') return null;
  // SECURITY: the cap on what the engine would sign for; an unreadable worth is never let through.
  if (cents == null) return _unreadable;
  return cents > BigInt.from(productionCapUsd * 100) ? _overCap : null;
}

/// The quote's worth, as the quote and Execute check it.
BigInt? quoteWorthCents(WirexTradeQuote quote) => worthCents(
      side: quote.side,
      amountIn: quote.amountIn,
      tokenInDecimals: quote.tokenInDecimals,
      estimatedAmountOut: quote.estimatedAmountOut,
      tokenOutDecimals: quote.tokenOutDecimals,
      transferFee: quote.transferFee,
    );

/// An open order's worth, as Resume checks it. A buy counts `amountIn` alone.
BigInt? orderWorthCents(WirexTradeOrder order) => worthCents(
      side: order.side,
      amountIn: order.amountIn,
      tokenInDecimals: order.tokenInDecimals,
      estimatedAmountOut: order.estimatedAmountOut,
      tokenOutDecimals: order.tokenOutDecimals,
    );

/// Decimal text as base units at [decimals]; null for anything else, or more decimals than that.
BigInt? parseUnits(String text, int decimals) {
  final RegExpMatch? match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(text);
  if (match == null || decimals < 0) return null;
  final String fraction = match.group(2) ?? '';
  if (fraction.length > decimals) return null;
  final BigInt whole = BigInt.parse(match.group(1)!) * BigInt.from(10).pow(decimals);
  return decimals == 0 ? whole : whole + BigInt.parse(fraction.padRight(decimals, '0'));
}

/// Base units at [decimals] as decimal text, trailing zeros dropped; the text itself when unreadable.
String formatUnits(String units, int decimals) {
  final BigInt? value = BigInt.tryParse(units);
  if (value == null || value.isNegative || decimals < 0) return units;
  if (decimals == 0) return value.toString();
  final String digits = value.toString().padLeft(decimals + 1, '0');
  final String whole = digits.substring(0, digits.length - decimals);
  final String fraction = digits.substring(digits.length - decimals).replaceAll(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

/// Cents as `$12.34`, or a dash.
String formatCents(BigInt? cents) {
  if (cents == null) return '—';
  final String text = cents.toString().padLeft(3, '0');
  return '\$${text.substring(0, text.length - 2)}.${text.substring(text.length - 2)}';
}

BigInt? _sum(BigInt? a, BigInt? b) => a == null || b == null ? null : a + b;
