import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

class LocalCacheService {
  static const String _filesKey = 'cached_drive_files';
  static const String _contentsKey = 'cached_drive_contents';

  /// Saves the list of drive files to local storage
  Future<void> saveFiles(List<drive.File> files) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> rawList = files.map((file) {
      return {
        'id': file.id,
        'name': file.name,
        'mimeType': file.mimeType,
        'modifiedTime': file.modifiedTime?.toIso8601String(),
        'size': file.size,
        'parents': file.parents,
      };
    }).toList();

    await prefs.setString(_filesKey, json.encode(rawList));
  }

  /// Loads the cached files list from local storage
  Future<List<drive.File>> loadFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_filesKey);
    if (jsonStr == null) return [];

    try {
      final List<dynamic> decoded = json.decode(jsonStr);
      return decoded.map((item) {
        final map = item as Map<String, dynamic>;
        return drive.File()
          ..id = map['id'] as String?
          ..name = map['name'] as String?
          ..mimeType = map['mimeType'] as String?
          ..modifiedTime = map['modifiedTime'] != null
              ? DateTime.parse(map['modifiedTime'] as String)
              : null
          ..size = map['size'] as String?
          ..parents = map['parents'] != null
              ? List<String>.from(map['parents'] as List)
              : null;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Saves the file contents cache map to local storage
  Future<void> saveContents(Map<String, String> contents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentsKey, json.encode(contents));
  }

  /// Loads the cached file contents map from local storage
  Future<Map<String, String>> loadContents() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_contentsKey);
    if (jsonStr == null) return {};

    try {
      final Map<String, dynamic> decoded = json.decode(jsonStr);
      return decoded.map((key, value) => MapEntry(key, value as String));
    } catch (e) {
      return {};
    }
  }

  /// Clears all local cache (useful on logout)
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_filesKey);
    await prefs.remove(_contentsKey);
  }
}
