import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AdvertiserAuthService {
  static const String providerId = 'oidc.proconnect';

  static Future<User?> signInWithProConnectPopup() async {
    final provider = OAuthProvider(providerId)
      ..addScope('openid')
      ..addScope('email');

    debugPrint('AUTH ANNONCEUR : ouverture de ProConnect');

    final credential = await FirebaseAuth.instance.signInWithPopup(provider);
    return credential.user;
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