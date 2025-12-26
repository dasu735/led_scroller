import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

class FileHandler {
  /// Request storage permission
  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.status;
      if (!status.isGranted) {
        final result = await Permission.storage.request();
        return result.isGranted;
      }
      return true;
    }
    return true; // iOS/Desktop doesn't need explicit storage permission
  }

  /// Get optimal save directory
  static Future<Directory> getSaveDirectory() async {
    if (Platform.isAndroid) {
      // Try external storage first
      final external = await getExternalStorageDirectory();
      if (external != null) {
        final downloadDir = Directory(p.join(external.path, 'Download'));
        if (await downloadDir.exists()) {
          return downloadDir;
        } else {
          await downloadDir.create(recursive: true);
          return downloadDir;
        }
      }
      // If external storage is not available, return external which would be null
      // So we should return the documents directory instead
    }

    // Fallback to documents directory
    final documents = await getApplicationDocumentsDirectory();
    final ledDir = Directory(p.join(documents.path, 'LED_Videos'));
    if (!await ledDir.exists()) {
      await ledDir.create(recursive: true);
    }
    return ledDir;
  }

  /// Save bytes to file with proper naming
  static Future<File> saveBytesToFile(
    Uint8List bytes, {
    required String filename,
    String? extension,
  }) async {
    final dir = await getSaveDirectory();
    final fullPath = p.join(dir.path, filename);
    final file = File(fullPath);
    return await file.writeAsBytes(bytes, flush: true);
  }

  /// Get file size in human readable format
  static String getFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Clean old temporary files
  static Future<void> cleanTempFiles({int maxAgeHours = 24}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(Duration(hours: maxAgeHours));

      final files = tempDir.listSync(recursive: true);
      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          if (stat.modified.isBefore(cutoff)) {
            try {
              await file.delete();
            } catch (e) {
              print('Failed to delete ${file.path}: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error cleaning temp files: $e');
    }
  }

  /// Check available storage space
  static Future<int?> getAvailableStorage() async {
    try {
      final dir = await getSaveDirectory();
      // Use Directory.stat instead of FileSystemEntity.stat
      final stat = await dir.stat();
      // FileStat doesn't have statSize, we'll return the directory size differently
      // Since we can't easily get available space, we'll just return null for now
      // In a real implementation, you might want to use platform-specific code
      return null;
    } catch (e) {
      print('Error checking storage: $e');
      return null;
    }
  }
}
