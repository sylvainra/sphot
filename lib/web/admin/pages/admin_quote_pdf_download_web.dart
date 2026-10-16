import 'dart:html' as html;
import 'dart:typed_data';

void downloadPdf(Uint8List bytes, String filename) {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  // Retarder la libération pour laisser le navigateur commencer le transfert.
  Future<void>.delayed(
    const Duration(seconds: 5),
    () => html.Url.revokeObjectUrl(url),
  );
}
