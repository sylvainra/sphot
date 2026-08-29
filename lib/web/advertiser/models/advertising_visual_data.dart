import 'dart:typed_data';

class AdvertisingVisualData {
  const AdvertisingVisualData({
    this.bytes,
    this.url,
    this.fileName,
    this.extension,
    this.mimeType,
    this.fileSizeBytes,
    this.width,
    this.height,
  });

  final Uint8List? bytes;
  final String? url;
  final String? fileName;
  final String? extension;
  final String? mimeType;
  final int? fileSizeBytes;
  final int? width;
  final int? height;

  bool get isAvailable => bytes != null || (url?.trim().isNotEmpty ?? false);
}
