import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

import 'memory_cache.dart';
import 'sample_config.dart';

/// "Can this device pay at all", before any quote exists — what a partner runs at screen build to
/// decide whether to show the wallet row.
class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({required this.config, required this.cache, super.key});

  final WirexWalletConfig config;
  final MemoryAvailabilityCache cache;

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  late final WirexWalletAvailabilityChecker _checker;
  final List<String> _log = <String>[];
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    // Pre-quote, so the DEFAULT provider's block: resolve(topup, null). The sample block stands in
    // for the app config's `topup` value here; on Android its (absent) WebView / Play Services
    // floors are what the probe would check first.
    final TopupParse parsed = parseTopup(sampleTopupJson);
    _checker = WirexWalletAvailabilityChecker(
      config: widget.config,
      providerConfig: parsed is TopupParseOk ? parsed.config : null,
    )
      ..onChange = (WirexWalletAvailability availability) {
        if (!mounted) return;
        setState(() => _log.add(_stamp(
            'onChange — applePay=${availability.applePay} googlePay=${availability.googlePay}')));
      }
      ..onDiagnostic = (WirexWalletDiagnostic diagnostic) {
        if (!mounted) return;
        setState(() =>
            _log.add(_stamp('diagnostic — ${diagnostic.kind.wire} ${diagnostic.fields}')));
      };
  }

  @override
  void dispose() {
    _checker.stop();
    super.dispose();
  }

  String _stamp(String line) {
    final DateTime now = DateTime.now();
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(now.hour)}:${pad(now.minute)}:${pad(now.second)}  $line';
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _log.add(_stamp('start() — cache read first, then one fresh probe per process'));
    });
    try {
      await _checker.start();
      if (!mounted) return;
      setState(() => _log.add(_stamp('start() returned — current: ${_checker.current}')));
    } on PlatformException catch (error) {
      if (!mounted) return;
      // `badRequest` here would mean the plugin's two halves disagree — worth seeing verbatim.
      setState(() => _log.add(_stamp('start() threw ${error.code}: ${error.message}')));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    await _checker.stop();
    if (!mounted) return;
    setState(() => _log.add(_stamp('stop() — current keeps its value')));
  }

  @override
  Widget build(BuildContext context) {
    final WirexWalletAvailability? current = _checker.current;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'The probe runs the REAL tokenization path: an offscreen web view with the same '
            'payment-enabled configuration as the checkout. `current` answers instantly from the '
            'cache; `onChange` fires once per session with a real probe answer. On ANDROID the '
            'provider config\'s WebView / Play Services floor verdict shows here too — below a '
            'floor the probe answers googlePay=false without loading anything.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text(
            'current: ${current == null ? '— (no cached answer yet)' : 'applePay=${current.applePay} googlePay=${current.googlePay}'}\n'
            'running: ${_checker.isRunning}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(onPressed: _starting ? null : _start, child: const Text('Start')),
              OutlinedButton(onPressed: _stop, child: const Text('Stop')),
              OutlinedButton(
                onPressed: () {
                  widget.cache.clear();
                  setState(() => _log.add(_stamp(
                      'cache cleared — a fresh install: next process start probes with no cache')));
                },
                child: const Text('Clear cache'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Cache (host storage — this example keeps it in memory)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: widget.cache,
            builder: (BuildContext context, Widget? child) => _Box(
              text: widget.cache.isEmpty
                  ? 'empty — nothing persisted. The SDK only ever writes two booleans, and only '
                      'from a REAL probe answer.'
                  : widget.cache.entries.entries
                      .map((MapEntry<String, String> e) => '${e.key}: ${e.value}')
                      .join('\n'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Log', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          _Box(
            text: _log.isEmpty ? 'nothing yet — press Start' : _log.reversed.join('\n'),
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
      );
}
