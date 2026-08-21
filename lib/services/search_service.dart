import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:krag_app/constants/index.dart' as constants;
import 'package:krag_app/utils/logger.dart';
import '../utils/encoding.dart';
import 'crypto_service.dart';
import 'session_service.dart';
import 'persistence_service.dart';

class SearchService {
  // Inverted Index: Token -> Set of Note IDs
  Map<String, Set<String>> _index = {};
  // Store document metadata if needed for scoring, but simple set is fine for MVP

  Timer? _autoSaveTimer;
  bool _isInitialized = false;
  static const int _autoSaveDebounceMs = 5000;

  final CryptoService _cryptoService = CryptoService();
  final SessionService _sessionService = SessionService();

  Future<void> initialize() async {
    if (_isInitialized) return;

    final dmk = await _sessionService.loadDMKFromSession();
    if (dmk != null) {
      await loadIndex(key: dmk as SecretKey);
    }
    _isInitialized = true;
  }

  Future<SecretKey> _getDMK() async {
    final dmk = await _sessionService.loadDMKFromSession();
    if (dmk == null) {
      throw Exception('DMK not available. User must be authenticated.');
    }
    return dmk as SecretKey;
  }

  /// Tokenizes text into searchable terms
  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(
            RegExp(r'[^\w\s#@]'), '') // Remove punctuation except # and @
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  Future<void> indexNote(String noteId, String content,
      {List<String> tags = const [], List<String> labels = const []}) async {
    // Remove existing entries for this noteId to ensure clean update
    await removeNote(noteId, scheduleSave: false);

    final textToTokenize =
        '$content ${tags.map((t) => '#$t').join(' ')} ${labels.map((l) => '@$l').join(' ')}';
    final tokens = _tokenize(textToTokenize);

    for (final token in tokens) {
      if (!_index.containsKey(token)) {
        _index[token] = {};
      }
      _index[token]!.add(noteId);
    }

    _scheduleAutoSave();
  }

  Future<void> removeNote(String noteId, {bool scheduleSave = true}) async {
    for (final token in _index.keys) {
      _index[token]?.remove(noteId);
    }
    // Cleanup empty tokens
    _index.removeWhere((key, value) => value.isEmpty);

    if (scheduleSave) {
      _scheduleAutoSave();
    }
  }

  Future<List<String>> search(String query) async {
    final tokens = _tokenize(query);
    if (tokens.isEmpty) return [];

    Set<String>? resultIds;

    for (final token in tokens) {
      // Simple partial match search
      final matchingTokens = _index.keys.where((k) => k.contains(token));

      final currentTokenMatches = <String>{};
      for (final match in matchingTokens) {
        if (_index[match] != null) {
          currentTokenMatches.addAll(_index[match]!);
        }
      }

      if (resultIds == null) {
        resultIds = currentTokenMatches;
      } else {
        // Intersection for AND behavior
        resultIds = resultIds.intersection(currentTokenMatches);
      }

      if (resultIds.isEmpty) return [];
    }

    return resultIds?.toList() ?? [];
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer =
        Timer(const Duration(milliseconds: _autoSaveDebounceMs), () {
      saveIndex();
    });
  }

  Future<void> forceSave() async {
    _autoSaveTimer?.cancel();
    await saveIndex();
  }

  Future<void> saveIndex({SecretKey? key}) async {
    try {
      final dmk = key ?? await _getDMK();

      // Convert Set to List for JSON serialization
      final serializableIndex = _index.map((k, v) => MapEntry(k, v.toList()));
      final jsonString = jsonEncode(serializableIndex);

      final encrypted = await _cryptoService.encrypt(dmk, jsonString);

      // Store as map compatible with Hive
      await PersistenceService.save(constants.StorageKeys.searchIndex, {
        'iv': uint8ArrayToBase64(encrypted['iv'] as Uint8List),
        'cipherText': uint8ArrayToBase64(encrypted['cipherText'] as Uint8List),
      });
    } catch (e) {
      KragLogger.error(
          LogDomain.search, 'SearchService: Failed to save index: $e');
    }
  }

  Future<void> loadIndex({SecretKey? key}) async {
    try {
      final encryptedData =
          await PersistenceService.load(constants.StorageKeys.searchIndex);
      if (encryptedData == null) return;

      final dmk = key ?? await _getDMK();

      // Handle Hive returning Map<dynamic, dynamic>
      final map = Map<String, dynamic>.from(encryptedData as Map);

      final iv = base64ToUint8Array(map['iv'] as String);
      final cipherText = base64ToUint8Array(map['cipherText'] as String);

      final jsonString = await _cryptoService.decrypt(dmk, iv, cipherText);
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;

      // Reconstruct index
      _index = decoded
          .map((k, v) => MapEntry(k, (v as List).cast<String>().toSet()));
    } catch (e) {
      KragLogger.error(
          LogDomain.search, 'SearchService: Failed to load index: $e');
      // If decryption fails, we start with empty index
      _index = {};
    }
  }
}
