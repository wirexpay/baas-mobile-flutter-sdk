/// The test signer against viem's `privateKeyToAccount` and `signMessage`, for the contract's two
/// synthetic test keys (`contract/vectors/trade/signature.json`). Both keys hold nothing.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wirex_mobile_sdk_example/test_signer.dart';

class _Vector {
  const _Vector(this.key, this.address, this.loginSignature, this.hashSignature);
  final String key;
  final String address;
  final String loginSignature;
  final String hashSignature;
}

const String _company = '11111111-1111-1111-1111-111111111111';

const List<_Vector> _vectors = <_Vector>[
  _Vector(
    '0x0101010101010101010101010101010101010101010101010101010101010101',
    '0x1a642f0E3c3aF545E7AcBD38b07251B3990914F1',
    '0x896151005f262445a45c3de1326dd86e081f545b720bb1b7ac2d5cec2694539a6e9eb858438dcd27505a85302e1af9b4bd0536c4f25643a81f0a76b477bb3c7e1b',
    '0x7a74165fa3417ce8bcbf5e37198bc716d10a62bdff3a362e3ee621894cced81319a4190af9718ede6726a4c7e7dc78749c0b014d99e6e0e8042a0748c575c30e1c',
  ),
  _Vector(
    '0x0202020202020202020202020202020202020202020202020202020202020202',
    '0x5050A4F4b3f9338C3472dcC01A87C76A144b3c9c',
    '0xa4b2478430cf7d1d24a4b4f16fee7c762e64cd660fb5a39b80cae1255c52b0164aaeee50602551411f093319c5e95e149c7b770ed1b8637a522879e5cf3c14d51c',
    '0x3c9ccab67ef465fe56554d5da44ab7f4e3d5ea846dd30f05a9cd5df5387b63904c3ad4d8307fc39c75efdd4bae108d7b0c8ae78c180dcd933a32098b5cd6559e1b',
  ),
];

void main() {
  for (final _Vector vector in _vectors) {
    group('test key ${vector.address}', () {
      final TestSigner signer = TestSigner.fromHex(vector.key);

      test('derives the EIP-55 address', () => expect(signer.address, vector.address));

      test('signs the login message as viem does', () {
        final String message = 'I, owner of account ${vector.address} confirm that I request access token '
            'for company $_company on chain 8453 at 1700000000';
        expect(hexOf(signer.signPersonalMessage(message)), vector.loginSignature);
      });

      test('signs a raw 32-byte hash as viem does, 65 bytes with v 27 or 28', () {
        final Uint8List signature = signer.signPersonalHash(Uint8List.fromList(List<int>.filled(32, 0xab)));
        expect(signature.length, 65);
        expect(hexOf(signature), vector.hashSignature);
      });
    });
  }

  test('refuses a key that is not 32 bytes of hex, without quoting it', () {
    expect(() => TestSigner.fromHex('0x1234'), throwsFormatException);
    expect(() => TestSigner.fromHex('zz' * 32), throwsFormatException);
    expect(() => TestSigner.fromHex('00' * 32), throwsFormatException);
  });

  test('refuses a hash that is not 32 bytes', () {
    expect(() => TestSigner.fromHex(_vectors.first.key).signPersonalHash(Uint8List(31)), throwsArgumentError);
  });
}
