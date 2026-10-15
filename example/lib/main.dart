import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

import 'appearance_screen.dart';
import 'checkout_screen.dart';
import 'collect_screen.dart';
import 'config_screen.dart';
import 'example_config.dart';
import 'live_config.dart';
import 'memory_cache.dart';
import 'threeds_screen.dart';

void main() => runApp(const ExampleApp());

/// What a partner application has to implement.
///
/// The entire integration contract for authentication: the SDK never manages a user session, so it
/// asks the host for a token whenever it needs one. A real app returns the token it already holds
/// and runs whatever action-token it uses.
class StubCredentials implements WirexCredentialProvider {
  StubCredentials();

  @override
  String? userEmail = 'cardholder@example.com';

  @override
  String? userWallet = '0x0000000000000000000000000000000000000001';

  /// Set from the UI to exercise the decline path.
  bool declineNextActionToken = false;

  @override
  Future<String> accessToken() async => LiveConfig.instance.credential('bearer');

  @override
  Future<String> actionToken(String scope) async {
    if (declineNextActionToken) {
      declineNextActionToken = false;
      // The SDK abandons the whole reveal rather than prompting again for the remaining fields.
      throw const WirexDeclined();
    }
    // `scope` is `cardData` or `pin`, so the PIN could demand a stronger prompt; the backend has one
    // `GetCardDetails` action type today, so both answer the same way.
    //
    // The token the host holds. A real application returns whatever its own flow produced; this one
    // returns what was pasted. What this deliberately does NOT show is how to obtain one: that is the
    // host's flow against the host's backend, and an example that picked one would be teaching a
    // choice the SDK does not make.
    final supplied = LiveConfig.instance.credential('actionToken');
    if (supplied.isEmpty) {
      // No token. Reported the way a host whose own flow failed would report it.
      throw StateError('no action token supplied');
    }
    return supplied;
  }
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Wirex card SDK — Flutter',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF7C3AED)),
    home: const _Tabs(),
  );
}

/// One tab per package, plus appearance.
///
/// Reveal DISPLAYS a card the user owns; collect CAPTURES one they type; 3DS presents a step-up.
/// No package imports another, and this example takes all three only because it demonstrates them.
class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int _index = 0;
  bool _collectConfigured = false;

  // Wallet is bootstrapped async (it reads its environment name from wirex-wallet-sdk.json and the
  // native SDK resolves it). Until then the Wallet tab shows its status; on failure, the reason.
  final MemoryAvailabilityCache _walletCache = MemoryAvailabilityCache();
  WirexWalletConfig? _walletConfig;
  String? _walletError;

  @override
  void initState() {
    super.initState();
    // Appearance is a tab of its own and applies to BOTH surfaces, so the container listens once and
    // rebuilds them together. The native examples post a notification for the same reason.
    LiveConfig.instance.addListener(_restyle);
    // A value typed on the Config tab: reconfigure collect so the fresh environment / chainId /
    // bearer take effect. Reveal and 3DS observe the same revision for themselves.
    LiveConfig.instance.credentialsRevision.addListener(_configureCollect);
    _configureCollect();
    _bootstrapWallet();
  }

  Future<void> _bootstrapWallet() async {
    final ExampleBootstrap result = await bootstrap(cache: _walletCache);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case ExampleBootstrapReady(:final config):
          _walletConfig = config;
        case ExampleBootstrapFailed(:final reason):
          _walletError = reason;
      }
    });
  }

  @override
  void dispose() {
    LiveConfig.instance.removeListener(_restyle);
    LiveConfig.instance.credentialsRevision.removeListener(_configureCollect);
    _walletCache.dispose();
    super.dispose();
  }

  void _restyle() {
    setState(() {});
  }

  /// The Wallet tab: the hosted Apple Pay / Google Pay checkout once the environment resolves, or the
  /// reason it could not (rendered, never a spinner forever).
  Widget _walletTab() {
    final config = _walletConfig;
    if (config != null) return CheckoutScreen(config: config);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
          _walletError ?? 'Preparing wallet…',
          style: TextStyle(fontSize: 13, color: _walletError == null ? null : Colors.red),
        ),
      ),
    );
  }

  /// The collect SDK is configured separately from reveal's, because they are separate SDKs that
  /// happen to share a credential source. A partner integrating one calls one of these.
  Future<void> _configureCollect() async {
    try {
      await WirexCollect.configure(
        testMode: LiveConfig.instance.isTestMode,
        chainId: LiveConfig.instance.credential('chainId'),
        // The same token the reveal screen's provider mints. Collect asks only for this one: entering
        // a card the user is holding is not an action token-gated action.
        accessToken: () async => LiveConfig.instance.credential('bearer'),
      );
      if (mounted) setState(() => _collectConfigured = true);
    } on PlatformException {
      if (mounted) setState(() => _collectConfigured = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (_index) {
        0 => 'Config — Flutter',
        1 => 'Reveal — Flutter',
        2 => 'Collect — Flutter',
        3 => '3DS — Flutter',
        4 => 'Wallet — Flutter',
        _ => 'Appearance — Flutter',
      }),
    ),
    body: IndexedStack(
      index: _index,
      // NOT `const`.
      //
      // A const widget is canonicalised: every rebuild of this screen hands `IndexedStack` the
      // SAME instance, Flutter sees `identical(old, new)` and skips the subtree entirely — so
      // `didUpdateWidget` never runs on the rows, no `update` crosses the channel, and the native
      // view keeps the appearance it was built with. Switching tabs looked like a rendering bug and
      // was a rebuild that never happened.
      //
      // `CollectScreen` was never const because it takes a changing parameter, which is exactly why
      // that surface picked up a restyle immediately and this one did not — the difference that
      // located this.
      children: <Widget>[
        const ConfigScreen(),
        RevealScreen(),
        CollectScreen(configured: _collectConfigured),
        ThreeDSScreen(),
        _walletTab(),
        AppearanceScreen(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (int index) {
        setState(() => _index = index);
      },
      destinations: const <NavigationDestination>[
        NavigationDestination(icon: Icon(Icons.tune), label: 'Config'),
        NavigationDestination(icon: Icon(Icons.credit_card), label: 'Reveal'),
        NavigationDestination(icon: Icon(Icons.keyboard), label: 'Collect'),
        NavigationDestination(icon: Icon(Icons.verified_user), label: '3DS'),
        NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
        NavigationDestination(icon: Icon(Icons.palette), label: 'Appearance'),
      ],
    ),
  );
}

class RevealScreen extends StatefulWidget {
  const RevealScreen({super.key});

  @override
  State<RevealScreen> createState() => _RevealScreenState();
}

class _RevealScreenState extends State<RevealScreen> {
  /// What this screen hands the row, logged at the moment it hands it.
  WirexRevealAppearance _loggedAppearance(bool osIsDark, WirexRevealField field) {
    final appearance = LiveConfig.instance.appearance(osIsDark);
    return appearance;
  }


  /// `cardholderName` is not sensitive and is not fetched — the host already has it.
  static const List<WirexRevealField> fields = <WirexRevealField>[
    WirexRevealField.cardholderName,
    WirexRevealField.pan,
    WirexRevealField.expiry,
    WirexRevealField.cvv,
    WirexRevealField.pin,
  ];

  StubCredentials? _credentials;

  WirexRevealSession? _session;
  /// Null until the session has published one.
  ///
  /// A snapshot is READ, not built: the SDK gives no public constructor, deliberately, because a
  /// host that can build one can hand its own UI a state the session never reported. "Nothing yet"
  /// is the host's own concept and belongs here, as a null, rather than as a fabricated idle
  /// snapshot the SDK would have to allow everyone to make.
  WirexRevealSnapshot? _snapshot;

  /// PER FIELD, not one flag for the screen.
  ///
  /// A single flag made every row share one fate: when one row masked itself, its `onMaskedChange`
  /// flipped the flag and the prop masked the other three, which nothing had happened to. Coming
  /// back to the tab, the flag was still true, so a second Reveal was needed for rows that had never
  /// been refused. The React Native example carried the same defect and was split the same way.
  final Map<WirexRevealField, bool> _maskedByField = <WirexRevealField, bool>{};

  /// Fields whose reveal the row is currently REFUSING, which is not the same as masked.
  ///
  /// The request stands while this is set: the row reveals itself once capture protection is back,
  /// without the user asking again. So the host's intent — `_maskedByField` — is deliberately NOT
  /// changed when a refusal arrives. Setting it to masked there is what the example used to do, and
  /// it withdrew the very request the SDK was holding, so turning AirPlay off did nothing and the
  /// user had to press Reveal a second time.
  final Set<WirexRevealField> _refused = <WirexRevealField>{};

  bool _isMasked(WirexRevealField field) => _maskedByField[field] ?? true;

  /// `''` means the host supplied nothing, and the SDK's contract for "no cardholder name" is
  /// absence rather than an empty string.
  static String? _nullIfBlank(String value) => value.trim().isEmpty ? null : value;

  void _setMaskedAll(bool value) {
    for (final field in fields) {
      _maskedByField[field] = value;
    }
    // Masking WITHDRAWS a held request — it is the one thing that does — so nothing is still being
    // held once the user has pressed Mask. Revealing clears it too: the rows are about to answer for
    // themselves, and a stale entry would report a hold that had already been resolved.
    _refused.clear();
  }

  /// For the status line: revealed only when nothing is still masked.
  ///
  /// The host's INTENT, which is what the prop carries. A row can be intent-revealed and drawn
  /// masked at the same time — that is what `_refused` reports — so the two are shown separately
  /// rather than folded into one flag that would have to lie about one of them.
  bool get _masked => fields.any((field) => _maskedByField[field] != false);
  bool _configuring = false;
  String? _configureError;
  bool _protectionActive = false;
  String _note = '';

  /// What the live session was built from, so a re-apply can tell whether it is stale.
  String _sessionIdentity = '';

  @override
  void initState() {
    super.initState();
    // A value typed on the Config tab: rebuild the session only if the card it captured changed.
    LiveConfig.instance.credentialsRevision.addListener(_onCredentialsChanged);
    _configure();
  }

  void _onCredentialsChanged() {
    if (_session != null) unawaited(_recreateSessionIfIdentityChanged());
  }

  @override
  void dispose() {
    LiveConfig.instance.credentialsRevision.removeListener(_onCredentialsChanged);
    _session?.destroy();
    super.dispose();
  }

  /// Shown in place of the rows while there is no session.
  ///
  /// Carries the reason and a way out rather than a spinner: the side can be switched, and
  /// the credentials panel below stays usable throughout.
  Widget _configureStatus() {
    final error = _configureError;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: error == null ? Colors.grey : Colors.red),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_configuring)
            const Row(
              children: <Widget>[
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('configuring…', style: TextStyle(fontSize: 12)),
              ],
            )
          else
            Text(
              error ?? 'No session yet.',
              style: TextStyle(fontSize: 12, color: error == null ? null : Colors.red),
            ),
          const SizedBox(height: 8),
          const Text(
            'Set the Chain ID (and a bearer and card id) on the Config tab, then press Configure. '
            '`missingChainId` means the environment is chosen but the chain id is still blank — the '
            'environment (test / production) is a side, never a URL, and the SDK holds both addresses.',
            style: TextStyle(fontSize: 10),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _configuring ? null : _configure,
              child: const Text('Configure'),
            ),
          ),
        ],
      ),
    );
  }

  /// Rebuilds the session when a credential the session CAPTURED has changed.
  ///
  /// Not unconditional: a rebuild drops loaded values and re-masks, so doing it for a pasted
  /// `actionToken` — read lazily, therefore already live — would throw away work for nothing.
  Future<void> _recreateSessionIfIdentityChanged() async {
    final identity =
        '${LiveConfig.instance.credential('cardId')}|'
        '${LiveConfig.instance.credential('cardholderName')}';
    if (identity == _sessionIdentity) return;
    _sessionIdentity = identity;
    await _createSession();
    setState(() => _note = 'session rebuilt — cardId or cardholderName changed');
  }

  /// Configures the SDK and opens a session.
  ///
  /// Everything is caught and surfaced. An uncaught failure leaves the screen on a spinner with no
  /// way forward — the worst mode available, because it is indistinguishable from a slow network.
  /// The panels stay reachable instead, and the side can be switched by hand.
  Future<void> _configure() async {
    setState(() {
      _configureError = null;
      _configuring = true;
    });
    try {
      final credentials = StubCredentials();
      _credentials = credentials;

      await WirexReveal.instance.configure(
        testMode: LiveConfig.instance.isTestMode,
        chainId: LiveConfig.instance.credential('chainId'),
        credentials: credentials,
      );
      await _createSession();
    } catch (error) {
      if (mounted) setState(() => _configureError = '$error');
    } finally {
      if (mounted) setState(() => _configuring = false);
    }
  }

  Future<void> _createSession() async {
    await _session?.destroy();
    _sessionIdentity =
        '${LiveConfig.instance.credential('cardId')}|'
        '${LiveConfig.instance.credential('cardholderName')}';
    final session = await WirexReveal.instance.createSession(
      cardId: LiveConfig.instance.credential('cardId'),
      fields: fields,
      // Host-supplied, never fetched: `source: cardsList`, and the web SDK does the same.
      // NULL, not the empty string. `credential()` returns `''` for a key nobody set, and the SDK
      // now trims the handed-over name and treats a blank one as NO NAME — so `''` makes the
      // cardholder row report `idle` rather than `loaded`. That is the honest outcome either way,
      // but saying "absent" by passing absent is what a host should copy from an example.
      cardholderName: _nullIfBlank(LiveConfig.instance.credential('cardholderName')),
    );
    session.onSnapshot((snapshot) => setState(() => _snapshot = snapshot));
    setState(() {
      _session = session;
      _snapshot = session.snapshot;
      _setMaskedAll(true);
    });
  }

  /// Strings the SDK draws. It ships no locale packs on purpose — a card SDK must not invent copy a
  /// screen reader reads aloud.
  static const WirexRevealStrings _strings = WirexRevealStrings(
    fieldLabels: <WirexRevealField, String>{
      WirexRevealField.cardholderName: 'Cardholder',
      WirexRevealField.pan: 'Card number',
      WirexRevealField.expiry: 'Expires',
      WirexRevealField.cvv: 'CVV',
      WirexRevealField.pin: 'PIN',
    },
    copy: 'Copy',
    copied: 'Copied',
  );

  @override
  Widget build(BuildContext context) {
    final session = _session;
    // The EXAMPLE resolves its own `system` choice — the SDK is handed one map and told which mode
    // it is, never a policy to follow.
    final osIsDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    // No Scaffold of its own: this is a tab now, and the container owns the app bar.
    //
    // No `session == null` gate on the whole body either: that replaces every panel with a spinner
    // on a failed `configure`, putting the one thing that could fix it — pasting credentials or
    // switching the side by hand — out of reach. The rows section reports the problem instead.
    return SingleChildScrollView(
      // Scaffold already shrinks the body by the IME inset and Flutter scrolls the focused
      // field into view, so no inset arithmetic is needed here — unlike the native
      // examples. This only adds the missing exit: a multiline TextField has no return key.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Each row below is a NATIVE view, inserted into this Flutter tree as a platform '
            'view. The value never enters the Dart VM.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (session == null) _configureStatus(),
          if (session != null)
            for (final field in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                // No height: the row reports its own, so the appearance tokens decide it.
                child: WirexRevealFieldView(
                  session: session,
                  field: field,
                  strings: _strings,
                  themeMode: LiveConfig.instance.isDarkMode(osIsDark)
                      ? WirexThemeMode.dark
                      : WirexThemeMode.light,
                  appearance: _loggedAppearance(osIsDark, field),
                  masked: _isMasked(field),
                  // This example's tabs live in an `IndexedStack`, so the screen is never destroyed
                  // — but the PLATFORM VIEW still leaves the window on a switch (measured: 8 detach
                  // events). Under the SDK's default that re-masks a row the user is coming straight
                  // back to. A detach here is a hand-off, not a loss of custody.
                  masksWhenDetached: false,
                  onCopyResult: (copied) =>
                      setState(() => _note = copied ? 'Copied ${field.wireName}' : 'Copy refused'),
                  onMaskedChange: (masked, protectionActive) => setState(() {
                    // The host's intent is NOT touched here — see `_refused`. What arrived is "the
                    // row is masked right now", and the reason is outside the user's control: the
                    // screen is being recorded, mirrored or AirPlayed. The request is still held by
                    // the row and will be honoured when that stops.
                    if (masked) {
                      _refused.add(field);
                    } else {
                      _refused.remove(field);
                    }
                    _protectionActive = protectionActive;
                    _note = 'Reveal held for ${field.wireName} — '
                        'the screen is being captured. It will show when that stops.';
                  }),
                ),
              ),
          const SizedBox(height: 12),
          Text(
            'state: ${_snapshot?.state.name ?? 'no session'}\n'
            '${_snapshot?.fields.map((f) => '${f.field.wireName}: ${f.outcome.name}').join(', ') ?? ''}\n'
            'requested-masked: $_masked   capture-protected: $_protectionActive'
            '${_refused.isEmpty ? '' : '\nheld for: ${_refused.map((f) => f.wireName).join(', ')}'}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
          if (_note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_note, style: const TextStyle(fontSize: 12, color: Colors.deepPurple)),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilledButton(onPressed: session?.load, child: const Text('Load')),
              OutlinedButton(
                onPressed: () => setState(() => _setMaskedAll(false)),
                child: const Text('Reveal'),
              ),
              OutlinedButton(
                onPressed: () => setState(() => _setMaskedAll(true)),
                child: const Text('Mask'),
              ),
              OutlinedButton(onPressed: session?.clear, child: const Text('Clear')),
              OutlinedButton(onPressed: _createSession, child: const Text('New session')),
              OutlinedButton(
                onPressed: () => setState(() {
                  _credentials?.declineNextActionToken = true;
                  _note = 'The next action-token will be declined';
                }),
                child: const Text('Decline next'),
              ),
            ],
          ),

          // Credentials and identity are entered on the Config tab now, shared by every surface.
        ],
      ),
    );
  }
}
