/// The Config (debug) tab: a per-field form over [LiveConfig], so QA types every integration
/// parameter and credential straight into the running build — no rebuild, no source edit, no pasted
/// JSON.
///
/// Mirrors the React Native example's Config screen: the same field contract (PARTNER-CONFIG.md), the
/// same two tiers (non-secret integration parameters, memory-only secrets) and the same dark palette.
/// Every surface reads [LiveConfig] live; a change to a value a session captured (the card id) rebuilds
/// that session through [LiveConfig.credentialsRevision].
library;

import 'package:flutter/material.dart';

import 'live_config.dart';

/// The React Native example's palette, so the Config tab reads as the same product on every platform.
class _P {
  static const bg = Color(0xFF0E0E1A);
  static const surface = Color(0xFF17172A);
  static const surfaceAlt = Color(0xFF1F1F38);
  static const border = Color(0xFF2A2A47);
  static const accent = Color(0xFF5753EA);
  static const pink = Color(0xFFFF407F);
  static const pinkDim = Color(0x22FF407F);
  static const teal = Color(0xFF57C9F9);
  static const text = Color(0xFFFFFFFF);
  static const textDim = Color(0xFFA0A0C0);
  static const textFaint = Color(0xFF6D6D8A);
}

class _FieldSpec {
  const _FieldSpec(this.key, this.label, this.hint, {this.secure = false});
  final String key;
  final String label;
  final String? hint;
  final bool secure;
}

const _integration = <_FieldSpec>[
  _FieldSpec('chainId', 'Chain ID', 'X-Chain-Id — Wirex assigns per integration'),
  _FieldSpec('email', 'User email', 'X-User-Email'),
  _FieldSpec('wallet', 'User wallet', 'X-User-Wallet (EOA)'),
  _FieldSpec('cardId', 'Card ID', 'the card Reveal / Collect act on'),
  _FieldSpec('cardholderName', 'Cardholder name', null),
  _FieldSpec('baasApiUrl', 'BaaS API URL', 'for the Wallet “Fetch estimate” helper'),
];
const _secrets = <_FieldSpec>[
  _FieldSpec('bearer', 'Bearer token', 'getAccessToken — Wirex bearer for the user', secure: true),
  _FieldSpec('actionToken', 'Step-up action token', 'getActionToken — card data / PIN', secure: true),
];

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final Map<String, TextEditingController> _controllers = <String, TextEditingController>{};
  final Map<String, FocusNode> _focus = <String, FocusNode>{};
  // The same `wirexqa://seed?d=…` link the app opens as a deep link, pasted instead — for a device
  // where opening the link is awkward (a chat that strips the scheme, a locked-down browser).
  final TextEditingController _seed = TextEditingController();
  String? _seedStatus;
  bool _seedOk = false;

  @override
  void initState() {
    super.initState();
    for (final spec in <_FieldSpec>[..._integration, ..._secrets]) {
      _controllers[spec.key] = TextEditingController(text: LiveConfig.instance.credential(spec.key));
      final node = FocusNode();
      node.addListener(() {
        // On blur: post the change, so a screen that captured the value (the card id) rebuilds once.
        if (!node.hasFocus) {
          LiveConfig.instance.setCredential(spec.key, _controllers[spec.key]!.text);
          setState(() {});
        }
      });
      _focus[spec.key] = node;
    }
    // A seed deep link (or any other code path) can change a value while this tab is built. Pull the
    // new values into the fields when that happens, skipping the one being edited so typing is not cut.
    LiveConfig.instance.credentialsRevision.addListener(_syncControllers);
  }

  void _syncControllers() {
    if (!mounted) return;
    for (final entry in _controllers.entries) {
      if (_focus[entry.key]?.hasFocus ?? false) continue;
      final String value = LiveConfig.instance.credential(entry.key);
      if (entry.value.text != value) entry.value.text = value;
    }
    setState(() {});
  }

  @override
  void dispose() {
    LiveConfig.instance.credentialsRevision.removeListener(_syncControllers);
    for (final c in _controllers.values) {
      c.dispose();
    }
    _seed.dispose();
    for (final n in _focus.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _applySeed() {
    final int? applied = LiveConfig.instance.applySeedLinkText(_seed.text);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _seedOk = applied != null;
      _seedStatus = applied == null ? 'Not a wirexqa://seed link' : 'Applied $applied value${applied == 1 ? '' : 's'}';
      if (applied != null) _seed.clear();
    });
  }

  void _resetAll() {
    LiveConfig.instance.resetCredentials();
    for (final c in _controllers.values) {
      c.clear();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final environment = LiveConfig.instance.environment;
    return Container(
      color: _P.bg,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Configuration',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _P.text)),
            const SizedBox(height: 6),
            const Text(
              "Type a partner's parameters here; every screen reads them live. Secrets stay in memory only.",
              style: TextStyle(fontSize: 13, color: _P.textDim),
            ),
            _section('Seed link'),
            _card(<Widget>[
              TextField(
                controller: _seed,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _applySeed(),
                style: const TextStyle(fontSize: 15, color: _P.text),
                decoration: _decoration('wirexqa://seed?d=…'),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _pill('Apply', _P.text, _P.accent, _P.accent, _applySeed),
              ),
              const SizedBox(height: 8),
              Text(
                _seedStatus ??
                    'Paste the link the QA kit prints (the same one the app opens as a deep link); Apply fills every field below.',
                style: TextStyle(
                    fontSize: 12, color: _seedStatus == null ? _P.textFaint : (_seedOk ? _P.teal : _P.pink)),
              ),
            ]),
            _section('Environment'),
            Row(
              children: <Widget>[
                _chip('test', environment == 'test'),
                const SizedBox(width: 10),
                _chip('production', environment == 'production'),
              ],
            ),
            _section('Integration parameters'),
            _group(_integration),
            _section('Secrets · memory only'),
            _group(_secrets),
            _section('Screen capture'),
            _card(<Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Screen-capture protection (FLAG_SECURE)',
                    style: TextStyle(color: _P.text, fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text(
                  'On — card data is HIDDEN from screenshots / screen-recording on Reveal & Collect '
                  '(the secure default).\n'
                  'Off — data is VISIBLE so QA can capture it for a test.',
                  style: TextStyle(color: _P.textDim, fontSize: 11),
                ),
                value: !LiveConfig.instance.disableScreenProtection,
                onChanged: (bool protect) {
                  LiveConfig.instance.setCredential('disableScreenProtection', protect ? 'false' : 'true');
                  setState(() {});
                },
              ),
            ]),
            _section('Credentials status'),
            _card(<Widget>[
              Text(
                LiveConfig.instance.credentialsStatus(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: _P.textDim),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: _pill('Refresh status', _P.teal, _P.surfaceAlt, _P.border, () => setState(() {})),
              ),
            ]),
            const SizedBox(height: 26),
            Align(
              alignment: Alignment.centerLeft,
              child: _pill('Reset all', _P.pink, _P.pinkDim, _P.pink, _resetAll),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: _P.textFaint, letterSpacing: 0.8),
        ),
      );

  Widget _chip(String name, bool on) => GestureDetector(
        onTap: () {
          LiveConfig.instance.setCredential('environment', name);
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: on ? _P.accent : _P.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? _P.accent : _P.border),
          ),
          child: Text(
            name,
            style: TextStyle(fontWeight: FontWeight.w700, color: on ? _P.text : _P.textDim),
          ),
        ),
      );

  Widget _group(List<_FieldSpec> specs) => _card(<Widget>[
        for (int i = 0; i < specs.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 12),
          _field(specs[i]),
        ],
      ]);

  Widget _field(_FieldSpec spec) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(spec.label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _P.text)),
          if (spec.hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(spec.hint!, style: const TextStyle(fontSize: 12, color: _P.textFaint)),
            ),
          const SizedBox(height: 4),
          TextField(
            controller: _controllers[spec.key],
            focusNode: _focus[spec.key],
            obscureText: spec.secure,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontSize: 15, color: _P.text),
            // Mid-edit: keep the store live without posting, so screens do not rebuild per keystroke.
            onChanged: (value) => LiveConfig.instance.setCredential(spec.key, value, notify: false),
            decoration: _decoration(spec.secure ? 'paste…' : ''),
          ),
        ],
      );

  InputDecoration _decoration(String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(color: _P.textFaint),
        filled: true,
        fillColor: _P.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _P.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _P.accent),
        ),
      );

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _P.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _P.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _pill(String text, Color textColor, Color fill, Color stroke, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: stroke),
          ),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: textColor)),
        ),
      );
}
