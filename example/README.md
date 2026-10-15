# Wirex Mobile SDK — Flutter example

A Flutter app (Dart) that exercises **every surface** of the SDK — card **Reveal**, card **Collect**,
the **3-D Secure** step-up and **Wallet** top-up (Apple Pay / Google Pay).

The Wirex Mobile SDK is **one package** — `wirex_mobile_sdk` — carrying all four surfaces. A single
`import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart'` brings Reveal, Collect, 3-D Secure and
Wallet top-up.

## Install & run

```sh
flutter pub get
flutter run
```

The package is resolved from pub.dev (`wirex_mobile_sdk: ^0.3.7` in `pubspec.yaml`).

## The environment

- Card surfaces: `wirex-card-sdk.json` (`{ "testMode": true }`).
- Wallet surface: `wirex-wallet-sdk.json` (`{ "environment": "test" }`).

Both are Flutter assets (declared under `flutter: assets:` in `pubspec.yaml`). The environment is a
name, never a URL; the SDK maps it onto the hosts it holds.

## Enter credentials at runtime

Nothing is compiled in. On the Reveal / Collect screens, paste a JSON subset into the credentials box —
`{"bearer":"…","cardId":"…","actionToken":"…","cardholderName":"…"}` — a key you omit keeps its value.

## The surfaces

| Tab | What it shows |
|---|---|
| **Reveal** | the cardholder's own PAN / expiry / CVV / PIN as native platform views |
| **Collect** | a sealed form that tokenizes an external funding card at the acquirer |
| **3DS** | paste a top-up orchestrator URL → the issuer challenge, and the outcome |
| **Wallet** | the hosted Apple Pay / Google Pay checkout (paste a provider block, build a quote — legacy tokenise flow) |

The field contract is the same across the React Native / iOS / Android examples — see
`../PARTNER-CONFIG.md`.

> A revealed value is a native view; on the iOS Simulator the capture-proof layer renders blank (PCI
> protection, not a bug). The Apple/Google Pay sheet needs a real device; the checkout still arms.
