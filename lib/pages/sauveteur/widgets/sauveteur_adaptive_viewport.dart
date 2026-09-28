import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Garde les pages SPHOT SAUVETEUR fixes sur un écran de hauteur normale,
/// tout en autorisant un défilement vertical uniquement sur les écrans
/// réellement plus courts.
class SauveteurAdaptiveViewport extends StatelessWidget {
  const SauveteurAdaptiveViewport({
    super.key,
    required this.child,
    this.minContentHeight = 700,
  });

  final Widget child;
  final double minContentHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final targetHeight = math.max(minContentHeight, availableHeight);
        final needsScroll = availableHeight + 0.5 < minContentHeight;

        return SingleChildScrollView(
          physics: needsScroll
              ? const BouncingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          child: SizedBox(
            height: targetHeight,
            child: child,
          ),
        );
      },
    );
  }
}
