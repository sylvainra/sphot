String getWebOrigin() => '';

Future<void> openHtmlPrintDocument(
  String documentHtml, {
  Duration revokeDelay = const Duration(seconds: 10),
}) async {
  throw UnsupportedError(
    'L’impression HTML du portail Admin est disponible uniquement sur le Web.',
  );
}
