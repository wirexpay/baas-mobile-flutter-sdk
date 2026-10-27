import 'package:flutter/material.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

import 'diag_log.dart';
import 'live_config.dart';

/// The card-ENTRY screen, on the sibling package.
///
/// What it is here to demonstrate, in order:
///
/// 1. **The form is a NATIVE view.** Everything below the heading is one platform view. Flutter never
///    sees a keystroke, and there is no Dart object holding what was typed — `onChange` carries
///    validity and a scheme, and that is the entire event.
/// 2. **The host owns the wording.** Labels and error text come from this file, not the SDK.
/// 3. **Tokenisation returns an opaque token**, which is what a host stores.
///
/// The two packages coexist here without either importing the other, which is the arrangement a
/// partner taking only one of them relies on.
class CollectScreen extends StatefulWidget {
  const CollectScreen({required this.configured, super.key});

  /// Whether `WirexCollect.configure` has succeeded. The form renders regardless — an unconfigured
  /// plugin shows an empty native view and says so — but tokenising would fail, so the button is off.
  final bool configured;

  @override
  State<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends State<CollectScreen> {
  WirexCollectFormController? _controller;

  /// Whether this screen lays the fields out itself. The Android example does the same thing with
  /// expiry and CVV side by side; here it is a toggle so both paths are exercised in one build.
  bool _hostPlacement = false;

  /// Fields the form reported it does not have, so the layout leaves them out rather than showing a
  /// gap. `oct-destination` has no CVV and no expiry.
  final Set<WirexCollectField> _absent = <WirexCollectField>{};
  WirexCollectState _state = const WirexCollectState.empty();
  WirexCollectProfile _profile = WirexCollectProfile.topup;
  WirexErrorLine _errorLine = WirexErrorLine.animated;
  String _result = '—';
  bool _submitting = false;

  /// Deliberately NOT the SDK's own wording, so the screen proves the hook is live rather than that
  /// it exists. The wildcard entry is the shape most hosts want: one sentence per reason.
  static const WirexCollectStrings _strings = WirexCollectStrings(
    labels: <WirexCollectField, String>{
      WirexCollectField.number: 'Card number',
      WirexCollectField.expiry: 'Expires',
      WirexCollectField.cvv: 'CVV',
      WirexCollectField.name: 'Cardholder',
    },
    errors: <WirexCollectField?, Map<WirexCollectFieldError, String?>>{
      null: <WirexCollectFieldError, String?>{
        WirexCollectFieldError.incomplete: 'Finish this field — it is incomplete',
        WirexCollectFieldError.invalid: 'That does not look right',
        WirexCollectFieldError.expired: 'That card has expired',
      },
      WirexCollectField.number: <WirexCollectFieldError, String?>{
        WirexCollectFieldError.invalid: 'Check the card number and try again',
      },
    },
  );

  Future<void> _tokenize() async {
    DiagLog.instance.tap('Collect: Tokenize tapped (profile=${_profile.name} complete=${_state.isComplete} '
        'brand=${_state.brand} configured=${widget.configured} controller=${_controller != null})');
    final controller = _controller;
    if (controller == null) {
      DiagLog.instance.err('Collect: tokenize skipped — no form controller yet');
      return;
    }
    setState(() {
      _submitting = true;
      _result = 'submitting…';
    });
    DiagLog.instance.sdk('collect tokenize started (${_profile == WirexCollectProfile.topup ? 'topup' : 'oct-destination'})');
    try {
      if (_profile == WirexCollectProfile.topup) {
        // A real host collects a billing address in its own UI: it is not card data and lives outside
        // the sealed surface on purpose.
        final token = await controller.tokenizeTopUp(
          const WirexTopUpTokenizeParams(
            billingDetails: WirexBillingDetails(
              line1: '1 Example Street',
              zipCode: 'SW1A 1AA',
              city: 'London',
              country: 'GB',
            ),
          ),
        );
        _result = 'linked\ncardId: ${token.cardId}\n'
            '${token.brand} •••• ${token.last4}  bin ${token.bin}\n'
            'expiry: ${token.expiryMonth}/${token.expiryYear}';
        DiagLog.instance.sdk('collect tokenize ok: cardId ${token.cardId.length} chars, brand=${token.brand} last4=${token.last4}');
      } else {
        final token = await controller.tokenizeOctDestination(
          const WirexOctTokenizeParams(
            cardLabel: 'Example recipient',
            isSaved: false,
            isThirdParty: true,
          ),
        );
        _result = 'registered\nexternalCardId: ${token.externalCardId}\n'
            '${token.brand} •••• ${token.last4}  bin ${token.bin}';
        DiagLog.instance.sdk('collect tokenize ok: externalCardId ${token.externalCardId.length} chars, brand=${token.brand} last4=${token.last4}');
      }
    } on WirexCollectError catch (error) {
      // `retryable` is the whole point of the envelope: a transport failure on a CREATING call comes
      // back false, because the card may already exist.
      _result = 'failed: ${error.code} (retryable: ${error.retryable})';
      DiagLog.instance.err('collect tokenize failed: ${error.code} retryable=${error.retryable}');
    } catch (error) {
      _result = 'failed: $error';
      DiagLog.instance.err('collect tokenize threw: ${error.runtimeType} $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The layout a card form usually wants and the SDK deliberately does not decide: expiry and CVV
  /// on one line.
  ///
  /// PARTIAL on purpose, which is the case worth demonstrating — the form above goes on stacking
  /// number and name, and its box shrinks by exactly the two rows that left. Taking every field
  /// works too and leaves the form drawing nothing.
  ///
  /// `oct-destination` has neither of these fields, so on that profile this renders nothing and the
  /// form draws its whole (shorter) set. That is what `onUnavailable` reports, and it is not an
  /// error: a host asking an OCT form for a CVV is asking about a field that does not exist.
  Widget _placedFields(WirexCollectFormController controller) {
    Widget field(WirexCollectField f) => WirexCollectFieldView(
          controller: controller,
          field: f,
          onUnavailable: (WirexCollectField missing) {
            DiagLog.instance.sdk('collect field unavailable: ${missing.wireName}');
            setState(() => _absent.add(missing));
          },
        );

    final bool expiry = !_absent.contains(WirexCollectField.expiry);
    final bool cvv = !_absent.contains(WirexCollectField.cvv);
    if (!expiry && !cvv) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (expiry) Expanded(child: field(WirexCollectField.expiry)),
          if (expiry && cvv) const SizedBox(width: 12),
          if (cvv) Expanded(child: field(WirexCollectField.cvv)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The EXAMPLE resolves its own `system` choice — the SDK is handed one map and told which mode
    // it is, never a policy to follow.
    final osIsDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final perField = _state.fields
        .map((f) => '${f.field.wireName}: '
            '${f.isValid ? 'ok' : (f.isEmpty ? 'empty' : 'invalid')}'
            '${f.isTouched ? '' : ' (untouched)'}')
        .join('\n');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'The form below is a NATIVE view inserted into this Flutter tree. Flutter never sees a '
            'keystroke and no Dart object holds what was typed.',
          ),
          const SizedBox(height: 12),
          SegmentedButton<WirexCollectProfile>(
            segments: const <ButtonSegment<WirexCollectProfile>>[
              ButtonSegment<WirexCollectProfile>(
                value: WirexCollectProfile.topup,
                label: Text('topup'),
              ),
              ButtonSegment<WirexCollectProfile>(
                value: WirexCollectProfile.octDestination,
                label: Text('oct'),
              ),
            ],
            selected: <WirexCollectProfile>{_profile},
            onSelectionChanged: (Set<WirexCollectProfile> selected) {
              DiagLog.instance.tap("Collect: profile chip '${selected.first.name}' tapped");
              setState(() => _profile = selected.first);
            },
          ),
          const SizedBox(height: 8),
          SegmentedButton<WirexErrorLine>(
            segments: const <ButtonSegment<WirexErrorLine>>[
              ButtonSegment<WirexErrorLine>(value: WirexErrorLine.animated, label: Text('anim')),
              ButtonSegment<WirexErrorLine>(value: WirexErrorLine.reserved, label: Text('reserved')),
              ButtonSegment<WirexErrorLine>(value: WirexErrorLine.hidden, label: Text('hidden')),
            ],
            selected: <WirexErrorLine>{_errorLine},
            onSelectionChanged: (Set<WirexErrorLine> selected) {
              DiagLog.instance.tap("Collect: error line '${selected.first.name}' tapped");
              setState(() => _errorLine = selected.first);
            },
          ),
          const SizedBox(height: 12),
          // No height: the form reports its own, so the appearance tokens decide it.
          WirexCollectFormView(
              // The SAME tokens the reveal rows get, from the Appearance tab. Passed as raw maps
              // because the collect binding hands the document to the native reader rather than
              // parsing it in Dart — one implementation of the fallback chain per platform.
              appearance: LiveConfig.instance.appearanceTokens(osIsDark),
              themeMode: LiveConfig.instance.isDarkMode(osIsDark)
                  ? WirexThemeMode.dark
                  : WirexThemeMode.light,
              // The key forces a fresh native form when the PROFILE changes — a different profile is
              // a different set of fields. Appearance and the error line are pushed instead, because
              // a restyle must never clear what is typed.
              key: ValueKey<WirexCollectProfile>(_profile),
              profile: _profile,
              strings: _strings,
              errorLine: _errorLine,
              // setState, because the field views below cannot be built until the controller exists
              // — it is what they name the form with.
              onCreated: (WirexCollectFormController controller) {
                DiagLog.instance.sdk('collect form created (profile=${_profile.name})');
                setState(() => _controller = controller);
              },
            onChange: (WirexCollectState state) {
              DiagLog.instance.sdk('collect state: complete=${state.isComplete} brand=${state.brand} '
                  '${state.fields.map((f) => '${f.field.wireName}=${f.isValid ? 'ok' : (f.isEmpty ? 'empty' : 'invalid')}').join(' ')}');
              setState(() => _state = state);
            },
          ),
          if (_hostPlacement && _controller != null) _placedFields(_controller!),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hostPlacement,
            // The KEY changes with it, so switching rebuilds the native form. Taking rows out of a
            // form and giving them back mid-life is not something the SDK supports, and an example
            // should not be the place that finds out.
            onChanged: (bool on) => setState(() {
              DiagLog.instance.tap('Collect: host placement switched ${on ? 'on' : 'off'}');
              _hostPlacement = on;
              _absent.clear();
              _controller = null;
            }),
            title: const Text('Place expiry and CVV myself'),
            subtitle: const Text('on one line — the form stacks the rest'),
          ),
          const SizedBox(height: 12),
          Text(
            'complete: ${_state.isComplete}\nbrand: ${_state.brand}\n$perField',
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilledButton(
                onPressed:
                    (_state.isComplete && widget.configured && !_submitting) ? _tokenize : null,
                child: const Text('Tokenize'),
              ),
              OutlinedButton(
                onPressed: () {
                  DiagLog.instance.tap('Collect: Clear tapped');
                  final controller = _controller;
                  if (controller != null) logged(controller.clear(), 'collect clear');
                },
                child: const Text('Clear'),
              ),
              OutlinedButton(
                onPressed: () async {
                  DiagLog.instance.tap('Collect: Capture state tapped');
                  final protected = await _controller?.isScreenshotProtectionActive() ?? false;
                  DiagLog.instance.sdk('collect capture-protected: $protected');
                  setState(() => _result = 'capture-protected: $protected');
                },
                child: const Text('Capture state'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(_result, style: const TextStyle(fontFamily: 'Menlo', fontSize: 12)),
        ],
      ),
    );
  }
}
