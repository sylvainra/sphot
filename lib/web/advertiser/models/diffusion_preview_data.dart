import 'dart:typed_data';

enum DiffusionPreviewType { map, premium, pack }

class DiffusionPreviewData {
  const DiffusionPreviewData({
    this.type,
    this.bannerBytes,
    this.bannerUrl,
    this.advertiserName = '',
    this.logoUrl,
    this.latitude,
    this.longitude,
    this.radiusKm = 0.5,
  });

  final DiffusionPreviewType? type;
  final Uint8List? bannerBytes;
  final String? bannerUrl;
  final String advertiserName;
  final String? logoUrl;
  final double? latitude;
  final double? longitude;
  final double radiusKm;

  bool get hasSelection => type != null;
}
