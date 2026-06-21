import 'package:firebase_auth/firebase_auth.dart';

class AdvertiserAuthService {
  static const String providerId = 'oidc.proconnect';

  static Future<void> signInWithProConnectRedirect() async {
    final provider = OAuthProvider(providerId)
      ..addScope('openid')
      ..addScope('email')
      ..addScope('profile');

    await FirebaseAuth.instance.signInWithRedirect(provider);
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