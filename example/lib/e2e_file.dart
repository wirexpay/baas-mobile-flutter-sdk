/// Reads `e2e/e2e.local.json`, the gitignored file that prefills the config for a local trade run. FOR
/// TESTING ONLY: a debug build reads it, and a release or profile build fails while it exists.
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;

import 'diag_log.dart';
import 'live_config.dart';

const String e2eAssetPath = 'e2e/${LiveConfig.e2eFileName}';

/// Loads the file into [LiveConfig] as its top source. A missing file is no source, not an error.
Future<void> loadE2eFile() async {
  // SECURITY: the file holds a private key; the native build steps also refuse a non-debug build.
  if (!kDebugMode) return;
  final String text;
  try {
    text = await rootBundle.loadString(e2eAssetPath, cache: false);
  } catch (_) {
    DiagLog.instance.config('${LiveConfig.e2eFileName}: none');
    return;
  }
  final ConfigOutcome outcome = LiveConfig.instance.applyFileText(text);
  if (outcome is ConfigRejected) DiagLog.instance.err(outcome.reason);
}
