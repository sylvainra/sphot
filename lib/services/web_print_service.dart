import 'web_print_service_stub.dart'
    if (dart.library.html) 'web_print_service_web.dart';

class WebPrintService {
  static bool get isSupported => WebPrintServiceImpl.isSupported;

  static String get origin => WebPrintServiceImpl.origin;

  static bool openPrintableHtml(String html) {
    return WebPrintServiceImpl.openPrintableHtml(html);
  }
}
