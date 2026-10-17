import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

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
  static const int targetStoredPhotoSizeBytes = 350 * 1024;
  static const int maxStoredPhotoDimension = 1600;

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

    return optimizePhoto(bytes: bytes, fileName: file.name);
  }

  /// Réduit le volume des nouveaux clichés avant leur transfert à Firebase.
  /// Les photos déjà légères sont conservées sans modification.
  static SphotPhotoSelection optimizePhoto({
    required Uint8List bytes,
    required String fileName,
  }) {
    final extension = _extensionFromName(fileName).toLowerCase();
    if (!allowedPhotoExtensions.contains(extension)) {
      throw StateError('Format non accepté. Utilisez PNG, JPG, JPEG ou WebP.');
    }
    if (bytes.isEmpty) {
      throw StateError('La photo sélectionnée est vide.');
    }
    if (bytes.length > maxPhotoSizeBytes) {
      throw StateError('La photo ne doit pas dépasser 5 Mo.');
    }

    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      throw StateError('Le fichier image ne peut pas être lu.');
    }
    if (decoded == null) {
      throw StateError('Le fichier image ne peut pas être lu.');
    }

    final originalMaxSide =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    if (originalMaxSide <= maxStoredPhotoDimension &&
        bytes.length <= targetStoredPhotoSizeBytes) {
      return SphotPhotoSelection(
        bytes: bytes,
        fileName: fileName,
        extension: extension,
        mimeType: _mimeTypeForExtension(extension),
        sizeBytes: bytes.length,
      );
    }

    // Orientation des photos prises avec un téléphone conservée après JPEG.
    final oriented = img.bakeOrientation(decoded);
    final sourceMaxSide =
        oriented.width > oriented.height ? oriented.width : oriented.height;

    for (final maxSide in <int>[1600, 1280, 960, 720, 560]) {
      final side = sourceMaxSide < maxSide ? sourceMaxSide : maxSide;
      final img.Image scaled;
      if (side < sourceMaxSide) {
        scaled = oriented.width >= oriented.height
            ? img.copyResize(
                oriented,
                width: side,
                interpolation: img.Interpolation.linear,
              )
            : img.copyResize(
                oriented,
                height: side,
                interpolation: img.Interpolation.linear,
              );
      } else {
        scaled = oriented;
      }

      // Une transparence PNG/WebP devient blanche, pas noire, en JPEG.
      final img.Image toEncode;
      if (scaled.hasAlpha) {
        final background = img.Image(
          width: scaled.width, height: scaled.height, numChannels: 3,
        );
        img.fill(background, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(background, scaled);
        toEncode = background;
      } else {
        toEncode = scaled;
      }

      for (final quality in <int>[80, 68, 54]) {
        final optimized = img.encodeJpg(toEncode, quality: quality);
        if (optimized.length <= targetStoredPhotoSizeBytes) {
          final lastDot = fileName.lastIndexOf('.');
          final name = lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
          return SphotPhotoSelection(
            bytes: optimized,
            fileName: '$name.jpg',
            extension: 'jpg',
            mimeType: 'image/jpeg',
            sizeBytes: optimized.length,
          );
        }
      }
    }
    throw StateError(
      'Photo trop volumineuse après optimisation. Choisissez un autre cliché.',
    );
  }

  static Future<void> deletePhoto(String storagePath) async {
    if (storagePath.trim().isEmpty) return;
    await FirebaseStorage.instance.ref().child(storagePath).delete();
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
