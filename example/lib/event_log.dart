/// One line per checkout event, safe to render and to keep in a scrollback.
///
/// SECURITY: the token line carries method, card network, PAN last4, display name and the payload's
/// LENGTH — never the payload, not even truncated. The payload's one path is the host's execute
/// call; an example that printed it would teach partners to log it. `test/event_log_test.dart`
/// pins this. In token mode no event carries a token of either kind — the host's top-up token goes
/// in (`WirexWalletCheckoutAuth`) and never comes back out — so those lines have nothing to hide.
library;

import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

String describeCheckoutEvent(WirexWalletCheckoutEvent event) {
  // An if-chain with a fallback rather than an exhaustive switch: `WirexWalletCheckoutEvent` grows
  // when the frame grows in later SDK versions, and HOSTS must keep a default arm — the SDK
  // switches exhaustively so a new event reaches every shell; hosts must not.
  if (event is WirexWalletCheckoutReady) {
    return 'ready — review screen rendered, buttons live';
  }
  if (event is WirexWalletCheckoutNaturalHeight) {
    return 'naturalHeight ${event.height.toStringAsFixed(1)} — the widget sized itself';
  }
  if (event is WirexWalletCheckoutSheetOpen) {
    return 'sheetOpen — keep the view mounted until this attempt settles';
  }
  if (event is WirexWalletCheckoutCancelled) {
    return 'cancelled — sheet dismissed, nothing tokenized';
  }
  if (event is WirexWalletCheckoutAttemptFailed) {
    final String suffix =
        event.known == null ? ' (unknown slug — a host shows its generic line)' : '';
    return 'attemptFailed: ${event.reason}$suffix';
  }
  if (event is WirexWalletCheckoutEstimationExpired) {
    return 'estimationExpired — re-estimate and press "New quote (rearm)"';
  }
  if (event is WirexWalletCheckoutToken) {
    final WirexWalletPaymentToken token = event.token;
    // SECURITY: metadata and LENGTH only. The payload itself is never rendered or logged.
    return 'token — method=${token.method.wire}'
        ' cardNetwork=${token.cardNetwork ?? '—'}'
        ' panLast4=${token.panLast4 ?? '—'}'
        ' displayName=${token.displayName ?? '—'}'
        ' payload=${token.walletPaymentToken.length} chars (not shown)'
        ' → a real host calls execute now';
  }
  if (event is WirexWalletCheckoutExecuting) {
    return 'executing — token mode: the sheet closed, the frame is calling execute';
  }
  if (event is WirexWalletCheckoutExecuted) {
    final WirexWalletExecuteResult result = event.result;
    return 'executed — id=${result.id} status=${result.status} method=${result.method.wire}'
        ' — token mode: reconcile by status, as after your own execute';
  }
  if (event is WirexWalletCheckoutExecuteFailed) {
    final WirexWalletExecuteError error = event.error;
    final String suffix =
        error.known == null ? ' (unknown slug — a host shows its generic line)' : '';
    return 'executeFailed: ${error.reason}$suffix'
        ' status=${error.statusCode ?? '—'} detail=${error.detail ?? '—'}'
        ' — re-arm with a fresh quote AND a fresh token';
  }
  if (event is WirexWalletCheckoutFailed) {
    final WirexWalletError error = event.error;
    return 'failed: ${error.kind.wire}'
        ' code=${error.code ?? '—'} status=${error.statusCode ?? '—'}'
        ' detail=${error.detail ?? '—'} — dead end for this mount';
  }
  if (event is WirexWalletCheckoutDiagnostic) {
    return 'diagnostic: ${event.diagnostic.kind.wire} ${event.diagnostic.fields}';
  }
  if (event is WirexWalletCheckoutDebug) {
    return 'frame[${event.level}]: ${event.message}';
  }
  return 'event: ${event.runtimeType}';
}
