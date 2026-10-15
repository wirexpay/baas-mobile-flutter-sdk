/// The sample provider configuration, and the parse the Checkout tab runs over pasted JSON.
library;

import 'dart:convert';

import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

/// SHAPE ONLY. Field names and nesting match what your app config returns under `topup`; the values
/// are illustrative, not a live gateway's. The plugin hands the matched provider block to the frame
/// VERBATIM — nothing in it is validated, defaulted or re-cased by the SDK — so pasting a real
/// environment's block is the same mechanics.
const String sampleTopupJson = '''
{
  "default_provider": "example",
  "providers": {
    "example": {
      "apple_pay": {
        "merchant_name": "Example Merchant",
        "merchant_country_code": "GB",
        "merchant_capabilities": ["supports3DS"],
        "supported_networks": ["visa", "masterCard"],
        "required_billing_contact_fields": [],
        "api_version": 3
      },
      "google_pay": {
        "allowed_auth_methods": ["CRYPTOGRAM_3DS"],
        "allowed_card_networks": ["VISA", "MASTERCARD"],
        "api_version": 2,
        "api_version_minor": 0
      }
    }
  }
}''';

sealed class TopupParse {
  const TopupParse();
}

final class TopupParseOk extends TopupParse {
  const TopupParseOk(this.config, {required this.matchedKey});

  final WirexWalletProviderConfig config;
  final String matchedKey;
}

final class TopupParseError extends TopupParse {
  const TopupParseError(this.message);

  final String message;
}

/// Decodes pasted text and resolves it EXACTLY the way a partner resolves the app config's `topup`
/// value: through `WirexWalletProviderConfigResolver`, before any view exists. The four resolution
/// outcomes are rendered, not collapsed — in a real host `absent` is the feature switched off
/// (silent) and the two `unusable` shapes are report-once-offer-nothing.
TopupParse parseTopup(String text, {String? provider}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    return TopupParseError('not valid JSON: ${error.message}');
  }
  final WirexWalletProviderConfigResolution resolution =
      WirexWalletProviderConfigResolver.resolve(decoded, provider);
  return switch (resolution) {
    WirexWalletProviderConfigBlock(:final config, :final matchedKey) =>
      TopupParseOk(config, matchedKey: matchedKey),
    WirexWalletProviderConfigAbsent() => const TopupParseError(
        'resolved ABSENT — no `providers` key (or the document is null): the feature is off, and '
        'a real host offers nothing, silently'),
    WirexWalletProviderConfigUnusableTopLevel() => const TopupParseError(
        'resolved UNUSABLE (top level) — `topup`, `providers` or `default_provider` has the wrong '
        'shape: a real host reports `config_unusable` once and offers nothing'),
    WirexWalletProviderConfigUnusableProviderBlock() => const TopupParseError(
        'resolved UNUSABLE (provider block) — no provider key matched, or the matched block is not '
        'an object: a real host reports `config_unusable` once and offers nothing'),
  };
}
