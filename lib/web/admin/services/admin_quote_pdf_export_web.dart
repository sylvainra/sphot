// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<void> exportAdminQuotePdf(
  Uint8List pdfBytes,
  String filename, {
  Rect? sharePositionOrigin,
}) async {
  final blob = html.Blob(<Object>[pdfBytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    final anchor = html.AnchorElement(href: url)
      ..download = filename;
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    // Le navigateur peut encore lire le blob au moment du clic.
    Future<void>.delayed(
      const Duration(seconds: 10),
      () => html.Url.revokeObjectUrl(url),
    );
  }
}
