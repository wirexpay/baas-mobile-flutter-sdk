## 0.3.14

- Native SDKs bumped to 0.3.14: reveal now honours `dangerouslyDisableScreenProtection` for a row attached before its session binds (the window no longer stays `FLAG_SECURE` when protection was disabled), and a reveal field redacts its own debug output.

## 0.3.13

Reveal
- A row masked when the app leaves the foreground keeps your reveal request and draws again on return, as long as the session still holds the value. Past the session's 120 s lifetime the row stays masked until you load again.
- A hidden segmented field (PIN) shows the masked placeholder's glyph in every cell instead of empty boxes.
- iOS floor is 15.0 on every plugin pod.
- Android: PIN cells sized like iOS; card entry no longer leaks through a screen capture.
- Android: Reveal: PIN cells fill the row at `controlMinHeight` height in a host box of exactly that height: a blank label collapses and a field without a copy control gives the copy slot to the value.
- Reveal: new string `maskedSegmentGlyph`, drawn in every PIN cell while masked (default `*`; pass `•` for dots).

## 0.3.7

- 3-D Secure: presents the card issuer's authentication page a top-up asks for and reports the outcome.
- Wallet top-up: token mode. The checkout can execute the top-up itself and report executing / executed / failed instead of handing back a token. Standalone launch helpers build the checkout URL and parse the return link for hosts that open the checkout in a browser tab; the return link is matched at a path boundary.
- Privacy manifests ship with the iOS artifacts.
- Collect: the credential channel resolves the right pending request, times out, and no longer crashes Android on a host decline.

## 0.3.1

First public release.

- Card reveal: shows a cardholder their own card number, expiry, CVV and PIN inside the host app.
- Card collect: takes a card the user is entering and returns a token.
- Wallet top-up: hosts the Wirex checkout with Apple Pay and Google Pay.
- One environment model for every surface: `production` and `test`.
