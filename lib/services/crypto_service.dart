import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'interfaces.dart';
import '../utils/encoding.dart';
import 'package:cryptography/cryptography.dart' as cryptography;

class CryptoService implements ICryptoService {
  static const int _iterations = 600000;
  static const int _saltLength = 16;
  static const int _ivLength = 12;

  final _algorithm = AesGcm.with256bits();
  final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  @override
  Future<Uint8List> generateSalt() async {
    final secretKey = cryptography.SecretKeyData.random(length: _saltLength);
    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }

  @override
  Future<SecretKey> deriveKey(String password, Uint8List salt) async {
    final secretKey = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    return secretKey;
  }

  @override
  Future<Map<String, dynamic>> encrypt(dynamic key, String plaintext) async {
    if (key is! SecretKey) throw ArgumentError('Key must be a SecretKey');

    final data = stringToBytes(plaintext);
    final secretBox = await _algorithm.encrypt(
      data,
      secretKey: key,
      nonce: null, // Random nonce (IV) generated automatically by AesGcm
    );

    return {
      'iv': Uint8List.fromList(secretBox.nonce),
      'cipherText': Uint8List.fromList(secretBox.cipherText),
    };
  }

  @override
  Future<String> decrypt(
      dynamic key, Uint8List iv, Uint8List cipherText) async {
    if (key is! SecretKey) throw ArgumentError('Key must be a SecretKey');

    return bytesToString(await decryptBinary(key, iv, cipherText));
  }

  @override
  Future<Map<String, dynamic>> encryptBinary(
      dynamic key, Uint8List data) async {
    if (key is! SecretKey) throw ArgumentError('Key must be a SecretKey');

    // Generate random IV
    final nonce = cryptography.SecretKeyData.random(length: _ivLength);
    final nonceBytes = await nonce.extractBytes();

    final secretBox = await _algorithm.encrypt(
      data,
      secretKey: key,
      nonce: nonceBytes,
    );

    // Web Crypto API format: Ciphertext + Tag
    final combined =
        Uint8List(secretBox.cipherText.length + secretBox.mac.bytes.length);
    combined.setAll(0, secretBox.cipherText);
    combined.setAll(secretBox.cipherText.length, secretBox.mac.bytes);

    return {
      'iv': Uint8List.fromList(nonceBytes),
      'encrypted': combined,
    };
  }

  @override
  Future<Uint8List> decryptBinary(
      dynamic key, Uint8List iv, Uint8List encrypted) async {
    if (key is! SecretKey) throw ArgumentError('Key must be a SecretKey');

    // Extract MAC tag (last 16 bytes for AES-GCM usually)
    if (encrypted.length < 16) throw Exception('Data too short');

    final macLength = 16;
    final cipherTextLength = encrypted.length - macLength;

    final cipherTextBytes = encrypted.sublist(0, cipherTextLength);
    final macBytes = encrypted.sublist(cipherTextLength);

    final secretBox = SecretBox(
      cipherTextBytes,
      nonce: iv,
      mac: Mac(macBytes),
    );

    final decrypted = await _algorithm.decrypt(
      secretBox,
      secretKey: key,
    );

    return Uint8List.fromList(decrypted);
  }

  Future<SecretKey> generateDMK() async {
    return await _algorithm.newSecretKey();
  }

  Future<Map<String, dynamic>> wrapDMK(SecretKey kek, SecretKey dmk) async {
    final dmkBytes = await dmk.extractBytes();
    final result = await encryptBinary(kek, Uint8List.fromList(dmkBytes));

    return {
      'iv': result['iv'],
      'wrappedKey': uint8ArrayToBase64(result['encrypted']),
    };
  }

  Future<SecretKey> unwrapDMK(
      SecretKey kek, Uint8List iv, String wrappedKeyBase64) async {
    final wrappedBytes = base64ToUint8Array(wrappedKeyBase64);
    final dmkBytes = await decryptBinary(kek, iv, wrappedBytes);
    return SecretKey(dmkBytes);
  }

  Future<String> computeHash(Uint8List data) async {
    final hashAlgorithm = Sha256();
    final hash = await hashAlgorithm.hash(data);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }
}
