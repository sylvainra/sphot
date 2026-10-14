import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'admin_quote_pdf_export_stub.dart'
    if (dart.library.html) 'admin_quote_pdf_export_web.dart' as platform;

/// Télécharge sur Flutter Web et utilise la feuille de partage ailleurs.
Future<void> exportAdminQuotePdf(
  Uint8List pdfBytes,
  String filename, {
  Rect? sharePositionOrigin,
}) =>
    platform.exportAdminQuotePdf(
      pdfBytes,
      filename,
      sharePositionOrigin: sharePositionOrigin,
    );
