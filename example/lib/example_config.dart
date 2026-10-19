/// How this example chooses an environment: the NAME selected on the Config tab (`test` /
/// `production`), resolved by the native SDK against its own build. Never a URL — an unknown or
/// unbuilt name is an error, never a fallback, and every failure here is RENDERED with a reason.
library;

import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

import 'live_config.dart';

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

/// Resolves the environment name from the Config tab.
Future<ExampleBootstrap> bootstrap({required WirexWalletAvailabilityCache cache}) async {
  // The NAME selected on the Config tab (`test` / `production`), never a URL.
  final String name = LiveConfig.instance.environment;

  // The native SDK refuses a name rather than falling back; the example renders the refusal instead
  // of picking an origin of its own.
  final WirexWalletEnvironment environment;
  try {
    environment = await WirexWalletEnvironment.resolve(name);
  } on WirexWalletEnvironmentUnavailable catch (unavailable) {
    return ExampleBootstrapFailed(switch (unavailable.reason) {
      WirexWalletEnvironmentUnavailableReason.unknownName =>
        'Unknown environment "$name". This build accepts: '
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
