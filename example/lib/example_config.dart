/// How this example chooses an environment: a NAME in `wirex-wallet-sdk.json`, resolved by the native
/// SDK against its own build. Never a URL — an unknown or unbuilt name is an error, never a fallback.
///
/// Mirrors the card SDK examples' `wirex-card-sdk.json` pattern: the file is a Flutter asset, read
/// through `rootBundle`. If it is not declared under `assets:` in pubspec.yaml the load throws at
/// startup — the file existing on disk is exactly what makes that omission easy to miss — so every
/// failure here is RENDERED with a reason, never spun over.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

/// The asset this example ships: `{ "environment": "test" }`.
const String walletConfigAsset = 'wirex-wallet-sdk.json';

/// The environment NAME out of the asset's JSON document, or null when the document is not a JSON
/// object or carries no non-empty `environment` string. Pure, so the test suite can run every shape.
String? environmentNameFrom(String raw) {
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final Object? name = decoded['environment'];
    return (name is String && name.isNotEmpty) ? name : null;
  } catch (_) {
    return null;
  }
}

/// The startup outcome: a usable [WirexWalletConfig], or the reason there is none.
sealed class ExampleBootstrap {
  const ExampleBootstrap();
}

final class ExampleBootstrapReady extends ExampleBootstrap {
  const ExampleBootstrapReady(this.config);

  final WirexWalletConfig config;
}

final class ExampleBootstrapFailed extends ExampleBootstrap {
  const ExampleBootstrapFailed(this.reason);

  final String reason;
}

/// Reads the asset and resolves the name.
Future<ExampleBootstrap> bootstrap({required WirexWalletAvailabilityCache cache}) async {
  String raw;
  try {
    raw = await rootBundle.loadString(walletConfigAsset);
  } catch (_) {
    return const ExampleBootstrapFailed(
      '$walletConfigAsset could not be read. It must exist next to pubspec.yaml AND be declared '
      'under `flutter: assets:` — the file existing on disk is not enough.',
    );
  }

  final String? name = environmentNameFrom(raw);
  if (name == null) {
    return const ExampleBootstrapFailed(
      '$walletConfigAsset names no environment. Expected: { "environment": "test" }.',
    );
  }

  // The native SDK refuses a name rather than falling back; the example renders the refusal instead
  // of picking an origin of its own.
  final WirexWalletEnvironment environment;
  try {
    environment = await WirexWalletEnvironment.resolve(name);
  } on WirexWalletEnvironmentUnavailable catch (unavailable) {
    return ExampleBootstrapFailed(switch (unavailable.reason) {
      WirexWalletEnvironmentUnavailableReason.unknownName =>
        'Unknown environment "$name" in $walletConfigAsset. This build accepts: '
            '${unavailable.known.join(', ')}. The environment is a name, never a URL, and there is '
            'no fallback.',
      WirexWalletEnvironmentUnavailableReason.notBuilt =>
        'The SDK has no configuration for "$name". Set the environment Wirex assigned '
            '(test / production).',
      WirexWalletEnvironmentUnavailableReason.malformedEndpoints =>
        'The SDK could not resolve a valid configuration for "$name".',
    });
  }

  return ExampleBootstrapReady(WirexWalletConfig(environment: environment, cache: cache));
}
