import 'dart:typed_data';
import '../types/index.dart';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';

abstract class IGoogleAuthService {
  Future<String> getAuthUrl(String clientId, String redirectUri);
  Future<void> handleCallback(String code, String clientId, String redirectUri);
  Future<void> signIn();
  Future<void> signOut();
  bool isAuthenticated();
  String? getToken();
  Future<void> refreshAccessToken();
  void clearTokens();
  Future<http.Client?> getAuthenticatedClient();
  Future<void> requestScopesIfNeeded();
}

abstract class IDriveAdapter {
  Future<bool> verifyRootFolder(String path);
  Future<String> initializeRootFolder(String folderName);
  Future<String> ensureFolder(String folderName, String parentId);
  Future<String> getFolderIdByPath(String path);
  Future<List<DriveFileMetadata>> listFiles(
    String parentIdOrPath, {
    bool useCache = true,
  });
  Future<String> ensureFile(
    String fileName,
    Uint8List content,
    String mimeType,
    String parentIdOrPath, {
    int? version,
  });
  Future<String> createFile(
    String name,
    Uint8List content,
    String mimeType,
    String parentIdOrPath, {
    int? version,
  });
  Future<void> updateFile(
    String fileId,
    Uint8List content, {
    int? version,
  });
  Future<Uint8List> getFile(String fileId);
  Future<DriveFileMetadata> getFileMetadata(String fileId);
  Future<void> trashFile(String fileId);
  Future<List<DriveFileMetadata>> checkForChanges(
    String parentIdOrPath,
    String modifiedAfter,
  );
}

abstract class ISessionService {
  Future<void> saveDMKToSession(dynamic dmk);
  Future<Map<String, dynamic>?> loadDMKFromSession();
  Future<void> clearSession();
}

abstract class IVaultKeyService {
  Future<bool> vaultExists();
  Future<Uint8List?> getSalt();
  Future<Map<String, dynamic>> initializeVault(String password);
  Future<Map<String, dynamic>> unlockVault(
    String password, {
    Uint8List? storedSalt,
  });
}

abstract class ICryptoService {
  Future<Uint8List> generateSalt();
  Future<SecretKey> deriveKey(String password, Uint8List salt);
  Future<Map<String, dynamic>> encrypt(dynamic key, String plaintext);
  Future<String> decrypt(dynamic key, Uint8List iv, Uint8List cipherText);
  Future<Map<String, dynamic>> encryptBinary(dynamic key, Uint8List data);
  Future<Uint8List> decryptBinary(
    dynamic key,
    Uint8List iv,
    Uint8List encrypted,
  );
}

abstract class IIndexManager {
  void initialize(SecretKey dataMasterKey);
  Future<List<dynamic>> loadIndex({
    bool checkMismatch = true,
    bool forceRemote = false,
  });
  Future<void> saveIndex(List<dynamic> index);
  Future<void> updateIndexEntry(Note note, {String? driveId});
  Future<List<dynamic>> rebuildIndex();
  Future<List<dynamic>> reconcileIndex(
    List<dynamic> currentIndex,
    List<DriveFileMetadata> physicalFiles,
  );
  Future<(List<Map<String, dynamic>>, List<String>)> pruneGhostEntries(
    List<dynamic> currentIndex,
    List<DriveFileMetadata> physicalFiles,
  );
  Map<String, dynamic>? getIndexEntry(List<dynamic> index, String noteId);
  Future<void> removeIndexEntry(String noteId);
  Future<void> clearCache();
}

class HydrationCheckResult {
  final String noteId;
  final bool needsHydration;
  final HydrationReason? reason;
  final int? localVersion;
  final int? indexVersion;
  HydrationCheckResult({
    required this.noteId,
    required this.needsHydration,
    this.reason,
    this.localVersion,
    this.indexVersion,
  });
}

enum HydrationReason {
  missingFromCache,
  versionMismatch,
  emptyContent,
  corruptedCache,
}

abstract class IFileHydrationService {
  Future<HydrationCheckResult> checkNeedHydration(
    String noteId,
    Map<String, dynamic> indexEntry,
  );
  Future<Note?> hydrateNote(String noteId, Map<String, dynamic> indexEntry);
  Future<Map<String, Note?>> hydrateNotes(
    List<String> noteIds,
    List<dynamic> index,
  );
  Future<List<String>> verifyAndHydrateAll(List<dynamic> index);
  Future<bool> hasLocalCache(String noteId);
  Future<Uint8List?> getCachedData(String noteId);
  Future<void> clearCache(String noteId);
}

class OrphanReconciliationResult {
  final String noteId;
  final OrphanAction action;
  final String? driveId;
  final Note? restoredNote;
  final String? reason;
  OrphanReconciliationResult({
    required this.noteId,
    required this.action,
    this.driveId,
    this.restoredNote,
    this.reason,
  });
}

enum OrphanAction {
  restored,
  deleted,
  skipped,
  error,
}

abstract class IOrphanReconciliationService {
  Future<List<String>> findOrphanFiles(List<dynamic> index);
  Future<OrphanReconciliationResult> reconcileOrphan(
    String noteId,
    List<dynamic> index,
  );
  Future<Map<String, OrphanReconciliationResult>> reconcileAllOrphans(
    List<dynamic> index,
  );
  Future<OrphanReconciliationSummary> performCleanup(List<dynamic> index);
}

class OrphanReconciliationSummary {
  final int totalOrphans;
  final int restored;
  final int deleted;
  final int skipped;
  final int errors;
  final List<String> restoredIds;
  final List<String> deletedIds;
  OrphanReconciliationSummary({
    required this.totalOrphans,
    required this.restored,
    required this.deleted,
    required this.skipped,
    required this.errors,
    required this.restoredIds,
    required this.deletedIds,
  });
  @override
  String toString() {
    return 'OrphanReconciliation:$totalOrphans found,'
        '$restored restored,$deleted deleted,$skipped skipped,$errors errors';
  }
}
