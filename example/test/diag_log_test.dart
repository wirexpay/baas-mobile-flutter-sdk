/// The diagnostic log leaves the device with a bug report, so what it redacts and what the seed-link
/// outcome says are pinned here. Every platform's example reports the same reasons.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wirex_mobile_sdk_example/diag_log.dart';
import 'package:wirex_mobile_sdk_example/live_config.dart';

void main() {
  group('DiagLog.redact', () {
    test('replaces a JWT, a PAN-length digit run and a wallet address', () {
      const String jwt = 'eyJ0eXAiOiJ0ZXN0In0.eyJzdWIiOiIxIn0.abcDEF';
      expect(DiagLog.redact('bearer $jwt'), 'bearer <jwt>');
      expect(DiagLog.redact('pan 4111111111111111 typed'), 'pan <digits> typed');
      expect(
        DiagLog.redact('0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9f8e'),
        '0x1a2b…9f8e',
      );
    });

    test('leaves short numbers and ordinary text alone', () {
      expect(DiagLog.redact('chainId 5042002 set (7 chars)'), 'chainId 5042002 set (7 chars)');
    });
  });

  group('applySeedLinkDetailed', () {
    final LiveConfig config = LiveConfig.instance;
    // {"chainId":"5042002","email":"qa@example.com"}
    const String payload = 'eyJjaGFpbklkIjoiNTA0MjAwMiIsImVtYWlsIjoicWFAZXhhbXBsZS5jb20ifQ';

    test('names the keys it applied, for either accepted scheme', () {
      for (final String scheme in <String>['wirexqa', 'wirexqa-flutter']) {
        final SeedLinkOutcome outcome = config.applySeedLinkTextDetailed('$scheme://seed?d=$payload');
        expect(outcome.isApplied, isTrue, reason: scheme);
        expect(outcome.keys, <String>['chainId', 'email']);
        expect(outcome.applied, 2);
      }
    });

    test('says why another example\'s scheme is refused', () {
      final SeedLinkOutcome outcome = config.applySeedLinkTextDetailed('wirexqa-rn://seed?d=$payload');
      expect(outcome.isApplied, isFalse);
      expect(outcome.reason, "scheme 'wirexqa-rn' is not accepted by this example (accepts: wirexqa, wirexqa-flutter)");
      expect(outcome.applied, isNull);
    });

    test('names the other refusals', () {
      expect(config.applySeedLinkTextDetailed('wirexqa://other?d=$payload').reason, "host is 'other', expected seed");
      expect(config.applySeedLinkTextDetailed('wirexqa://seed').reason, 'no d= parameter');
      expect(config.applySeedLinkTextDetailed('wirexqa://seed?d=!!!').reason, 'base64 decode failed');
      expect(config.applySeedLinkTextDetailed('wirexqa://seed?d=bm90IGpzb24').reason, startsWith('JSON parse failed'));
    });

    test('a cut-short link is reported by length, never by its content', () {
      // The JSON stops mid-value, as when a field or a chat truncates the link.
      final String? reason = config.applySeedLinkTextDetailed('wirexqa://seed?d=eyJjaGFpbklkIjoiMSIsImJlYXJlciI6ImRvLW5vdC1lY2hvLXRoaXM').reason;
      expect(reason, startsWith('JSON parse failed: the link looks cut short'));
      expect(reason, isNot(contains('do-not-echo-this')));
      expect(reason, isNot(contains('bearer')));
    });
  });
}
