import 'dart:convert';

import 'package:flutter/material.dart';

import 'live_config.dart';

/// One place to restyle every field on both surfaces.
///
/// Appearance is a screen of its own and applies to BOTH surfaces: both listen to [LiveConfig], so
/// a preset or a pasted document lands everywhere at once. That is also the invariant worth watching
/// here — restyling must not clear what is typed into the collect form, and must not unmask a reveal
/// row.
///
/// The same six presets the iOS and Android examples carry, token for token. They are hardcoded on
/// purpose: they are the fastest way to see the vocabulary do something visible, and each one
/// exercises a group of tokens rather than trying to look nice.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _Preset {
  const _Preset(this.name, this.exercises, this.light, this.dark);

  final String name;

  /// What it is here to demonstrate. Shown under the button, so the tab teaches the vocabulary.
  final String exercises;
  final Map<String, Object?> light;
  final Map<String, Object?> dark;
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  /// ONE document — whichever the device is asking for. There is no second editor: the SDK holds no
  /// palette and resolves no theme, so a "dark-only" box described a layering the SDK never does.
  late final TextEditingController _tokens = TextEditingController();
  String _status = '—';

  // A preset that sets no colours carries the same map twice on purpose: geometry does not change with
  // the mode, and an empty dark map would leave a dark device with nothing to apply (and an empty editor).
  static const List<_Preset> _presets = <_Preset>[
    _Preset(
      'SDK defaults',
      "every token unset — the mode's own defaults",
      <String, Object?>{},
      <String, Object?>{},
    ),
    _Preset(
      'Boxed',
      'colorBackground, borderWidth, borderRadius, paddingValue*',
      <String, Object?>{
        'surfaceColor': '#FFFFFF',
        'colorBackground': '#F1F5F9',
        'colorBorder': '#CBD5E1',
        'borderWidth': 1,
        'borderRadius': 16,
        'paddingHorizontal': 14,
        'paddingVertical': 12,
        'paddingValueHorizontal': 12,
        'paddingValueVertical': 10,
        'colorText': '#0F172A',
        'colorLabel': '#64748B',
      },
      <String, Object?>{
        'surfaceColor': '#0B1120',
        'colorBackground': '#1E293B',
        'colorBorder': '#334155',
        'borderWidth': 1,
        'borderRadius': 16,
        'paddingHorizontal': 14,
        'paddingVertical': 12,
        'paddingValueHorizontal': 12,
        'paddingValueVertical': 10,
        'colorText': '#F8FAFC',
        'colorLabel': '#94A3B8',
      },
    ),
    _Preset(
      'Right-aligned',
      'textAlignBase, textAlignLabel — the two the collect field ignored',
      <String, Object?>{
        'textAlignBase': 'right',
        'textAlignLabel': 'right',
        'colorBackground': '#F8FAFC',
        'paddingValueHorizontal': 12,
        'borderRadius': 12,
      },
      <String, Object?>{
        'textAlignBase': 'right',
        'textAlignLabel': 'right',
        'colorBackground': '#111827',
        'paddingValueHorizontal': 12,
        'borderRadius': 12,
      },
    ),
    _Preset(
      'Large type',
      'fontSizeBase, lineHeightBase, controlMinHeight, iconSize',
      <String, Object?>{
        'fontSizeBase': 24,
        'lineHeightBase': 34,
        'fontSizeLabel': 15,
        'lineHeightLabel': 20,
        'controlMinHeight': 56,
        'iconSize': 24,
        'spacingLabel': 8,
        'spacingUnit': 20,
      },
      <String, Object?>{
        'fontSizeBase': 24,
        'lineHeightBase': 34,
        'fontSizeLabel': 15,
        'lineHeightLabel': 20,
        'controlMinHeight': 56,
        'iconSize': 24,
        'spacingLabel': 8,
        'spacingUnit': 20,
      },
    ),
    _Preset(
      'Compact',
      'the same tokens the other way — a dense list',
      <String, Object?>{
        'fontSizeBase': 15,
        'lineHeightBase': 20,
        'fontSizeLabel': 11,
        'lineHeightLabel': 14,
        'controlMinHeight': 36,
        'iconSize': 12,
        'spacingLabel': 2,
        'spacingUnit': 6,
        'paddingHorizontal': 8,
        'paddingVertical': 6,
      },
      <String, Object?>{
        'fontSizeBase': 15,
        'lineHeightBase': 20,
        'fontSizeLabel': 11,
        'lineHeightLabel': 14,
        'controlMinHeight': 36,
        'iconSize': 12,
        'spacingLabel': 2,
        'spacingUnit': 6,
        'paddingHorizontal': 8,
        'paddingVertical': 6,
      },
    ),
    _Preset(
      'High contrast',
      'colorFocus and colorError, which drive the caret and the error text',
      <String, Object?>{
        'surfaceColor': '#000000',
        'colorBackground': '#000000',
        'colorText': '#FFFFFF',
        'colorLabel': '#FFD400',
        'colorPlaceholder': '#7A7A7A',
        'colorFocus': '#FFD400',
        'colorError': '#FF453A',
        'colorBorder': '#FFD400',
        'borderWidth': 2,
        'borderRadius': 4,
      },
      <String, Object?>{
        'surfaceColor': '#000000',
        'colorBackground': '#000000',
        'colorText': '#FFFFFF',
        'colorLabel': '#FFD400',
        'colorPlaceholder': '#7A7A7A',
        'colorFocus': '#FFD400',
        'colorError': '#FF453A',
        'colorBorder': '#FFD400',
        'borderWidth': 2,
        'borderRadius': 4,
      },
    ),
  ];

  @override
  void dispose() {
    _tokens.dispose();
    super.dispose();
  }

  void _applyPreset(_Preset preset) {
    LiveConfig.instance.setAppearance(preset.light, preset.dark);
    // BOTH documents are replaced; the editor shows whichever the device is asking for.
    _tokens.text = _pretty(_osIsDark(context) ? preset.dark : preset.light);
    setState(() => _status = "applied '${preset.name}' — both surfaces restyled");
  }

  static String _pretty(Map<String, Object?> tokens) =>
      tokens.isEmpty ? '' : const JsonEncoder.withIndent('  ').convert(tokens);

  void _report(ConfigOutcome outcome) => setState(() {
        _status = switch (outcome) {
          ConfigMerged(:final String summary) => summary,
          ConfigRejected(:final String reason) => 'rejected: $reason',
        };
      });

  static bool _osIsDark(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'One document, and the SDK draws exactly it. There is no theme to choose: the SDK '
            'resolves none and holds no palette. The device decides which document this example '
            'hands over, and the editor below shows the one in force.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),
          Text('Presets', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Applied to BOTH surfaces at once. Watch that a restyle never clears the collect form '
            'or unmasks a reveal row — that is the invariant, not a detail.',
            style: TextStyle(fontSize: 12),
          ),
          for (final _Preset preset in _presets) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _applyPreset(preset),
              child: Text(preset.name),
            ),
            Text(preset.exercises, style: const TextStyle(fontSize: 11)),
          ],
          const SizedBox(height: 20),
          Text('Tokens (JSON)', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Editable. Merged into the document in force, so a partial one is fine — an absent '
            "token falls through to the SDK's own default.",
            style: TextStyle(fontSize: 12),
          ),
          TextField(
            controller: _tokens,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => _report(
                  LiveConfig.instance.applyAppearance(_tokens.text, _osIsDark(context)),
                ),
                child: const Text('Apply'),
              ),
              OutlinedButton(
                onPressed: () {
                  LiveConfig.instance.resetAppearance();
                  _tokens.clear();
                  setState(() => _status = 'reset to the SDK defaults');
                },
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(_status, style: const TextStyle(fontFamily: 'Menlo', fontSize: 11)),
        ],
      ),
    );
  }
}
