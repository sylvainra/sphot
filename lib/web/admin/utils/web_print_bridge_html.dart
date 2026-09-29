// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

String getWebOrigin() => html.window.location.origin;

Future<void> openHtmlPrintDocument(
  String documentHtml, {
  Duration revokeDelay = const Duration(seconds: 10),
}) async {
  final blob = html.Blob(
    [documentHtml],
    'text/html;charset=utf-8',
  );

  final url = html.Url.createObjectUrlFromBlob(blob);

  html.window.open(
    url,
    '_blank',
    'noopener,noreferrer',
  );

  Future<void>.delayed(
    revokeDelay,
    () => html.Url.revokeObjectUrl(url),
  );
}
