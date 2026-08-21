import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:krag_app/constants/index.dart' as constants;

import 'interfaces.dart';
import 'google_auth_service.dart';
import '../types/index.dart';
import '../utils/logger.dart';

class DriveAdapter implements IDriveAdapter {
  final GoogleAuthService _authService;

  // Cache keys
  static const String _pathCacheKey = 'drive_folder_path_cache';
  static const String _rootPathKey = 'drive_root_folder_path';
  static const String _folderIdCacheKey = 'drive_folder_id_cache_v2';

  // Cache TTL: 24 hours (in milliseconds)
  static const int _folderCacheTtlMs = 24 * 60 * 60 * 1000;

  // File list cache (in-memory, short-lived)
  final Map<String, _FileListCacheEntry> _fileListCache = {};
  static const int _cacheTtlMs = 30000; // 30 seconds for file lists

  // In-flight request deduplication
  final Map<String, Future<String>> _inFlightFolderRequests = {};
  final Map<String, Future<List<DriveFileMetadata>>> _inFlightListRequests = {};

  DriveAdapter(this._authService);

  Future<drive.DriveApi> _getApi() async {
    final client = await _authService.getAuthenticatedClient();
    if (client == null) throw Exception('Not authenticated with Google Drive');
    return drive.DriveApi(client);
  }

  // ============================================================================
  // FOLDER ID PERSISTENT CACHE METHODS
  // ============================================================================

  /// Get cached folder ID with TTL check
  Future<String?> _getCachedFolderId(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_folderIdCacheKey);

      if (cacheJson == null) return null;

      final cache = jsonDecode(cacheJson) as Map<String, dynamic>;
      final entry = cache[path] as Map<String, dynamic>?;

      if (entry == null) return null;

      final folderId = entry['id'] as String;
      final timestamp = entry['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Check if cache is expired
      if (now - timestamp > _folderCacheTtlMs) {
        KragLogger.info(
          LogDomain.sync,
          'Folder cache expired for path: $path (age: ${((now - timestamp) / 1000 / 60).toStringAsFixed(1)} minutes)',
        );
        return null;
      }

      KragLogger.info(
        LogDomain.sync,
        'Folder cache HIT for path: $path -> $folderId (age: ${((now - timestamp) / 1000 / 60).toStringAsFixed(1)} minutes)',
      );

      return folderId;
    } catch (e) {
      KragLogger.warn(
        LogDomain.sync,
        'Failed to read folder cache for path: $path - $e',
      );
      return null;
    }
  }

  /// Store folder ID with timestamp
  Future<void> _setCachedFolderId(String path, String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_folderIdCacheKey);

      Map<String, dynamic> cache = {};
      if (cacheJson != null) {
        cache = jsonDecode(cacheJson) as Map<String, dynamic>;
      }

      cache[path] = {
        'id': id,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await prefs.setString(_folderIdCacheKey, jsonEncode(cache));

      KragLogger.info(
        LogDomain.sync,
        'Folder cache STORED for path: $path -> $id',
      );
    } catch (e) {
      KragLogger.warn(
        LogDomain.sync,
        'Failed to store folder cache for path: $path - $e',
      );
    }
  }

  /// Verify that a cached folder ID still exists and is valid on Drive
  Future<bool> _verifyCachedFolderId(String id) async {
    try {
      final api = await _getApi();
      final file = await api.files.get(
        id,
        $fields: 'mimeType,trashed',
        supportsAllDrives: true,
      ) as drive.File;

      final isValid = file.mimeType == 'application/vnd.google-apps.folder' &&
          (file.trashed != true);

      KragLogger.info(
        LogDomain.sync,
        'Folder verification for $id: ${isValid ? "VALID" : "INVALID"}',
      );

      return isValid;
    } catch (e) {
      KragLogger.warn(
        LogDomain.sync,
        'Folder verification failed for $id: $e',
      );
      return false;
    }
  }

  /// Invalidate specific folder cache entry
  Future<void> _invalidateFolderCache(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_folderIdCacheKey);

      if (cacheJson == null) return;

      final cache = jsonDecode(cacheJson) as Map<String, dynamic>;
      cache.remove(path);

      await prefs.setString(_folderIdCacheKey, jsonEncode(cache));

      KragLogger.info(
        LogDomain.sync,
        'Folder cache INVALIDATED for path: $path',
      );
    } catch (e) {
      KragLogger.warn(
        LogDomain.sync,
        'Failed to invalidate folder cache for path: $path - $e',
      );
    }
  }

  /// Clear all folder cache entries
  Future<void> _clearFolderCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_folderIdCacheKey);

      KragLogger.info(
        LogDomain.sync,
        'All folder cache CLEARED',
      );
    } catch (e) {
      KragLogger.warn(
        LogDomain.sync,
        'Failed to clear folder cache: $e',
      );
    }
  }

  // ============================================================================
  // PUBLIC INTERFACE METHODS (Optimized with Persistent Cache)
  // ============================================================================

  @override
  Future<bool> verifyRootFolder(String path) async {
    try {
      String? folderId;

      if (path == constants.AppConstants.vaultRootFolderName) {
        // Check persistent cache first
        folderId = await _getCachedFolderId(path);

        // If cache miss, try legacy storage
        if (folderId == null) {
          folderId = await _getStoredRootFolderId();
        }
      } else {
        try {
          folderId = await getFolderIdByPath(path);
        } catch (_) {
          return false;
        }
      }

      if (folderId == null) return false;

      // Verify the folder still exists and is valid
      return await _verifyCachedFolderId(folderId);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> initializeRootFolder(String folderName) async {
    // Check persistent cache first
    final cachedId = await _getCachedFolderId(folderName);

    if (cachedId != null) {
      // Verify cached ID is still valid
      if (await _verifyCachedFolderId(cachedId)) {
        KragLogger.info(
          LogDomain.sync,
          'Root folder loaded from cache: $cachedId',
        );
        return cachedId;
      } else {
        // Cache is stale, invalidate it
        await _invalidateFolderCache(folderName);
      }
    }

    final api = await _getApi();
    final q =
        "name='$folderName' and mimeType='application/vnd.google-apps.folder' and trashed=false";

    KragLogger.info(LogDomain.sync, 'Searching for root folder with query: $q');

    final list = await api.files.list(
      q: q,
      $fields: 'files(id,createdTime)',
      orderBy: 'createdTime',
      includeItemsFromAllDrives: true,
      supportsAllDrives: true,
      spaces: 'drive',
    );

    String id;
    if (list.files?.isNotEmpty ?? false) {
      id = list.files!.first.id!;
      KragLogger.info(LogDomain.sync, 'Found existing root folder: $id');
    } else {
      KragLogger.info(
        LogDomain.sync,
        'Root folder not found. Creating new one: $folderName',
      );
      final f = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';
      id = (await api.files.create(f, $fields: 'id')).id!;
    }

    // Store in both new persistent cache and legacy storage
    await _setCachedFolderId(folderName, id);
    await _storeRootFolderId(id);

    return id;
  }

  @override
  Future<String> ensureFolder(String name, String parentId) async {
    final path = '$parentId/$name'; // Create a composite cache key

    // Check persistent cache first
    final cachedId = await _getCachedFolderId(path);

    if (cachedId != null) {
      // Verify cached ID is still valid
      if (await _verifyCachedFolderId(cachedId)) {
        KragLogger.info(
          LogDomain.sync,
          'Folder loaded from cache: $name -> $cachedId',
        );
        return cachedId;
      } else {
        // Cache is stale, invalidate it
        await _invalidateFolderCache(path);
      }
    }

    final api = await _getApi();
    final q =
        "name='$name' and mimeType='application/vnd.google-apps.folder' and '$parentId' in parents and trashed=false";

    final list = await api.files.list(
      q: q,
      $fields: 'files(id)',
      includeItemsFromAllDrives: true,
      supportsAllDrives: true,
      spaces: 'drive',
    );

    String id;
    if (list.files?.isNotEmpty ?? false) {
      id = list.files!.first.id!;
      KragLogger.info(
        LogDomain.sync,
        'Found existing folder: $name -> $id',
      );
    } else {
      final f = drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId];
      id = (await api.files.create(f, $fields: 'id')).id!;
      KragLogger.info(
        LogDomain.sync,
        'Created new folder: $name -> $id',
      );
    }

    // Store in persistent cache
    await _setCachedFolderId(path, id);

    return id;
  }

  @override
  Future<String> getFolderIdByPath(String path) async {
    final normPath = path.trim().replaceAll(RegExp(r'^/+|/+$'), '');

    // Deduplicate concurrent requests
    if (_inFlightFolderRequests.containsKey(normPath)) {
      KragLogger.info(
        LogDomain.sync,
        'Deduplicating concurrent getFolderIdByPath request for: $normPath',
      );
      return await _inFlightFolderRequests[normPath]!;
    }

    final future = _getFolderIdByPathInternal(normPath);
    _inFlightFolderRequests[normPath] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _inFlightFolderRequests.remove(normPath);
    }
  }

  Future<String> _getFolderIdByPathInternal(String normPath) async {
    // Handle root folder
    if (normPath.isEmpty ||
        normPath == constants.AppConstants.vaultRootFolderName) {
      return await initializeRootFolder(
          constants.AppConstants.vaultRootFolderName);
    }

    // Check persistent cache first
    final cachedId = await _getCachedFolderId(normPath);

    if (cachedId != null) {
      // Verify cached ID is still valid
      if (await _verifyCachedFolderId(cachedId)) {
        return cachedId;
      } else {
        // Cache is stale, invalidate it
        await _invalidateFolderCache(normPath);
      }
    }

    // Initialize root if needed
    final effectiveRootId = await initializeRootFolder(
      constants.AppConstants.vaultRootFolderName,
    );

    // Handle subfolders
    String folderId;
    if (normPath.startsWith('${constants.AppConstants.vaultRootFolderName}/')) {
      final sub = normPath
          .substring(constants.AppConstants.vaultRootFolderName.length + 1);
      folderId = await ensureFolder(sub, effectiveRootId);
    } else {
      folderId = await ensureFolder(normPath, effectiveRootId);
    }

    // Store in persistent cache
    await _setCachedFolderId(normPath, folderId);

    return folderId;
  }

  @override
  Future<List<DriveFileMetadata>> listFiles(
    String parentIdOrPath, {
    bool useCache = true,
  }) async {
    // Check in-memory cache for file lists
    if (useCache) {
      final c = _fileListCache[parentIdOrPath];
      if (c != null &&
          DateTime.now().millisecondsSinceEpoch - c.timestamp < _cacheTtlMs) {
        KragLogger.info(
          LogDomain.sync,
          'Serving listFiles from cache for: $parentIdOrPath',
        );
        return c.files;
      }
    }

    // Deduplicate concurrent list requests
    if (_inFlightListRequests.containsKey(parentIdOrPath)) {
      KragLogger.info(
        LogDomain.sync,
        'Deduplicating concurrent listFiles request for: $parentIdOrPath',
      );
      return await _inFlightListRequests[parentIdOrPath]!;
    }

    final future = _listFilesInternal(parentIdOrPath, useCache: useCache);
    _inFlightListRequests[parentIdOrPath] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _inFlightListRequests.remove(parentIdOrPath);
    }
  }

  Future<List<DriveFileMetadata>> _listFilesInternal(
    String parentIdOrPath, {
    bool useCache = true,
  }) async {
    // Late check for in-memory cache
    if (useCache) {
      final c = _fileListCache[parentIdOrPath];
      if (c != null &&
          DateTime.now().millisecondsSinceEpoch - c.timestamp < _cacheTtlMs) {
        KragLogger.info(
          LogDomain.sync,
          'Serving listFiles from cache (late check) for: $parentIdOrPath',
        );
        return c.files;
      }
    }

    // Resolve parent ID (using persistent cache for folders)
    String pId = parentIdOrPath;
    if (pId.contains('/') ||
        pId == constants.AppConstants.vaultRootFolderName) {
      pId = await getFolderIdByPath(pId);
    }

    final api = await _getApi();
    final q =
        "'$pId' in parents and trashed=false and mimeType != 'application/vnd.google-apps.folder'";

    final all = <DriveFileMetadata>[];
    String? token;
    int pageCount = 0;

    KragLogger.info(
      LogDomain.sync,
      'Fetching file list from Drive for folder: $pId (useCache: $useCache)',
    );
    KragLogger.info(
      LogDomain.sync,
      'Drive API parameters: spaces=drive, includeItemsFromAllDrives=true, supportsAllDrives=true',
    );

    try {
      do {
        pageCount++;
        final res = await api.files.list(
          q: q,
          $fields:
              'nextPageToken, files(id, name, createdTime, modifiedTime, properties)',
          pageToken: token,
          pageSize: 1000,
          includeItemsFromAllDrives: true,
          supportsAllDrives: true,
          spaces: 'drive',
        );

        if (res.files != null) {
          for (var f in res.files!) {
            int? v;
            if (f.properties?['_v'] != null) {
              v = int.tryParse(f.properties!['_v']!);
            }
            all.add(
              DriveFileMetadata(
                id: f.id!,
                name: f.name!,
                createdTime: f.createdTime?.toIso8601String() ?? '',
                modifiedTime: f.modifiedTime?.toIso8601String() ?? '',
                v: v,
              ),
            );
          }

          if (token != null || res.nextPageToken != null) {
            KragLogger.info(
              LogDomain.sync,
              'Fetched page $pageCount of file list. Total items so far: ${all.length}',
            );
          }
        }

        token = res.nextPageToken;
      } while (token != null);
    } catch (e, stack) {
      KragLogger.error(
        LogDomain.sync,
        'CRITICAL: Failed to list files from Drive at page $pageCount. Aborting to prevent partial data pruning.',
        e,
        stack,
      );
      throw Exception(
          'Drive listFiles failed during pagination at page $pageCount: $e');
    }

    // Update in-memory cache
    _fileListCache[parentIdOrPath] = _FileListCacheEntry(
      all,
      DateTime.now().millisecondsSinceEpoch,
    );

    KragLogger.info(
      LogDomain.sync,
      'Successfully listed ${all.length} files from Drive for $parentIdOrPath (space: drive, cross-platform verified)',
    );

    return all;
  }

  @override
  Future<String> ensureFile(
    String name,
    Uint8List content,
    String mime,
    String parentIdOrPath, {
    int? version,
  }) async {
    KragLogger.info(
      LogDomain.sync,
      '[ensureFile] : $name, $parentIdOrPath',
    );
    final files = await listFiles(parentIdOrPath, useCache: false);
    final match = files.where((f) => f.name == name);

    if (match.isNotEmpty) {
      final id = match.first.id;
      await updateFile(id, content, version: version);
      return id;
    }

    return await createFile(name, content, mime, parentIdOrPath,
        version: version);
  }

  @override
  Future<String> createFile(
    String name,
    Uint8List content,
    String mime,
    String parentIdOrPath, {
    int? version,
  }) async {
    // Resolve parent ID (using persistent cache)
    String pId = parentIdOrPath;
    if (pId.contains('/') ||
        pId == constants.AppConstants.vaultRootFolderName) {
      pId = await getFolderIdByPath(pId);
    }

    final api = await _getApi();
    final f = drive.File()
      ..name = name
      ..parents = [pId]
      ..mimeType = mime;

    if (version != null) f.properties = {'_v': '$version'};

    KragLogger.info(LogDomain.sync, '>>>01 Creating file>>>: ${f.toJson()}');

    final media = drive.Media(Stream.value(content), content.length);
    final result = await api.files.create(
      f,
      uploadMedia: media,
      $fields: 'id',
      supportsAllDrives: true,
    );

    final meta = await api.files.get(
      result.id!,
      $fields:
          'id,name,parents,spaces,capabilities,driveId,teamDriveId,shared,ownedByMe',
      supportsAllDrives: true,
    ) as drive.File;

    KragLogger.info(LogDomain.sync, '>>>01 Meta (detailed)>>>:');
    KragLogger.info(LogDomain.sync, '  - File ID: ${meta.id}');
    KragLogger.info(LogDomain.sync, '  - File Name: ${meta.name}');
    KragLogger.info(LogDomain.sync, '  - Parents: ${meta.parents}');
    KragLogger.info(LogDomain.sync, '  - Spaces: ${meta.spaces}');
    KragLogger.info(LogDomain.sync, '  - Drive ID: ${meta.driveId}');
    KragLogger.info(LogDomain.sync, '  - Team Drive ID: ${meta.teamDriveId}');
    KragLogger.info(LogDomain.sync, '  - Shared: ${meta.shared}');
    KragLogger.info(LogDomain.sync, '  - Owned By Me: ${meta.ownedByMe}');
    KragLogger.info(
      LogDomain.sync,
      '  - Capabilities: ${jsonEncode(meta.capabilities?.toJson())}',
    );

    try {
      final perms = await api.permissions.list(
        result.id!,
        supportsAllDrives: true,
      );
      KragLogger.info(
        LogDomain.sync,
        '>>>01 PERMS (count: ${perms.permissions?.length ?? 0})>>>:',
      );
      if (perms.permissions != null) {
        for (var perm in perms.permissions!) {
          KragLogger.info(
            LogDomain.sync,
            '  - Permission: ${perm.type}/${perm.role}/${perm.emailAddress ?? perm.displayName ?? "N/A"}',
          );
        }
      }
    } catch (e, st) {
      KragLogger.error(LogDomain.sync, '>>>01 PERMS ERROR: $e');
      KragLogger.error(LogDomain.sync, '>>>01 PERMS ERROR: ${st.toString()}');
    }

    return result.id!;
  }

  @override
  Future<void> updateFile(
    String id,
    Uint8List content, {
    int? version,
  }) async {
    final api = await _getApi();
    final f = drive.File();

    if (version != null) f.properties = {'_v': '$version'};

    final media = drive.Media(Stream.value(content), content.length);
    await api.files.update(
      f,
      id,
      uploadMedia: media,
      supportsAllDrives: true,
    );
  }

  @override
  Future<Uint8List> getFile(String id) async {
    try {
      final api = await _getApi();
      final media = await api.files.get(
        id,
        downloadOptions: drive.DownloadOptions.fullMedia,
        supportsAllDrives: true,
      ) as drive.Media;

      final data = <int>[];
      await media.stream.forEach(data.addAll);
      return Uint8List.fromList(data);
    } catch (e, stack) {
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('404') ||
          errorString.contains('not found') ||
          errorString.contains('file not found')) {
        KragLogger.warn(
          LogDomain.sync,
          'File not found (404) for ID: $id. This will trigger fallback search by filename.',
        );
        throw Exception('File not found (404): $id');
      }
      KragLogger.error(
        LogDomain.sync,
        'Failed to retrieve file $id from Drive',
        e,
        stack,
      );
      rethrow;
    }
  }

  @override
  Future<DriveFileMetadata> getFileMetadata(String id) async {
    final api = await _getApi();
    final f = await api.files.get(
      id,
      $fields: 'id,name,createdTime,modifiedTime,properties',
    ) as drive.File;

    KragLogger.info(LogDomain.sync, '>>>01 f: $f');
    KragLogger.info(LogDomain.sync, '>>>01 f.properties: ${f.properties}');
    KragLogger.info(
        LogDomain.sync, '>>>01 f.properties["_v"]: ${f.properties?['_v']}');
    KragLogger.info(
      LogDomain.sync,
      '>>>01 f.properties["_v"] as int: ${int.tryParse(f.properties?['_v'] ?? '0')}',
    );

    int? v;
    if (f.properties?['_v'] != null) v = int.tryParse(f.properties!['_v']!);

    return DriveFileMetadata(
      id: f.id!,
      name: f.name!,
      createdTime: f.createdTime?.toIso8601String() ?? '',
      modifiedTime: f.modifiedTime?.toIso8601String() ?? '',
      v: v,
    );
  }

  @override
  Future<void> trashFile(String id) async {
    final api = await _getApi();
    await api.files.update(drive.File()..trashed = true, id);

    // Clear file list cache since we modified the file structure
    _fileListCache.clear();

    KragLogger.info(
      LogDomain.sync,
      'Trashed file $id and invalidated file list cache',
    );
  }

  @override
  Future<List<DriveFileMetadata>> checkForChanges(
    String path,
    String modifiedAfter,
  ) async {
    KragLogger.info(
      LogDomain.sync,
      '[checkForChanges] : $path, $modifiedAfter',
    );
    final files = await listFiles(path, useCache: false);
    final dt = DateTime.parse(modifiedAfter);
    return files
        .where((f) => DateTime.parse(f.modifiedTime).isAfter(dt))
        .toList();
  }

  // ============================================================================
  // LEGACY STORAGE METHODS (Kept for backward compatibility)
  // ============================================================================

  Future<String?> _getStoredRootFolderId() async =>
      (await SharedPreferences.getInstance()).getString(_rootPathKey);

  Future<void> _storeRootFolderId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_rootPathKey, id);
    await _setPathInStorage(constants.AppConstants.vaultRootFolderName, id);
  }

  Future<void> _setPathInStorage(String path, String id) async {
    final p = await SharedPreferences.getInstance();
    final map = jsonDecode(p.getString(_pathCacheKey) ?? '{}');
    map[path] = id;
    await p.setString(_pathCacheKey, jsonEncode(map));
  }
}

class _FileListCacheEntry {
  final List<DriveFileMetadata> files;
  final int timestamp;

  _FileListCacheEntry(this.files, this.timestamp);
}
