import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class SphotPhotoSelection {
  final Uint8List bytes;
  final String fileName;
  final String extension;
  final String mimeType;
  final int sizeBytes;

  const SphotPhotoSelection({
    required this.bytes,
    required this.fileName,
    required this.extension,
    required this.mimeType,
    required this.sizeBytes,
  });
}

class SphotPhotoUploadResult {
  final String url;
  final String storagePath;
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  const SphotPhotoUploadResult({
    required this.url,
    required this.storagePath,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });
}

class SphotMediaStorageService {
  static const int maxPhotoSizeBytes = 5 * 1024 * 1024;

  static const Set<String> allowedPhotoExtensions = {
    'png',
    'jpg',
    'jpeg',
    'webp',
  };

  static Future<SphotPhotoSelection?> pickPhoto() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedPhotoExtensions.toList(),
      withData: true,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final bytes = file.bytes;

    if (bytes == null || bytes.isEmpty) {
      throw StateError('La photo sélectionnée ne peut pas être lue.');
    }

    final extension = (file.extension ?? _extensionFromName(file.name))
        .trim()
        .toLowerCase();

    if (!allowedPhotoExtensions.contains(extension)) {
      throw StateError(
        'Format non accepté. Utilisez PNG, JPG, JPEG ou WebP.',
      );
    }

    if (bytes.length > maxPhotoSizeBytes) {
      throw StateError('La photo ne doit pas dépasser 5 Mo.');
    }

    return SphotPhotoSelection(
      bytes: bytes,
      fileName: file.name,
      extension: extension,
      mimeType: _mimeTypeForExtension(extension),
      sizeBytes: bytes.length,
    );
  }

  static Future<SphotPhotoUploadResult> uploadPhoto({
    required String territoireId,
    required String spotId,
    required SphotPhotoSelection selection,
  }) async {
    final cleanTerritoireId = territoireId.trim();
    final cleanSpotId = spotId.trim();

    if (cleanTerritoireId.isEmpty || cleanSpotId.isEmpty) {
      throw StateError('Territoire ou SPHOT introuvable.');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = _safeFileName(selection.fileName);
    final storagePath =
        'territoires/$cleanTerritoireId/spots/$cleanSpotId/photos/'
        '${timestamp}_$safeName';

    final reference = FirebaseStorage.instance.ref().child(storagePath);

    await reference.putData(
      selection.bytes,
      SettableMetadata(
        contentType: selection.mimeType,
        customMetadata: {
          'territoireId': cleanTerritoireId,
          'spotId': cleanSpotId,
          'originalFileName': selection.fileName,
        },
      ),
    );

    final url = await reference.getDownloadURL();

    return SphotPhotoUploadResult(
      url: url,
      storagePath: storagePath,
      fileName: selection.fileName,
      mimeType: selection.mimeType,
      sizeBytes: selection.sizeBytes,
    );
  }

  static String _extensionFromName(String fileName) {
    final index = fileName.lastIndexOf('.');
    if (index < 0 || index == fileName.length - 1) return '';
    return fileName.substring(index + 1);
  }

  static String _mimeTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  static String _safeFileName(String fileName) {
    final normalized = fileName.trim().replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '_',
    );

    return normalized.isEmpty ? 'photo' : normalized;
  }
}
