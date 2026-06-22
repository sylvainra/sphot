import 'web_pending_auth_storage_stub.dart'
    if (dart.library.html) 'web_pending_auth_storage_web.dart';

class WebPendingAuthStorage {
  static String? getPendingAuth() {
    return WebPendingAuthStorageImpl.getPendingAuth();
  }

  static void setPendingAuth(String value) {
    WebPendingAuthStorageImpl.setPendingAuth(value);
  }

  static void clearPendingAuth() {
    WebPendingAuthStorageImpl.clearPendingAuth();
  }
}