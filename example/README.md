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

The package is resolved from pub.dev (`wirex_mobile_sdk: ^0.3.14` in `pubspec.yaml`).

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
| **Trade** | a stock or coin trade: Account, Catalog, Quote, Trade and Open orders, signed by a test user's key |
| **Crypto** | a send to an address on any network, and the account's deposit addresses: Balances, Send, Pending and Deposit |
| **Appearance** | restyle every sealed surface at once — presets or a pasted token document |

The field contract is the same across the React Native / iOS / Android examples — see
`../PARTNER-CONFIG.md`.

> A revealed value is a native view; on the iOS Simulator the capture-proof layer renders blank (PCI
> protection, not a bug). The Apple/Google Pay sheet needs a real device; the checkout still arms.

## Run a trade or a send from a local build

The Trade and Crypto tabs sign with a test user's exported private key. Use a test user only, and keep
amounts small: on `production` each tab refuses a trade or a send worth more than 10 USD.

The Crypto tab counts a send at its amount, then at what leaves with the fee, at `Send` and `Resume`.
USDC, USDT and WUSD count at face value, EURC and WEUR at 1.25 USD, and any other token is refused.
It holds its quotes in memory only. After a restart, `Load pending` still lists an open send. A row
with no held quote shows "no quote held for this send" and cannot resume.

### Prefill the config from a file

1. Copy `e2e/e2e.example.json` to `e2e/e2e.local.json`. Git ignores the copy.
2. Fill in `environment`, `chainId`, `companyId`, `baasApiUrl` and `ownerKey`. The example values are fake.
3. Run a debug build: `flutter run`.

The file wins over the Config tab and a seed link. Only a debug build reads it. A release or profile
build fails while the file exists, so move it away before you build one. A seed link never carries
`ownerKey`, and the Config tab keeps it in memory only.

The app gets its bearer from the key. It signs the login message and calls
`POST /api/v1/user/authorize` at `baasApiUrl`. A `bearer` pasted on the Config tab wins over the login.

### Build against local SDK sources

Until the SDK release with `Trade` and `Crypto` is out, the tabs build only against local checkouts of the plugin
and the native SDKs. Without these steps the example builds against the published package.

1. Point pub at the plugin checkout. Create `example/pubspec_overrides.yaml`, which git ignores:

   ```yaml
   dependency_overrides:
     wirex_mobile_sdk:
       path: <the plugin checkout>/mobile-sdk/flutter
   ```

2. Point the native builds at the native SDK checkouts:
   - iOS: `WIREX_IOS_SDK=<iOS SDK checkout> flutter run`. The Podfile then builds the native SDK from
     its sources.
   - Android: pick an empty folder for the SDK build, never `~/.m2`, and set `WIREX_SDK_REPO` to it.
     Step 4 publishes the SDK there.
3. Write the endpoint table. The native SDKs hold no API addresses in their sources, so a build from
   source refuses to send without it. In both native checkouts, run `node tools/inject-endpoints.mjs`.
4. Android only: in the Android SDK checkout, run
   `./gradlew :mobile-sdk:publishToMavenLocal -Dmaven.repo.local="$WIREX_SDK_REPO"`.
5. Build and run the example. On Android, run
   `WIREX_SDK_REPO=<that folder> WIREX_ANDROID_SDK=<Android SDK checkout> flutter run`. Gradle then takes
   `com.wirexapp.baas:mobile-sdk` only from that folder, at the checkout's `VERSION`, in place of the
   published artifact.
6. In both native checkouts, run `node tools/inject-endpoints.mjs --empty` to put the empty table
   back. Never commit an injected table.

A local build rewrites `ios/Podfile.lock` and `pubspec.lock` with local paths. Put both back before
you commit.

