# Example configuration — the debug menu

This example is one binary that exercises **every SDK surface** against **any partner's data**. Nothing
is hard-coded: the **Config** tab is a per-field editor for the integration parameters and credentials, and
every screen reads it live. The same field set is the contract for the iOS, Android, React Native and Flutter
examples, so QA enters the same values everywhere; the Wallet screen additionally takes the estimation id and
the provider block, or fetches an estimate with your bearer.

## Fields

### Environment
| Field | What it is |
|---|---|
| `environment` | `test` or `production`. Maps to the SDK's `testMode`; the SDK holds the hosts itself. |

### Integration parameters (non-secret)
| Field | What it is | Who gives it |
|---|---|---|
| `chainId` | `X-Chain-Id` — the chain the partner operates on | **Wirex**, per integration |
| `clientId` | `?client=` on the hosted pages (optional) | **Wirex** |
| `userEmail` / `userWallet` | identity headers `X-User-Email` / `X-User-Wallet` | partner (the signed-in user) |
| `cardId` | the card Reveal / Collect act on | partner (a provisioned card) |
| `cardholderName` | display name on Collect | partner |
| `walletAmount` / `walletCurrency` / `walletProvider` | the top-up quote the Wallet screens arm with | partner (from an estimate) |
| `baasApiUrl` | the BaaS API base URL (https), for the Trade tab's login and the Wallet screen's **Fetch estimate** helper. That helper only checks a bearer: pricing is the partner backend's job | **Wirex**, per environment |
| `companyId` | `X-Company-Id` of the Trade and Crypto tabs' login, and part of the message it signs | **Wirex**, per integration |
| `returnUrl` | Custom Tab App Link — **https, verified for this app's package** (`assetlinks.json`) | partner |

### Secrets (memory only — never persisted, never logged)
| Field | What it is | In production it is |
|---|---|---|
| `bearer` | `getAccessToken` — Wirex bearer for the user | minted by the partner's auth |
| `actionToken` | `getActionToken` — step-up for card data / PIN | the user's **wallet signature**, exchanged by the partner's backend |
| `checkoutToken` | token mode — the short-lived top-up token | minted by the **partner's backend** |
| `ownerKey` | the Trade and Crypto tabs' signer: a **test user's** exported private key. It signs the login and each UserOp hash. Never in a seed link | the user's own **wallet**, which signs; a real app never holds the key |

### Dev options
| Toggle | What it does |
|---|---|
| `Disable screen protection` | **DEV ONLY**: draws the revealed PAN/CVV on the iOS **Simulator** (the SDK's secure capture layer renders blank there). **Off by default** — leave off on a real device and in any shippable build; on it defeats PCI screen-capture protection. |

## What each surface needs

| Surface | What to enter |
|---|---|
| **Reveal** (PAN/CVV/expiry/PIN) | environment, chainId, bearer, actionToken, cardId |
| **Collect** (tokenize a card) | environment, chainId, bearer |
| **3DS step-up** | environment; a top-up orchestrator URL (the 3DS screen takes it directly — the SDK makes no call and needs no credentials) |
| **Wallet — Apple Pay / Google Pay** | environment, chainId, bearer, walletProvider, walletAmount/Currency; paste the estimation id + provider config on the Wallet screen |
| **Wallet — token mode** | the above + a `checkoutToken` your backend minted |
| **Trade** (stocks and coins) | environment, chainId, companyId, baasApiUrl, ownerKey. A pasted `bearer` wins over the key's login |
| **Crypto** (sends and deposit addresses) | the same fields as Trade. One login serves both tabs |

## Where the values come from

Each app fills the config from three sources. A higher source wins over a lower one.

| Order | Source | Notes |
|---|---|---|
| 1, highest | `example/e2e/e2e.local.json` | Gitignored. Only a debug build reads it, and a release or profile build fails while it exists. Copy `e2e/e2e.example.json` to start |
| 2 | The Config tab | `ownerKey` and the other secrets stay in memory only |
| 3 | A `wirexqa://seed` link | Never carries `ownerKey`: a link that does is refused whole. It leaves alone the keys the file or the Config tab set |

The other examples read the same fields from their own top source:

| Platform | Top source |
|---|---|
| iOS | The launch environment, from the Xcode scheme or `SIMCTL_CHILD_*` |
| Android | Intent extras, through `adb shell am start -e` |
| React Native and Flutter | A gitignored `e2e.local.json`, read only in debug builds |

The Trade and Crypto tabs get their bearer from the key. It signs `I, owner of account <owner> confirm that I request access token for company <companyId> on chain <chainId> at <nonce>` and sends it to `POST /api/v1/user/authorize` at `baasApiUrl`, with `X-Company-Id` and `X-Chain-Id`. The nonce is the Unix time in seconds.

On `production` the Trade tab refuses a trade worth more than 10 USD. The Crypto tab refuses a send whose amount, or what leaves with the fee, is worth more than 10 USD. It counts USDC, USDT and WUSD at face value, EURC and WEUR at 1.25 USD, and refuses any other token.

## Credentials in a real integration

The example lets QA **paste** `bearer` and `actionToken` so a device needs no backend or wallet. A real
partner implements the credential provider instead:

- `getAccessToken()` → a bearer from the partner's auth against Wirex BaaS.
- `getActionToken(scope)` → the **user's wallet signature** over the confirmation action (`cardData`, `pin`).
- `userEmail` / `userWallet` → the identity headers.
- `WirexTradeSigner.signPersonal(hash)` → the **user's wallet** signs each 32-byte hash. The example's `ownerKey` stands in for that wallet and is for testing only.

`WirexThreeDS.configure({ testMode })` takes **no** credentials: the host authenticates to obtain the
orchestrator URL and hands it over.
