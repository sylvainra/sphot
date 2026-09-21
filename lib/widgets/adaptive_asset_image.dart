import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders SVG and raster assets without changing their layout constraints.
class AdaptiveAssetImage extends StatelessWidget {
  final String assetName;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;

  const AdaptiveAssetImage(
    this.assetName, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (assetName.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        assetName,
        width: width,
        height: height,
        fit: fit ?? BoxFit.scaleDown,
        alignment: alignment,
        errorBuilder: errorBuilder,
      );
    }

    return Image.asset(
      assetName,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      errorBuilder: errorBuilder,
    );
  }
}
