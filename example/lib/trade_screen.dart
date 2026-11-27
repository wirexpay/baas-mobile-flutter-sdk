/// The Trade tab: a stock or coin trade end to end, signed by the test user's key on the Config tab.
/// Its panels, buttons and wording match the iOS, Android and React Native examples.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

import 'diag_log.dart';
import 'live_config.dart';
import 'test_signer.dart';
import 'trade_error_line.dart';
import 'trade_guard.dart';
import 'trade_session.dart';

class TradeScreen extends StatefulWidget {
  const TradeScreen({super.key, this.session});

  /// The trade source; a test passes a fake. Null builds the real one.
  final TradeSession? session;

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  late final TradeSession _session = widget.session ?? TradeSession();
  final TextEditingController _symbol = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  WirexTradeMarket _market = WirexTradeMarket.stock;
  WirexTradeSide _side = WirexTradeSide.buy;

  bool _busy = false;
  final Map<String, String> _status = <String, String>{};

  WirexTradeAccount? _account;
  List<WirexTradeCatalogItem> _catalog = const <WirexTradeCatalogItem>[];
  WirexTradeQuote? _quote;
  String? _quoteRefusal;
  final Map<WirexTradeStep, WirexTradeStepEvent> _steps = <WirexTradeStep, WirexTradeStepEvent>{};
  WirexTradeOrder? _ended;
  List<WirexTradeOpenOrder> _open = const <WirexTradeOpenOrder>[];

  @override
  void initState() {
    super.initState();
    LiveConfig.instance.credentialsRevision.addListener(_configChanged);
  }

  @override
  void dispose() {
    LiveConfig.instance.credentialsRevision.removeListener(_configChanged);
    unawaited(_session.dispose());
    _symbol.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _configChanged() {
    if (mounted) setState(() {});
  }

  String get _environment => LiveConfig.instance.environment;

  void _update(VoidCallback change) {
    if (mounted) setState(change);
  }

  /// Runs one call with every button disabled, and shows its failure as one line in [panel].
  Future<void> _run(String panel, String button, Future<String?> Function(WirexTrade trade) call) async {
    DiagLog.instance.tap('Trade: $button tapped');
    _update(() {
      _busy = true;
      _status[panel] = '$button…';
    });
    String? outcome;
    try {
      final WirexTrade trade = await _session.current();
      // The login's own reason first: through the SDK it would read only as token_unavailable.
      await _session.login.accessToken();
      outcome = await call(trade);
    } catch (error) {
      outcome = tradeErrorLine(error);
      DiagLog.instance.err('Trade: $button failed: ${error is WirexTradeError ? error.reason : error.runtimeType}');
    }
    _update(() {
      _busy = false;
      _status[panel] = outcome ?? '$button: done';
    });
  }

  void _onStep(WirexTradeStepEvent event) {
    DiagLog.instance.sdk('Trade step ${event.step.wire} ${event.state.wire}'
        '${event.status == null ? '' : ' status ${event.status}'}${event.reason == null ? '' : ' reason ${event.reason}'}');
    _update(() => _steps[event.step] = event);
  }

  Future<void> _readAccount() => _run('Account', 'Read account', (WirexTrade trade) async {
        final WirexTradeAccount account = await trade.account();
        _update(() => _account = account);
        return null;
      });

  Future<void> _setUpAccount() => _run('Account', 'Set up account', (WirexTrade trade) async {
        _update(_steps.clear);
        final WirexTradeAccount account = await trade.setUpAccount(onStep: _onStep);
        _update(() => _account = account);
        return null;
      });

  Future<void> _loadCatalog() => _run('Catalog', 'Load catalog', (WirexTrade trade) async {
        final List<WirexTradeCatalogItem> catalog = await trade.catalog();
        _update(() => _catalog = catalog);
        return '${catalog.length} symbols';
      });

  Future<void> _getQuote() async {
    final String symbol = _symbol.text.trim();
    // The typed decimal text, as the engine takes it: USD on a buy, the token on a sale.
    final String amount = _amount.text.trim();
    // SECURITY: cap point 1, the typed buy amount, before anything is asked for.
    final String? refusal = refuseBuyAmount(environment: _environment, side: _side.wire, amount: amount);
    String? problem = refusal;
    if (problem == null && symbol.isEmpty) problem = 'set a symbol';
    if (problem == null && amount.isEmpty) problem = 'set an amount';
    if (problem != null) {
      DiagLog.instance.tap('Trade: Get quote tapped');
      if (refusal != null) DiagLog.instance.app('Trade: quote refused by the cap');
      _update(() => _status['Quote'] = problem!);
      return;
    }
    await _run('Quote', 'Get quote', (WirexTrade trade) async {
      _update(() {
        _quote = null;
        _quoteRefusal = null;
      });
      final WirexTradeQuote quote = await trade.quote(market: _market, side: _side, symbol: symbol, amount: amount);
      // SECURITY: cap point 2, the quote's worth; a refused quote leaves Execute disabled.
      final String? capped = refuseWorth(environment: _environment, cents: quoteWorthCents(quote));
      _update(() {
        _quote = quote;
        _quoteRefusal = capped;
      });
      if (capped != null) DiagLog.instance.app('Trade: quote refused by the cap');
      return capped;
    });
  }

  Future<void> _execute() async {
    final WirexTradeQuote? quote = _quote;
    if (quote == null) return;
    // SECURITY: cap point 3, the same check again at Execute.
    final String? capped = refuseWorth(environment: _environment, cents: quoteWorthCents(quote));
    if (capped != null) {
      DiagLog.instance.app('Trade: execute refused by the cap');
      _update(() => _status['Trade'] = capped);
      return;
    }
    await _run('Trade', 'Execute', (WirexTrade trade) async {
      _update(() {
        _steps.clear();
        _ended = null;
      });
      final WirexTradeOrder order = await trade.execute(quote, onStep: _onStep);
      _update(() => _ended = order);
      DiagLog.instance.sdk('Trade: order ended ${order.status}');
      return 'order ${order.status}';
    });
  }

  Future<void> _loadOpenOrders() => _run('Open orders', 'Load open orders', (WirexTrade trade) async {
        final List<WirexTradeOpenOrder> open = await trade.openOrders();
        _update(() => _open = open);
        return '${open.length} open';
      });

  Future<void> _resume(WirexTradeOpenOrder order) async {
    // SECURITY: cap point 4, the open order's own terms, before Resume.
    final String? capped = refuseWorth(environment: _environment, cents: orderWorthCents(order));
    if (capped != null) {
      DiagLog.instance.app('Trade: resume refused by the cap');
      _update(() => _status['Open orders'] = capped);
      return;
    }
    final WirexTradeQuote? quote = _quote?.orderId == order.orderId ? _quote : null;
    await _run('Open orders', 'Resume', (WirexTrade trade) async {
      _update(() {
        _steps.clear();
        _ended = null;
      });
      final WirexTradeOrder ended = await trade.resume(order.orderId, quote: quote, onStep: _onStep);
      _update(() => _ended = ended);
      DiagLog.instance.sdk('Trade: order ended ${ended.status}');
      return 'order ${ended.status}';
    });
  }

  String _signerLine() {
    final String key = LiveConfig.instance.credential('ownerKey');
    if (key.isEmpty) return 'Signer: no ownerKey — set it on the Config tab or in ${LiveConfig.e2eFileName}';
    final String source = LiveConfig.instance.fromFile('ownerKey') ? LiveConfig.e2eFileName : 'the Config tab';
    if (key != _signerKey) {
      _signerKey = key;
      try {
        _signerAddress = TestSigner.fromHex(key).address;
      } on FormatException catch (error) {
        _signerAddress = error.message;
      }
    }
    return 'Signer: $_signerAddress, from $source';
  }

  String? _signerKey;
  String _signerAddress = '';

  @override
  Widget build(BuildContext context) {
    final LiveConfig config = LiveConfig.instance;
    final String chainId = config.credential('chainId');
    final String companyId = config.credential('companyId');
    final WirexTradeQuote? quote = _quote;
    final WirexTradeOrder? ended = _ended;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Environment ${config.environment} · chain ${chainId.isEmpty ? '—' : chainId} · '
          'company ${companyId.isEmpty ? '—' : companyId}',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(_signerLine(), style: const TextStyle(fontSize: 12)),
        if (config.environment == 'production')
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Production: real money. The tab refuses a trade worth more than $productionCapUsd USD.',
                style: TextStyle(fontSize: 12, color: Colors.orange)),
          ),
        _panel(
          'Account',
          "The main account's chain, both addresses, and whether the investment account is ready",
          <Widget>[
            _button('Read account', _readAccount),
            _button('Set up account', _setUpAccount),
          ],
          body: _accountBody(),
        ),
        _panel(
          'Catalog',
          'Stock and coin symbols. A company with its own tokens lists no coins.',
          <Widget>[_button('Load catalog', _loadCatalog)],
          body: <Widget>[
            if (_catalog.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                for (final WirexTradeCatalogItem item in _catalog)
                  ActionChip(
                    label: Text('${item.symbol} · ${item.market.wire}'),
                    onPressed: _busy
                        ? null
                        : () {
                            DiagLog.instance.tap('Trade: catalog symbol picked');
                            _update(() {
                              _symbol.text = item.symbol;
                              _market = item.market;
                            });
                          },
                  ),
              ]),
          ],
        ),
        _panel(
          'Quote',
          'Market, side, symbol and amount go in. Amounts, fee and expiry come back.',
          <Widget>[_button('Get quote', _getQuote)],
          inputs: <Widget>[
            _choice<WirexTradeMarket>(WirexTradeMarket.values, _market, (WirexTradeMarket v) => _update(() => _market = v)),
            const SizedBox(height: 8),
            _choice<WirexTradeSide>(WirexTradeSide.values, _side, (WirexTradeSide v) => _update(() => _side = v)),
            const SizedBox(height: 8),
            TextField(
              controller: _symbol,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Symbol', isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _side == WirexTradeSide.buy ? 'Amount, USD' : 'Amount, in the token',
                isDense: true,
              ),
            ),
          ],
          body: quote == null ? const <Widget>[] : _quoteBody(quote),
        ),
        _panel(
          'Trade',
          'Every step and its status, until the order ends',
          <Widget>[_button('Execute', quote == null || _quoteRefusal != null ? null : _execute)],
          body: <Widget>[
            if (_steps.isNotEmpty) _stepsTable(),
            if (ended != null) ..._orderLines(ended),
          ],
        ),
        _panel(
          'Open orders',
          'A trade carries on after the app is killed',
          <Widget>[_button('Load open orders', _loadOpenOrders)],
          body: <Widget>[
            for (final WirexTradeOpenOrder order in _open)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: <Widget>[
                  Expanded(
                    child: Text(
                      '${order.side.wire} ${order.market.wire} · ${order.status} · next ${order.nextStep?.wire ?? '—'}\n'
                      'worth ${formatCents(orderWorthCents(order))} · '
                      'created ${order.createdAt ?? '—'} · updated ${order.updatedAt ?? '—'}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  _button('Resume', () => _resume(order)),
                ]),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _accountBody() {
    final WirexTradeAccount? account = _account;
    if (account == null) return const <Widget>[];
    final WirexTradeMoney? cash = account.cash;
    return <Widget>[
      _lines(<String>[
        'Chain ${account.chainId}',
        'Main account ${account.mainAccount}',
        'Investment account ${account.investmentAccount ?? '—'}',
        'Set up: ${account.isSetUp ? 'yes' : 'no'}',
        'Cash ${cash == null ? '—' : '${formatUnits(cash.units, cash.decimals)} USDC'}',
        for (final WirexTradeHolding holding in account.holdings)
          '${holding.symbol}: ${holding.sharesShown ?? formatUnits(holding.units, holding.decimals)}'
              ' · ${formatCents(holding.valueCents == null ? null : BigInt.tryParse(holding.valueCents!))}',
      ]),
    ];
  }

  List<Widget> _quoteBody(WirexTradeQuote quote) {
    // A stock's shares are at the stock token's decimals: what a buy gets, or what a sale spends.
    final int shareDecimals = quote.side == WirexTradeSide.buy ? quote.tokenOutDecimals : quote.tokenInDecimals;
    return <Widget>[
      _lines(<String>[
        'Order ${quote.orderId} · ${quote.side.wire} ${quote.symbol} · ${quote.executionMethod}',
        'In ${formatUnits(quote.amountIn, quote.tokenInDecimals)}',
        'Out about ${formatUnits(quote.estimatedAmountOut, quote.tokenOutDecimals)}, '
            'at least ${formatUnits(quote.minimumAmountOut, quote.tokenOutDecimals)}',
        if (quote.estimatedShares != null) 'Shares about ${formatUnits(quote.estimatedShares!, shareDecimals)}',
        'Fee ${quote.feeAmount} (base units)'
            '${quote.transferFee == null ? '' : ' · transfer fee ${formatUnits(quote.transferFee!, 6)} USDC'}',
        'Worth ${formatCents(quoteWorthCents(quote))}',
        'Valid until ${quote.validUntil} · sign by ${quote.signBy}',
      ]),
      if (_quoteRefusal != null) Text(_quoteRefusal!, style: const TextStyle(fontSize: 12, color: Colors.red)),
    ];
  }

  Widget _stepsTable() => Table(
        columnWidths: const <int, TableColumnWidth>{0: IntrinsicColumnWidth(), 1: IntrinsicColumnWidth()},
        children: <TableRow>[
          const TableRow(children: <Widget>[
            _Cell('step', bold: true),
            _Cell('state', bold: true),
            _Cell('status · reason · tx', bold: true),
          ]),
          for (final WirexTradeStepEvent event in _steps.values)
            TableRow(children: <Widget>[
              _Cell(event.step.wire),
              _Cell(event.state.wire),
              _Cell(<String>[
                ?event.status,
                ?event.reason,
                if (event.transactionHash != null) _short(event.transactionHash!),
              ].join(' · ')),
            ]),
        ],
      );

  List<Widget> _orderLines(WirexTradeOrder order) => <Widget>[
        const SizedBox(height: 8),
        _lines(<String>[
          'Order ${order.orderId}: ${order.status}${order.statusReason == null ? '' : ' (${order.statusReason})'}',
          'Out ${formatUnits(order.amountOut, order.tokenOutDecimals)}${order.shares == null ? '' : ' · shares ${order.shares}'}',
          'Refunded ${formatUnits(order.refundedAmount, order.tokenInDecimals)}',
          'Tx ${order.transactionHash == null ? '—' : _short(order.transactionHash!)}',
          'Created ${order.createdAt ?? '—'} · updated ${order.updatedAt ?? '—'}',
        ]),
      ];

  static String _short(String hash) =>
      hash.length > 14 ? '${hash.substring(0, 8)}…${hash.substring(hash.length - 4)}' : hash;

  Widget _lines(List<String> lines) => SelectableText(lines.join('\n'), style: const TextStyle(fontSize: 12));

  Widget _panel(
    String title,
    String hint,
    List<Widget> buttons, {
    List<Widget> inputs = const <Widget>[],
    List<Widget> body = const <Widget>[],
  }) =>
      Card(
        margin: const EdgeInsets.only(top: 16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(hint, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              ...inputs,
              if (inputs.isNotEmpty) const SizedBox(height: 10),
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

  Widget _choice<T extends Enum>(List<T> values, T selected, ValueChanged<T> onChanged) => SegmentedButton<T>(
        segments: <ButtonSegment<T>>[
          for (final T value in values) ButtonSegment<T>(value: value, label: Text(value.name)),
        ],
        selected: <T>{selected},
        onSelectionChanged: _busy ? null : (Set<T> picked) => onChanged(picked.first),
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
