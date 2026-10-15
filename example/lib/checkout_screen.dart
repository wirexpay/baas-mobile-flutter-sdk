import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

import 'event_log.dart';
import 'live_config.dart';
import 'quote_fields.dart';
import 'sample_config.dart';

/// The Checkout tab: provider config in, quote in, `WirexWalletCheckoutView` mounted, every event
/// logged. What a partner's top-up screen does, minus the estimate and execute calls — the SDK
/// knows nothing about either, so this example has nothing to call.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({required this.config, super.key});

  final WirexWalletConfig config;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final TextEditingController _providerJson = TextEditingController();
  final TextEditingController _estimationId = TextEditingController(text: defaultEstimationId);
  final TextEditingController _sourceAmount = TextEditingController(text: defaultSourceAmount);
  final TextEditingController _destinationAmount =
      TextEditingController(text: defaultDestinationAmount);
  final TextEditingController _fee = TextEditingController(text: defaultFee);
  final TextEditingController _currency = TextEditingController(text: defaultCurrency);
  final TextEditingController _ttlSeconds = TextEditingController(text: defaultTtlSeconds);

  /// Never in a release build: it is the one switch that makes the payment web view inspectable.
  bool _debug = false;
  bool _branding = true;
  bool _buttons = false;

  /// What is MOUNTED — captured at mount, not read live from the fields, because a platform view
  /// takes its creation params at creation. Edits reach it through "Mount checkout" (a new view)
  /// or "New quote (rearm)" (the same view, re-armed).
  WirexWalletQuote? _quote;
  WirexWalletProviderConfig? _providerConfig;

  /// Forces a NEW platform view per "Mount checkout" press. A new price never needs this — that is
  /// what rearm is for; remounting reloads the page and, on iOS, drops the Apple Pay session.
  int _mountGeneration = 0;

  WirexWalletCheckoutController? _controller;
  final List<String> _events = <String>[];
  String _note = '';

  @override
  void dispose() {
    _providerJson.dispose();
    _estimationId.dispose();
    _sourceAmount.dispose();
    _destinationAmount.dispose();
    _fee.dispose();
    _currency.dispose();
    _ttlSeconds.dispose();
    super.dispose();
  }

  String _stamp(String line) {
    final DateTime now = DateTime.now();
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(now.hour)}:${pad(now.minute)}:${pad(now.second)}  $line';
  }

  ({WirexWalletQuote quote, WirexWalletProviderConfig config})? _parseInputs() {
    final TopupParse provider = parseTopup(_providerJson.text);
    if (provider is TopupParseError) {
      setState(() => _note = 'provider config: ${provider.message}');
      return null;
    }
    final QuoteParse quote = parseQuoteFields(
      estimationId: _estimationId.text,
      sourceAmount: _sourceAmount.text,
      currency: _currency.text,
      destinationAmount: _destinationAmount.text,
      fee: _fee.text,
      ttlSeconds: _ttlSeconds.text,
    );
    if (quote is QuoteParseError) {
      setState(() => _note = 'quote: ${quote.message}');
      return null;
    }
    return (
      quote: (quote as QuoteParseOk).quote,
      config: (provider as TopupParseOk).config,
    );
  }

  // Prices a top-up with the documented Wirex BaaS API using the bearer on the Config tab, and fills
  // the estimation id. Pricing a top-up is the partner backend's job; this is a convenience to verify
  // a token and get a real id without a backend. The SDK only consumes the id.
  Future<void> _fetchEstimate() async {
    final String base =
        LiveConfig.instance.credential('baasApiUrl').trim().replaceAll(RegExp(r'/+$'), '');
    final String bearer = LiveConfig.instance.credential('bearer');
    final String chainId = LiveConfig.instance.credential('chainId');
    final String wallet = LiveConfig.instance.credential('wallet');
    final String email = LiveConfig.instance.credential('email');
    if (base.isEmpty || bearer.isEmpty) {
      setState(() => _note = 'Fetch estimate: set BaaS API URL + bearer on the Config tab');
      return;
    }
    final Map<String, String> headers = <String, String>{
      'Authorization': 'Bearer $bearer',
      'X-Chain-Id': chainId,
      'Content-Type': 'application/json',
    };
    if (wallet.isNotEmpty) {
      headers['X-User-Wallet'] = wallet;
    } else if (email.isNotEmpty) {
      headers['X-User-Email'] = email;
    } else {
      setState(() => _note = 'Fetch estimate: set a user wallet or email on the Config tab');
      return;
    }
    final String currency = _currency.text.trim().isEmpty ? 'EUR' : _currency.text.trim();
    final String amount =
        _destinationAmount.text.trim().isEmpty ? '100.00' : _destinationAmount.text.trim();
    setState(() => _note = 'fetching estimate…');
    try {
      // settlement token for the currency — GET /api/v1/config/tokens (documented).
      final http.Response toks = await http.get(Uri.parse('$base/api/v1/config/tokens'), headers: headers);
      if (toks.statusCode != 200) throw 'GET /config/tokens → HTTP ${toks.statusCode}';
      final dynamic toksBody = jsonDecode(toks.body);
      final List<dynamic> rows =
          toksBody is List ? toksBody : (toksBody['data'] as List<dynamic>? ?? <dynamic>[]);
      final Map<String, dynamic> token = rows.cast<Map<String, dynamic>>().firstWhere(
            (Map<String, dynamic> t) =>
                ((t['equivalent_symbols'] as List<dynamic>?)?.contains(currency) ?? false) ||
                (t['symbol'] as String? ?? '').endsWith(currency),
            orElse: () => <String, dynamic>{},
          );
      if (token.isEmpty) throw 'no settlement token for $currency';
      final String address =
          (token['address'] as String?) ?? (token['contract_address'] as String?) ?? '';
      final int decimals = (token['decimals'] as int?) ?? 18;
      // price — POST /api/v1/cards/topup/estimate (documented).
      final http.Response est = await http.post(
        Uri.parse('$base/api/v1/cards/topup/estimate'),
        headers: headers,
        body: jsonEncode(<String, Object?>{
          'destination_amount': _toBaseUnits(amount, decimals),
          'destination_token_address': address,
          'payment_method': 'apple_pay',
        }),
      );
      if (est.statusCode != 200) {
        throw 'POST /cards/topup/estimate → HTTP ${est.statusCode}: ${est.body}';
      }
      final String id = (jsonDecode(est.body) as Map<String, dynamic>)['estimation_id'] as String;
      setState(() {
        _estimationId.text = id;
        _note = 'estimate: $id';
      });
    } catch (e) {
      setState(() => _note = 'estimate failed: $e');
    }
  }

  /// display amount (e.g. "100.00") → base-units string (amount * 10^decimals), without float loss.
  String _toBaseUnits(String amount, int decimals) {
    final List<String> parts = amount.split('.');
    final String whole = parts[0];
    final String frac = parts.length > 1 ? parts[1] : '';
    final String fracPadded = (frac + '0' * decimals).substring(0, decimals);
    final String scaled = (whole + fracPadded).replaceFirst(RegExp(r'^0+'), '');
    return scaled.isEmpty ? '0' : scaled;
  }

  void _mount() {
    final ({WirexWalletQuote quote, WirexWalletProviderConfig config})? parsed = _parseInputs();
    if (parsed == null) return;
    setState(() {
      _quote = parsed.quote;
      _providerConfig = parsed.config;
      _mountGeneration += 1;
      _controller = null;
      _events.clear();
      _note = 'mounted — the box is zero tall until the frame\'s first resize, then it sizes itself';
    });
  }

  Future<void> _rearm() async {
    final WirexWalletCheckoutController? controller = _controller;
    if (controller == null || controller.isDestroyed) {
      setState(() => _note = 'nothing mounted — press "Mount checkout" first');
      return;
    }
    final ({WirexWalletQuote quote, WirexWalletProviderConfig config})? parsed = _parseInputs();
    if (parsed == null) return;
    // Through the CONTROLLER, deliberately: passing a changed quote to the widget makes the same
    // call, and doing both here would re-arm twice. Either way the buttons stay and the review
    // screen and countdown refresh — never remount for a new price.
    await controller.rearm(parsed.quote, parsed.config);
    setState(() =>
        _note = 'rearmed with estimationId "${parsed.quote.estimationId}" — countdown restarted');
  }

  void _unmount() {
    setState(() {
      _quote = null;
      _providerConfig = null;
      _controller = null;
      _note = 'unmounted — a real host keeps the view mounted until token, cancelled, '
          'attemptFailed or failed; tearing it down mid-attempt kills the payment sheet';
    });
  }

  void _onEvent(WirexWalletCheckoutEvent event) {
    if (!mounted) return;
    setState(() {
      _events.add(_stamp(describeCheckoutEvent(event)));
      if (_events.length > 200) _events.removeRange(0, _events.length - 200);
    });
  }

  @override
  Widget build(BuildContext context) {
    final WirexWalletQuote? quote = _quote;
    final WirexWalletProviderConfig? providerConfig = _providerConfig;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'The checkout below is the NATIVE SDK\'s web view in a platform view: a Wirex-hosted '
            'page draws the review screen and the wallet button, and the sheet\'s encrypted '
            'payload comes back in ONE event. This example never calls estimate or execute — the '
            'SDK knows nothing about either.',
            style: TextStyle(fontSize: 12),
          ),
          _panel(
            title: 'Provider config (the app config\'s `topup` value, JSON)',
            initiallyExpanded: true,
            children: <Widget>[
              const Text(
                'Resolved through WirexWalletProviderConfigResolver before any view exists, then '
                'handed to the frame VERBATIM. The sample is SHAPE ONLY — paste a real '
                'environment\'s value for a live run.',
                style: TextStyle(fontSize: 10),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _providerJson,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  OutlinedButton(
                    onPressed: () => setState(() => _providerJson.text = sampleTopupJson),
                    child: const Text('Sample (shape only)'),
                  ),
                ],
              ),
            ],
          ),
          _panel(
            title: 'Quote (stands in for a real estimate)',
            children: <Widget>[
              _field('estimationId — what a re-arm compares', _estimationId),
              Row(
                children: <Widget>[
                  Expanded(child: _field('source amount', _sourceAmount)),
                  const SizedBox(width: 8),
                  Expanded(child: _field('currency', _currency)),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(child: _field('destination amount (optional)', _destinationAmount)),
                  const SizedBox(width: 8),
                  Expanded(child: _field('fee (optional)', _fee)),
                ],
              ),
              _field('expires in (seconds; empty = no countdown)', _ttlSeconds),
              const Text(
                'Amounts are passed as strings, verbatim — the frame formats them. Expiry becomes '
                'expiresAtMs when the quote is built.',
                style: TextStyle(fontSize: 10),
              ),
            ],
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('debug', style: TextStyle(fontSize: 13)),
            subtitle: const Text(
              'frame console relay + inspectable web view. NEVER in a release build.',
              style: TextStyle(fontSize: 10),
            ),
            value: _debug,
            onChanged: (bool value) => setState(() => _debug = value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('branding — partner name in the processing disclosure',
                style: TextStyle(fontSize: 13)),
            value: _branding,
            onChanged: (bool value) => setState(() => _branding = value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('buttons — send explicit presets', style: TextStyle(fontSize: 13)),
            subtitle: const Text(
              'off = sent ABSENT, so the frame applies its own defaults — no binding substitutes '
              'one of its own.',
              style: TextStyle(fontSize: 10),
            ),
            value: _buttons,
            onChanged: (bool value) => setState(() => _buttons = value),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton(onPressed: _fetchEstimate, child: const Text('Fetch estimate')),
              FilledButton(onPressed: _mount, child: const Text('Mount checkout')),
              OutlinedButton(onPressed: _rearm, child: const Text('New quote (rearm)')),
              OutlinedButton(onPressed: _unmount, child: const Text('Unmount')),
            ],
          ),
          if (_note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_note, style: const TextStyle(fontSize: 12, color: Colors.deepPurple)),
            ),
          if (quote != null && providerConfig != null) ...<Widget>[
            const SizedBox(height: 12),
            // The web view is transparent and reports its own height; the host owns background and
            // padding — and the background is DARK on purpose: the frame's text is styled for a dark
            // host surface (the app renders it over #141414, the frame's popup mode boots on the same
            // colour), so a light box washes the review card out. No fixed height around it.
            ColoredBox(
              color: const Color(0xFF141414),
              child: WirexWalletCheckoutView(
                key: ValueKey<int>(_mountGeneration),
                config: widget.config,
                quote: quote,
                providerConfig: providerConfig,
                branding: _branding
                    ? const WirexWalletBranding(processingDisclosurePartnerName: 'Example Partner')
                    : null,
                buttons: _buttons
                    ? const WirexWalletButtons(
                        applePay: WirexWalletApplePayButton(),
                        googlePay: WirexWalletGooglePayButton(),
                      )
                    : null,
                debug: _debug,
                onCreated: (WirexWalletCheckoutController controller) => _controller = controller,
                onEvent: _onEvent,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text('Events (${_events.length})', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _events.isEmpty
                  ? 'nothing yet — press "Mount checkout". The token line carries metadata and the '
                      'payload\'s LENGTH, never the payload.'
                  : _events.reversed.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: controller,
          autocorrect: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Widget _panel({
    required String title,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) =>
      ExpansionTile(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        initiallyExpanded: initiallyExpanded,
        children: children,
      );
}
