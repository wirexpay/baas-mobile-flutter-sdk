# Wirex Mobile SDK for Flutter — Integration Guide

One pub.dev package, four sealed surfaces: card **Reveal**, card **Collect**, **3-D Secure** and **Wallet** top-up with Apple Pay and Google Pay. Card values stay in native views and never cross the Dart bridge. Every snippet below is analyzed against `wirex_mobile_sdk` 0.3.7.

<!-- badges: Flutter · Dart | wirex_mobile_sdk 0.3.7 · pub.dev | Reveal · Collect · 3-D Secure · Wallet -->

## 1. What the SDK does

The SDK owns **sealed UI surfaces** and nothing else. A revealed card number, a card the user is typing and a wallet payment token live inside a native view or a Wirex-hosted web frame and **never reach Dart**. The SDK never mints a credential, never stores one, and never moves money on its own.

Your app supplies two things:

- **Authentication.** A credential provider the SDK calls on demand: the user's bearer, a step-up action token when card data or PIN is read, and the user's identity.
- **Orchestration.** Your backend prices and executes money-moving calls through the Wirex BaaS API (top-up estimate and execute, the 3-D Secure URL, the wallet checkout token) and ships the wallet provider config. The SDK renders the result and reports events back.

| Surface | Credentials | What it does |
|---|---|---|
| Reveal | yes | Shows the cardholder their own PAN, expiry, CVV and PIN in sealed native rows. |
| Collect | yes | Captures an external card in a sealed native form and tokenizes it at the acquirer. |
| 3-D Secure | **no** | Renders the issuer challenge for a card payment and reports the outcome. |
| Wallet | yes | Embeds the Wirex-hosted Apple Pay / Google Pay checkout for a backend-priced top-up. |

:::diagram model Apple/Google Pay

## 2. Requirements and install

- **Flutter 3.19 or later**, Dart 3.3 or later.
- **iOS 15 or later**, Xcode 26.5 or later. **Android 6.0 (API 23) or later**, `mavenCentral()` among your repositories (Flutter templates already have it).

```sh
flutter pub add wirex_mobile_sdk
```

```yaml
# pubspec.yaml
dependencies:
  wirex_mobile_sdk: ^0.3.7
```

The native SDKs are installed with the package: the `WirexMobileSDK` pod from CocoaPods trunk and `com.wirexapp.baas:mobile-sdk` from Maven Central, both at the package's own version. The Android artifact merges the `<queries>` block Google Pay needs on Android 11 and later into your manifest. One import covers every surface:

```dart
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';
```

Wirex assigns these values per integration. Everything else is your user's data.

| Value | What it is | Where it goes |
|---|---|---|
| `testMode` / environment name | The card surfaces take `testMode` (`false` = production, `true` = the Wirex test environment). The wallet takes the same choice by name: `WirexWalletEnvironment.resolve('test')` or `'production'`. The SDK holds the hosts; no API takes a URL. | `WirexReveal.instance.configure`, `WirexCollect.configure`, `WirexThreeDS.instance.configure`; `WirexWalletConfig.environment`. |
| `chainId` | The chain your integration operates on, sent as `X-Chain-Id` on every authenticated call. Required for Reveal and Collect. | `chainId:` in `configure(...)`. |
| `clientId` | **Optional, wallet only.** A partner id that selects your branding and configuration on the Wirex-hosted checkout pages. Wirex tells you if you have one; most integrations do not. It is not a credential and grants nothing. | `WirexWalletConfig(clientId: …)`; omit unless Wirex gave you one. |

## 3. Credential provider

One object you implement. The SDK calls it when it needs a token, so you never push tokens in advance.

```dart
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

class AppCredentials extends WirexCredentialProvider {
  @override
  Future<String> accessToken() async => '<bearer for the signed-in user, from your backend>';

  /// [scope] is 'cardData' for PAN / expiry / CVV and 'pin' for the PIN.
  @override
  Future<String> actionToken(String scope) async {
    final bool approved = await _promptStepUp(scope);
    if (!approved) throw const WirexDeclined();   // the user said no: not an error
    return '<short-lived action token for $scope>';
  }

  @override
  String? get userEmail => 'user@example.com';     // return ONE of email / wallet address

  @override
  String? get userWallet => null;

  Future<bool> _promptStepUp(String scope) async => true;
}
```

- **Exactly one identity.** Return either `userEmail` or `userWallet`. Sending both is a backend `400`.
- **The SDK sends the bearer as-is and does not retry a 401.** Check expiry in `accessToken()` and refresh before returning.
- `actionToken(scope)` is the step-up for reading card data (`'cardData'`) or the PIN (`'pin'`). Throw `const WirexDeclined()` when the user backs out; the SDK stops the operation and reports it as declined.
- Collect needs no action token: `WirexCollect.configure` takes an `accessToken` callback plus `userEmail` / `userWallet`.

## 4. Reveal {creds}

Shows the cardholder their own card details. Each field is a `WirexRevealFieldView` widget; the native side draws the value inside it.

```dart
import 'package:flutter/widgets.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

Future<WirexRevealSession> openReveal(WirexCredentialProvider credentials, String cardId) async {
  await WirexReveal.instance.configure(chainId: '<chain id>', credentials: credentials, testMode: true);
  final WirexRevealSession session = await WirexReveal.instance.createSession(
    cardId: cardId,
    fields: const <WirexRevealField>[WirexRevealField.pan, WirexRevealField.expiry, WirexRevealField.cvv, WirexRevealField.pin],
    cardholderName: 'JANE DOE',
  );
  session.onSnapshot((WirexRevealSnapshot snapshot) {
    if (snapshot.state == WirexRevealState.error) debugPrint('${snapshot.error?.code}');
  });
  await session.load();                                 // idempotent; failures land in the snapshot
  return session;
}

class RevealRow extends StatelessWidget {
  const RevealRow({required this.session, required this.field, super.key});
  final WirexRevealSession session;
  final WirexRevealField field;

  @override
  Widget build(BuildContext context) => WirexRevealFieldView(
        session: session,
        field: field,
        strings: const WirexRevealStrings(
          fieldLabels: <WirexRevealField, String>{WirexRevealField.pan: 'Card number'},
          copy: 'Copy',
          copied: 'Copied',
        ),
        onMaskedChange: (bool masked, bool screenshotProtectionActive) {},
      );
}
```

- `fields` are `WirexRevealField` values: `cardholderName`, `pan`, `expiry`, `cvv`, `pin`. Omit `pin` for a virtual card.
- `pan`, `cvv` and `pin` start **masked**. Control it with the `masked` parameter; `onMaskedChange` reports the masked state and whether screenshot protection is active. Rows re-mask when detached unless `masksWhenDetached: false`.
- Session state is `snapshot.state`: `WirexRevealState.idle`, `loading`, `ready`, `error`. Per-field results are `snapshot.outcomeFor(field)` (`WirexRevealFieldOutcome.idle`, `loading`, `loaded`, `failed`) plus the `snapshot.loaded` and `snapshot.failed` sets, so one failed field does not hide the others.
- `session.load()` resolves with the snapshot and never throws for a request failure; `refresh()` reloads, `clear()` wipes values, `destroy()` releases the native session. Values are wiped two minutes after the first load. `WirexReveal.instance.destroyAll()` tears down everything.
- `onCopyResult(copied)` fires when the user copies a copyable field. The row sizes itself from the native content.

> **Gotcha · sizing** A native row cannot be sized from Dart. Give it the width and let it take its natural height; a box shorter than the content clips the value.

> **Note · simulator** The value is drawn in a secure, capture-proof layer that the iOS Simulator renders blank. That is the PCI protection working. For simulator development only, pass `dangerouslyDisableScreenProtection: true` to `configure(...)`. Never ship it on.

## 5. Collect {creds}

Captures a card the user is entering. The form is one native widget; Dart receives a token, never the PAN or CVV.

:::flow Collect: user types the card | SDK tokenizes at the acquirer | your backend: estimate | execute → 3-D Secure URL

```dart
import 'package:flutter/widgets.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

Future<void> configureCollect() => WirexCollect.configure(
      chainId: '<chain id>',
      accessToken: () async => '<bearer for the signed-in user>',
      userEmail: 'user@example.com',
      testMode: true,
    );

class TopUpForm extends StatefulWidget {
  const TopUpForm({super.key});
  @override
  State<TopUpForm> createState() => _TopUpFormState();
}

class _TopUpFormState extends State<TopUpForm> {
  WirexCollectFormController? _controller;
  WirexCollectState _state = const WirexCollectState.empty();

  @override
  Widget build(BuildContext context) => WirexCollectFormView(
        profile: WirexCollectProfile.topup,
        strings: const WirexCollectStrings(labels: <WirexCollectField, String>{WirexCollectField.number: 'Card number'}),
        onCreated: (WirexCollectFormController controller) => _controller = controller,
        onChange: (WirexCollectState state) => setState(() => _state = state),   // state.isComplete, state.brand
      );

  Future<void> submit() async {
    final WirexCollectFormController? controller = _controller;
    if (controller == null || !_state.isComplete) return;
    try {
      final WirexTopUpCardToken token = await controller.tokenizeTopUp(const WirexTopUpTokenizeParams(
        billingDetails: WirexBillingDetails(line1: '1 Main St', zipCode: 'SW1A 1AA', city: 'London', country: 'GB'),
        label: 'My card',
      ));
      debugPrint('${token.cardId} ${token.brand} ${token.last4} ${token.expiryMonth}/${token.expiryYear}');
    } on WirexCollectError catch (error) {
      debugPrint('${error.code} retryable=${error.retryable} reason=${error.reason}');
    }
  }
}
```

- Profiles: `WirexCollectProfile.topup` (fund a top-up with this card) and `octDestination` (register a payout card via `controller.tokenizeOctDestination(WirexOctTokenizeParams(cardLabel:, isSaved:, isThirdParty:))`, which returns `externalCardId`).
- `WirexCollectState` carries `isComplete`, `brand` (`'Visa'`, `'MasterCard'`, `'unknown'`) and per-field `fields` with `isValid` and `error` (`WirexCollectFieldError.incomplete`, `invalid`, `expired`).
- Billing details (`line1`, `zipCode`, `city`, `country` as ISO alpha-2) are required by the tokenizer; `line2` and `state` are optional. The **card user must be enrolled at the acquirer**, otherwise tokenization throws.
- After tokenizing, **your backend** prices and executes the top-up with the `cardId`; a card payment may return a 3-D Secure URL for the next section.
- To lay fields out yourself, keep the form mounted and render one `WirexCollectFieldView(controller:, field:)` per field; `errorLine` (`WirexErrorLine.hidden`, `reserved`, `animated`) controls where validation messages render.

## 6. 3-D Secure {nocreds}

Presents the issuer challenge for a card payment. Your backend obtains the orchestrator URL from the top-up execute response; the SDK renders the flow and reports the outcome. No credentials are needed.

```dart
import 'package:flutter/widgets.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

Future<WirexThreeDSOutcome> runStepUp(String orchestratorUrl, void Function(WirexThreeDSSession) mount) async {
  await WirexThreeDS.instance.configure(testMode: true);
  final WirexThreeDSSession session = await WirexThreeDS.instance.createSession(orchestratorUrl);
  mount(session);                                        // render StepUpOverlay(session) full-size
  await session.start();
  final WirexThreeDSOutcome outcome = await session.settled();   // status + optional error
  await session.destroy();
  return outcome;
}

class StepUpOverlay extends StatelessWidget {
  const StepUpOverlay({required this.session, super.key});
  final WirexThreeDSSession session;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: WirexThreeDSView(
          session: session,
          strings: const WirexThreeDSStrings(title: 'Verify your card', close: 'Close', loading: 'Loading'),
        ),
      );
}
```

| State (`WirexThreeDSState`) | Outcome status (`WirexThreeDSStatus`) | Outcome error code |
|---|---|---|
| `idle` · `loading` · `challenge` · `settled` | `completed` · `pending` · `failed` · `unknown` | `originRefused` · `declined` · `unavailable` |

- Keep the view mounted full-size for the life of the session; it ignores pointers until a challenge is visible. `session.onSnapshot` reports `state` and `isChallengeVisible`. `cancel()` settles with `unknown`.
- A refused URL comes back already settled with `originRefused`. `configure` also takes `pageLoadTimeout`.

> **Note** `pending` means the payment is not settled *yet*; it is not an error. Reconcile the real result from your backend's status feed, not from the 3-D Secure status alone.

## 7. Wallet · Apple Pay / Google Pay {creds|device}

Embeds the Wirex-hosted checkout for a top-up your backend has already priced. The frame renders the quote and the wallet button; the Pay sheet is native. No Apple Pay entitlement or merchant identifier is needed in your app.

Three inputs, all from your backend and your app config:

| Input | What it is |
|---|---|
| `quote` | `estimationId` + `sourceAmount` from your backend's top-up estimate. Short TTL; a changed `estimationId` re-arms the checkout. |
| `providerConfig` | The wallet provider block from your app config, passed **verbatim** (`WirexWalletProviderConfig(rawMap)` or the resolver below). |
| `auth` | Token mode: a `checkoutToken` your backend minted for this top-up flow. Omit it for legacy mode. |

:::diagram wallet

```dart
import 'package:flutter/widgets.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

Future<WirexWalletConfig> walletConfig() async =>
    WirexWalletConfig(environment: await WirexWalletEnvironment.resolve('test'));   // clientId optional

// 1. Availability: decide whether to show a Pay button at all.
Future<WirexWalletAvailabilityChecker> probe(WirexWalletConfig config, WirexWalletProviderConfig providerConfig) async {
  final WirexWalletAvailabilityChecker checker = WirexWalletAvailabilityChecker(config: config, providerConfig: providerConfig);
  checker.onChange = (WirexWalletAvailability a) => debugPrint('applePay=${a.applePay} googlePay=${a.googlePay}');
  await checker.start();
  return checker;                                        // later: await checker.stop();
}

// 2. Checkout: arm it with a backend-priced quote and the provider block.
class Checkout extends StatefulWidget {
  const Checkout({required this.config, required this.quote, required this.providerConfig, this.checkoutToken, super.key});
  final WirexWalletConfig config;
  final WirexWalletQuote quote;                          // WirexWalletQuote(estimationId:, sourceAmount: WirexWalletMoney(amount: '10.00', currency: 'EUR'))
  final WirexWalletProviderConfig providerConfig;
  final String? checkoutToken;
  @override
  State<Checkout> createState() => _CheckoutState();
}

class _CheckoutState extends State<Checkout> {
  WirexWalletCheckoutController? _controller;

  @override
  Widget build(BuildContext context) => WirexWalletCheckoutView(
        config: widget.config,
        quote: widget.quote,
        providerConfig: widget.providerConfig,
        auth: widget.checkoutToken == null ? null : WirexWalletCheckoutAuth(checkoutToken: widget.checkoutToken!),
        onCreated: (WirexWalletCheckoutController c) => _controller = c,
        onEvent: (WirexWalletCheckoutEvent event) {
          switch (event) {
            case WirexWalletCheckoutReady() || WirexWalletCheckoutSheetOpen() || WirexWalletCheckoutCancelled() || WirexWalletCheckoutExecuting():
              break;
            case WirexWalletCheckoutNaturalHeight(:final height):
              debugPrint('height $height');              // apply to the widget's box
            case WirexWalletCheckoutAttemptFailed(:final reason):
              debugPrint(reason);
            case WirexWalletCheckoutEstimationExpired():
              break;                                     // re-price on your backend, then controller.rearm(...)
            case WirexWalletCheckoutToken(:final token):
              debugPrint(token.walletPaymentToken);      // legacy mode: your backend executes
            case WirexWalletCheckoutExecuted(:final result):
              debugPrint('${result.id} ${result.status}');
            case WirexWalletCheckoutExecuteFailed(:final error):
              debugPrint(error.reason);
            case WirexWalletCheckoutFailed(:final error):
              debugPrint(error.kind.wire);
            case WirexWalletCheckoutDiagnostic() || WirexWalletCheckoutDebug():
              break;
          }
        },
      );

  Future<void> newQuote(WirexWalletQuote quote, String? checkoutToken) async {
    await _controller?.rearm(quote, widget.providerConfig,
        auth: checkoutToken == null ? null : WirexWalletCheckoutAuth(checkoutToken: checkoutToken));
  }

  @override
  void dispose() {
    _controller?.destroy();
    super.dispose();
  }
}
```

- **Legacy vs token mode.** Without `auth`, the sheet tokenizes and the checkout emits `WirexWalletCheckoutToken`; your backend executes the top-up with it. With a backend-minted `checkoutToken`, the frame executes itself and emits `Executing` → `Executed` or `ExecuteFailed`; nothing sensitive reaches Dart. The mode is fixed when the view is created.
- `estimationId` and `checkoutToken` are two independent values from two backend calls; the id is not derived from the token.
- Events are the sealed `WirexWalletCheckoutEvent` subtypes: `Ready`, `NaturalHeight`, `SheetOpen`, `Cancelled`, `AttemptFailed`, `EstimationExpired`, `Token`, `Executing`, `Executed`, `ExecuteFailed`, `Failed` (terminal), `Diagnostic`, `Debug` (only with `debug: true`).
- `WirexWalletMoney.amount` is a decimal **string** (`'10.00'`). `WirexWalletQuote` also accepts optional `destinationAmount`, `fee`, `rate` and `expiresAtMs`.
- `providerConfig` is passed verbatim. Do not re-case keys or add defaults; an absent `apple_pay` or `google_pay` key means "do not offer". `WirexWalletProviderConfigResolver.resolve(topupJson, providerName)` picks the block out of your app config and tells you when it is absent or unusable.
- `WirexWalletConfig(cache:)` takes an optional key-value store (`WirexWalletAvailabilityCache`) so the availability answer survives relaunch. The SDK writes one key with two booleans.
- Standalone launch in a browser or Custom Tab: `WirexWalletLaunch.buildUrl(config, WirexWalletLaunchParams(checkoutToken:, quote:, provider:, returnUrl:))` builds the URL your app opens; `WirexWalletReturnLink.matches(url, returnUrl)` and `parse(url)` read the result on return. The SDK opens no browser itself.

> **Gotcha · availability** Start a `WirexWalletAvailabilityChecker` with the real provider block before you show a Pay button; `onChange` reports the native answer. On the iOS Simulator it reports unavailable, and the Pay sheet cannot present. Test on a device with a provisioned card.

## 8. Appearance, strings and sizing

Every surface takes an appearance object and a strings object. The SDK ships no copy, so your app supplies every word the views draw.

```dart
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

const WirexThemeMode themeMode = WirexThemeMode.dark;   // a parameter on every card view
const WirexRevealAppearance revealAppearance = WirexRevealAppearance(   // colours '#RRGGBB', sizes in logical px
  colorText: '#FFFFFF', colorLabel: '#9AA0B5', colorFocus: '#5753EA', colorBackground: '#1B1E2B',
  fontFamily: 'Inter', fontSizeBase: 16, fontWeightBase: '500', borderRadius: 8, controlMinHeight: 44,
);
const Map<String, Object?> collectAppearance = <String, Object?>{   // Collect and 3-D Secure take the same token names as a map
  'colorText': '#FFFFFF', 'colorFocus': '#5753EA', 'borderRadius': 8, 'fontSizeBase': 16,
};
const WirexRevealStrings revealStrings = WirexRevealStrings(
  fieldLabels: <WirexRevealField, String>{WirexRevealField.pan: 'Card number', WirexRevealField.cvv: 'CVV'},
  copy: 'Copy', copied: 'Copied',
);
const WirexCollectStrings collectStrings = WirexCollectStrings(
  labels: <WirexCollectField, String>{WirexCollectField.number: 'Card number', WirexCollectField.expiry: 'Expiry'},
  errors: <WirexCollectField?, Map<WirexCollectFieldError, String?>>{
    null: <WirexCollectFieldError, String?>{WirexCollectFieldError.incomplete: 'Required', WirexCollectFieldError.invalid: 'Check this field'},
    WirexCollectField.expiry: <WirexCollectFieldError, String?>{WirexCollectFieldError.expired: 'Card expired'},
  },
);
const WirexWalletAppearance walletAppearance = WirexWalletAppearance(theme: WirexWalletTheme.dark, variables: <String, String>{'--wx-accent': '#5753EA'});
const WirexWalletButtons walletButtons = WirexWalletButtons(
  applePay: WirexWalletApplePayButton(style: SpecWalletApplePayButtonStyle.black, type: SpecWalletApplePayButtonType.topUp),
  googlePay: WirexWalletGooglePayButton(color: SpecWalletGooglePayButtonColor.black, type: SpecWalletGooglePayButtonType.pay),
);
const WirexWalletBranding walletBranding = WirexWalletBranding(logo: WirexWalletLogo.hidden(), processingDisclosurePartnerName: 'Acme');
```

- Card views take `themeMode` (`WirexThemeMode.light` / `dark`) and an appearance: typed `WirexRevealAppearance` for Reveal, a `Map<String, Object?>` with the same token names for Collect and 3-D Secure. Tokens: colours (`colorText`, `colorLabel`, `colorPlaceholder`, `colorError`, `colorFocus`, `colorBackground`, `colorBorder`, `surfaceColor`), typography (`fontFamily`, `fontSizeBase`, `fontSizeLabel`, `lineHeightBase`, `lineHeightLabel`, `fontWeightBase`, `fontWeightLabel`), geometry (`borderRadius`, `borderWidth`, `spacingUnit`, `paddingHorizontal`, `paddingVertical`, `spacingLabel`, `spacingError`, `iconSize`, `controlMinHeight`). Icons are PNG bytes wrapped in `WirexArtwork`: `WirexRevealIcons(copy:, copied:)`, `WirexCollectIcons.brands(visa:, mastercard:)`, `WirexThreeDSIcons(close:)`.
- Strings: `WirexRevealStrings` (field labels, masked placeholder, copy texts), `WirexCollectStrings` (labels, placeholders, per-field errors with a `null` key as the default), `WirexThreeDSStrings(title:, close:, loading:)`.
- Wallet: `appearance` passes CSS variables to the frame; `buttons` sets the Apple Pay `style`/`type` and Google Pay `color`/`type`; `branding` sets the logo (`WirexWalletLogo.wirex()`, `hidden()`, `custom(dataUri)`), the processing disclosure and a privacy URL; `strings` is a `Map<SpecWalletStringKey, String>` overriding the 11 labels of the checkout.
- **Sizing.** Reveal rows and the collect form size themselves from the native content; the wallet emits a `WirexWalletCheckoutNaturalHeight` event and exposes `controller.naturalHeight`. Apply those heights instead of hardcoding them.

## 9. Logging, timeouts and errors

```dart
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

Future<void> configureWithDiagnostics(WirexCredentialProvider credentials) => WirexReveal.instance.configure(
      chainId: '<chain id>',
      credentials: credentials,
      logging: 'info',                                              // null (default) | 'debug' | 'info' | 'warn' | 'error'
      timeouts: const WirexTimeouts(requestMillis: 15000, resourceMillis: 30000),
    );

const WirexWalletLogging walletLogging = WirexWalletLogging(level: WirexWalletLogLevel.info);   // default WirexWalletLogging.disabled

bool isRetryable3ds(WirexThreeDSError error) => error.code == WirexThreeDSErrorCode.unavailable && error.retryable;

Future<WirexWalletEnvironment?> safeResolve(String name) async {
  try {
    return await WirexWalletEnvironment.resolve(name);
  } on WirexWalletEnvironmentUnavailable catch (e) {
    return switch (e.reason) {                                      // unknownName · notBuilt · malformedEndpoints
      WirexWalletEnvironmentUnavailableReason.unknownName => null,
      WirexWalletEnvironmentUnavailableReason.notBuilt => null,
      WirexWalletEnvironmentUnavailableReason.malformedEndpoints => null,
    };
  }
}
```

- Logging is off by default. The card surfaces and 3-D Secure take `logging: 'debug' | 'info' | 'warn' | 'error'` (iOS unified log, Android logcat). The wallet takes `WirexWalletLogging(level:, sink:)`; without a sink nothing is written. Every logged value passes a redactor.
- `WirexTimeouts(requestMillis:, resourceMillis:)` default to 15 and 30 seconds; `resourceMillis` applies on iOS only. 3-D Secure takes `pageLoadTimeout: Duration`.
- Errors are per surface: Reveal reports `WirexRevealError { code, retryable }` **in the snapshot**; Collect throws `WirexCollectError { code, retryable, reason }` from `tokenize*()`, with `reason` `'cardAlreadyLinked'` or `'cardLimitReached'` when the backend says so; 3-D Secure returns `WirexThreeDSError` in the outcome; the wallet emits `WirexWalletError { kind, code, statusCode, detail }` in the `Failed` event.
- `WirexDeclined` is the one shared sentinel: the user said no, and nothing was sent.
- An unknown wallet environment name throws `WirexWalletEnvironmentUnavailable`; an empty `chainId` on the card surfaces fails `configure` with an `invalid_environment` platform error. Show the reason; never fall back to another environment.

## 10. Your backend

The SDK makes none of these calls. Your backend performs them with the partner credentials Wirex issued, and the app passes the results in:

- **Price a top-up** → `estimationId` and `sourceAmount` for the wallet quote. Short TTL; re-price to re-arm an expired checkout.
- **Execute a top-up** → settles it; a card payment returns the 3-D Secure orchestrator URL.
- **Mint a checkout token** (wallet token mode) → `checkoutToken`, scoped to the top-up flow.
- **Serve the wallet provider config** → the provider block the app passes to the wallet verbatim.

Authenticated calls carry `Authorization: Bearer`, `X-Chain-Id` and one identity header (`X-User-Email` or `X-User-Wallet`, never both). For exact paths and payloads see the Wirex BaaS API reference provided with your integration.

## 11. The example app

[`example/`](example/) is a Flutter app that exercises all four surfaces against your own data; nothing is compiled in. Run `flutter pub get` and `flutter run`; it resolves the SDK from pub.dev. Paste the integration JSON (`chainId`, `bearer`, `actionToken`, `cardId`, identity) on the Reveal screen; the Wallet screen takes an estimation id and the provider block. The field list is in [`PARTNER-CONFIG.md`](PARTNER-CONFIG.md). Reveal values render blank on the iOS Simulator and the Pay sheet needs a real device.

## 12. Patterns from a production integration

The SDK ships inside a production cardholder app built on the same BaaS API. The patterns below are not required by the API; they are what that integration settled on, with the app-specific parts removed.

### Credentials in practice

```dart
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

abstract class AuthSession {
  Future<({String token, DateTime expiresAt})?> accessToken();
  Future<String?> refreshAccessToken();
  Future<String> signAction(String scope);
  String? get email;
}

class ProductionCredentials extends WirexCredentialProvider {
  ProductionCredentials(this._auth);
  final AuthSession _auth;
  ({String scope, String token})? _offered;

  /// Sign BEFORE the sheet opens and hand the token over one-shot: the user confirms once.
  void offerStepUpToken(String scope, String token) => _offered = (scope: scope, token: token);
  void revokeOfferedStepUpToken() => _offered = null;

  @override
  Future<String> accessToken() async {
    // Expiry, not just presence: the SDK sends what it is given and never retries a 401.
    final current = await _auth.accessToken();
    if (current != null && current.expiresAt.difference(DateTime.now()).inSeconds > 30) return current.token;
    final refreshed = await _auth.refreshAccessToken();
    if (refreshed != null) return refreshed;
    throw StateError('no access token available');
  }

  @override
  Future<String> actionToken(String scope) async {
    final offered = _offered;
    if (offered != null && offered.scope == scope) {
      _offered = null;
      return offered.token;
    }
    return _auth.signAction(scope);                              // fallback: sign now
  }

  @override
  String? get userEmail => _auth.email;
  @override
  String? get userWallet => null;
}
```

- **Check the bearer's expiry, not just its presence.** Your own API client probably refreshes on a 401 and retries; the SDK does neither. Use the same expiry buffer your client uses so the two agree on "about to expire", refresh before returning, and only fall back to a still-valid token when the refresh fails.
- **Sign once.** The user confirms a card reveal with a step-up *before* the sheet opens. Mint the action token there, offer it to the provider one-shot, and revoke it if the flow is abandoned. Otherwise the SDK asks for a second confirmation for the same action.
- **Configure once per process**, cached behind a promise or a flag, and clear the cache on failure so a later attempt can retry. Derive `testMode` from your *runtime* environment if your app can switch backends. Log at `debug` in development builds and `warn` in release.
- **Identity is read at `configure` time.** Re-run `configure` when the signed-in user changes; a stale or absent identity header is a flat `401`, not a soft failure.

### Reveal in practice

- **One session per open sheet, destroyed with it.** The session holds the retrieved values natively; leaving one alive after the sheet closes keeps a PAN in memory for nothing.
- **Unmask immediately when the user already confirmed.** After the step-up signature, render the rows with `masked: false` instead of asking for another tap.
- **Log which fields failed together with the snapshot's error code.** The row shows only *that* a field failed, never why.

### Collect in practice

```dart
import 'package:flutter/widgets.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

/// The sealed form plus your own billing-address and card-label fields; submit only when both are ready.
class NewCardForm extends StatefulWidget {
  const NewCardForm({required this.billing, required this.onToken, super.key});
  final WirexBillingDetails? billing;                      // filled by your own address screen
  final void Function(String cardId) onToken;
  @override
  State<NewCardForm> createState() => _NewCardFormState();
}

class _NewCardFormState extends State<NewCardForm> {
  WirexCollectFormController? _controller;
  bool _isComplete = false;

  bool get canSubmit => _isComplete && widget.billing != null;

  Future<void> submit() async {
    final WirexCollectFormController? controller = _controller;
    final WirexBillingDetails? billing = widget.billing;
    if (controller == null || billing == null) return;
    final WirexTopUpCardToken token = await controller.tokenizeTopUp(WirexTopUpTokenizeParams(billingDetails: billing));
    widget.onToken(token.cardId);                            // your backend prices and executes with it
  }

  @override
  Widget build(BuildContext context) => Column(children: <Widget>[
        WirexCollectFormView(
          profile: WirexCollectProfile.topup,
          onCreated: (WirexCollectFormController c) => _controller = c,
          onChange: (WirexCollectState s) => setState(() => _isComplete = s.isComplete),
        ),
        // your own billing-address cell and card-label input go here
      ]);
}
```

- The sealed rows replace only the card inputs. Keep your own billing-address entry and card label, enable submit on `isComplete` **and** a complete address, and release the form when the screen goes away.

### 3-D Secure in practice

```dart
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

/// Settle exactly once, and tell the three endings apart.
class StepUpWatcher {
  StepUpWatcher({required this.onError, required this.onDismissed, required this.onComplete, required this.onChallengeVisible});
  final void Function(String message) onError;
  final void Function() onDismissed;
  final void Function(WirexThreeDSStatus status) onComplete;
  final void Function(bool visible) onChallengeVisible;
  bool _settled = false;

  void Function() watch(WirexThreeDSSession session) => session.onSnapshot((WirexThreeDSSnapshot snapshot) {
        onChallengeVisible(snapshot.isChallengeVisible);        // hide your own header while true
        final WirexThreeDSOutcome? outcome = snapshot.outcome;
        if (snapshot.state != WirexThreeDSState.settled || outcome == null || _settled) return;
        _settled = true;
        final WirexThreeDSError? error = outcome.error;
        if (error != null) {
          onError(error.message ?? error.code.name);           // show it
          return;
        }
        if (outcome.status == WirexThreeDSStatus.unknown) {
          onDismissed();                                        // the user closed it: reconcile by backend status
          return;
        }
        onComplete(outcome.status);                             // completed · pending · failed
      });
}
```

- Start the session only after the view is mounted; a challenge can appear within a frame of the page asking for one.
- Three endings, not interchangeable: an outcome with an `error` is shown; `unknown` *without* an error means the user closed the challenge, which is a decision, not a failure, and the payment may still complete; anything else is a real status. Reconcile the first two against your backend.

### Wallet top-up in practice

```dart
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

/// One token per armed quote. A failed mint is not fatal in-app: run legacy mode instead.
Future<WirexWalletCheckoutAuth?> armAuth(Future<String> Function() mint) async {
  try {
    return WirexWalletCheckoutAuth(checkoutToken: await mint());
  } catch (_) {
    return null;
  }
}

/// An expired estimate is re-priced on your backend, then the same view is re-armed.
Future<void> onExpired(WirexWalletCheckoutController controller,
    Future<(WirexWalletQuote, WirexWalletProviderConfig, WirexWalletCheckoutAuth?)> Function() reprice) async {
  final (WirexWalletQuote quote, WirexWalletProviderConfig providerConfig, WirexWalletCheckoutAuth? auth) = await reprice();
  await controller.rearm(quote, providerConfig, auth: auth);
}

/// Custom Tab (Android, token mode only): your app opens the URL and reads the return link.
sealed class TabOutcome {}
class TabExecuted extends TabOutcome { TabExecuted(this.outcome); final SpecWalletLaunchOutcome outcome; }
class TabFailed extends TabOutcome {}
class TabUnknown extends TabOutcome {}                       // reconcile by backend status

Future<String> launchUrl(WirexWalletConfig config, WirexWalletCheckoutAuth auth, WirexWalletQuote quote, String provider, String returnUrl) =>
    WirexWalletLaunch.buildUrl(config, WirexWalletLaunchParams(checkoutToken: auth.checkoutToken, quote: quote, provider: provider, returnUrl: returnUrl));

TabOutcome readReturn(String? url, String returnUrl, WirexWalletQuote quote) {
  if (url == null || !WirexWalletReturnLink.matches(url, returnUrl)) return TabUnknown();   // tab closed without the link
  final WirexWalletReturnLink back = WirexWalletReturnLink.parse(url);
  if (back.estimationId != null && back.estimationId != quote.estimationId) return TabUnknown();
  return switch (back.outcome) {
    SpecWalletLaunchOutcome.completed || SpecWalletLaunchOutcome.pending => TabExecuted(back.outcome!),
    SpecWalletLaunchOutcome.failed => TabFailed(),
    _ => TabUnknown(),                                         // alreadyExecuted or no outcome
  };
}
```

- **One `checkoutToken` per armed quote.** Mint it on your backend for the quote you are about to arm; a re-arm mints again. Never hand the user's session bearer to the frame.
- **A failed mint is not fatal in-app.** Run legacy mode instead: the frame tokenizes and your backend executes. Keep `debug` off outside development builds.
- **Custom Tab is the partner path for Google Pay on Android** when your own WebView cannot complete it. Use an **https App Link** as `returnUrl` (a custom scheme can be claimed by any installed app), open the URL in a Custom Tab, and treat every ending that is not `completed`, `pending` or `failed` as unknown: Android cannot close the tab for you, and a closed tab says nothing about the payment. A Custom Tab needs token mode; there is nobody to hand a wallet token to.

## 13. Troubleshooting

- **A revealed field is blank.** iOS Simulator (secure layer), or the row was given a box shorter than its content.
- **`configure` fails with `invalid_environment`.** This build has no endpoints for that side, or `chainId` is empty.
- **Reveal or Collect fails with `unauthorized`.** The bearer is stale; `accessToken()` must refresh. The SDK never retries a 401.
- **Collect cannot tokenize.** The user is not enrolled at the acquirer, or billing details are missing.
- **The Pay button is unavailable.** The checker was not started, the provider block is empty, or you are on the iOS Simulator.
- **3-D Secure ends in `pending`.** Not an error. Settle by your backend's status.
- **Both `userEmail` and `userWallet` are set.** The backend answers `400`. Return exactly one.
