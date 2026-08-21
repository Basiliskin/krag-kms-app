import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:krag_app/utils/logger.dart';
import '../types/index.dart';
import 'interfaces.dart';

class FirestoreAdapter implements IDriveAdapter {
  final FirebaseFirestore _firestore;
  final String _userId;

  FirestoreAdapter(this._firestore, this._userId);

  /// Maps legacy folder-based paths to valid Firestore subcollection names.
  /// Firestore requires alternating collection/document segments.
  /// Legacy: users/{id}/krag-vault/config (Invalid collection path - 4 segments)
  /// New: users/{id}/vault-config (Valid collection path - 3 segments)
  String _mapPath(String path) {
    final normalized = path.trim().replaceAll(RegExp(r'^/+|/+$'), '');

    // If it's already a mapped subcollection or a full path, don't re-map
    if (normalized.startsWith('vault-') || normalized.startsWith('users/')) {
      return normalized;
    }

    String mapped;
    if (normalized == 'krag-vault/config' || normalized == 'config') {
      mapped = 'vault-config';
    } else if (normalized == 'krag-vault/docs' || normalized == 'docs') {
      mapped = 'vault-docs';
    } else if (normalized.startsWith('krag-vault/config/')) {
      mapped = normalized.replaceFirst('krag-vault/config/', 'vault-config/');
    } else if (normalized.startsWith('krag-vault/docs/')) {
      mapped = normalized.replaceFirst('krag-vault/docs/', 'vault-docs/');
    } else if (normalized == 'krag-vault' || normalized.isEmpty) {
      mapped = 'vault-root';
    } else {
      mapped = normalized;
    }

    if (mapped != normalized) {
      KragLogger.info(
        LogDomain.sync,
        'Firestore: Path mapping applied: "$normalized" -> "$mapped"',
      );
    }
    return mapped;
  }

  /// Returns a full Firestore path scoped to the current user.
  String _getUserPath(String path) {
    final normalized = path.trim().replaceAll(RegExp(r'^/+|/+$'), '');

    // If it's already a full user-scoped path, return as is
    if (normalized.startsWith('users/$_userId/')) {
      return normalized;
    }

    // Map the relative path and then scope it
    return 'users/$_userId/${_mapPath(normalized)}';
  }

  @override
  Future<bool> verifyRootFolder(String path) async {
    try {
      final userPath = _getUserPath(path);
      // In Firestore, we verify a collection by attempting to access it.
      // Collection paths must have an odd number of segments.
      await _firestore.collection(userPath).limit(1).get();
      KragLogger.info(
        LogDomain.sync,
        'Firestore: Root collection verified: $userPath',
      );
      return true;
    } catch (e) {
      KragLogger.error(
        LogDomain.sync,
        'Firestore: Root collection verification failed for path: $path',
        e,
      );
      return false;
    }
  }

  @override
  Future<String> initializeRootFolder(String folderName) async {
    final userPath = _getUserPath(folderName);
    KragLogger.info(
      LogDomain.sync,
      'Firestore: Initializing root collection: $userPath',
    );
    // Return the original folder name to maintain compatibility with DriveSyncService
    return folderName;
  }

  @override
  Future<String> ensureFolder(String folderName, String parentId) async {
    final path = '$parentId/$folderName';
    final userPath = _getUserPath(path);
    KragLogger.info(
      LogDomain.sync,
      'Firestore: Ensuring collection path: $userPath',
    );
    return path;
  }

  @override
  Future<String> getFolderIdByPath(String path) async {
    // In FirestoreAdapter, the path itself acts as the ID/Reference
    return path;
  }

  @override
  Future<List<DriveFileMetadata>> listFiles(
    String parentIdOrPath, {
    bool useCache = true,
  }) async {
    final path = _getUserPath(parentIdOrPath);
    try {
      KragLogger.info(
        LogDomain.sync,
        'Firestore: Listing documents in: $path',
      );

      final querySnapshot = await _firestore
          .collection(path)
          .where('trashed', isNotEqualTo: true)
          .get(GetOptions(
            source: useCache ? Source.serverAndCache : Source.server,
          ));

      final results = querySnapshot.docs.map((doc) {
        return _mapDocToMetadata(doc, path);
      }).toList();

      KragLogger.info(
        LogDomain.sync,
        'Firestore: Listed ${results.length} documents from: $path',
      );
      return results;
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Firestore: Failed to list documents in $path',
        e,
        stack,
      );
      if (e.toString().contains('permission-denied') ||
          e.toString().contains('PERMISSION_DENIED')) {
        return [];
      }
      rethrow;
    }
  }

  @override
  Future<String> ensureFile(
    String fileName,
    Uint8List content,
    String mimeType,
    String parentIdOrPath, {
    int? version,
  }) async {
    final userPath = _getUserPath(parentIdOrPath);
    final docId = fileName.replaceAll('.bin', '');
    final docRef = _firestore.collection(userPath).doc(docId);

    final doc = await docRef.get();
    if (doc.exists) {
      await updateFile(docRef.path, content, version: version);
      return docRef.path;
    } else {
      return await createFile(
        fileName,
        content,
        mimeType,
        parentIdOrPath,
        version: version,
      );
    }
  }

  @override
  Future<String> createFile(
    String name,
    Uint8List content,
    String mimeType,
    String parentIdOrPath, {
    int? version,
  }) async {
    final userPath = _getUserPath(parentIdOrPath);
    final docId = name.replaceAll('.bin', '');
    final docRef = _firestore.collection(userPath).doc(docId);

    final data = {
      'name': name,
      'content': Blob(content),
      'mimeType': mimeType,
      '_v': version ?? 0,
      'trashed': false,
      'createdTime': FieldValue.serverTimestamp(),
      'modifiedTime': FieldValue.serverTimestamp(),
    };

    KragLogger.info(
      LogDomain.sync,
      'Firestore: Creating document: ${docRef.path}',
    );
    await docRef.set(data);
    return docRef.path;
  }

  @override
  Future<void> updateFile(
    String fileId,
    Uint8List content, {
    int? version,
  }) async {
    final docRef = _getDocRef(fileId);
    final data = <String, dynamic>{
      'content': Blob(content),
      'modifiedTime': FieldValue.serverTimestamp(),
    };
    if (version != null) {
      data['_v'] = version;
    }

    KragLogger.info(
        LogDomain.sync, 'Firestore: Updating document: ${docRef.path}');
    await docRef.update(data);
  }

  @override
  Future<Uint8List> getFile(String fileId) async {
    try {
      final docRef = _getDocRef(fileId);
      final doc = await docRef.get();
      if (!doc.exists) {
        throw Exception('Firestore: Document not found: $fileId');
      }
      final data = doc.data() as Map<String, dynamic>;
      final blob = data['content'] as Blob?;
      return blob?.bytes ?? Uint8List(0);
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'Firestore: Failed to get file content: $fileId',
        e,
        stack,
      );
      rethrow;
    }
  }

  @override
  Future<DriveFileMetadata> getFileMetadata(String fileId) async {
    final docRef = _getDocRef(fileId);
    final doc = await docRef.get();
    if (!doc.exists) {
      throw Exception('Firestore: Document not found: $fileId');
    }
    final pathSegments = doc.reference.path.split('/');
    final parentPath = pathSegments.take(pathSegments.length - 1).join('/');
    return _mapDocToMetadata(doc, parentPath);
  }

  @override
  Future<void> trashFile(String fileId) async {
    final docRef = _getDocRef(fileId);
    KragLogger.info(
        LogDomain.sync, 'Firestore: Trashing document: ${docRef.path}');
    await docRef.update({
      'trashed': true,
      'modifiedTime': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<DriveFileMetadata>> checkForChanges(
    String parentIdOrPath,
    String modifiedAfter,
  ) async {
    final userPath = _getUserPath(parentIdOrPath);
    final dt = DateTime.parse(modifiedAfter);
    final timestamp = Timestamp.fromDate(dt);

    final querySnapshot = await _firestore
        .collection(userPath)
        .where('modifiedTime', isGreaterThan: timestamp)
        .where('trashed', isNotEqualTo: true)
        .get();

    return querySnapshot.docs.map((doc) {
      return _mapDocToMetadata(doc, userPath);
    }).toList();
  }

  DocumentReference _getDocRef(String fileId) {
    final userScopedPath = _getUserPath(fileId);
    final segments = userScopedPath.split('/');

    // Document paths must have an even number of segments (e.g., users/id/coll/doc)
    if (segments.length % 2 == 0) {
      return _firestore.doc(userScopedPath);
    }

    // If it's an odd number of segments, it's likely a raw ID or a collection path.
    // We default to the vault-docs subcollection for raw IDs.
    if (!fileId.contains('/')) {
      final fallbackPath = _getUserPath('krag-vault/docs/$fileId');
      return _firestore.doc(fallbackPath);
    }

    throw Exception(
        'Invalid Firestore document path (odd segments): $userScopedPath');
  }

  DriveFileMetadata _mapDocToMetadata(
    DocumentSnapshot doc,
    String parentPath,
  ) {
    final data = doc.data() as Map<String, dynamic>;
    final createdTime =
        (data['createdTime'] as Timestamp?)?.toDate() ?? DateTime.now();
    final modifiedTime =
        (data['modifiedTime'] as Timestamp?)?.toDate() ?? DateTime.now();

    return DriveFileMetadata(
      id: doc.reference.path,
      name: data['name'] as String? ?? doc.id,
      createdTime: createdTime.toIso8601String(),
      modifiedTime: modifiedTime.toIso8601String(),
      v: data['_v'] as int?,
    );
  }
}
