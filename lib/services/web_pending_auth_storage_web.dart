// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class WebPendingAuthStorageImpl {
  static String? getPendingAuth() {
    return html.window.localStorage['sphot_pending_auth'];
  }

  static void setPendingAuth(String value) {
    html.window.localStorage['sphot_pending_auth'] = value;
  }

  static void clearPendingAuth() {
    html.window.localStorage.remove('sphot_pending_auth');
  }
}