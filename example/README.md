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

The package is resolved from pub.dev (`wirex_mobile_sdk: ^0.3.13` in `pubspec.yaml`).

## Configure at runtime

Nothing is compiled in. The **Config** tab is a per-field editor over `LiveConfig`, the single store
every surface reads live — type a value and the next call picks it up, no rebuild. It holds:

- the **environment** (`test` / `production`), which drives the card surfaces' `testMode` — a side,
  never a URL; the SDK holds both addresses;
- integration parameters — chain id, user email, user wallet, card id, cardholder name;
- secrets (bearer, step-up action token), held in memory only and never persisted or logged.

The Wallet surface takes the same environment name from the Config tab.

## The surfaces

| Tab | What it shows |
|---|---|
| **Config** | a per-field editor for the environment, integration parameters and secrets, shared by every surface |
| **Reveal** | the cardholder's own PAN / expiry / CVV / PIN as native platform views |
| **Collect** | a sealed form that tokenizes an external funding card at the acquirer |
| **3DS** | paste a top-up orchestrator URL → the issuer challenge, and the outcome |
| **Wallet** | the hosted Apple Pay / Google Pay checkout (paste a provider block, build a quote — legacy tokenise flow) |
| **Appearance** | restyle every sealed surface at once — presets or a pasted token document |

The field contract is the same across the React Native / iOS / Android examples — see
`../PARTNER-CONFIG.md`.

> A revealed value is a native view; on the iOS Simulator the capture-proof layer renders blank (PCI
> protection, not a bug). The Apple/Google Pay sheet needs a real device; the checkout still arms.
