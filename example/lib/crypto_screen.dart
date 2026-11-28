/// The Crypto tab: a send from the main account over any rail, and a deposit address, signed by the
/// test user's key on the Config tab. Its panels, buttons and wording match the other examples.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

import 'crypto_guard.dart';
import 'crypto_session.dart';
import 'diag_log.dart';
import 'live_config.dart';
import 'trade_error_line.dart';
import 'trade_guard.dart' show formatUnits;

const List<String> _networks = <String>[
  'ARC', 'BASE', 'ETHEREUM', 'ARBITRUM', 'OPTIMISM', 'AVALANCHE', 'MATIC_POS', 'BINANCE', 'TRON', 'SOLANA',
];
const List<String> _families = <String>['EVM', 'TRX', 'SOL', 'XLM', 'BTC'];
const List<String> _providers = <String>['', 'cctp', 'rhino', 'across'];

/// A send to another network leaves and arrives in USDC or USDT, at 6 decimals.
const int _sendDecimals = 6;

class CryptoScreen extends StatefulWidget {
  const CryptoScreen({super.key, this.session});

  /// The engine source; a test passes a fake. Null builds the real one.
  final CryptoSession? session;

  @override
  State<CryptoScreen> createState() => _CryptoScreenState();
}

class _CryptoScreenState extends State<CryptoScreen> {
  late final CryptoSession _session = widget.session ?? CryptoSession();
  final TextEditingController _token = TextEditingController(text: 'USDC');
  final TextEditingController _to = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  String _network = 'BASE';
  String _provider = '';
  String _family = 'EVM';

  bool _busy = false;
  final Map<String, String> _status = <String, String>{};
  WirexCrypto? _engine;

  List<WirexCryptoBalance>? _balances;
  WirexSendQuote? _quote;
  // Every quote this tab made, in memory only, so a pending row can find its own.
  List<WirexSendQuote> _held = const <WirexSendQuote>[];
  final List<WirexCryptoStepEvent> _steps = <WirexCryptoStepEvent>[];
  WirexSendResult? _result;
  WirexSendStatus? _delivery;
  List<WirexPendingSend>? _pending;
  WirexDepositAddress? _deposit;

  @override
  void initState() {
    super.initState();
    LiveConfig.instance.credentialsRevision.addListener(_configChanged);
  }

  @override
  void dispose() {
    LiveConfig.instance.credentialsRevision.removeListener(_configChanged);
    unawaited(_session.dispose());
    _token.dispose();
    _to.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _configChanged() {
    if (mounted) setState(() {});
  }

  void _update(VoidCallback change) {
    if (mounted) setState(change);
  }

  String get _environment => LiveConfig.instance.environment;

  /// What the typed amount gives against the cap, or null while it may be quoted.
  String? get _amountRefusal {
    final String amount = _amount.text.trim();
    if (amount.isEmpty) return null;
    // SECURITY: cap point 1, the typed amount in its token, before anything is asked for.
    return refuseSend(environment: _environment, symbol: _token.text, cents: sendTextCents(amount));
  }

  /// Runs one call with every button disabled, and shows its failure as one line in [panel].
  Future<void> _run(String panel, String button, Future<String?> Function(WirexCrypto crypto) call) async {
    DiagLog.instance.tap('Crypto: $button tapped');
    _update(() {
      _busy = true;
      _status[panel] = '$button…';
    });
    String? outcome;
    try {
      final WirexCrypto crypto = await _session.current();
      if (!identical(crypto, _engine)) {
        // A new instance for a new config: what the old one quoted is not this account's.
        _update(() {
          _engine = crypto;
          _balances = _quote = _result = _delivery = _pending = _deposit = null;
          _held = const <WirexSendQuote>[];
          _steps.clear();
        });
      }
      // The login's own reason first: through the SDK it would read only as token_unavailable.
      await _session.login.accessToken();
      outcome = await call(crypto);
    } catch (error) {
      outcome = tradeErrorLine(error);
      DiagLog.instance.err('Crypto: $button failed: ${error is WirexCryptoError ? error.reason : error.runtimeType}');
    }
    _update(() {
      _busy = false;
      _status[panel] = outcome ?? '$button: done';
    });
  }

  void _onStep(WirexCryptoStepEvent event) {
    DiagLog.instance.sdk('Crypto step ${event.step.wire} ${event.state.wire}${event.reason == null ? '' : ' reason ${event.reason}'}');
    _update(() => _steps.add(event));
  }

  Future<void> _readBalances() => _run('Balances', 'Read balances', (WirexCrypto crypto) async {
        final List<WirexCryptoBalance> rows = await crypto.balances();
        _update(() => _balances = rows);
        return rows.isEmpty ? 'no balances' : null;
      });

  Future<void> _getQuote() async {
    final String? refusal = _amountRefusal;
    if (refusal != null) {
      DiagLog.instance.app('Crypto: quote refused by the cap');
      _update(() => _status['Send'] = 'Get quote $refusal');
      return;
    }
    await _run('Send', 'Get quote', (WirexCrypto crypto) async {
      _update(() => _quote = null);
      final WirexSendQuote made = await crypto.quoteSend(
        to: _to.text,
        network: _network,
        token: _token.text.trim(),
        amount: _amount.text.trim(),
        provider: _provider.isEmpty ? null : _provider,
      );
      _update(() {
        _quote = made;
        _held = <WirexSendQuote>[..._held.where((WirexSendQuote q) => q.sendId != made.sendId), made];
      });
      return null;
    });
  }

  /// The cap on [quote] at Send and Resume, against a fresh balances read.
  Future<String?> _capRefusal(WirexCrypto crypto, WirexSendQuote quote) async {
    if (_environment != 'production') return null;
    final List<WirexCryptoBalance> rows = await crypto.balances();
    _update(() => _balances = rows);
    return refuseQuotedSend(environment: _environment, quote: quote, balances: rows);
  }

  Future<void> _send() async {
    final WirexSendQuote? quote = _quote;
    if (quote == null) return;
    await _run('Send', 'Send', (WirexCrypto crypto) async {
      // SECURITY: cap point 2, at the tap, on what leaves for the quote send is handed.
      final String? refusal = await _capRefusal(crypto, quote);
      if (refusal != null) {
        DiagLog.instance.app('Crypto: send refused by the cap');
        return refusal;
      }
      _update(() {
        _steps.clear();
        _result = _delivery = null;
      });
      final WirexSendResult result = await crypto.send(quote, onStep: _onStep);
      _update(() => _result = result);
      return null;
    });
  }

  Future<void> _checkDelivery() async {
    final WirexSendResult? result = _result;
    if (result == null) return;
    await _run('Send', 'Check delivery', (WirexCrypto crypto) async {
      final WirexSendStatus status = await crypto.sendStatus(result);
      _update(() => _delivery = status);
      DiagLog.instance.sdk('Crypto: delivery ${status.state.wire}');
      return null;
    });
  }

  Future<void> _loadPending() => _run('Pending', 'Load pending', (WirexCrypto crypto) async {
        final List<WirexPendingSend> rows = await crypto.pendingSends();
        _update(() => _pending = rows);
        return '${rows.length} pending';
      });

  /// The held quote of a pending row, matched by `requestHash` in lower case: a row names no `sendId`.
  WirexSendQuote? _heldFor(WirexPendingSend row) {
    for (final WirexSendQuote held in _held) {
      if (held.requestHash.toLowerCase() == row.hash.toLowerCase()) return held;
    }
    return null;
  }

  Future<void> _resume(WirexSendQuote held) => _run('Pending', 'Resume', (WirexCrypto crypto) async {
        // SECURITY: cap point 3, a resume still sends the execute, so the held quote is capped again.
        final String? refusal = await _capRefusal(crypto, held);
        if (refusal != null) {
          DiagLog.instance.app('Crypto: resume refused by the cap');
          return refusal;
        }
        _update(() {
          _steps.clear();
          _result = _delivery = null;
        });
        final WirexSendResult result = await crypto.resumeSend(held.sendId, held, onStep: _onStep);
        _update(() => _result = result);
        return null;
      });

  Future<void> _getDeposit() => _run('Deposit', 'Get deposit address', (WirexCrypto crypto) async {
        _update(() => _deposit = null);
        final WirexDepositAddress deposit = await crypto.depositAddress(family: _family);
        _update(() => _deposit = deposit);
        return null;
      });

  /// The decimals a quote's amounts show at: 6 to another network, the pay token's on the own chain.
  int? _quoteDecimals(WirexSendQuote quote) {
    if (quote.rail != WirexSendRail.transfer) return _sendDecimals;
    for (final WirexCryptoBalance row in _balances ?? const <WirexCryptoBalance>[]) {
      if (row.token.toLowerCase() == quote.payToken.toLowerCase()) return row.decimals;
    }
    return null;
  }

  static String _shown(String units, int? decimals) =>
      decimals == null ? '$units (base units)' : formatUnits(units, decimals);

  static String _short(String hash) =>
      hash.length > 14 ? '${hash.substring(0, 8)}…${hash.substring(hash.length - 4)}' : hash;

  static String _unixTime(String seconds) {
    final int? value = int.tryParse(seconds);
    if (value == null) return seconds;
    final DateTime local = DateTime.fromMillisecondsSinceEpoch(value * 1000).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final LiveConfig config = LiveConfig.instance;
    final String chainId = config.credential('chainId');
    final WirexSendQuote? quote = _quote;
    final WirexSendResult? result = _result;
    final String? amountRefusal = _amountRefusal;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Environment ${config.environment} · chain ${chainId.isEmpty ? '—' : chainId}',
            style: const TextStyle(fontSize: 12)),
        if (config.environment == 'production')
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Production: real money. Every send spends the test user\'s own funds. '
                'The tab refuses a send worth more than 10 USD.',
                style: TextStyle(fontSize: 12, color: Colors.orange)),
          ),
        _panel('Balances', <Widget>[_button('Read balances', _readBalances)], body: <Widget>[
          for (final WirexCryptoBalance row in _balances ?? const <WirexCryptoBalance>[])
            Text('${row.symbol}: ${formatUnits(row.units, row.decimals)} · ${row.token}',
                style: const TextStyle(fontSize: 12)),
        ]),
        _panel(
          'Send',
          <Widget>[
            _button('Get quote', _to.text.trim().isEmpty || _amount.text.trim().isEmpty || amountRefusal != null ? null : _getQuote),
          ],
          inputs: <Widget>[
            _dropdown('Network', _networks, _network, (String v) => _update(() => _network = v)),
            TextField(
              controller: _token,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => _update(() {}),
              decoration: const InputDecoration(labelText: 'Token', isDense: true),
            ),
            TextField(
              controller: _to,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => _update(() {}),
              decoration: const InputDecoration(labelText: 'Recipient, an address on that network', isDense: true),
            ),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _update(() {}),
              decoration: const InputDecoration(labelText: 'Amount, what arrives', isDense: true),
            ),
            _dropdown('Provider (optional)', _providers, _provider, (String v) => _update(() => _provider = v),
                display: (String v) => v.isEmpty ? 'any' : v),
            if (amountRefusal != null)
              Text(amountRefusal, style: const TextStyle(fontSize: 12, color: Colors.red)),
          ],
          body: <Widget>[
            if (quote != null) _quoteLines(quote),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              _button('Send', quote == null ? null : _send),
              if (result != null && result.rail != WirexSendRail.transfer) _button('Check delivery', _checkDelivery),
            ]),
            if (_steps.isNotEmpty) _stepsTable(),
            if (result != null)
              Text('sent by ${result.rail.wire}'
                  '${result.transactionHash == null ? ' · the execute ran before' : ' · ${_short(result.transactionHash!)}'}',
                  style: const TextStyle(fontSize: 12)),
            if (_delivery != null) Text(_deliveryLine(_delivery!), style: const TextStyle(fontSize: 12)),
          ],
        ),
        _panel('Pending', <Widget>[_button('Load pending', _loadPending)], body: <Widget>[
          for (final WirexPendingSend row in _pending ?? const <WirexPendingSend>[]) _pendingRow(row),
        ]),
        _panel(
          'Deposit',
          <Widget>[_button('Get deposit address', _getDeposit)],
          inputs: <Widget>[_dropdown('Family', _families, _family, (String v) => _update(() => _family = v))],
          body: <Widget>[if (_deposit != null) ..._depositLines(_deposit!)],
        ),
      ],
    );
  }

  Widget _quoteLines(WirexSendQuote quote) {
    final int? decimals = _quoteDecimals(quote);
    return SelectableText(
      <String>[
        'sendId ${quote.sendId}',
        'rail ${quote.rail.wire}',
        'to ${quote.to} on ${quote.network}',
        'arrives ${_shown(quote.amount, decimals)} ${quote.token}',
        'fee ${_shown(quote.fee, decimals)}',
        'leaves ${_shown(quote.payUnits, decimals)}${quote.unwrap == null ? '' : ' (unwrapped first)'}',
        'validUntil ${_unixTime(quote.validUntil)}',
      ].join('\n'),
      style: const TextStyle(fontSize: 12),
    );
  }

  Widget _stepsTable() => Table(
        columnWidths: const <int, TableColumnWidth>{0: IntrinsicColumnWidth(), 1: IntrinsicColumnWidth()},
        children: <TableRow>[
          const TableRow(children: <Widget>[
            _Cell('step', bold: true),
            _Cell('state', bold: true),
            _Cell('reason · transaction', bold: true),
          ]),
          for (final WirexCryptoStepEvent event in _steps)
            TableRow(children: <Widget>[
              _Cell(event.step.wire),
              _Cell(event.state.wire),
              _Cell(<String>[?event.reason, if (event.transactionHash != null) _short(event.transactionHash!)].join(' · ')),
            ]),
        ],
      );

  static String _deliveryLine(WirexSendStatus status) {
    final WirexSendRefund? refund = status.refund;
    return <String>[
      status.state.wire,
      ?status.vendorState,
      if (status.destinationTxHash != null) _short(status.destinationTxHash!),
      if (refund != null) 'refund ${<String>[?refund.amount, ?refund.token, ?refund.network].join(' ')}',
    ].join(' · ');
  }

  Widget _pendingRow(WirexPendingSend row) {
    final WirexSendQuote? held = _heldFor(row);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: <Widget>[
        Expanded(
          child: Text(
            '${formatUnits(row.units, row.decimals)} · ${row.token}\n'
            'valid ${row.validAfter} to ${row.validBefore}'
            '${held == null ? '\nno quote held for this send' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        _button('Resume', held == null ? null : () => _resume(held)),
      ]),
    );
  }

  List<Widget> _depositLines(WirexDepositAddress deposit) => <Widget>[
        SelectableText('${deposit.family} · ${deposit.address}', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Table(children: <TableRow>[
          const TableRow(children: <Widget>[
            _Cell('network', bold: true),
            _Cell('token', bold: true),
            _Cell('min USD', bold: true),
            _Cell('max USD', bold: true),
          ]),
          for (final WirexDepositNetwork entry in deposit.networks)
            for (final WirexDepositToken item in entry.tokens)
              TableRow(children: <Widget>[_Cell(entry.network), _Cell(item.symbol), _Cell(item.minUsd), _Cell(item.maxUsd)]),
        ]),
      ];

  Widget _panel(String title, List<Widget> buttons,
          {List<Widget> inputs = const <Widget>[], List<Widget> body = const <Widget>[]}) =>
      Card(
        margin: const EdgeInsets.only(top: 16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final Widget input in inputs) Padding(padding: const EdgeInsets.only(bottom: 8), child: input),
              Wrap(spacing: 8, runSpacing: 8, children: buttons),
              if (_status[title] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SelectableText(_status[title]!, style: const TextStyle(fontSize: 12)),
                ),
              if (body.isNotEmpty) const SizedBox(height: 8),
              ...body,
            ],
          ),
        ),
      );

  /// Disabled while any call runs, or when [onPressed] is null.
  Widget _button(String label, VoidCallback? onPressed) =>
      FilledButton(onPressed: _busy ? null : onPressed, child: Text(label));

  Widget _dropdown(String label, List<String> values, String selected, ValueChanged<String> onChanged,
          {String Function(String)? display}) =>
      DropdownButtonFormField<String>(
        initialValue: selected,
        isDense: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: <DropdownMenuItem<String>>[
          for (final String value in values) DropdownMenuItem<String>(value: value, child: Text(display?.call(value) ?? value)),
        ],
        onChanged: _busy ? null : (String? value) => value == null ? null : onChanged(value),
      );
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.bold = false});
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10, bottom: 4),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w700 : null)),
      );
}
