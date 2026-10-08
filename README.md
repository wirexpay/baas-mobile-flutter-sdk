# wirex_mobile_sdk

Wirex card and wallet features for a Flutter app. The card values stay in native views and never
cross the Dart bridge.

- **Reveal** (`WirexReveal`, `WirexRevealFieldView`) shows cardholders their own card number, expiry,
  CVV and PIN.
- **Collect** (`WirexCollect`, `WirexCollectFormView`) takes a card the user is entering and returns
  a token in place of the card values.
- **Wallet top-up** (`WirexWalletCheckoutView`) hosts the Wirex checkout with Apple Pay and Google
  Pay.

Use of the SDK requires an agreement with Wirex. See [LICENSE](LICENSE).

## Requirements

- Flutter 3.19 or later.
- iOS 13 or later (Flutter 3.35 and later itself requires iOS 15); Android 6.0 (API 23) or later.

## Installation

```sh
flutter pub add wirex_mobile_sdk
```

The native SDK is installed with the package: the `WirexMobileSDK` pod from CocoaPods trunk on iOS,
and `com.wirexapp.baas:mobile-sdk` from Maven Central on Android, both at the package's own version.
The Android project needs `mavenCentral()` among its repositories, which Flutter templates already
include.

## Environments

The SDK supports two environments, `production` and `test`, and the same two apply to every surface.
The card surfaces take `testMode`; the wallet takes the environment by name. The native SDK holds the
addresses, and no API takes a URL. An unknown name is an error: the SDK never falls back to another
environment.

The card surfaces also need the chain ID of the partner's integration, passed as `chainId` when they
are configured.

## Credentials

The SDK never issues credentials. The host implements `WirexCredentialProvider`, which returns the
user's access token, an action token for each scope the SDK asks for, and the user's email and wallet
address. The SDK asks for a token when it needs one.

## Documentation

Every public type and member is documented in the package's API reference on pub.dev.
