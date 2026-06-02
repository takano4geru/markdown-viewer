import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../services/google_drive_service.dart';
import '../services/local_cache_service.dart';
import 'auth_provider.dart';

class DriveState {
  final List<drive.File> files;
  final Map<String, String> fileContents; // fileId -> content
  final Map<String, Uint8List> mediaCache; // fileId -> raw bytes
  final bool isLoading;
  final String? operationType; // 'list', 'create', 'read', 'update', 'delete'
  final String? activeFileId; // The file ID currently being processed (read, update, delete)
  final String? errorMessage;
  final String? rootFolderId;

  DriveState({
    this.files = const [],
    this.fileContents = const {},
    this.mediaCache = const {},
    this.isLoading = false,
    this.operationType,
    this.activeFileId,
    this.errorMessage,
    this.rootFolderId,
  });

  DriveState copyWith({
    List<drive.File>? files,
    Map<String, String>? fileContents,
    Map<String, Uint8List>? mediaCache,
    bool? isLoading,
    String? operationType,
    String? activeFileId,
    String? errorMessage,
    String? rootFolderId,
    bool clearActiveFields = false,
  }) {
    return DriveState(
      files: files ?? this.files,
      fileContents: fileContents ?? this.fileContents,
      mediaCache: mediaCache ?? this.mediaCache,
      isLoading: isLoading ?? this.isLoading,
      operationType: clearActiveFields ? null : (operationType ?? this.operationType),
      activeFileId: clearActiveFields ? null : (activeFileId ?? this.activeFileId),
      errorMessage: errorMessage ?? this.errorMessage,
      rootFolderId: rootFolderId ?? this.rootFolderId,
    );
  }
}

class DriveNotifier extends StateNotifier<DriveState> {
  final Ref _ref;
  final _cacheService = LocalCacheService();

  DriveNotifier(this._ref) : super(DriveState()) {
    // 1. Initialize data from local cache
    _initCache();

    // 2. Listen for authentication state changes
    _ref.listen<AuthState>(authProvider, (previous, next) async {
      if (next.client != null && previous?.client == null) {
        await loadFiles();
      } else if (next.client == null && previous?.client != null) {
        await _cacheService.clear();
        state = DriveState(); // Clear state when logging out
      }
    });
  }

  /// Load files from local storage on startup for instant offline reading
  Future<void> _initCache() async {
    state = state.copyWith(isLoading: true);
    final cachedFiles = await _cacheService.loadFiles();
    final cachedContents = await _cacheService.loadContents();
    
    // Find cached root folder ID offline
    String? rootFolderId;
    try {
      final rootFolder = cachedFiles.firstWhere(
        (f) => f.name == 'CloudSync Docs' && f.mimeType == 'application/vnd.google-apps.folder',
      );
      rootFolderId = rootFolder.id;
    } catch (_) {
      // Not cached/found yet
    }

    state = DriveState(
      files: cachedFiles,
      fileContents: cachedContents,
      rootFolderId: rootFolderId,
      isLoading: false,
    );

    // If client is already active on initialization, fetch latest files from Google Drive in background
    if (_ref.read(authProvider).client != null) {
      loadFiles();
    }
  }

  /// Resolves the Google Drive service dynamically using the current client from AuthState
  GoogleDriveService? get _driveService {
    final client = _ref.read(authProvider).client;
    return client != null ? GoogleDriveService(client) : null;
  }

  /// Helper to check if an error is network/offline related
  bool _isNetworkError(Object error) {
    final errStr = error.toString().toLowerCase();
    return errStr.contains('socketexception') ||
        errStr.contains('connection failed') ||
        errStr.contains('network') ||
        errStr.contains('failed host lookup') ||
        errStr.contains('xmlhttprequest error') ||
        errStr.contains('http connection');
  }

  /// Executes an API action with automatic token refresh & retry on auth failure
  Future<T> _executeWithRetry<T>(Future<T> Function(GoogleDriveService service) action) async {
    var service = _driveService;
    if (service == null) {
      throw Exception('Not authenticated with Google');
    }

    try {
      return await action(service);
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      // Detect token expiration or authorization issues (401, 403, unauthorized)
      if (errStr.contains('401') || 
          errStr.contains('unauthorized') || 
          errStr.contains('invalid_credentials') || 
          errStr.contains('403')) {
        
        try {
          // Trigger a silent sign-in to refresh the client
          await _ref.read(authProvider.notifier).silentSignIn();
          
          final newService = _driveService;
          if (newService != null) {
            // Retry the operation with the refreshed client
            return await action(newService);
          }
        } catch (refreshErr) {
          // If refresh fails, throw the original authorization error
          throw e;
        }
      }
      rethrow;
    }
  }

  Future<void> loadFiles() async {
    if (_driveService == null) return;
    state = state.copyWith(isLoading: true, operationType: 'list', errorMessage: null);

    try {
      final rootFolderId = await _executeWithRetry((service) => service.getRootFolderId());
      final files = await _executeWithRetry((service) => service.listFiles());
      
      // Sort files by modifiedTime descending
      files.sort((a, b) {
        if (a.modifiedTime == null) return 1;
        if (b.modifiedTime == null) return -1;
        return b.modifiedTime!.compareTo(a.modifiedTime!);
      });

      // Save files metadata to local cache
      await _cacheService.saveFiles(files);

      state = state.copyWith(
        files: files,
        rootFolderId: rootFolderId,
        isLoading: false,
        clearActiveFields: true,
      );
    } catch (e) {
      final isOffline = _isNetworkError(e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: isOffline
            ? 'Offline Mode: Displaying cached notes.'
            : 'Failed to load files from Drive: $e',
        clearActiveFields: true,
      );
    }
  }

  Future<String?> createFile(String title, String content, {String? parentFolderId}) async {
    if (_driveService == null) return null;
    state = state.copyWith(isLoading: true, operationType: 'create', errorMessage: null);

    try {
      final newFile = await _executeWithRetry(
        (service) => service.createFile(title, content, parentFolderId: parentFolderId)
      );
      
      // Update local contents cache
      final newContents = Map<String, String>.from(state.fileContents);
      if (newFile.id != null) {
        newContents[newFile.id!] = content;
      }
      await _cacheService.saveContents(newContents);

      // Reload list to get metadata and sort (saves to files cache automatically)
      await loadFiles();
      state = state.copyWith(fileContents: newContents);
      return newFile.id;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _isNetworkError(e)
            ? 'Cannot save while offline. Check your network connection.'
            : 'Failed to create file: $e',
        clearActiveFields: true,
      );
      rethrow;
    }
  }

  Future<void> createFolder(String name, {String? parentFolderId}) async {
    if (_driveService == null) return;
    state = state.copyWith(isLoading: true, operationType: 'create', errorMessage: null);

    try {
      await _executeWithRetry(
        (service) => service.createFolder(name, parentFolderId: parentFolderId)
      );
      await loadFiles();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _isNetworkError(e)
            ? 'Cannot create folder while offline.'
            : 'Failed to create folder: $e',
        clearActiveFields: true,
      );
      rethrow;
    }
  }

  Future<void> readFile(String fileId) async {
    if (_driveService == null) return;
    
    state = state.copyWith(
      isLoading: true, 
      operationType: 'read', 
      activeFileId: fileId, 
      errorMessage: null,
    );

    try {
      final content = await _executeWithRetry((service) => service.readFile(fileId));
      
      final newContents = Map<String, String>.from(state.fileContents);
      newContents[fileId] = content;

      // Save contents cache to local storage
      await _cacheService.saveContents(newContents);

      state = state.copyWith(
        fileContents: newContents,
        isLoading: false,
        clearActiveFields: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _isNetworkError(e)
            ? 'Displaying local cached note. Unable to sync.'
            : 'Failed to read file: $e',
        clearActiveFields: true,
      );
    }
  }

  Future<void> updateFile(String fileId, String content) async {
    if (_driveService == null) return;
    state = state.copyWith(
      isLoading: true, 
      operationType: 'update', 
      activeFileId: fileId, 
      errorMessage: null,
    );

    try {
      await _executeWithRetry((service) => service.updateFile(fileId, content));
      
      // Update local contents cache
      final newContents = Map<String, String>.from(state.fileContents);
      newContents[fileId] = content;
      await _cacheService.saveContents(newContents);

      // Reload files to update modified time metadata (saves to files cache automatically)
      await loadFiles();
      state = state.copyWith(fileContents: newContents);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _isNetworkError(e)
            ? 'Cannot update while offline. Check your network connection.'
            : 'Failed to update file: $e',
        clearActiveFields: true,
      );
      rethrow;
    }
  }

  Future<void> moveFile(String fileId, String newParentId, {String? oldParentId}) async {
    if (_driveService == null) return;
    state = state.copyWith(
      isLoading: true,
      operationType: 'update',
      activeFileId: fileId,
      errorMessage: null,
    );

    try {
      await _executeWithRetry(
        (service) => service.moveFile(fileId, newParentId, oldParentId: oldParentId)
      );
      await loadFiles();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _isNetworkError(e)
            ? 'Cannot move file while offline. Check your network connection.'
            : 'Failed to move file: $e',
        clearActiveFields: true,
      );
      rethrow;
    }
  }

  Future<void> deleteFile(String fileId) async {
    if (_driveService == null) return;
    state = state.copyWith(
      isLoading: true, 
      operationType: 'delete', 
      activeFileId: fileId, 
      errorMessage: null,
    );

    try {
      await _executeWithRetry((service) => service.deleteFile(fileId));
      
      // Remove from local contents cache
      final newContents = Map<String, String>.from(state.fileContents);
      newContents.remove(fileId);
      await _cacheService.saveContents(newContents);

      // Reload files list (saves to files cache automatically)
      await loadFiles();
      state = state.copyWith(fileContents: newContents);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _isNetworkError(e)
            ? 'Cannot delete while offline. Check your network connection.'
            : 'Failed to delete file: $e',
        clearActiveFields: true,
      );
      rethrow;
    }
  }

  Future<void> downloadMedia(String fileId) async {
    if (_driveService == null) return;
    
    if (state.mediaCache.containsKey(fileId)) return;
    
    state = state.copyWith(
      isLoading: true,
      operationType: 'read',
      activeFileId: fileId,
      errorMessage: null,
    );

    try {
      final bytes = await _executeWithRetry((service) => service.downloadFileBytes(fileId));
      
      final newMediaCache = Map<String, Uint8List>.from(state.mediaCache);
      newMediaCache[fileId] = bytes;

      state = state.copyWith(
        mediaCache: newMediaCache,
        isLoading: false,
        clearActiveFields: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _isNetworkError(e)
            ? 'Cannot download media while offline.'
            : 'Failed to download media: $e',
        clearActiveFields: true,
      );
    }
  }

  Future<drive.File?> uploadMedia(String name, Uint8List bytes, String mimeType, {String? parentFolderId}) async {
    if (_driveService == null) return null;
    state = state.copyWith(isLoading: true, operationType: 'create', errorMessage: null);

    try {
      final newFile = await _executeWithRetry(
        (service) => service.uploadMedia(name, bytes, mimeType, parentFolderId: parentFolderId)
      );

      if (newFile.id != null) {
        final newMediaCache = Map<String, Uint8List>.from(state.mediaCache);
        newMediaCache[newFile.id!] = bytes;
        state = state.copyWith(mediaCache: newMediaCache);
      }

      await loadFiles();
      return newFile;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _isNetworkError(e)
            ? 'Cannot upload media while offline.'
            : 'Failed to upload media: $e',
        clearActiveFields: true,
      );
      rethrow;
    }
  }
}

final driveProvider = StateNotifierProvider<DriveNotifier, DriveState>((ref) {
  return DriveNotifier(ref);
});
