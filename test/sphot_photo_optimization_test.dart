import 'dart:typed_data';

import 'package:bathing_spots_app/services/sphot_media_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('une photo déjà légère conserve son fichier et son format', () {
    final source = img.Image(width: 200, height: 120);
    img.fill(source, color: img.ColorRgb8(50, 130, 210));
    final png = img.encodePng(source);
    final result = SphotMediaStorageService.optimizePhoto(
      bytes: png,
      fileName: 'plage.png',
    );
    expect(result.bytes, png);
    expect(result.fileName, 'plage.png');
    expect(result.mimeType, 'image/png');
  });

  test('une grande photo est limitée à 1600 px et 350 Kio', () {
    final source = img.Image(width: 2400, height: 1350);
    img.fill(source, color: img.ColorRgb8(70, 130, 180));
    final png = img.encodePng(source);
    final result = SphotMediaStorageService.optimizePhoto(
      bytes: png,
      fileName: 'panorama.png',
    );
    expect(result.mimeType, 'image/jpeg');
    expect(result.extension, 'jpg');
    expect(result.fileName, 'panorama.jpg');
    expect(
      result.sizeBytes,
      lessThanOrEqualTo(SphotMediaStorageService.targetStoredPhotoSizeBytes),
    );
    final photo = img.decodeJpg(result.bytes);
    expect(photo, isNotNull);
    expect(photo!.width, lessThanOrEqualTo(1600));
    expect(photo.height, lessThanOrEqualTo(1600));
    expect(photo.width / photo.height, closeTo(2400 / 1350, 0.02));
  });

  test('un faux fichier image est rejeté', () {
    expect(
      () => SphotMediaStorageService.optimizePhoto(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        fileName: 'photo.jpg',
      ),
      throwsStateError,
    );
  });

  test('un fichier au-delà de 5 Mo est refusé', () {
    expect(
      () => SphotMediaStorageService.optimizePhoto(
        bytes: Uint8List(5 * 1024 * 1024 + 1),
        fileName: 'photo.jpg',
      ),
      throwsStateError,
    );
  });
}
