/// Text fields → `WirexWalletQuote`: the Checkout tab's only real parsing, pinned by
/// `test/quote_fields_test.dart`.
///
/// Amounts stay STRINGS on purpose: `WirexWalletMoney.amount` is passed to the frame as the host
/// has it and the frame formats — the example does no arithmetic and no locale parsing on them.
/// The one number parsed is the expiry, because the SDK wants an instant (`expiresAtMs`) and a
/// text field wants a duration.
library;

import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

const String defaultEstimationId = 'example-1';
const String defaultSourceAmount = '105.50';
const String defaultDestinationAmount = '100.00';
const String defaultFee = '5.50';
const String defaultCurrency = 'EUR';

/// 900 s — the shape a real estimate's TTL has. Turned into `expiresAtMs` when the quote is BUILT,
/// so the frame's countdown starts from "now", not from when the screen opened.
const String defaultTtlSeconds = '900';

sealed class QuoteParse {
  const QuoteParse();
}

final class QuoteParseOk extends QuoteParse {
  const QuoteParseOk(this.quote);

  final WirexWalletQuote quote;
}

final class QuoteParseError extends QuoteParse {
  const QuoteParseError(this.message);

  final String message;
}

QuoteParse parseQuoteFields({
  required String estimationId,
  required String sourceAmount,
  required String currency,
  String destinationAmount = '',
  String fee = '',
  String ttlSeconds = '',
  DateTime? now,
}) {
  final String id = estimationId.trim();
  final String source = sourceAmount.trim();
  final String ccy = currency.trim();
  final String destination = destinationAmount.trim();
  final String feeAmount = fee.trim();
  final String ttl = ttlSeconds.trim();

  if (id.isEmpty) {
    return const QuoteParseError('estimationId is required — it is what a re-arm compares');
  }
  if (source.isEmpty) return const QuoteParseError('source amount is required');
  if (ccy.isEmpty) return const QuoteParseError('currency is required');

  int? expiresAtMs;
  if (ttl.isNotEmpty) {
    final int? seconds = int.tryParse(ttl);
    if (seconds == null || seconds <= 0) {
      return const QuoteParseError(
          'expiry must be a positive whole number of seconds (leave empty for no countdown)');
    }
    expiresAtMs = (now ?? DateTime.now()).millisecondsSinceEpoch + seconds * 1000;
  }

  return QuoteParseOk(WirexWalletQuote(
    estimationId: id,
    sourceAmount: WirexWalletMoney(amount: source, currency: ccy),
    destinationAmount:
        destination.isEmpty ? null : WirexWalletMoney(amount: destination, currency: ccy),
    fee: feeAmount.isEmpty ? null : WirexWalletMoney(amount: feeAmount, currency: ccy),
    expiresAtMs: expiresAtMs,
  ));
}
