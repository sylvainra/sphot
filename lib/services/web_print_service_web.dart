// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class WebPrintServiceImpl {
  static bool get isSupported => true;

  static String get origin => html.window.location.origin;

  static bool openPrintableHtml(String documentHtml) {
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
      const Duration(seconds: 10),
      () => html.Url.revokeObjectUrl(url),
    );

    return true;
  }
}
