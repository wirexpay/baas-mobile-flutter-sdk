/// The Trade tab's one `WirexTrade`: rebuilt, the old one disposed, when the environment, the chain or
/// the key's address changes. A fake stands in for the plugin, so nothing crosses a channel.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wirex_mobile_sdk/wirex_mobile_sdk.dart';
import 'package:wirex_mobile_sdk_example/live_config.dart';
import 'package:wirex_mobile_sdk_example/test_signer.dart';
import 'package:wirex_mobile_sdk_example/trade_session.dart';

// The contract's synthetic test keys; both hold nothing.
const String _key1 = '0x0101010101010101010101010101010101010101010101010101010101010101';
const String _key2 = '0x0202020202020202020202020202020202020202020202020202020202020202';

class _FakeTrade implements WirexTrade {
  _FakeTrade(this.testMode, this.chainId, this.address);
  final bool testMode;
  final String chainId;
  final String address;
  bool disposed = false;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final LiveConfig config = LiveConfig.instance;
  final List<_FakeTrade> made = <_FakeTrade>[];

  TradeSession session() => TradeSession(create: ({
        required bool testMode,
        required String chainId,
        required WirexTradeTokenProvider tokenProvider,
        required WirexTradeSigner signer,
      }) async {
        final _FakeTrade trade = _FakeTrade(testMode, chainId, signer.address);
        made.add(trade);
        return trade;
      });

  setUp(() {
    made.clear();
    config.resetCredentials();
    config.clearFileValues();
    config.applyCredentials(jsonEncode(<String, String>{'ownerKey': _key1, 'chainId': '8453', 'environment': 'production'}));
  });

  test('builds one trade and keeps it while the config holds', () async {
    final TradeSession trades = session();
    final WirexTrade first = await trades.current();
    expect(await trades.current(), same(first));
    expect(made, hasLength(1));
    expect(made.single.testMode, isFalse);
    expect(made.single.address, '0x1a642f0E3c3aF545E7AcBD38b07251B3990914F1');
  });

  test('rebuilds, disposing the old one, on a new environment, chain or key', () async {
    final TradeSession trades = session();
    await trades.current();
    config.setCredential('environment', 'test');
    await trades.current();
    config.setCredential('chainId', '5042');
    await trades.current();
    config.setCredential('ownerKey', _key2);
    await trades.current();
    expect(made, hasLength(4));
    expect(made.take(3).every((_FakeTrade trade) => trade.disposed), isTrue);
    expect(made.last.disposed, isFalse);
    expect(made[1].testMode, isTrue);
    expect(made[2].chainId, '5042');
    expect(made.last.address, '0x5050A4F4b3f9338C3472dcC01A87C76A144b3c9c');
  });

  test('a company change keeps the trade: the login reads it live', () async {
    final TradeSession trades = session();
    await trades.current();
    config.setCredential('companyId', '11111111-1111-1111-1111-111111111111');
    await trades.current();
    expect(made, hasLength(1));
  });

  test('names the missing or wrong field instead of building', () async {
    config.setCredential('ownerKey', '');
    await expectLater(session().current(), throwsA(isA<TradeUnavailable>()));
    config.setCredential('ownerKey', '0x1234');
    await expectLater(session().current(), throwsA(isA<TradeUnavailable>()));
    expect(made, isEmpty);
  });

  test('dispose disposes the trade', () async {
    final TradeSession trades = session();
    await trades.current();
    await trades.dispose();
    expect(made.single.disposed, isTrue);
  });

  test('the signer answers the SDK hex in, hex out, as viem signs', () async {
    final ExampleTradeSigner signer = ExampleTradeSigner(TestSigner.fromHex(_key1));
    expect(signer.address, '0x1a642f0E3c3aF545E7AcBD38b07251B3990914F1');
    expect(
      await signer.signPersonal('0x${'ab' * 32}'),
      '0x7a74165fa3417ce8bcbf5e37198bc716d10a62bdff3a362e3ee621894cced81319a4190af9718ede6726a4c7e7dc78749c0b014d99e6e0e8042a0748c575c30e1c',
    );
    await expectLater(signer.signPersonal('0x1234'), throwsArgumentError);
    await expectLater(signer.signPersonal('not hex'), throwsFormatException);
  });
}
