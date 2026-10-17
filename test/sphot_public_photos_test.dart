import 'package:flutter_test/flutter_test.dart';
import 'package:bathing_spots_app/models/flag_state.dart';

void main() {
  test('trois photos maximum pour un SPHOT sans webcam', () {
    final spot = SpotFlagState.fromFirestore('spot-1', {
      'mediaType': 'photo',
      'photoSphotUrls': [
        'https://example.org/1.jpg',
        'https://example.org/2.jpg',
        'https://example.org/3.jpg',
        'https://example.org/4.jpg',
      ],
    });
    expect(spot.publicPhotoUrls, [
      'https://example.org/1.jpg',
      'https://example.org/2.jpg',
      'https://example.org/3.jpg',
    ]);
    expect(spot.publicMediaType, 'photo');
    expect(spot.publicMediaUrl, 'https://example.org/1.jpg');
  });

  test('une webcam masque la galerie même si une ancienne photo existe', () {
    final spot = SpotFlagState.fromFirestore('spot-2', {
      'mediaType': 'webcam',
      'adresseWebcam': 'https://example.org/direct',
      'photoSphotUrls': ['https://example.org/photo.jpg'],
      'photoSphotUrl': 'https://example.org/ancienne.jpg',
    });
    expect(spot.publicPhotoUrls, isEmpty);
    expect(spot.publicMediaType, 'webcam');
    expect(spot.publicMediaUrl, 'https://example.org/direct');
  });

  test('ancienne photo unique préservée', () {
    final spot = SpotFlagState.fromFirestore('spot-3', {
      'photoSphotUrl': 'https://example.org/unique.jpg',
    });
    expect(spot.publicPhotoUrls, ['https://example.org/unique.jpg']);
    expect(spot.publicMediaType, 'photo');
  });

  test('ancien lien direct image conserve son affichage', () {
    final spot = SpotFlagState.fromFirestore('spot-4', {
      'adresseWebcam': 'https://example.org/photo.webp',
    });
    expect(spot.publicPhotoUrls, ['https://example.org/photo.webp']);
    expect(spot.publicMediaType, 'photo');
  });
}
