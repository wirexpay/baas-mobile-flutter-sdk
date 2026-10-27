/// The example's diagnostic log: one process-wide, in-memory list of what the example and the SDK
/// reported this run, with a Share button on the Config tab so a tester can attach it to a bug report.
///
/// SECURITY: nothing here is persisted and nothing sensitive is written. Callers log key NAMES and
/// LENGTHS, never values; [DiagLog.append] redacts anything that still looks like a token, a card
/// number or a wallet address. The shared text leaves the device — treat every line as public.
library;

import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;

/// One line per event. `HH:mm:ss.SSS [tag] message`.
class DiagLog extends ChangeNotifier {
  DiagLog._();

  static final DiagLog instance = DiagLog._();

  static const int maxLines = 2000;

  final List<String> _lines = <String>[];
  String? _lastBody;

  /// Every line, oldest first.
  List<String> get lines => List<String>.unmodifiable(_lines);

  int get length => _lines.length;

  /// Lines from `[tag]` sources: `app`, `link`, `config`, `tap`, `kbd`, `sdk`, `err`.
  void append(String tag, String message) {
    final String body = '[$tag] ${redact(message)}';
    // The same event twice in a row (a framework warning on every rebuild) is one line.
    if (body == _lastBody) return;
    _lastBody = body;
    final String line = '${_stamp(DateTime.now())} $body';
    _lines.add(line);
    if (_lines.length > maxLines) _lines.removeRange(0, _lines.length - maxLines);
    debugPrint('[diag] $line');
    _notify();
  }

  bool _notifyScheduled = false;

  /// Listeners rebuild widgets, and a line can be logged while the framework is building (a
  /// FlutterError report, a widget's own log call), so listeners hear about lines in a microtask:
  /// after the current synchronous build, once per burst.
  void _notify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  void app(String message) => append('app', message);
  void link(String message) => append('link', message);
  void config(String message) => append('config', message);
  void tap(String message) => append('tap', message);
  void kbd(String message) => append('kbd', message);
  void sdk(String message) => append('sdk', message);
  void err(String message) => append('err', message);

  void clear() {
    _lines.clear();
    _lastBody = null;
    _notify();
  }

  /// The text the Share and Copy buttons hand out: a header, every line, then the native log.
  Future<String> export() async {
    final String? size = DiagObserver.screen();
    if (size != null) header['screen'] = size;
    final Map<String, String> info = await Diagnostics.appInfo();
    final String native = await Diagnostics.nativeLog();
    final List<String> nativeLines =
        native.isEmpty ? const <String>[] : native.split('\n').where((String l) => l.isNotEmpty).toList();
    final StringBuffer out = StringBuffer()
      ..writeln('Wirex Mobile SDK example — diagnostic log')
      ..writeln('exported: ${DateTime.now().toIso8601String()}');
    for (final MapEntry<String, String> e in (header..addAll(info)).entries) {
      out.writeln('${e.key}: ${e.value}');
    }
    out
      ..writeln('lines: ${_lines.length}')
      ..writeln()
      ..writeln('--- example log (${_lines.length} lines) ---');
    _lines.forEach(out.writeln);
    out
      ..writeln()
      ..writeln('--- native log (${nativeLines.length} lines) ---');
    nativeLines.map(redact).forEach(out.writeln);
    return out.toString();
  }

  /// What the Dart side knows about this run: filled at launch by the app root (screen, locale, SDK
  /// version); the native side adds app id, version, model and OS at export time.
  final Map<String, String> header = <String, String>{};

  static String _stamp(DateTime t) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${p2(t.hour)}:${p2(t.minute)}:${p2(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }

  static final RegExp _jwt = RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.?[A-Za-z0-9_-]*');
  static final RegExp _digits = RegExp(r'(?<!\d)\d{13,19}(?!\d)');
  static final RegExp _address = RegExp(r'0x([0-9a-fA-F]{4})[0-9a-fA-F]{32}([0-9a-fA-F]{4})');

  /// SECURITY: the last line of defence for the shared text. A bearer or action token, a PAN-length
  /// digit run and a full wallet address are replaced even if a caller logged one by mistake.
  static String redact(String message) => message
      .replaceAll(_jwt, '<jwt>')
      .replaceAll(_digits, '<digits>')
      .replaceAllMapped(_address, (Match m) => '0x${m[1]}…${m[2]}');
}

/// The native side of the log: the system share sheet, the process's own system log and the app's
/// identity. One method channel, implemented in `MainActivity.kt` and `AppDelegate.swift`.
class Diagnostics {
  Diagnostics._();

  static const MethodChannel _channel = MethodChannel('wirex.example/diagnostics');

  /// Opens the system share sheet with [text].
  static Future<void> share(String text) async {
    try {
      await _channel.invokeMethod<void>('share', <String, Object?>{'text': text});
    } on PlatformException catch (e) {
      DiagLog.instance.err('share failed: ${e.code} ${e.message ?? ''}');
    } on MissingPluginException {
      DiagLog.instance.err('share: native channel not available');
    }
  }

  /// The process's own system log (logcat on Android, the unified log on iOS), as text. Empty when
  /// the platform cannot provide it; the reason is logged.
  static Future<String> nativeLog() async {
    try {
      return await _channel.invokeMethod<String>('nativeLog') ?? '';
    } on PlatformException catch (e) {
      return 'native log unavailable: ${e.code} ${e.message ?? ''}';
    } on MissingPluginException {
      return 'native log unavailable: channel not registered';
    }
  }

  /// `appId`, `version`, `build`, `model`, `os`.
  static Future<Map<String, String>> appInfo() async {
    try {
      final Map<Object?, Object?>? raw = await _channel.invokeMethod<Map<Object?, Object?>>('appInfo');
      return <String, String>{
        for (final MapEntry<Object?, Object?> e in (raw ?? <Object?, Object?>{}).entries) '${e.key}': '${e.value}',
      };
    } on PlatformException catch (e) {
      return <String, String>{'appInfo': 'unavailable: ${e.code}'};
    } on MissingPluginException {
      return <String, String>{'appInfo': 'unavailable: channel not registered'};
    }
  }
}

/// Logs lifecycle changes and keyboard show / hide transitions (once per transition).
class DiagObserver extends WidgetsBindingObserver {
  DiagObserver();

  bool _keyboardShown = false;
  bool _screenLogged = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    DiagLog.instance.app('lifecycle: ${state.name}');
  }

  /// `<logical width>x<logical height> @<scale>x`, or null before the window has a size.
  static String? screen() {
    final FlutterView view = WidgetsBinding.instance.platformDispatcher.views.first;
    if (view.physicalSize.isEmpty) return null;
    final double w = view.physicalSize.width / view.devicePixelRatio;
    final double h = view.physicalSize.height / view.devicePixelRatio;
    return '${w.toStringAsFixed(0)}x${h.toStringAsFixed(0)} @${view.devicePixelRatio}x';
  }

  @override
  void didChangeMetrics() {
    final FlutterView view = WidgetsBinding.instance.platformDispatcher.views.first;
    if (!_screenLogged) {
      final String? size = screen();
      if (size != null) {
        _screenLogged = true;
        DiagLog.instance.header['screen'] = size;
        DiagLog.instance.app('screen: $size');
      }
    }
    final double inset = view.viewInsets.bottom / view.devicePixelRatio;
    final bool shown = inset > 0;
    if (shown == _keyboardShown) return;
    _keyboardShown = shown;
    DiagLog.instance.kbd(shown ? 'keyboard shown (height ${inset.toStringAsFixed(0)})' : 'keyboard hidden');
  }
}

/// `void` for a `Future` the caller does not await, with the failure logged rather than lost.
void logged(Future<Object?> future, String what) {
  unawaited(future.then<void>((_) {}, onError: (Object e) => DiagLog.instance.err('$what: ${e.runtimeType} $e')));
}
