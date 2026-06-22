import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../services/web_pending_auth_storage.dart';

enum WebAdminAccessStatus {
  approved,
  pending,
  rejected,
  registrationRequired,
  signedOut,
}

class WebAdminAccessResult {
  final WebAdminAccessStatus status;
  final User? user;

  const WebAdminAccessResult({
    required this.status,
    this.user,
  });
}

class WebProConnectAuthService {
  WebProConnectAuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static const String providerId = 'oidc.proconnect';

  Future<WebAdminAccessResult> signIn() async {
  final provider = OAuthProvider(providerId)
    ..addScope('openid')
    ..addScope('email');

  try {
    print('===== REDIRECT PROCONNECT START =====');

    WebPendingAuthStorage.setPendingAuth('admin');

    await _auth.signInWithRedirect(provider);

    return const WebAdminAccessResult(
      status: WebAdminAccessStatus.signedOut,
    );
  } on FirebaseAuthException catch (e) {
    print('===== REDIRECT FIREBASE ERROR =====');
    print('code: ${e.code}');
    print('message: ${e.message}');

    rethrow;
  } catch (e) {
    print('===== REDIRECT UNKNOWN ERROR =====');
    print(e.toString());

    rethrow;
  }
}

  Future<WebAdminAccessResult> handleRedirectResult() async {
  try {
    final credential = await _auth.getRedirectResult();

    print('===== PROCONNECT =====');
print('credential.user = ${credential.user?.uid}');
print('currentUser = ${_auth.currentUser?.uid}');
print('providerId = ${credential.credential?.providerId}');
  } on FirebaseAuthException catch (e) {
    print('===== FIREBASE AUTH ERROR =====');
print('code: ${e.code}');
print('message: ${e.message}');
  } catch (e) {
    print('===== UNKNOWN ERROR =====');
    print(e.toString());
  }

  return checkAccess();
}

  Future<WebAdminAccessResult> checkAccess() async {
  final user = _auth.currentUser;

  print('===== CHECK ACCESS =====');
  print('uid = ${user?.uid}');
  print('email = ${user?.email}');

  if (user == null) {
      return const WebAdminAccessResult(
        status: WebAdminAccessStatus.signedOut,
      );
    }

    final adminDoc = await _firestore.collection('admins').doc(user.uid).get();

    if (adminDoc.exists) {
      final data = adminDoc.data();

      if (data?['accessStatus'] == 'approved') {
        return WebAdminAccessResult(
          status: WebAdminAccessStatus.approved,
          user: user,
        );
      }

      if (data?['accessStatus'] == 'rejected') {
        return WebAdminAccessResult(
          status: WebAdminAccessStatus.rejected,
          user: user,
        );
      }
    }

    final requestDoc =
        await _firestore.collection('adminRequests').doc(user.uid).get();

    if (requestDoc.exists) {
      final data = requestDoc.data();

      if (data?['status'] == 'pending') {
        return WebAdminAccessResult(
          status: WebAdminAccessStatus.pending,
          user: user,
        );
      }

      if (data?['status'] == 'rejected') {
        return WebAdminAccessResult(
          status: WebAdminAccessStatus.rejected,
          user: user,
        );
      }
    }

    return WebAdminAccessResult(
      status: WebAdminAccessStatus.registrationRequired,
      user: user,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}