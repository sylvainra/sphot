import 'dart:typed_data';

enum DiffusionPreviewType { map, premium, pack }

/* Deux emplacements réels ; le Pack les regroupe sans nouveau statut. */
enum DiffusionPlacement { map, spotPanels }

class DiffusionPlacementSelection {
  const DiffusionPlacementSelection({
    this.onMap = false,
    this.inSpotPanels = false,
  });

  final bool onMap;
  final bool inSpotPanels;

  factory DiffusionPlacementSelection.fromType(DiffusionPreviewType? type) {
    return switch (type) {
      DiffusionPreviewType.map =>
        const DiffusionPlacementSelection(onMap: true),
      DiffusionPreviewType.premium =>
        const DiffusionPlacementSelection(inSpotPanels: true),
      DiffusionPreviewType.pack =>
        const DiffusionPlacementSelection(
          onMap: true,
          inSpotPanels: true,
        ),
      null => const DiffusionPlacementSelection(),
    };
  }

  DiffusionPreviewType? get type {
    if (onMap && inSpotPanels) return DiffusionPreviewType.pack;
    if (onMap) return DiffusionPreviewType.map;
    if (inSpotPanels) return DiffusionPreviewType.premium;
    return null;
  }

  DiffusionPlacementSelection toggle(DiffusionPlacement placement) {
    return switch (placement) {
      DiffusionPlacement.map => DiffusionPlacementSelection(
          onMap: !onMap,
          inSpotPanels: inSpotPanels,
        ),
      DiffusionPlacement.spotPanels => DiffusionPlacementSelection(
          onMap: onMap,
          inSpotPanels: !inSpotPanels,
        ),
    };
  }
}

class DiffusionPreviewData {
  const DiffusionPreviewData({
    this.type,
    this.bannerBytes,
    this.bannerUrl,
    this.advertiserName = '',
    this.logoUrl,
    this.latitude,
    this.longitude,
  });

  final DiffusionPreviewType? type;
  final Uint8List? bannerBytes;
  final String? bannerUrl;
  final String advertiserName;
  final String? logoUrl;
  final double? latitude;
  final double? longitude;

  bool get hasSelection => type != null;
}
