import 'dart:typed_data';

enum DiffusionPreviewType {
  map,
  premium,
  pack,
}

class DiffusionPreviewData {
  const DiffusionPreviewData({
    this.type,
    this.bannerBytes,
    this.bannerUrl,
    this.advertiserName = '',
    this.logoUrl,
  });

  final DiffusionPreviewType? type;
  final Uint8List? bannerBytes;
  final String? bannerUrl;
  final String advertiserName;
  final String? logoUrl;

  bool get hasSelection => type != null;
}
