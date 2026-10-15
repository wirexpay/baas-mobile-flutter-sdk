# Wirex Mobile SDK (Flutter) — integration context (for an AI assistant)

> Audience: an AI assistant helping a partner integrate the Wirex Mobile SDK on Flutter (Dart).
> This file is the working context — read top to bottom; every fact is load-bearing. Dense on purpose:
> no marketing. The human-facing version is `INTEGRATION.html`. For exact backend request/response
> shapes, defer to the Wirex BaaS API reference — this file does not restate them.

---

## 1. Mental model (the one thing to get right)

The SDK owns **sealed UI surfaces** and nothing else. Secrets (a revealed PAN/CVV, a typed card number,
a wallet payment token) live inside a native platform view or a Wirex-hosted web frame and **never cross
the Dart bridge**. The SDK **never mints a credential, never stores one**, and (except where noted)
**never decides a money movement**.

The integrator supplies two things:

1. **Authentication** — a `WirexCredentialProvider` the SDK calls on demand (bearer + step-up signature + identity).
2. **Orchestration** — the partner **backend** prices and executes money-moving work (top-up pricing/execution, the 3DS URL, the wallet checkout token) and ships the provider config.

| Surface | Needs credentials? | What it does |
|---|---|---|
| Reveal | yes | show the cardholder their own PAN/expiry/CVV/PIN as native platform views |
| Collect | yes | capture an external card in a sealed native form and tokenize it at the acquirer |
| 3-D Secure | **no** | render the issuer challenge for a card payment; report the outcome |
| Wallet | yes | embed the Wirex-hosted Apple Pay / Google Pay checkout |

**One package.** `wirex_mobile_sdk` carries all four surfaces (card reveal, card collect, 3-D Secure,
wallet top-up) under a single `import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';` — the former
per-surface packages are consolidated into it.

---

## 2. Who integrates, and exactly what they must have

**The integrator is a partner** issuing Wirex-backed cards to their own users.

Wirex assigns (per integration):
- `environment` — a NAME (`test` / `production`). Cards resolve it internally (via a `testMode` flag / config asset); wallet via `WirexWalletEnvironment.resolve(...)`. Never a URL; the SDK holds the hosts.
- `chainId` — the `X-Chain-Id` on every authenticated call.
- `clientId` — optional. Not auth.

Partner owns / must build:
- **A bearer** for the signed-in user → `accessToken()`.
- **A wallet step-up signature** capability (user signs a confirmation message; the backend exchanges it for a short-lived action token) → `actionToken(scope)`.
- **The identity**: ONE of email or EOA wallet address → `userEmail` / `userWallet`.
- **A provisioned card** (card id) for Reveal/Collect.
- **Backend orchestration** for Wallet/Collect top-ups (price, execute, mint a checkout token, obtain the 3DS URL). Wirex BaaS API — see its reference.
- **Provider config** for Wallet: the wallet provider block from the partner's app config.

---

## 3. Install

```yaml
# pubspec.yaml — one package, all four surfaces. From pub.dev:
dependencies:
  wirex_mobile_sdk: ^0.3.7
```
No Apple Pay **app entitlement** — wallet Apple Pay runs inside the Wirex web frame, not native PassKit.

---

## 4. Credential provider (the one object the partner implements)

```dart
class AppCredentials implements WirexCredentialProvider {
  @override Future<String> accessToken() async { /* partner auth → Wirex bearer */ }
  @override Future<String> actionToken(String scope) async { /* 'cardData' | 'pin' → action token */ }
  @override String? userEmail;   // return ONE of email / wallet
  @override String? userWallet;  // the EOA address, if identifying by wallet
}
```

Rules the SDK enforces / expects:
- **Exactly one identity.** Both set is a backend `400`. Return one.
- **The SDK sends the bearer as-is and does not retry a 401.** `accessToken()` must check expiry and refresh.
- `actionToken(scope)` is the user's **wallet signature** over a confirmation action, exchanged by the backend for a short-lived, one-shot token. A user declining throws `WirexDeclined`.
- Read **per call** — a value refreshed mid-session takes effect on the next SDK call.

---

## 5. Surfaces — exact API

### 5.1 Reveal  (needs credentials)
```dart
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

await WirexReveal.instance.configure(testMode: isTestMode, chainId: chainId, credentials: credentials);
final session = await WirexReveal.instance.createSession(
  cardId: cardId,
  fields: const [WirexRevealField.cardholderName, WirexRevealField.pan,
                 WirexRevealField.expiry, WirexRevealField.cvv, WirexRevealField.pin], // omit pin for virtual
  cardholderName: cardholderName);
session.onSnapshot((s) { /* s.state: idle|loading|ready|error */ });
await session.load();
```
- Render one `WirexRevealFieldView(session: session, field: …)` per field — a native platform view. On the **iOS Simulator** the capture-proof layer renders **blank** (PCI protection, not a bug).

### 5.2 Collect  (needs credentials)
```dart
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

await WirexCollect.configure(testMode: isTestMode, chainId: chainId, accessToken: () async => bearer);
// WirexCollectFormView(...) with a WirexCollectFormController; onChange reports validity + brand
final token = await controller.tokenizeTopUp(
  WirexTopUpTokenizeParams(billingDetails: WirexBillingDetails(line1: …, zipCode: …, city: …, country: …)));
// token: brand, last4, expiryMonth, expiryYear — opaque; PAN/CVV never cross the Dart bridge
```
- The **card user must be enrolled at the acquirer**; a non-enrolled user fails tokenization. The **partner backend** then funds the top-up (§6).

### 5.3 3-D Secure  (NO credentials)
```dart
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

await WirexThreeDS.instance.configure(testMode: isTestMode, logging: 'info');  // no credentials
final session = await WirexThreeDS.instance.createSession(url);                 // url from the top-up execute response
// WirexThreeDSView(session: session) full-size; session.onSnapshot((s) => s.state == WirexThreeDSState.settled)
```
- State: `idle | loading | challenge | settled`; status: `completed | pending | failed | unknown`.
- `pending` = **not settled yet**, not an error. Reconcile the real outcome from the backend status feed.

### 5.4 Wallet  (needs credentials; real device only for the Pay sheet)
```dart
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

final env = await WirexWalletEnvironment.resolve(environmentName);  // throws WirexWalletEnvironmentUnavailable
final config = WirexWalletConfig(environment: env, cache: cache);

WirexWalletCheckoutView(
  config: config,
  quote: WirexWalletQuote(estimationId: id, sourceAmount: WirexWalletMoney(amount: '10.00', currency: 'EUR')),
  providerConfig: providerBlock,   // WirexWalletProviderConfig from your app config, VERBATIM
  auth: tokenMode ? WirexWalletCheckoutAuth(checkoutToken: token) : null,
  onCreated: (WirexWalletCheckoutController c) => controller = c,
  onEvent: (event) { /* ready, naturalHeight, sheetOpen, cancelled, attemptFailed, estimationExpired,
      token (legacy), executing/executed/executeFailed (token mode), failed, diagnostic */ },
);
// controller.rearm(quote, providerConfig) after estimationExpired
```
- **Legacy** (no `auth`): the sheet tokenizes → `token` event → the backend executes. **Token mode** (`auth`): the frame executes itself. On the Simulator the Pay sheet cannot present; the checkout still arms.

---

## 6. Backend orchestration (what the SDK does NOT do)

The partner backend owns these (Wirex BaaS API, partner credentials). The SDK consumes their results.

- **Price a top-up** → `estimationId` + fiat `sourceAmount`. Short TTL; re-price to re-arm.
- **Execute a top-up** → settles it; a card payment returns a **3DS orchestrator URL** for `WirexThreeDS.createSession(url)`.
- **Mint a checkout token** (token mode only) → the `checkoutToken`; scoped to the top-up flow, independent of a specific estimation.
- **Provider config** → the wallet provider block, served from your app config, passed to Wallet verbatim.

`estimationId` and `checkoutToken` are **two independent values**.

---

## 7. Invariants & gotchas

- **One identity.** email XOR wallet; both → 400.
- **Bearer expiry.** `accessToken()` must refresh; the SDK does not retry 401.
- **`estimationId` ≠ `checkoutToken`.**
- **Platform-view sizing.** The reveal/collect field views report their own height; let them size the row.
- **Wallet availability** reports unavailable on the Simulator / a device without a provisioned card — the real answer; the checkout still arms.
- **Collect needs an acquirer-enrolled user**, else tokenization fails.
- **3DS `pending` is not an error.** Settle by backend status.
- **`providerConfig` is passed verbatim.** Absent `apple_pay`/`google_pay` means "do not offer".
- **Assets.** The env config files must be declared under `flutter: assets:` in `pubspec.yaml`, or `rootBundle.loadString` throws at startup.
- **Unknown environment** throws `WirexWalletEnvironmentUnavailable` — render the reason; never fall back.

---

## 8. The runnable example

This repo is a runnable Flutter example covering all four surfaces. Credentials are entered
at runtime (pasted JSON on the Reveal/Collect screens). The field contract matches the React Native /
iOS / Android examples.

---

## 9. Quick decision rules

- "Which surface needs credentials?" → Reveal, Collect, Wallet yes; 3DS no.
- "Where does the `estimationId` come from?" → the partner backend prices the top-up; the SDK only consumes it. Not from any token.
- "Legacy or token mode for Wallet?" → token mode keeps the sheet payload off the device; legacy returns a token the backend executes. Both need a backend.
- "Why is the Pay button unavailable?" → simulator, no provisioned card, or an empty provider block.
- "Why is a revealed field blank?" → the iOS Simulator (secure layer), or the platform view wasn't allowed to size itself.
- "Why does Collect fail to tokenize?" → the user is not enrolled at the acquirer.
