/// FOR TESTING ONLY: signs with a test user's exported key, held in memory. A real app signs in the
/// user's wallet. The example's one signing file; only the example depends on `pointycastle`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// A secp256k1 key that signs EIP-191 personal messages. FOR TESTING ONLY.
class TestSigner {
  TestSigner._(this._d, this.address);

  /// Parses a 32-byte hex key, with or without `0x`. Throws [FormatException] without quoting it.
  factory TestSigner.fromHex(String hex) {
    final Uint8List bytes;
    try {
      bytes = _hexDecode(hex.trim());
    } on FormatException {
      throw const FormatException('ownerKey is not hex');
    }
    if (bytes.length != 32) throw const FormatException('ownerKey must be 32 bytes of hex');
    final BigInt d = _toBigInt(bytes);
    if (d == BigInt.zero || d >= _curve.n) throw const FormatException('ownerKey is not a valid secp256k1 key');
    final Uint8List point = (_curve.G * d)!.getEncoded(false);
    final Uint8List hash = keccak256(point.sublist(1));
    return TestSigner._(d, toChecksumAddress(_hexEncode(hash.sublist(12))));
  }

  final BigInt _d;

  /// The key's address, in its EIP-55 form.
  final String address;

  /// EIP-191 over UTF-8 [message]: the login signature `POST /api/v1/user/authorize` checks.
  Uint8List signPersonalMessage(String message) => _signPersonal(utf8.encode(message));

  /// EIP-191 over the raw 32 bytes of [hash], answered as 65 bytes `r ‖ s ‖ v` with v 27 or 28: what
  /// the SDK's `Trade` signer answers for a UserOp hash.
  Uint8List signPersonalHash(Uint8List hash) {
    if (hash.length != 32) throw ArgumentError.value(hash.length, 'hash', 'must be 32 bytes');
    return _signPersonal(hash);
  }

  Uint8List _signPersonal(List<int> payload) {
    final Uint8List digest = keccak256(<int>[
      ...utf8.encode('\x19Ethereum Signed Message:\n${payload.length}'),
      ...payload,
    ]);
    final ECDSASigner signer = ECDSASigner(null, HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(_d, _curve)));
    final ECSignature signature = (signer.generateSignature(digest) as ECSignature).normalize(_curve);
    final int recovery = _recoveryId(digest, signature);
    return Uint8List.fromList(<int>[..._toBytes32(signature.r), ..._toBytes32(signature.s), 27 + recovery]);
  }

  /// The y parity that recovers this key from [signature]. `r` below n always, so 0 or 1.
  int _recoveryId(Uint8List digest, ECSignature signature) {
    final ECPoint own = (_curve.G * _d)!;
    final BigInt n = _curve.n;
    final BigInt e = _toBigInt(digest);
    final BigInt rInverse = signature.r.modInverse(n);
    for (int recovery = 0; recovery < 2; recovery++) {
      final ECPoint? r = _curve.curve.decodePoint(<int>[0x02 + recovery, ..._toBytes32(signature.r)]);
      if (r == null) continue;
      final ECPoint? candidate = ((r * signature.s)! + (_curve.G * ((n - e) % n)))! * rInverse;
      if (candidate == own) return recovery;
    }
    throw StateError('no recovery id matches the key');
  }
}

final ECDomainParameters _curve = ECCurve_secp256k1();

/// keccak256, as Ethereum uses it.
Uint8List keccak256(List<int> data) => KeccakDigest(256).process(Uint8List.fromList(data));

/// EIP-55 form of a 20-byte address given as 40 hex characters, with or without `0x`.
String toChecksumAddress(String hex) {
  final String lower = (hex.startsWith('0x') ? hex.substring(2) : hex).toLowerCase();
  final String hash = _hexEncode(keccak256(ascii.encode(lower)));
  final StringBuffer out = StringBuffer('0x');
  for (int i = 0; i < lower.length; i++) {
    out.write(int.parse(hash[i], radix: 16) >= 8 ? lower[i].toUpperCase() : lower[i]);
  }
  return out.toString();
}

/// `0x`-prefixed lower-case hex.
String hexOf(List<int> bytes) => '0x${_hexEncode(bytes)}';

/// Bytes from hex, with or without `0x`. Throws [FormatException] without quoting the input.
Uint8List hexToBytes(String hex) => _hexDecode(hex.trim());

String _hexEncode(List<int> bytes) => bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _hexDecode(String hex) {
  final String body = hex.startsWith('0x') || hex.startsWith('0X') ? hex.substring(2) : hex;
  if (body.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(body)) {
    throw const FormatException('not hex');
  }
  return Uint8List.fromList(<int>[
    for (int i = 0; i < body.length; i += 2) int.parse(body.substring(i, i + 2), radix: 16),
  ]);
}

BigInt _toBigInt(List<int> bytes) => bytes.fold(BigInt.zero, (BigInt acc, int b) => (acc << 8) | BigInt.from(b));

Uint8List _toBytes32(BigInt value) {
  final Uint8List out = Uint8List(32);
  BigInt rest = value;
  for (int i = 31; i >= 0; i--) {
    out[i] = (rest & BigInt.from(0xff)).toInt();
    rest = rest >> 8;
  }
  return out;
}
