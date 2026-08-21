import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:krag_app/utils/logger.dart';
// We use universal_html to safely handle 'window' across platforms,
// or you can use 'dart:html' if your project is web-only.
import 'package:universal_html/html.dart' as html;
import 'interfaces.dart';

class SessionService implements ISessionService {
  static const String _sessionKey = 'krag_vault_session_key';

  // For Mobile: Use SecureStorage to persist significantly longer or strict memory for high security.
  // We'll use SecureStorage here for better UX on mobile restarts.
  final _secureStorage = const FlutterSecureStorage();

  @override
  Future<void> saveDMKToSession(dynamic keyData) async {
    final jsonString = jsonEncode(keyData);

    if (kIsWeb) {
      // WEB: Save to SessionStorage.
      // This survives Page Reload (F5) but is wiped on Tab Close.
      html.window.sessionStorage[_sessionKey] = jsonString;
    } else {
      // MOBILE: Save to Secure Storage
      await _secureStorage.write(key: _sessionKey, value: jsonString);
    }
  }

  @override
  Future<Map<String, dynamic>?> loadDMKFromSession() async {
    String? jsonString;

    if (kIsWeb) {
      jsonString = html.window.sessionStorage[_sessionKey];
    } else {
      jsonString = await _secureStorage.read(key: _sessionKey);
    }

    if (jsonString == null) return null;

    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);

      // Ensure the key bytes are restored as a List<int> for cryptography
      // Depending on how you saved it, you might need to cast specifically
      if (data.containsKey('k') && data['k'] is List) {
        data['k'] = (data['k'] as List).cast<int>();
      }

      return data;
    } catch (e) {
      KragLogger.error(
          LogDomain.general, "SessionService: Error parsing session data: $e");
      await clearSession();
      return null;
    }
  }

  @override
  Future<void> clearSession() async {
    if (kIsWeb) {
      html.window.sessionStorage.remove(_sessionKey);
    } else {
      await _secureStorage.delete(key: _sessionKey);
    }
  }
}
