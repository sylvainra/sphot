import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AdminLogoSelection {
  final Uint8List bytes;
  final String fileName;
  final String extension;
  final String mimeType;
  final int sizeBytes;

  const AdminLogoSelection({
    required this.bytes,
    required this.fileName,
    required this.extension,
    required this.mimeType,
    required this.sizeBytes,
  });

  bool get isSvg => extension == 'svg' || mimeType == 'image/svg+xml';
}

class AdminLogoUploadResult {
  final String url;
  final String storagePath;
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  const AdminLogoUploadResult({
    required this.url,
    required this.storagePath,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });
}

class AdminLogoStorageService {
  static const int maxLogoSizeBytes = 5 * 1024 * 1024;

  static const Set<String> allowedExtensions = {
    'png',
    'jpg',
    'jpeg',
    'webp',
    'svg',
  };

  static Future<AdminLogoSelection?> pickLogo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions.toList(),
      withData: true,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final bytes = file.bytes;

    if (bytes == null || bytes.isEmpty) {
      throw StateError('Le fichier sélectionné ne peut pas être lu.');
    }

    final extension = (file.extension ?? _extensionFromName(file.name))
        .trim()
        .toLowerCase();

    if (!allowedExtensions.contains(extension)) {
      throw StateError(
        'Format non accepté. Utilisez PNG, JPG, JPEG, WebP ou SVG.',
      );
    }

    if (bytes.length > maxLogoSizeBytes) {
      throw StateError('Le logo ne doit pas dépasser 5 Mo.');
    }

    return AdminLogoSelection(
      bytes: bytes,
      fileName: file.name,
      extension: extension,
      mimeType: _mimeTypeForExtension(extension),
      sizeBytes: bytes.length,
    );
  }

  static Future<AdminLogoUploadResult> uploadLogo({
    required String territoireId,
    required AdminLogoSelection selection,
    String? requestId,
  }) async {
    final cleanTerritoireId = territoireId.trim();

    if (cleanTerritoireId.isEmpty) {
      throw StateError('Identifiant du territoire introuvable.');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = _safeFileName(selection.fileName);
    final storagePath =
        'territoires/$cleanTerritoireId/logos/${timestamp}_$safeName';

    final reference = FirebaseStorage.instance.ref().child(storagePath);

    final metadata = SettableMetadata(
      contentType: selection.mimeType,
      customMetadata: {
        'territoireId': cleanTerritoireId,
        if (requestId != null && requestId.trim().isNotEmpty)
          'requestId': requestId.trim(),
        'originalFileName': selection.fileName,
      },
    );

    await reference.putData(selection.bytes, metadata);

    final url = await reference.getDownloadURL();

    return AdminLogoUploadResult(
      url: url,
      storagePath: storagePath,
      fileName: selection.fileName,
      mimeType: selection.mimeType,
      sizeBytes: selection.sizeBytes,
    );
  }

  static bool isSvgUrl(String url) {
    final normalized = url.toLowerCase();
    return normalized.contains('.svg');
  }

  static String _extensionFromName(String fileName) {
    final index = fileName.lastIndexOf('.');
    if (index < 0 || index == fileName.length - 1) {
      return '';
    }

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
      case 'svg':
        return 'image/svg+xml';
      default:
        return 'application/octet-stream';
    }
  }

  static String _safeFileName(String fileName) {
    final normalized = fileName.trim().replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '_',
    );

    if (normalized.isEmpty) {
      return 'logo';
    }

    return normalized;
  }
}
