import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

Future<void> exportAdminQuotePdf(
  Uint8List pdfBytes,
  String filename, {
  Rect? sharePositionOrigin,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      subject: 'SPHOT - Simulation tarifaire non contractuelle',
      text: 'Simulation tarifaire SPHOT : ni devis ni facture.',
      files: [
        XFile.fromData(
          pdfBytes,
          mimeType: 'application/pdf',
          name: filename,
        ),
      ],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}
