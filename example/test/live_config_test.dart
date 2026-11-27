/// The credential merge, which is the example's only real logic.
///
/// Every platform's example runs these same cases. They are the contract that keeps the examples
/// behaving identically — a divergence is a real defect, not a stylistic difference.
///
/// "Absent keeps" and "empty clears" are one line apart in the code and opposite in effect, and a
/// merge that treats an empty string as absent leaves a stale `actionToken` unremovable without
/// restarting the app.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wirex_mobile_sdk_example/live_config.dart';

/// `exp` is read from an UNVERIFIED payload, so a hand-built token is enough.
String tokenExpiring(int inSeconds) {
  final claims = jsonEncode(<String, Object?>{
    'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + inSeconds,
  });
  final payload = base64Url.encode(utf8.encode(claims)).replaceAll('=', '');
  return 'header.$payload.signature';
}

void main() {
  final config = LiveConfig.instance;

  setUp(() {
    // The store is a singleton; clear the keys each test touches.
    config.applyCredentials(
      jsonEncode(<String, String>{
        'bearer': '', 'actionToken': '', 'cardId': '', 'cardholderName': '',
      }),
    );
    config.resetAppearance();
  });

  group('applyCredentials', () {
    test('merges the keys it is given', () {
      expect(config.applyCredentials('{"bearer":"b1","cardId":"c1"}'), isA<ConfigMerged>());
      expect(config.credential('bearer'), 'b1');
      expect(config.credential('cardId'), 'c1');
    });

    test('a key that is ABSENT keeps its previous value', () {
      config.applyCredentials('{"bearer":"b1","cardId":"c1"}');
      config.applyCredentials('{"cardId":"c2"}');
      expect(config.credential('bearer'), 'b1');
      expect(config.credential('cardId'), 'c2');
    });

    test('a key set to an EMPTY string is cleared', () {
      config.applyCredentials('{"actionToken":"t1"}');
      expect(config.credential('actionToken'), 't1');

      final outcome = config.applyCredentials('{"actionToken":""}');
      expect(config.credential('actionToken'), '');
      // Named in the summary: a silent clear reads exactly like a failed paste.
      expect((outcome as ConfigMerged).summary, contains('CLEARED'));
    });

    test('an unknown key is reported rather than ignored', () {
      final outcome = config.applyCredentials('{"bearerr":"typo"}');
      expect((outcome as ConfigMerged).summary, contains('IGNORED'));
    });

    test('invalid JSON is rejected without touching the store', () {
      config.applyCredentials('{"bearer":"keep-me"}');
      expect(config.applyCredentials('{not json'), isA<ConfigRejected>());
      expect(config.credential('bearer'), 'keep-me');
    });
  });

  group('the Trade sources: e2e.local.json, then the Config tab, then a seed link', () {
    String seed(Map<String, String> payload) =>
        'wirexqa://seed?d=${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}';

    setUp(() {
      config.resetCredentials();
      config.clearFileValues();
    });

    tearDown(config.clearFileValues);

    test('a seed link carrying ownerKey is refused whole', () {
      final SeedLinkOutcome outcome =
          config.applySeedLinkTextDetailed(seed(<String, String>{'chainId': '8453', 'ownerKey': '0xfake'}));
      expect(outcome.isApplied, isFalse);
      expect(outcome.reason, contains('never carries ownerKey'));
      expect(outcome.reason, isNot(contains('0xfake')));
      expect(config.credential('chainId'), '');
      expect(config.credential('ownerKey'), '');
    });

    test('the file wins over the Config tab and a seed link', () {
      config.applyFileText('{"chainId":8453,"companyId":"11111111-1111-1111-1111-111111111111"}');
      config.setCredential('chainId', '5042');
      final SeedLinkOutcome outcome = config.applySeedLinkTextDetailed(seed(<String, String>{'companyId': 'other'}));
      expect(config.credential('chainId'), '8453');
      expect(config.credential('companyId'), '11111111-1111-1111-1111-111111111111');
      expect(outcome.skipped, <String>['companyId']);
      expect(config.fromFile('chainId'), isTrue);
    });

    test('the Config tab wins over a later seed link, which names what it kept', () {
      config.setCredential('companyId', 'from-tab');
      final SeedLinkOutcome outcome =
          config.applySeedLinkTextDetailed(seed(<String, String>{'companyId': 'from-seed', 'chainId': '8453'}));
      expect(config.credential('companyId'), 'from-tab');
      expect(config.credential('chainId'), '8453');
      expect(outcome.keys, <String>['chainId']);
      expect(outcome.skipped, <String>['companyId']);
    });

    test('an empty value on the tab still clears what a seed link set', () {
      config.applySeedLinkTextDetailed(seed(<String, String>{'bearer': 'from-seed'}));
      config.setCredential('bearer', '');
      expect(config.credential('bearer'), '');
    });

    test('the file reports unknown keys by name and keeps no empty value', () {
      final ConfigOutcome outcome = config.applyFileText('{"ownerKey":"","chainId":"8453","ownerkey":"0xfake"}');
      expect((outcome as ConfigMerged).summary, contains('IGNORED: ownerkey'));
      expect(outcome.summary, isNot(contains('0xfake')));
      expect(config.fromFile('ownerKey'), isFalse);
      expect(config.fromFile('chainId'), isTrue);
    });

    test('the status names where a value came from, never the value', () {
      config.applyFileText('{"ownerKey":"0x0101010101010101010101010101010101010101010101010101010101010101"}');
      final String status = config.credentialsStatus();
      expect(status, contains('ownerKey: set (e2e.local.json)'));
      expect(status, isNot(contains('0x0101')));
    });
  });

  group('appearance', () {
    test('each mode gets its own map, and nothing is layered between them', () {
      // `osIsDark` is the ONLY selector now — the example carries no theme choice, because the SDK
      // resolves no theme. Each call targets whichever document the device is asking for.
      config.applyAppearance('{"colorText":"#111111","borderRadius":8}', false);
      config.applyAppearance('{"colorText":"#EEEEEE"}', true);

      expect(config.appearance(false).colorText, '#111111');
      expect(config.appearance(false).borderRadius, 8);

      // Each map is complete on its own: the dark one carries no radius, and it does NOT inherit
      // the light one's. What an absent token falls through to is the SDK's own mode default.
      expect(config.appearance(true).colorText, '#EEEEEE');
      expect(config.appearance(true).borderRadius, isNull);
    });

    test('the device decides, and nothing else can override it', () {
      config.applyAppearance('{"colorText":"#111111"}', false);
      config.applyAppearance('{"colorText":"#EEEEEE"}', true);

      // There is no light/dark/system choice to interpose. This is the property that replaced it:
      // `isDarkMode` is the platform's answer, verbatim.
      expect(config.isDarkMode(true), isTrue);
      expect(config.isDarkMode(false), isFalse);
      expect(config.appearance(true).colorText, '#EEEEEE');
      expect(config.appearance(false).colorText, '#111111');
    });

    test('reset clears both maps', () {
      config.applyAppearance('{"colorText":"#111111"}', false);
      config.applyAppearance('{"colorText":"#EEEEEE"}', true);
      config.resetAppearance();
      expect(config.appearance(false).colorText, isNull);
      expect(config.appearance(true).colorText, isNull);
    });
  });
}
