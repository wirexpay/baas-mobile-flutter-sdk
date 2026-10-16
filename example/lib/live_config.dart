/// Everything the example needs at runtime that a rebuild would otherwise be required to change.
///
/// Seeded from `--dart-define`, then overridden from JSON pasted into the app. **Merge, not
/// replace**: a key absent from the pasted document keeps its previous value, so when one credential
/// expires you paste a document containing only that one. That is the whole reason this exists —
/// `action_token` lives 300 seconds, and rebuilding for each is not a workflow.
///
/// SECURITY: in memory only. Nothing here reaches shared preferences, a file or the keychain — the
/// SDK makes that promise about card values, and an example that persisted a bearer would teach the
/// opposite. Values die with the process.
///
/// The same keys every platform's example holds.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

/// Outcome of merging a pasted document.
sealed class ConfigOutcome {
  const ConfigOutcome();
}

class ConfigMerged extends ConfigOutcome {
  const ConfigMerged(this.summary);
  final String summary;
}

class ConfigRejected extends ConfigOutcome {
  const ConfigRejected(this.reason);
  final String reason;
}

/// Which look the example shows. The EXAMPLE's own policy, not the SDK's: `system` is resolved here
/// and the map that wins is handed over, because only a host knows what dark means to its own design
/// system.
/// Shared runtime state for every screen in this example.
///
/// A `ChangeNotifier` because appearance belongs to a TAB OF ITS OWN and applies to BOTH surfaces.
/// This is the Flutter equivalent of the notification the native examples post.
class LiveConfig extends ChangeNotifier {
  LiveConfig._();

  static final LiveConfig instance = LiveConfig._();

  static const List<String> _known = <String>[
    'environment', 'bearer', 'email', 'wallet', 'cardId', 'actionToken', 'cardholderName', 'chainId', 'baasApiUrl',
  ];

  /// Bumped whenever a credential / identity value changes, so a screen can rebuild. Separate from
  /// the `ChangeNotifier` this class uses for appearance: a credential change may have to rebuild a
  /// session or reconfigure a surface, an appearance change must never do either.
  final ValueNotifier<int> credentialsRevision = ValueNotifier<int>(0);

  final Map<String, String> _credentials = <String, String>{
    // `--dart-define` is the seed, so a scripted run needs no typing.
    if (const String.fromEnvironment('WIREX_BEARER').isNotEmpty)
      'bearer': const String.fromEnvironment('WIREX_BEARER'),
    if (const String.fromEnvironment('WIREX_EMAIL').isNotEmpty)
      'email': const String.fromEnvironment('WIREX_EMAIL'),
    if (const String.fromEnvironment('WIREX_WALLET').isNotEmpty)
      'wallet': const String.fromEnvironment('WIREX_WALLET'),
    if (const String.fromEnvironment('WIREX_CARD_ID').isNotEmpty)
      'cardId': const String.fromEnvironment('WIREX_CARD_ID'),
    if (const String.fromEnvironment('WIREX_ACTION_TOKEN').isNotEmpty)
      'actionToken': const String.fromEnvironment('WIREX_ACTION_TOKEN'),
    if (const String.fromEnvironment('WIREX_CARDHOLDER_NAME').isNotEmpty)
      'cardholderName': const String.fromEnvironment('WIREX_CARDHOLDER_NAME'),
    if (const String.fromEnvironment('WIREX_CHAIN_ID').isNotEmpty)
      'chainId': const String.fromEnvironment('WIREX_CHAIN_ID'),
  };

  /// The example keeps one map per mode and hands over the one that matches.
  final Map<String, Object?> _lightTokens = <String, Object?>{};
  final Map<String, Object?> _darkTokens = <String, Object?>{};

  String credential(String key) => _credentials[key] ?? '';

  /// Writes a single key — the per-field Config tab's edit. An EMPTY value CLEARS the key, matching
  /// [applyCredentials]. `notify` is false while a field is mid-edit (every keystroke) and true when
  /// it loses focus, so a screen rebuilds once on blur rather than on every character.
  void setCredential(String key, String value, {bool notify = true}) {
    if (value.isEmpty) {
      _credentials.remove(key);
    } else {
      _credentials[key] = value;
    }
    if (notify) credentialsRevision.value++;
  }

  /// The SDK environment NAME the Config tab selected, defaulting to `test`. A name, never a URL.
  String get environment {
    final value = credential('environment');
    return value.isEmpty ? 'test' : value;
  }

  /// `test` everywhere but the production name — mirrors `exampleConfig.ts`.
  bool get isTestMode => environment != 'production';

  /// Clears every credential / identity value back to empty (environment falls back to `test`).
  void resetCredentials() {
    _credentials.clear();
    credentialsRevision.value++;
  }

  ConfigOutcome applyCredentials(String json) {
    final parsed = _parse(json);
    if (parsed == null) return const ConfigRejected('not valid JSON');

    final applied = <String>[];
    final cleared = <String>[];
    final unknown = <String>[];
    parsed.forEach((key, value) {
      if (!_known.contains(key)) {
        unknown.add(key);
        return;
      }
      if (value is! String) return;
      // An EMPTY string clears the key — see LiveConfig.swift for why this is not the same as
      // omitting it.
      if (value.isEmpty) {
        _credentials.remove(key);
        cleared.add(key);
        return;
      }
      _credentials[key] = value;
      applied.add(key);
    });

    if (applied.isEmpty && cleared.isEmpty && unknown.isEmpty) {
      return const ConfigRejected('no recognised keys');
    }
    var summary = 'merged: ${(applied..sort()).join(', ')}';
    if (cleared.isNotEmpty) summary += ' · CLEARED: ${(cleared..sort()).join(', ')}';
    // Named rather than ignored: a typo in a key would otherwise look like a successful paste.
    if (unknown.isNotEmpty) summary += ' · IGNORED unknown: ${(unknown..sort()).join(', ')}';
    return ConfigMerged(summary);
  }

  /// Per-key presence, and for JWTs whether they are still valid. The expiry check is the point: an
  /// expired `action_token` and a missing one fail identically at the API, and knowing which is the
  /// difference between pasting a new token and hunting a bug.
  String credentialsStatus() => <String>['bearer', 'actionToken', 'cardId', 'cardholderName', 'email', 'wallet']
      .map((key) {
        final value = credential(key);
        if (value.isEmpty) return '$key: —';
        final expiry = _jwtExpirySeconds(value);
        if (expiry == null) return '$key: set';
        final remaining = expiry - DateTime.now().millisecondsSinceEpoch ~/ 1000;
        return remaining > 0 ? '$key: valid ${remaining}s' : '$key: EXPIRED ${-remaining}s ago';
      })
      .join('\n');

  /// Which look the example is showing, shared by both surfaces.
  ///
  /// `system` is the EXAMPLE's own policy, not the SDK's — it is resolved here against the platform
  /// brightness, and the SDK is handed the map that won together with the mode it IS.
  /// Whether the DEVICE is dark. Nothing else decides.
  ///
  /// The example used to carry its own `light | dark | system` choice, with a segmented control on
  /// the Appearance tab and a second editor for dark-only tokens. That put a theme vocabulary on
  /// screen the SDK does not have: it resolves no theme and holds no palette — it draws the one
  /// complete document it is handed. A control the SDK cannot honour teaches a partner the wrong
  /// contract, so the OS decides and the example swaps the document.
  bool isDarkMode(bool osIsDark) => osIsDark;

  /// The token maps as the collect binding takes them — raw, because its native reader parses the
  /// document rather than a Dart-side type. Reveal takes the typed form; both come from one source.
  ///
  /// A SNAPSHOT whose identity changes exactly when the tokens do — not on every read, and not never.
  /// Returning `Map.unmodifiable` per call makes every rebuild look like a change, so the collect form
  /// takes an `update` per keystroke; returning the mutable map itself makes no rebuild look like a
  /// change, so a preset does not reach the form until something else rebuilds it. A widget comparing
  /// `widget.appearance != oldWidget.appearance` needs identity to mean something.
  /// The map for the mode being shown, as the collect binding takes it.
  Map<String, Object?> appearanceTokens(bool osIsDark) =>
      isDarkMode(osIsDark) ? _darkSnapshot : _lightSnapshot;

  /// The raw maps, for the editor that edits them.
  Map<String, Object?> get lightTokens => _lightSnapshot;
  Map<String, Object?> get darkTokens => _darkSnapshot;

  Map<String, Object?> _lightSnapshot = const <String, Object?>{};
  Map<String, Object?> _darkSnapshot = const <String, Object?>{};

  void _publishAppearance() {
    _lightSnapshot = Map<String, Object?>.unmodifiable(_lightTokens);
    _darkSnapshot = Map<String, Object?>.unmodifiable(_darkTokens);
    notifyListeners();
  }

  /// Replaces both maps outright. What a preset button does — a merge would leave the last one on.
  void setAppearance(Map<String, Object?> light, Map<String, Object?> dark) {
    _lightTokens
      ..clear()
      ..addAll(light);
    _darkTokens
      ..clear()
      ..addAll(dark);
    _publishAppearance();
  }

  /// Merges into the document currently on screen — the one the editor is showing.
  ///
  /// One applier, not a light one and a dark one. The second editor described a layering the SDK
  /// never does: it is handed one complete document and draws it.
  ConfigOutcome applyAppearance(String json, bool osIsDark) {
    final parsed = _parse(json);
    if (parsed == null) return const ConfigRejected('not valid JSON');
    if (isDarkMode(osIsDark)) {
      _darkTokens.addAll(parsed);
    } else {
      _lightTokens.addAll(parsed);
    }
    _publishAppearance();
    return ConfigMerged('merged: ${(parsed.keys.toList()..sort()).join(', ')}');
  }

  void resetAppearance() {
    _lightTokens.clear();
    _darkTokens.clear();
    _publishAppearance();
  }

  /// The tokens for the mode being shown, named exactly as `contract/appearance.tokens.json` names them.
  /// Unset tokens are simply absent, so the SDK applies that mode's own default rather than
  /// something reimplemented here.
  WirexRevealAppearance appearance(bool osIsDark) => _appearanceFrom(
      isDarkMode(osIsDark) ? _darkTokens : _lightTokens);

  WirexRevealAppearance _appearanceFrom(Map<String, Object?> tokens) {
    String? text(String key) => tokens[key] as String?;
    double? number(String key) => (tokens[key] as num?)?.toDouble();

    return WirexRevealAppearance(
      colorText: text('colorText'),
      colorLabel: text('colorLabel'),
      colorPlaceholder: text('colorPlaceholder'),
      colorError: text('colorError'),
      colorFocus: text('colorFocus'),
      colorBackground: text('colorBackground'),
      colorBorder: text('colorBorder'),
      surfaceColor: text('surfaceColor'),
      fontFamily: text('fontFamily'),
      fontSizeBase: number('fontSizeBase'),
      fontSizeLabel: number('fontSizeLabel'),
      lineHeightBase: number('lineHeightBase'),
      lineHeightLabel: number('lineHeightLabel'),
      fontWeightBase: text('fontWeightBase'),
      fontWeightLabel: text('fontWeightLabel'),
      textAlignBase: text('textAlignBase'),
      textAlignLabel: text('textAlignLabel'),
      borderRadius: number('borderRadius'),
      borderWidth: number('borderWidth'),
      spacingUnit: number('spacingUnit'),
      paddingHorizontal: number('paddingHorizontal'),
      paddingVertical: number('paddingVertical'),
      paddingValueHorizontal: number('paddingValueHorizontal'),
      paddingValueVertical: number('paddingValueVertical'),
      spacingLabel: number('spacingLabel'),
      spacingAction: number('spacingAction'),
      iconSize: number('iconSize'),
      controlMinHeight: number('controlMinHeight'),
    );
  }

  Map<String, Object?>? _parse(String json) {
    final trimmed = json.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// `exp` from an unverified JWT payload. The signature is NOT checked and must not be: this is a
  /// convenience for the operator, and the server is the only thing entitled to trust a token.
  int? _jwtExpirySeconds(String token) {
    final segments = token.split('.');
    if (segments.length != 3) return null;
    try {
      var payload = segments[1].replaceAll('-', '+').replaceAll('_', '/');
      payload += '=' * ((4 - payload.length % 4) % 4);
      final claims = jsonDecode(utf8.decode(base64.decode(payload))) as Map<String, Object?>;
      final exp = claims['exp'];
      return exp is int ? exp : null;
    } catch (_) {
      return null;
    }
  }
}
