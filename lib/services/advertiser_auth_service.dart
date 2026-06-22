import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'web_pending_auth_storage.dart';

class AdvertiserAuthService {
  static const String providerId = 'oidc.proconnect';

  static Future<void> signInWithProConnectRedirect() async {
    try {
      final provider = OAuthProvider(providerId)
        ..addScope('openid')
        ..addScope('email')
        ..addScope('profile');

      WebPendingAuthStorage.setPendingAuth('advertiser');

      debugPrint('AUTH ANNONCEUR : pendingAuth enregistré');
      debugPrint('AUTH ANNONCEUR : lancement signInWithRedirect');

      await FirebaseAuth.instance.signInWithRedirect(provider);
    } catch (e) {
      debugPrint('ERREUR signInWithRedirect : $e');
      rethrow;
    }
  }

  static Future<User?> handleRedirectResult() async {
    final credential = await FirebaseAuth.instance.getRedirectResult();
    return credential.user ?? FirebaseAuth.instance.currentUser;
  }

  static User? currentUser() {
    return FirebaseAuth.instance.currentUser;
  }

  static Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }
}