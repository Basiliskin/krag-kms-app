import '../utils/encoding.dart';
import 'crypto_service.dart';
import 'interfaces.dart';

class BlockEncryptionService {
  final CryptoService _cryptoService;
  final ISessionService _sessionService;

  BlockEncryptionService(this._cryptoService, this._sessionService);

  Future<Map<String, String>> encryptBlockContent(String content) async {
    final dmk = await _sessionService.loadDMKFromSession();
    if (dmk == null) {
      throw Exception(
          'Data Master Key not available. User must be authenticated.');
    }

    final contentBytes = stringToBytes(content);
    final result = await _cryptoService.encryptBinary(dmk, contentBytes);

    return {
      'iv': uint8ArrayToBase64(result['iv']),
      'encryptedData': uint8ArrayToBase64(result['encrypted']),
    };
  }

  Future<String> decryptBlockContent(
      String ivBase64, String encryptedDataBase64) async {
    final dmk = await _sessionService.loadDMKFromSession();
    if (dmk == null) {
      throw Exception(
          'Data Master Key not available. User must be authenticated.');
    }

    final ivBytes = base64ToUint8Array(ivBase64);
    final encryptedBytes = base64ToUint8Array(encryptedDataBase64);

    final decrypted =
        await _cryptoService.decryptBinary(dmk, ivBytes, encryptedBytes);
    return bytesToString(decrypted);
  }

  static bool isBlockLocked(Map<String, dynamic> attrs) {
    return attrs['locked'] == true &&
        attrs['encryptedData'] != null &&
        attrs['iv'] != null;
  }
}
