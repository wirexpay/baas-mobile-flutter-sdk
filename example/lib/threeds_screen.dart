import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

import 'live_config.dart';

/// The 3DS step-up, end to end, with the orchestrator URL pasted in.
///
/// A real host takes `three_ds_state.url` from its own `POST /v1/cards/topup/execute` reply. This
/// shows the SDK's part: the origin refusal, the states, the challenge, and the outcome.
///
/// A URL passed as `--dart-define=WIREX_THREEDS_URL=…` fills the field and starts once, for scripted
/// runs.
class ThreeDSScreen extends StatefulWidget {
  const ThreeDSScreen({super.key});

  @override
  State<ThreeDSScreen> createState() => _ThreeDSScreenState();
}

class _ThreeDSScreenState extends State<ThreeDSScreen> {
  static const _launchUrl = String.fromEnvironment('WIREX_THREEDS_URL');

  final _url = TextEditingController(text: _launchUrl);
  final FocusNode _urlFocus = FocusNode();
  Future<void>? _configured;
  String? _configuredKey;
  WirexThreeDSSession? _session;
  String _status = 'no session';
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    if (_launchUrl.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    // A seed link (deep link or the Config tab's field) may carry `threeDsUrl`: prefill the field.
    _syncFromConfig();
    LiveConfig.instance.credentialsRevision.addListener(_syncFromConfig);
  }

  void _syncFromConfig() {
    final String seeded = LiveConfig.instance.credential('threeDsUrl');
    if (seeded.isNotEmpty && _url.text != seeded && !_urlFocus.hasFocus) _url.text = seeded;
  }

  @override
  void dispose() {
    LiveConfig.instance.credentialsRevision.removeListener(_syncFromConfig);
    _urlFocus.dispose();
    _url.dispose();
    unawaited(_session?.destroy());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      // `testMode` and the Screen capture switch are read at configure time: reconfigure when the
      // Config tab changed either.
      final bool testMode = LiveConfig.instance.isTestMode;
      final bool disableProtection = LiveConfig.instance.disableScreenProtection;
      final String key = '$testMode|$disableProtection';
      if (_configured == null || _configuredKey != key) {
        _configuredKey = key;
        _configured = WirexThreeDS.instance.configure(
          testMode: testMode,
          logging: 'info',
          // DEV/TEST ONLY — the Config tab's Screen capture switch, the same one Reveal and Collect
          // read. Off = the challenge is visible to screenshots and recording (device clouds).
          dangerouslyDisableScreenProtection: disableProtection,
        );
      }
      await _configured;
      final previous = _session;
      final session = await WirexThreeDS.instance.createSession(_url.text);
      session.onSnapshot(_render);
      _render(session.snapshot);
      setState(() => _session = session);
      await previous?.destroy();
      // After the frame that mounts the view with this session.
      WidgetsBinding.instance.addPostFrameCallback((_) => session.start());
    } on PlatformException catch (error) {
      setState(() => _status = 'could not start: ${error.message}');
    }
  }

  void _render(WirexThreeDSSnapshot snapshot) {
    final lines = <String>['state: ${snapshot.state.wireName}'];
    final outcome = snapshot.outcome;
    if (outcome != null) {
      lines.add('status: ${outcome.status.wireStatus}');
      final error = outcome.error;
      if (error != null) {
        lines.add('code: ${error.code.wireCode}');
        lines.add('retryable: ${error.retryable}');
        if (error.message != null) lines.add('message: ${error.message}');
      } else {
        // A dismissal carries no error.
        lines.add('error: none');
      }
    }
    if (!mounted) return;
    setState(() {
      // `cancel()` does nothing once the session has settled, so the button is disabled then.
      _settled = snapshot.state == WirexThreeDSState.settled;
      _status = lines.join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    final osIsDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final session = _session;
    return Stack(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _url,
                focusNode: _urlFocus,
                decoration: const InputDecoration(hintText: 'three_ds_state.url'),
                autocorrect: false,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  TextButton(
                    onPressed: _start,
                    child: Text(_settled ? 'Start another' : 'Start step-up'),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: session == null || _settled ? null : session.cancel,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(_status, style: const TextStyle(fontFamily: 'Menlo', fontSize: 12)),
            ],
          ),
        ),
        // THE WHOLE SCREEN, for the session's whole life. Never collapsed or faded; the SDK hides its
        // own content and passes touches through until a challenge needs them.
        if (session != null)
          Positioned.fill(
            child: WirexThreeDSView(
              key: ValueKey<String>(session.sessionId),
              session: session,
              themeMode: LiveConfig.instance.isDarkMode(osIsDark) ? WirexThemeMode.dark : WirexThemeMode.light,
              appearance: LiveConfig.instance.appearanceTokens(osIsDark),
            ),
          ),
      ],
    );
  }
}
