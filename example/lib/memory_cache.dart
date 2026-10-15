/// An in-memory `WirexWalletAvailabilityCache`, observable so the Availability tab can render what
/// the SDK persisted through it.
///
/// The only thing the SDK ever writes here is `{"applePay":bool,"googlePay":bool}` under the probe
/// cache key, and only from a REAL probe answer. A production host would back this with
/// `shared_preferences` or its own store; in-memory keeps the example dependency-free and makes
/// "Clear" an honest fresh-install simulation.
library;

import 'package:flutter/foundation.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';

class MemoryAvailabilityCache extends ChangeNotifier implements WirexWalletAvailabilityCache {
  final Map<String, String> _store = <String, String>{};

  /// A copy, for display.
  Map<String, String> get entries => Map<String, String>.unmodifiable(_store);

  bool get isEmpty => _store.isEmpty;

  @override
  String? read(String key) => _store[key];

  @override
  void write(String key, String value) {
    _store[key] = value;
    notifyListeners();
  }

  /// Simulates a fresh install: `current` starts null and the next process-start probes afresh.
  void clear() {
    _store.clear();
    notifyListeners();
  }
}
